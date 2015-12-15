%%%-------------------------------------------------------------------
%%% @author zy
%%% @copyright (C) 2015, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 11. 十二月 2015 8:36 PM
%%%-------------------------------------------------------------------
-module(redis_handler).
-author("zy").

-behaviour(redis_protocol).

%% API
-export([init/1, handle_redis/3, handle_info/3, terminate/1]).

-record(state, {
    command_type_dict,
    enable_read_forward
}).

init([CommandTypes]) ->
    random:seed(os:timestamp()),
    {ok, #state{
        command_type_dict = dict:from_list(CommandTypes),
        enable_read_forward = redis_proxy_config:enable_read_forward()
    }}.

handle_redis(Connection, Action, State) ->
    case parse_command(Action, State) of
        {ok, Type, KeyBin, Command} ->
            case request_replicas(Type, KeyBin, Command, State) of
                {ok, Response} ->
                    case parse_response(Type, Command, Response, State) of
                        {ok, Response2} ->
                            ok = reply(Connection, Response2);
                        {error, Reason} ->
                            ok = reply(Connection, {error, Reason})
                    end;
                {error, Reason} ->
                    ok = reply(Connection, {error, Reason})
            end;
        {ok, _Type, _Command} ->
            ok = reply(Connection, {error, <<"Not implemented">>});
        {error, Reason} ->
            ok = reply(Connection, {error, Reason})
    end,
    {ok, State}.

handle_info(_Connection, Info, State) ->
    lager:error("unknown info: ~p", [Info]),
    {stop, State}.

terminate(_State) ->
    ok.

parse_command(Command, #state{command_type_dict = CommandTypes}) when length(Command) > 1 ->
    [NameBin, KeyBin | _] = Command,
    Name = string:to_lower(binary_to_list(NameBin)),
    case dict:find(Name, CommandTypes) of
        {ok, Type} ->
            {ok, Type, KeyBin, Command};
        error ->
            {error, <<"Unknown type">>}
    end;
parse_command(Command, #state{command_type_dict = CommandTypes}) when length(Command) =:= 1 ->
    [NameBin] = Command,
    Name = string:to_lower(binary_to_list(NameBin)),
    case dict:find(Name, CommandTypes) of
        {ok, Type} ->
            {ok, Type, Command};
        error ->
            {error, <<"Unknown type">>}
    end;
parse_command(_Command, _State) ->
    {error, <<"Invalid command">>}.

request_replicas(r, KeyBin, Command, #state{enable_read_forward = EnableReadForward}) ->
    {ok, Ring} = distributed_proxy_ring_manager:get_ring(),
    [{Idx, GroupId}] = ring:locate_key(distributed_proxy_ring:get_chashbin(Ring), KeyBin),
    Nodes = distributed_proxy_ring:get_nodes(GroupId, Ring),
    case lists:member(node(), Nodes) of
        true ->
            GroupIndex = distributed_proxy_util:index_of(node(), Nodes),
            Response = request_replica([{GroupIndex, node()}], Idx, Command, 0),
            {ok, Response};
        false ->
            case redis_proxy_util:select_one_random_node(Nodes) of
                Node when EnableReadForward =:= true ->
                    GroupIndex = distributed_proxy_util:index_of(Node, Nodes),
                    Response = request_replica([{GroupIndex, Node}], Idx, Command, 0),
                    {ok, Response};
                Node when EnableReadForward =:= false ->
                    NodeBin = list_to_binary(atom_to_list(Node)),
                    {ok, [{forward, << "MOVED ", KeyBin/binary, " ", NodeBin/binary >>}]};
                none ->
                    {error, <<"Unavailable">>}
            end
    end;
request_replicas(w, KeyBin, Command, _State) ->
    {ok, Ring} = distributed_proxy_ring_manager:get_ring(),
    [{Idx, GroupId}] = ring:locate_key(distributed_proxy_ring:get_chashbin(Ring), KeyBin),
    Nodes = distributed_proxy_ring:get_nodes(GroupId, Ring),
    RequestNodes = redis_proxy_util:generate_apl(Nodes),
    Response = request_replica(RequestNodes, Idx, Command, 0),
    {ok, Response}.

parse_response(r, _Command, [{ok, Result}], _State) ->
    {ok, Result};
parse_response(r, Command, [{error, Reason}], _State) ->
    %% TODO: try again when the error is temporarily_unavailable
    lager:error("command ~p error ~p", [Command, Reason]),
    {error, <<"ERR response error">>};
parse_response(r, _Command, [{forward, Info}], _State) ->
    {error, Info};
parse_response(w, Command, Results, _State) ->
    case write_response_success(Results, length(Results)) of
        ok ->
            {ok, ok};
        {error, Reason} ->
            lager:error("command ~p error ~p", [Command, Reason]),
            {error, <<"ERR response error">>}
    end.

reply(Connection, Response) ->
    redis_protocol:answer(Connection, Response).

request_replica([], _Index, _Command, RequestNum) ->
    wait_for_response([], RequestNum);
request_replica([{GroupIndex, Node} | Rest], Index, Command, RequestNum) ->
    Proxy = distributed_proxy_util:replica_proxy_reg_name(list_to_binary(lists:flatten(io_lib:format("~w_~w", [Index, GroupIndex])))),
    distributed_proxy_message:send({Proxy, Node}, Command),
    request_replica(Rest, Index, Command, RequestNum + 1).

wait_for_response(Responses, 0) ->
    Responses;
wait_for_response(Responses, RequestNum) ->
    case distributed_proxy_message:recv() of
        {temporarily_unavailable, _} ->
            wait_for_response([{error, temporarily_unavailable} | Responses], RequestNum - 1);
        {error, Reason} ->
            wait_for_response([{error, Reason} | Responses], RequestNum - 1);
        {ok, Result} ->
            wait_for_response([{ok, Result} | Responses], RequestNum - 1)
    end.

write_response_success([], 0) ->
    {error, all_replicas_unavailable};
write_response_success([], _TmpUnaibleCount) ->
    ok;
write_response_success([{ok, <<"OK">>} | Rest], TmpUnaibleCount) ->
    write_response_success(Rest, TmpUnaibleCount);
write_response_success([{error, temporarily_unavailable} | Rest], TmpUnaibleCount) ->
    write_response_success(Rest, TmpUnaibleCount - 1);
write_response_success([{error, Reason} | _Rest], _TmpUnaibleCount) ->
    {error, Reason}.