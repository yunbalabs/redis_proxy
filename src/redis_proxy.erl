%%%-------------------------------------------------------------------
%%% @author zy
%%% @copyright (C) 2015, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 03. 十二月 2015 3:39 PM
%%%-------------------------------------------------------------------
-module(redis_proxy).
-author("zy").

%% API
-export([start/0, stop/0]).

start() ->
    application:ensure_started(?MODULE).

stop() ->
    application:stop(?MODULE).