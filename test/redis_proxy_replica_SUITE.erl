%% common_test suite for redis_proxy_replica

-module(redis_proxy_replica_SUITE).
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
        {requester, [sequence], [join_cluster, test_slaveof_without_data, test_slaveof_with_data, test_finished]}
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
    ok = filelib:ensure_dir("priv/redis/"),
    RedisConfPath = ct:get_config(redis_conf_path),
    {ok, _} = file:copy(RedisConfPath, "priv/redis/redis.conf"),
    RedisServerPath = ct:get_config(redis_server_path),
    {ok, _} = file:copy(RedisServerPath, "priv/redis/redis-server"),
    ok = file:change_mode("priv/redis/redis-server", 8#00755),

    ok = lager:start(),
    ok = application:ensure_started(clique),
    ok = distributed_proxy:start(),
    ok = application:ensure_started(hierdis),
    ok = application:ensure_started(ranch),
    ok = redis_proxy:start(),
    {ok, MyRing} = distributed_proxy_ring_manager:get_ring(),
    Owners = distributed_proxy_ring:get_owners(MyRing),
    wait_replica_started(node(), Owners),

    MasterNode = ct:get_config(master_node),
    DataSize = ct:get_config(data_size),
    [{data_size, DataSize}, {master_node, MasterNode} | Config].

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
        {write_data, Idx, Sender} ->
            {ok, ReplicaPid} = distributed_proxy_replica_manager:get_replica_pid(Idx),
            lists:foreach(
                fun (Key) ->
                    distributed_proxy_message:send(ReplicaPid, ["SET", integer_to_list(Key), "test"]),
                    {ok, <<"OK">>} = distributed_proxy_message:recv()
                end, lists:seq(1, ?config(data_size, Config))),
            Sender ! done,
            wait_for_message(Config);
        close ->
            ok
    end.

join_cluster(Config) ->
    {ok, MyRing} = distributed_proxy_ring_manager:get_ring(),
    Owners = distributed_proxy_ring:get_owners(MyRing),
    [AnotherNode] = lists:delete(?config(master_node, Config), nodes()),
    wait_replica_started(AnotherNode, Owners),

    [AnotherNode] = lists:delete(?config(master_node, Config), nodes()),
    ok = distributed_proxy:join_cluster(AnotherNode).

test_slaveof_without_data(_Config) ->
    Idx = 0,
    {ok, ReplicaPid} = distributed_proxy_replica_manager:get_replica_pid(Idx),
    exit(ReplicaPid, kill),
    wait_replica_started(node(), [{Idx, undefined}]).

test_slaveof_with_data(Config) ->
    Idx = 0,
    [AnotherNode] = lists:delete(?config(master_node, Config), nodes()),
    erlang:send({?MODULE, AnotherNode}, {write_data, Idx, self()}),
    receive done -> ok end,

    {ok, ReplicaPid} = distributed_proxy_replica_manager:get_replica_pid(Idx),
    exit(ReplicaPid, kill),
    wait_replica_started(node(), [{Idx, undefined}]),
    {ok, ReplicaPid2} = distributed_proxy_replica_manager:get_replica_pid(Idx),
    lists:foreach(
        fun (Key) ->
            distributed_proxy_message:send(ReplicaPid2, ["GET", integer_to_list(Key)]),
            {ok, <<"test">>} = distributed_proxy_message:recv()
        end, lists:seq(1, ?config(data_size, Config))),
    true.

test_finished(Config) ->
    [AnotherNode] = lists:delete(?config(master_node, Config), nodes()),
    erlang:send({?MODULE, AnotherNode}, close),
    true.

wait_replica_started(Node, Owners) ->
    NotActived = lists:filter(
        fun({Idx, _GroupId}) ->
            case distributed_proxy_util:safe_rpc(Node, distributed_proxy_replica_manager, get_replica_pid, [Idx], 3000) of
                {badrpc, _} -> true;
                {ok, Pid} ->
                    case catch sys:get_status(Pid, 3000) of
                        {status, _, _, [_, _, _, _, [_, {data, State} | _]]} ->
                            case lists:keyfind("StateName", 1, State) of
                                {"StateName", active} ->
                                    false;
                                {"StateName", _} ->
                                    true;
                                false ->
                                    true
                            end;
                        _Error ->
                            true
                    end;
                not_found ->
                    true
            end
        end, Owners),
    case NotActived of
        [] ->
            true;
        _ ->
            wait_replica_started(Node, NotActived)
    end.