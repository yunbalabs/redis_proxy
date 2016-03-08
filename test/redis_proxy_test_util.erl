%%%-------------------------------------------------------------------
%%% @author zy
%%% @copyright (C) 2015, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 22. 十二月 2015 4:02 PM
%%%-------------------------------------------------------------------
-module(redis_proxy_test_util).
-author("zy").

%% API
-export([start_application/0, wait_all_replica_started/3, wait_replica_started/2, repeat_call/4]).

start_application() ->
    ok = filelib:ensure_dir("priv/redis/"),
    RedisConfPath = ct:get_config(redis_conf_path),
    {ok, _} = file:copy(RedisConfPath, "priv/redis/redis.conf"),
    RedisServerPath = ct:get_config(redis_server_path),
    {ok, _} = file:copy(RedisServerPath, "priv/redis/redis-server"),
    ok = file:change_mode("priv/redis/redis-server", 8#00755),
    RedisCloseScriptPath = ct:get_config(redis_close_script_path),
    {ok, _} = file:copy(RedisCloseScriptPath, "priv/redis/close_redis.sh"),
    ok = file:change_mode("priv/redis/close_redis.sh", 8#00755),

    ok = lager:start(),
    ok = application:ensure_started(clique),
    ok = distributed_proxy:start(),
    ok = application:ensure_started(ranch),
    ok = application:ensure_started(eredis_pool),
    {ok, _} = application:ensure_all_started(exometer_influxdb),
    redis_proxy:start().

wait_all_replica_started(Node, Owners, MyRing) ->
    ActiveFun =
        fun (Idx, GroupIndex) ->
            case distributed_proxy_util:safe_rpc(Node, distributed_proxy_replica_manager, get_replica_pid, [{Idx, GroupIndex}], 100) of
                {badrpc, _} -> true;
                {ok, Pid} ->
                    case catch sys:get_status(Pid, 100) of
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
        end,

    NotActived = lists:filter(
        fun({Idx, GroupId}) ->
            IdealNodes = distributed_proxy_ring:get_ideal_nodes(GroupId, MyRing),
            case distributed_proxy_util:index_of(Node, IdealNodes) of
                not_found ->
                    false;
                IdealGroupIndex ->
                    ActiveFun(Idx, IdealGroupIndex)
            end
        end, Owners),
    case NotActived of
        [] ->
            true;
        _ ->
            wait_all_replica_started(Node, NotActived, MyRing)
    end.

wait_replica_started(Node, {Idx, GroupIndex}) ->
    case distributed_proxy_util:safe_rpc(Node, distributed_proxy_replica_manager, get_replica_pid, [{Idx, GroupIndex}], 100) of
        {badrpc, _} -> true;
        {ok, Pid} ->
            case catch sys:get_status(Pid, 100) of
                {status, _, _, [_, _, _, _, [_, {data, State} | _]]} ->
                    case lists:keyfind("StateName", 1, State) of
                        {"StateName", active} ->
                            true;
                        {"StateName", _} ->
                            wait_replica_started(Node, {Idx, GroupIndex});
                        false ->
                            wait_replica_started(Node, {Idx, GroupIndex})
                    end;
                _Error ->
                    wait_replica_started(Node, {Idx, GroupIndex})
            end;
        not_found ->
            wait_replica_started(Node, {Idx, GroupIndex})
    end.

repeat_call(_Dest, _Msg, _Interval, 0) ->
    {error, timeout};
repeat_call(Dest, Msg, Interval, TryTimes) ->
    erlang:send(Dest, Msg),
    receive
        Ret -> Ret
    after Interval -> repeat_call(Dest, Msg, Interval, TryTimes - 1)
    end.