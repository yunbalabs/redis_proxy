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
-export([redis_port/0, enable_read_forward/0]).

-define(DEFAULT_REDIS_PORT, 6379).
-define(ENABLE_READ_FORWARD, true).

redis_port() ->
    {ok, App}  = application:get_application(?MODULE),
    application:get_env(App, redis_port, ?DEFAULT_REDIS_PORT).

enable_read_forward() ->
    {ok, App}  = application:get_application(?MODULE),
    application:get_env(App, enable_read_forward, ?ENABLE_READ_FORWARD).