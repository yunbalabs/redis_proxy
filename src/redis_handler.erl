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
    enable_read_forward,
    read_max_try_times
}).

init([CommandTypes]) ->
    random:seed(os:timestamp()),
    {ok, #state{
        command_type_dict = dict:from_list(CommandTypes),
        enable_read_forward = redis_proxy_config:enable_read_forward(),
        read_max_try_times = redis_proxy_config:read_max_try_times()
    }}.

handle_redis(Connection, Action, State) ->
    case parse_command(Action, State) of
        {ok, Type, KeyBin, Command} ->
            handle_key_command(Connection, Type, KeyBin, Command, State, 0, []);
        {ok, c, Command} ->
            handle_control_command(Connection, Command);
        {ok, _Type, _Command} ->
            ok = reply(Connection, {error, <<"ERR not implemented">>});
        {error, Reason} ->
            ok = reply(Connection, {error, Reason})
    end,
    {ok, State}.

handle_info(_Connection, _Info, State) ->
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
            {error, <<"ERR unknown command '", NameBin/binary, "'">>}
    end;
parse_command(Command, #state{command_type_dict = CommandTypes}) when length(Command) =:= 1 ->
    [NameBin] = Command,
    Name = string:to_lower(binary_to_list(NameBin)),
    case dict:find(Name, CommandTypes) of
        {ok, Type} ->
            {ok, Type, Name};
        error ->
            {error, <<"ERR unknown command '", NameBin/binary, "'">>}
    end;
parse_command(_Command, _State) ->
    {error, <<"ERR invalid command">>}.

handle_key_command(Connection, _Type, _KeyBin, _Command,
        #state{read_max_try_times = MaxTryTimes},
        TryTimes, _TriedNodes) when TryTimes > MaxTryTimes ->
    ok = reply(Connection, {error, <<"ERR all replicas are unavailable">>});
handle_key_command(Connection, Type, KeyBin, Command, State, TryTimes, TriedNodes) ->
    case request_replicas(Type, KeyBin, Command, State, TriedNodes) of
        {ok, RequestNodes, Response} ->
            case parse_response(Type, Command, Response, State) of
                {ok, Response2} ->
                    ok = reply(Connection, Response2);
                {error, Reason} ->
                    ok = reply(Connection, {error, Reason});
                try_again ->
                    handle_key_command(Connection, Type, KeyBin, Command, State, TryTimes + 1, lists:append(RequestNodes, TriedNodes))
            end;
        {error, Reason} ->
            ok = reply(Connection, {error, Reason})
    end.

handle_control_command(Connection, _Command) ->
    ok = reply(Connection, {error, <<"ERR not implemented">>}).

request_replicas(r, KeyBin, Command, #state{enable_read_forward = EnableReadForward}, TriedNodes) ->
    {Idx, Nodes} = redis_proxy_util:locate_key(KeyBin),
    AvailableNodes = Nodes -- TriedNodes,
    LocalNode = node(),
    case lists:member(LocalNode, AvailableNodes) of
        true ->
            GroupIndex = distributed_proxy_util:index_of(LocalNode, Nodes),
            Response = request_replica([{GroupIndex, LocalNode}], Idx, Command),
            {ok, [LocalNode], Response};
        false ->
            case redis_proxy_util:select_one_random_node(AvailableNodes) of
                none ->
                    {error, <<"ERR all replicas are unavailable">>};
                Node when EnableReadForward =:= true ->
                    GroupIndex = distributed_proxy_util:index_of(Node, Nodes),
                    Response = request_replica([{GroupIndex, Node}], Idx, Command),
                    {ok, [Node], Response};
                Node when EnableReadForward =:= false ->
                    NodeBin = list_to_binary(atom_to_list(Node)),
                    {ok, [Node], [{forward, << "MOVED ", KeyBin/binary, " ", NodeBin/binary >>}]}
            end
    end;
request_replicas(w, KeyBin, Command, _State, _TriedNodes) ->
    {Idx, Nodes} = redis_proxy_util:locate_key(KeyBin),
    RequestNodes = redis_proxy_util:generate_apl(Nodes),
    Response = request_replica(RequestNodes, Idx, Command),
    {ok, Nodes, Response}.

parse_response(r, _Command, [{ok, Result}], _State) ->
    {ok, Result};
parse_response(r, _Command, [{error, temporarily_unavailable}], _State) ->
    try_again;
parse_response(r, Command, [{error, Reason}], _State) ->
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

request_replica(RequestNodes, Index, Command) ->
    IndexBin = integer_to_binary(Index),

    RequestFun =
        fun({GroupIndex, Node}) ->
            GroupIndexBin = integer_to_binary(GroupIndex),
            Proxy = distributed_proxy_util:replica_proxy_reg_name(<<IndexBin/binary, $_, GroupIndexBin/binary>>),
            distributed_proxy_message:send({Proxy, Node}, Command),
            case distributed_proxy_message:recv() of
                {temporarily_unavailable, _} ->
                    {error, temporarily_unavailable};
                {error, Reason} ->
                    {error, Reason};
                {ok, Result} ->
                    {ok, Result}
            end
        end,
    distributed_proxy_util:pmap(RequestFun, RequestNodes, length(RequestNodes)).

write_response_success([], 0) ->
    {error, all_replicas_unavailable};
write_response_success([], _TmpUnaibleCount) ->
    ok;
write_response_success([{ok, <<"OK">>} | Rest], TmpUnaibleCount) ->
    write_response_success(Rest, TmpUnaibleCount);
write_response_success([{error, temporarily_unavailable} | Rest], TmpUnaibleCount) ->
    write_response_success(Rest, TmpUnaibleCount - 1);
write_response_success([{error, Reason} | _Rest], _TmpUnaibleCount) ->
    lager:error("write_response error ~p", [Reason]),
    {error, Reason}.