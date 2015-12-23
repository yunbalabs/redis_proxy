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
-export([redis_port/0, enable_read_forward/0, redis_pool_size/0, redis_pool_max_overflow/0]).

-define(DEFAULT_REDIS_PORT, 6379).
-define(ENABLE_READ_FORWARD, true).
-define(DEFAULT_REDIS_POOL_SIZE, 10).
-define(DEFAULT_REDIS_POOL_MAX_OVERFLOW, 20).

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