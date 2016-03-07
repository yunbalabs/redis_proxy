%%%-------------------------------------------------------------------
%%% @author zy
%%% @copyright (C) 2015, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 11. 十二月 2015 8:15 PM
%%%-------------------------------------------------------------------
-module(redis_proxy_config).
-author("zy").

%% API
-export([
    redis_port/0, enable_read_forward/0,
    redis_pool_size/0, redis_pool_max_overflow/0,
    redis_client/0, read_max_try_times/0,
    enable_stat/0, stat_interval/0]).

-define(DEFAULT_REDIS_PORT, 6379).
-define(ENABLE_READ_FORWARD, true).
-define(DEFAULT_REDIS_POOL_SIZE, 40).
-define(DEFAULT_REDIS_POOL_MAX_OVERFLOW, 20).
-define(DEFAULT_REDIS_CLIENT, eredis).
-define(DEFAULT_READ_MAX_TRY_TIMES, 3).
-define(ENABLE_STAT, false).
-define(DEFAULT_STAT_INTERVAL, 1000).           %% ms

redis_port() ->
    {ok, App}  = application:get_application(?MODULE),
    application:get_env(App, redis_port, ?DEFAULT_REDIS_PORT).

enable_read_forward() ->
    {ok, App}  = application:get_application(?MODULE),
    application:get_env(App, enable_read_forward, ?ENABLE_READ_FORWARD).

redis_pool_size() ->
    case application:get_application(?MODULE) of
        undefined ->
            ?DEFAULT_REDIS_POOL_SIZE;
        {ok, App} ->
            application:get_env(App, redis_pool_size, ?DEFAULT_REDIS_POOL_SIZE)
    end.

redis_pool_max_overflow() ->
    case application:get_application(?MODULE) of
        undefined ->
            ?DEFAULT_REDIS_POOL_MAX_OVERFLOW;
        {ok, App} ->
            application:get_env(App, redis_pool_max_overflow, ?DEFAULT_REDIS_POOL_MAX_OVERFLOW)
    end.

redis_client() ->
    case application:get_application(?MODULE) of
        undefined ->
            ?DEFAULT_REDIS_CLIENT;
        {ok, App} ->
            application:get_env(App, redis_client, ?DEFAULT_REDIS_CLIENT)
    end.

read_max_try_times() ->
    case application:get_application(?MODULE) of
        undefined ->
            ?DEFAULT_READ_MAX_TRY_TIMES;
        {ok, App} ->
            application:get_env(App, read_max_try_times, ?DEFAULT_READ_MAX_TRY_TIMES)
    end.

enable_stat() ->
    case application:get_application(?MODULE) of
        undefined ->
            ?ENABLE_STAT;
        {ok, App} ->
            application:get_env(App, enable_stat, ?ENABLE_STAT)
    end.

stat_interval() ->
    case application:get_application(?MODULE) of
        undefined ->
            ?DEFAULT_STAT_INTERVAL;
        {ok, App} ->
            application:get_env(App, stat_interval, ?DEFAULT_STAT_INTERVAL)
    end.