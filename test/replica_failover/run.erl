#!/usr/bin/env escript
%% -*- erlang -*-
%%! -smp enable -name ct@127.0.0.1

%%%-------------------------------------------------------------------
%%% @author zy
%%% @copyright (C) 2015, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 11. 十二月 2015 5:52 PM
%%%-------------------------------------------------------------------
-module(run).
-author("zy").

main(_Args) ->
    ct_master:run("spec").