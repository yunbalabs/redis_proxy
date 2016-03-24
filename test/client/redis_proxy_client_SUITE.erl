%% common_test suite for redis_proxy_replica

-module(redis_proxy_client_SUITE).
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
        {requester, [sequence], [
            join_cluster,
            test_put_data,
            test_get_data_from_pool1, shutdown_replica1, test_get_data_from_pool2
        ]}
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
    ok = application:ensure_started(redis_hapool),
    {ok, MyRing} = distributed_proxy_ring_manager:get_ring(),
    Owners = distributed_proxy_ring:get_owners(MyRing),
    redis_proxy_test_util:wait_all_replica_started(node(), Owners, MyRing),

    MasterNode = ct:get_config(master_node),
    [{master_node, MasterNode} | Config].

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

wait_for_message(_Config) ->
    receive
        {shutdown, Sender} ->
            Sender ! done,
            init:stop()
    end.

join_cluster(Config) ->
    {ok, MyRing} = distributed_proxy_ring_manager:get_ring(),
    [AnotherNode] = lists:delete(?config(master_node, Config), nodes()),
    Owners = distributed_proxy_ring:get_owners(MyRing),
    redis_proxy_test_util:wait_all_replica_started(AnotherNode, Owners, MyRing),

    ok = distributed_proxy:join_cluster(AnotherNode),
    {ok, MyRing2} = distributed_proxy_ring_manager:get_ring(),
    Owners2 = distributed_proxy_ring:get_owners(MyRing2),
    redis_proxy_test_util:wait_all_replica_started(node(), Owners2, MyRing2),
    redis_proxy_test_util:wait_all_replica_started(AnotherNode, Owners2, MyRing2).

test_put_data(Config) ->
    Key = <<"1">>,
    [AnotherNode] = lists:delete(?config(master_node, Config), nodes()),
    {Idx, _Nodes} = redis_proxy_util:locate_key(Key),
    IndexBin = integer_to_binary(Idx),
    Proxy1 = distributed_proxy_util:replica_proxy_reg_name(<<IndexBin/binary, $_, "1">>),
    distributed_proxy_message:send({Proxy1, AnotherNode}, ["SET", Key, "1"]),
    {ok, <<"OK">>} = distributed_proxy_message:recv(),
    Proxy2 = distributed_proxy_util:replica_proxy_reg_name(<<IndexBin/binary, $_, "2">>),
    distributed_proxy_message:send({Proxy2, node()}, ["SET", Key, "2"]),
    {ok, <<"OK">>} = distributed_proxy_message:recv().

test_get_data_from_pool1(_Config) ->
    Key = <<"1">>,
    {ok, <<"1">>} = redis_hapool:q([<<"GET">>, Key]).

shutdown_replica1(Config) ->
    [AnotherNode] = lists:delete(?config(master_node, Config), nodes()),
    case redis_proxy_test_util:repeat_call({?MODULE, AnotherNode}, {shutdown, self()}, 10000, 1) of
        done -> ok
    end.

test_get_data_from_pool2(_Config) ->
    Key = <<"1">>,
    {ok, <<"2">>} = redis_hapool:q([<<"GET">>, Key]).