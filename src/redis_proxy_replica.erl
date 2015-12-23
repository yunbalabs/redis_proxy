%%%-------------------------------------------------------------------
%%% @author zy
%%% @copyright (C) 2015, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 03. 十二月 2015 3:47 PM
%%%-------------------------------------------------------------------
-module(redis_proxy_replica).
-author("zy").

%% API
-export([init/2, check_warnup_state/1, actived/1, handle_request/3, terminate/2, get_slaveof_state/1]).

-record(state, {index, group_index, warnup_state, redis_context, redis_host, redis_port, slaveof_replica}).

-define(DATA_DIR, "data/redis").
-define(REDIS_SERVER_PATH, "priv/redis/redis-server").
-define(REDIS_CONFIG_PATH, "priv/redis/redis.conf").
-define(REDIS_CLOSE_SCRIPT, "priv/redis/close_redis.sh").
-define(DEFAULT_SLAVE_OFFSET_THRESHOLD, 100).

init(Index, GroupIndex) ->
    case start_redis(Index, GroupIndex) of
        {ok, _RedisUnixSocketFile, RedisPort} ->
            case connect_redis(RedisPort) of
                {ok, RedisContext} ->
                    {ok, #state{
                        index = Index, group_index = GroupIndex,
                        warnup_state = loading,
                        redis_context = RedisContext,
                        redis_host = net_adm:localhost(), redis_port = RedisPort,
                        slaveof_replica = undefined
                    }};
                {error, Reason} ->
                    {error, Reason}
            end;
        {error, Reason} ->
            {error, Reason}
    end.

