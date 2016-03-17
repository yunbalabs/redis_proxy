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
-export([
    file_exists/1, wait_for_file/3, wait_for_file_deleted/3,
    select_one_random_node/1, generate_apl/1, locate_key/1,
    redis_pool_name/2, get_millisec/0, sequence/1, classify_keys/1]).

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
wait_for_file(_File, _Msec, Attempts) when Attempts =< 0 ->
    not_found.

wait_for_file_deleted(File, Msec, Attempts) when Attempts > 0 ->
    case file_exists(File) of
        true->
            timer:sleep(Msec),
            wait_for_file_deleted(File, Msec, Attempts - 1);
        false ->
            ok
    end;
wait_for_file_deleted(_File, _Msec, Attempts) when Attempts =< 0 ->
    timeout.

select_one_random_node([]) ->
    none;
select_one_random_node([Node]) ->
    case distributed_proxy_node_watcher:is_up(Node) of
        true ->
            Node;
        false ->
            none
    end;
select_one_random_node(Nodes) ->
    Index = random:uniform(length(Nodes)),
    Node = lists:nth(Index, Nodes),
    case distributed_proxy_node_watcher:is_up(Node) of
        true ->
            Node;
        false ->
            select_one_random_node(lists:delete(Node, Nodes))
    end.

%% Active Preference Lists
generate_apl(Nodes) ->
    generate_apl(Nodes, 1, []).

generate_apl([], _Count, APL) ->
    APL;
generate_apl([Node | Rest], Count, APL) ->
    case distributed_proxy_node_watcher:is_up(Node) of
        true ->
            generate_apl(Rest, Count + 1, [{Count, Node} | APL]);
        false ->
            generate_apl(Rest, Count + 1, APL)
    end.

locate_key(KeyBin) ->
    {ok, Ring} = distributed_proxy_ring_manager:get_ring(),
    {Idx, Pos, _GroupId} = ring:locate_key(distributed_proxy_ring:get_chashbin(Ring), KeyBin),
    Nodes = distributed_proxy_ring:get_nodes(Pos, Ring),
    {Idx, Nodes}.

redis_pool_name(Index, GroupIndex) ->
    IndexBin = integer_to_binary(Index),
    GroupIndexBin = integer_to_binary(GroupIndex),
    AllBin = <<$r,$e,$d,$i,$s,$_,$p,$r,$o,$x,$y,$_,$r,$e,$d,$i,$s,$_,$p,$o,$o,$l,$_, IndexBin/binary, $_, GroupIndexBin/binary>>,
    binary_to_atom(AllBin, latin1).

get_millisec() ->
    {Mega, Sec, Micro} = os:timestamp(),
    (Mega * 1000000 + Sec) * 1000 + round(Micro / 1000).

sequence(List) ->
    sequence(List, 0, []).

sequence([], _No, Results) ->
    Results;
sequence([Item | Rest], No, Results) ->
    sequence(Rest, No + 1, [{No, Item} | Results]).

classify_keys(SeqKeys) ->
    {ok, Ring} = distributed_proxy_ring_manager:get_ring(),
    classify_keys(SeqKeys, Ring, []).

classify_keys([], _Ring, Results) ->
    Results;
classify_keys([Item = {_No, KeyBin} | Rest], Ring, Results) ->
    {Idx, Pos, _GroupId} = ring:locate_key(distributed_proxy_ring:get_chashbin(Ring), KeyBin),
    Nodes = distributed_proxy_ring:get_nodes(Pos, Ring),
    NewResults = case lists:keyfind({Idx, Nodes}, 1, Results) of
                     false ->
                         lists:keystore({Idx, Nodes}, 1, Results, {{Idx, Nodes}, [Item]});
                     {{Idx, Nodes}, Keys} ->
                         lists:keystore({Idx, Nodes}, 1, Results, {{Idx, Nodes}, [Item] ++ Keys})
                 end,
    classify_keys(Rest, Ring, NewResults).