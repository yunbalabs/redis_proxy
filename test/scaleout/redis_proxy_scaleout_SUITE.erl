%% common_test suite for redis_proxy_replica

-module(redis_proxy_scaleout_SUITE).
-include_lib("common_test/include/ct.hrl").

-compile(export_all).

%%--------------------------------------------------------------------
%% Function: suite() -> Info
%%
%% Info = [tuple()]
%%   List of key/value pairs.
%%
%% Description: Returns list of tuples to set default properties
%%              for the suite.
%%
%% Note: The suite/0 function is only meant to be used to return
%% default data values, not perform any other operations.
%%--------------------------------------------------------------------
suite() ->
    [
        {timetrap, {seconds, 60}}    %% the maximum time each test case is allowed to execute
    ].

%%--------------------------------------------------------------------
%% Function: all() -> GroupsAndTestCases
%%
%% GroupsAndTestCases = [{group,GroupName} | TestCase]
%% GroupName = atom()
%%   Name of a test case group.
%% TestCase = atom()
%%   Name of a test case.
%%
%% Description: Returns the list of groups and test cases that
%%              are to be executed.
%%
%%      NB: By default, we export all 1-arity user defined functions
%%--------------------------------------------------------------------
all() ->
    [
        {group, responser},
        {group, requester}
    ].

groups() ->
    [
        {responser, [], [wait_for_messages]},
        {requester, [sequence], [test_put_data, a_join_cluster, test_checkout_data, c_join_cluster, test_finished]}
    ].

%%--------------------------------------------------------------------
%% Function: init_per_suite(Config0) ->
%%               Config1 | {skip,Reason} | {skip_and_save,Reason,Config1}
%%
%% Config0 = Config1 = [tuple()]
%%   A list of key/value pairs, holding the test case configuration.
%% Reason = term()
%%   The reason for skipping the suite.
%%
%% Description: Initialization before the suite.
%%
%% Note: This function is free to add any key/value pairs to the Config
%% variable, but should NOT alter/remove any existing entries.
%%--------------------------------------------------------------------
init_per_suite(Config) ->
    ok = redis_proxy_test_util:start_application(),
    {ok, MyRing} = distributed_proxy_ring_manager:get_ring(),
    Owners = distributed_proxy_ring:get_owners(MyRing),
    redis_proxy_test_util:wait_all_replica_started(node(), Owners, MyRing),

    DataSize = ct:get_config(data_size),
    RedisPort = redis_proxy_config:redis_port(),
    [{data_size, DataSize}, {redis_port, RedisPort} | Config].

%%--------------------------------------------------------------------
%% Function: end_per_suite(Config0) -> void() | {save_config,Config1}
%%
%% Config0 = Config1 = [tuple()]
%%   A list of key/value pairs, holding the test case configuration.
%%
%% Description: Cleanup after the suite.
%%--------------------------------------------------------------------
end_per_suite(_Config) ->
    ok.

%%--------------------------------------------------------------------
%% Function: init_per_testcase(TestCase, Config0) ->
%%               Config1 | {skip,Reason} | {skip_and_save,Reason,Config1}
%%
%% TestCase = atom()
%%   Name of the test case that is about to run.
%% Config0 = Config1 = [tuple()]
%%   A list of key/value pairs, holding the test case configuration.
%% Reason = term()
%%   The reason for skipping the test case.
%%
%% Description: Initialization before each test case.
%%
%% Note: This function is free to add any key/value pairs to the Config
%% variable, but should NOT alter/remove any existing entries.
%%--------------------------------------------------------------------
init_per_testcase(_TestCase, Config) ->
    Config.

%%--------------------------------------------------------------------
%% Function: end_per_testcase(TestCase, Config0) ->
%%               void() | {save_config,Config1} | {fail,Reason}
%%
%% TestCase = atom()
%%   Name of the test case that is finished.
%% Config0 = Config1 = [tuple()]
%%   A list of key/value pairs, holding the test case configuration.
%% Reason = term()
%%   The reason for failing the test case.
%%
%% Description: Cleanup after each test case.
%%--------------------------------------------------------------------
end_per_testcase(_TestCase, Config) ->
    Config.

wait_for_messages(Config) ->
    true = register(?MODULE, self()),
    wait_for_message(Config).

wait_for_message(Config) ->
    receive
        {join_me, Node, Sender} ->
            Result = distributed_proxy:join_cluster(Node),
            Sender ! Result,
            wait_for_message(Config);
        close ->
            ok
    end.

test_put_data(Config) ->
    {ok, C} = eredis:start_link("127.0.0.1", ?config(redis_port, Config)),
    lists:foreach(
        fun (Key) ->
            {ok, <<"OK">>} = eredis:q(C, ["SET", integer_to_list(Key), "test"])
        end, lists:seq(1, ?config(data_size, Config))),
    eredis:stop(C),
    ok.

a_join_cluster(_Config) ->
    ANode = list_to_atom("a@" ++ net_adm:localhost()),
    erlang:send({?MODULE, ANode}, {join_me, node(), self()}),
    receive
        Result ->
            Result = ok
    end.

test_checkout_data(Config) ->
    wait_reconciling(),
    {ok, C} = eredis:start_link("127.0.0.1", ?config(redis_port, Config)),
    lists:foreach(
        fun (Key) ->
            {ok, <<"test">>} = eredis:q(C, ["GET", integer_to_list(Key)])
        end, lists:seq(1, ?config(data_size, Config))),
    eredis:stop(C),
    true.

c_join_cluster(_Config) ->
    CNode = list_to_atom("c@" ++ net_adm:localhost()),
    erlang:send({?MODULE, CNode}, {join_me, node(), self()}),
    receive
        Result ->
            erlang:send({?MODULE, CNode}, close),
            Result = ring_full
    end.

test_finished(_Config) ->
    ANode = list_to_atom("a@" ++ net_adm:localhost()),
    erlang:send({?MODULE, ANode}, close),
    true.

wait_reconciling() ->
    {ok, Ring} = distributed_proxy_ring_manager:get_ring(),
    case distributed_proxy_ring:get_all_changes(Ring) of
        [] ->
            ok;
        _ ->
            timer:sleep(100),
            wait_reconciling()
    end.