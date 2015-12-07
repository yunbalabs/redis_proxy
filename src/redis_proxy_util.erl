%%%-------------------------------------------------------------------
%%% @author zy
%%% @copyright (C) 2015, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 04. 十二月 2015 11:56 AM
%%%-------------------------------------------------------------------
-module(redis_proxy_util).
-author("zy").

%% API
-export([file_exists/1, wait_for_file/3]).

file_exists(Filepath) ->
    case filelib:last_modified(filename:absname(Filepath)) of
        0 ->
            false;
        _ ->
            true
    end.

wait_for_file(File, Msec, Attempts) when Attempts > 0 ->
    case file_exists(File) of
        true->
            ok;
        false ->
            timer:sleep(Msec),
            wait_for_file(File, Msec, Attempts - 1)
    end;
wait_for_file(File, _Msec, Attempts) when Attempts =< 0 ->
    not_found.