check_warnup_state(State = #state{index = Index, redis_context = RedisContext, warnup_state = loading}) ->
    case eredis:q(RedisContext, ["PING"]) of
        {ok, <<"PONG">>} ->
            case get_available_replica(Index) of
                {ok, ReplicaPid, ReplicaHost, ReplicaPort} ->
                    case eredis:q(RedisContext, ["SLAVEOF", ReplicaHost, ReplicaPort]) of
                        {ok, <<"OK">>} ->
                            %% TODO: make sure slaveof started
                            {ok, warnup, State#state{warnup_state = slaveof, slaveof_replica = ReplicaPid}};
                        _ ->
                            {error, start_slaveof_failed}
                    end;
                not_found ->
                    {ok, up, State#state{warnup_state = finished}}
            end;
        _ ->
            {ok, warnup, State}
    end;
check_warnup_state(State = #state{redis_context = RedisContext, slaveof_replica = SlaveofReplica, warnup_state = slaveof}) ->
    case check_slaveof_state(SlaveofReplica) of
        working ->
            {ok, warnup, State};
        almost_finished ->
            refuse_request(SlaveofReplica),
            {ok, warnup, State};
        finished ->
            case eredis:q(RedisContext, ["SLAVEOF", "NO", "ONE"]) of
                {ok, <<"OK">>} ->
                    {ok, up, State#state{warnup_state = finished}};
                _ ->
                    {error, slaveof_no_one_failed}
            end;
        {error, Reason} ->
            lager:error("check slaveof state failed: ~p", [Reason]),
            {error, slaveof_failed}
    end;
check_warnup_state(State = #state{warnup_state = finished}) ->
    {ok, up, State}.

actived(State = #state{slaveof_replica = undefined}) ->
    {ok, State};
actived(State = #state{slaveof_replica = SlaveofReplica}) ->
    accept_request(SlaveofReplica),
    {ok, State}.

handle_request(Request, Sender, State = #state{redis_context = RedisContext}) ->
    lager:debug("receive the request ~p from ~p", [Request, Sender]),
    %% TODO: handle connection lost
    Result = eredis:q(RedisContext, Request),
    {reply, Result, State}.

terminate(_Reason, #state{redis_context = RedisContext}) ->
    eredis:q(RedisContext, [<<"SHUTDOWN">>]),
    ok.

get_slaveof_state(#state{redis_context = RedisContext}) ->
    case eredis:q(RedisContext, ["INFO"]) of
        {ok, InfoData} ->
            %% TODO: handle error
            [_, ReplicationInfo] = binary:split(InfoData, <<"\r\n# Replication">>),
            case binary:split(ReplicationInfo, <<",offset=">>, [trim]) of
                [_, SlaveOffset] ->
                    [SlaveOffset2, _] = binary:split(SlaveOffset, <<",lag=">>, [trim]),
                    [_, MasterOffset] = binary:split(ReplicationInfo, <<"master_repl_offset:">>, [trim]),
                    [MasterOffset2, _] = binary:split(MasterOffset, <<"\r\n">>, [trim]),
                    SlaveOffset3 = binary_to_integer(SlaveOffset2),
                    MasterOffset3 = binary_to_integer(MasterOffset2),
                    case MasterOffset3 - SlaveOffset3 of
                        Offset when Offset > ?DEFAULT_SLAVE_OFFSET_THRESHOLD ->
                            {ok, working};
                        Offset when Offset > 0 ->
                            {ok, almost_finished};
                        _ ->
                            {ok, finished}
                    end;
                _ ->
                    {ok, working}
            end;
        Reason ->
            {error, Reason}
    end.

start_redis(Index, GroupIndex) ->
    RedisDataDir = lists:flatten(io_lib:format("~s/~w_~w/", [?DATA_DIR, Index, GroupIndex])),
    RedisUnixSocketFile = lists:flatten(io_lib:format("/tmp/redis.proxy.unixsocket.~s.~w_~w", [node(), Index, GroupIndex])),
    RedisExecutable = filename:absname(?REDIS_SERVER_PATH),
    RedisConfigFile = filename:absname(?REDIS_CONFIG_PATH),
    RedisCloseScript = filename:absname(?REDIS_CLOSE_SCRIPT),
    RedisPidFile = filename:absname(lists:flatten(io_lib:format("~sredis.pid", [RedisDataDir]))),

    ok = filelib:ensure_dir(RedisDataDir),

    Clean = case redis_proxy_util:file_exists(RedisPidFile) of
        true ->
            case try_stop_redis(RedisCloseScript, RedisPidFile) of
                ok ->
                    ok;
                {error, Reason} ->
                    lager:error("stop old redis failed: ~p", [Reason]),
                    {error, try_stop_redis_failed}
            end;
        _ ->
            ok
    end,

    case Clean of
        ok ->
            %% TODO: backup data files

            case try_start_redis(RedisExecutable, RedisConfigFile, RedisUnixSocketFile, RedisDataDir, 50) of
                {ok, Port} ->
                    {ok, RedisUnixSocketFile, Port};
                {error, Reason2} ->
                    lager:error("start redis failed: ~p", [Reason2]),
                    {error, try_start_redis_failed}
            end;
        {error, Reason1} ->
            {error, Reason1}
    end.

connect_redis(RedisPort) ->
    case eredis:start_link("127.0.0.1", list_to_integer(RedisPort)) of
        {ok, Context} ->
            {ok, Context};
        {error, Reason} ->
            {error, Reason}
    end.

get_available_replica(Index) ->
    {ok, Ring} = distributed_proxy_ring_manager:get_ring(),
    AllOwners = distributed_proxy_ring:get_owners(Ring),
    {Index, GroupId} = lists:keyfind(Index, 1, AllOwners),
    Pos = distributed_proxy_ring:index2pos({Index, GroupId}, Ring),
    Nodes = distributed_proxy_ring:get_nodes(Pos, Ring),
    request_slaveof(lists:delete(node(), Nodes), Index, 1).

request_slaveof([], _Index, _GroupIndex) ->
    not_found;
request_slaveof([Node | Rest], Index, GroupIndex) ->
    case distributed_proxy_node_watcher:is_up(Node) of
        true ->
            ProxyName = distributed_proxy_util:replica_proxy_reg_name(list_to_binary(lists:flatten(io_lib:format("~w_~w", [Index, GroupIndex])))),
            case distributed_proxy_replica_proxy:get_my_replica_pid({ProxyName, Node}) of
                {ok, Pid} ->
                    case distributed_proxy_replica:get_state(Pid) of
                        {ok, #state{redis_host = ReplicaHost, redis_port = ReplicaPort}} ->
                            case distributed_proxy_replica:slaveof_request(Pid) of
                                ok ->
                                    {ok, Pid, ReplicaHost, ReplicaPort};
                                _Error ->
                                    request_slaveof(Rest, Index, GroupIndex + 1)
                            end;
                        {error, _Reason} ->
                            request_slaveof(Rest, Index, GroupIndex + 1)
                    end;
                not_started ->
                    request_slaveof(Rest, Index, GroupIndex + 1)
            end;
        false ->
            request_slaveof(Rest, Index, GroupIndex + 1)
    end.

check_slaveof_state(ReplicaPid) ->
    case distributed_proxy_replica:get_slaveof_state(ReplicaPid) of
        {ok, State} ->
            State;
        {error, Reason} ->
            {error, Reason}
    end.

refuse_request(ReplicaPid) ->
    distributed_proxy_replica:refuse_request(ReplicaPid).

accept_request(ReplicaPid) ->
    distributed_proxy_replica:accept_request(ReplicaPid).

try_start_redis(_Executable, _ConfigFile, _UnixSocketFile, _DataDir, 0) ->
    {error, unavailable_port};
try_start_redis(Executable, ConfigFile, UnixSocketFile, DataDir, TryTimes) ->
    random:seed(now()),
    ListenPort = integer_to_list(10000 + random:uniform(50000)),

    Args = [ConfigFile, "--unixsocket", UnixSocketFile, "--daemonize", "yes", "--port", ListenPort],
    Port = erlang:open_port({spawn_executable, [Executable]}, [{args, Args}, {cd, filename:absname(DataDir)}]),
    receive
        {'EXIT', Port, normal} ->
            case redis_proxy_util:wait_for_file(UnixSocketFile, 100, 50) of
                ok ->
                    {ok, ListenPort};
                not_found ->
                    try_start_redis(Executable, ConfigFile, UnixSocketFile, DataDir, TryTimes - 1)
            end;
        {'EXIT', Port, Reason} ->
            {error, Reason}
    end.

try_stop_redis(RedisCloseScript, RedisPidFile) ->
    Args = [RedisPidFile],
    erlang:open_port({spawn_executable, [RedisCloseScript]}, [{args, Args}]),
    case redis_proxy_util:wait_for_file_deleted(RedisPidFile, 100, 50) of
        ok ->
            ok;
        timeout ->
            {error, timeout}
    end.