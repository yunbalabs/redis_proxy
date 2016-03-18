%% common_test suite for redis_proxy_command

-module(redis_proxy_command_SUITE).
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
        {group, command}
    ].

groups() ->
    [
        {command, [sequence], [test_set, test_get, test_mget, test_dbsize]}
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

    RedisPort = redis_proxy_config:redis_port(),
    [{redis_port, RedisPort} | Config].

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

test_set(Config) ->
    {ok, C} = eredis:start_link("127.0.0.1", ?config(redis_port, Config)),
    {ok, <<"OK">>} = eredis:q(C, ["SET", "test", "test"]),
    eredis:stop(C),
    ok.

test_get(Config) ->
    {ok, C} = eredis:start_link("127.0.0.1", ?config(redis_port, Config)),
    {ok, <<"test">>} = eredis:q(C, ["GET", "test"]),
    eredis:stop(C),
    ok.

test_mget(Config) ->
    {ok, C} = eredis:start_link("127.0.0.1", ?config(redis_port, Config)),
    {ok, [<<"test">>]} = eredis:q(C, ["MGET", "test"]),
    eredis:stop(C),
    ok.

test_dbsize(Config) ->
    {ok, C} = eredis:start_link("127.0.0.1", ?config(redis_port, Config)),
    {ok, <<"1">>} = eredis:q(C, ["DBSIZE"]),
    eredis:stop(C),
    ok.