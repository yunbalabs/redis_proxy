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
    read_max_try_times,
    multi_op_max_concurrence
}).

init([CommandTypes]) ->
    random:seed(os:timestamp()),
    {ok, #state{
        command_type_dict = dict:from_list(CommandTypes),
        enable_read_forward = redis_proxy_config:enable_read_forward(),
        read_max_try_times = redis_proxy_config:read_max_try_times(),
        multi_op_max_concurrence = redis_proxy_config:multi_op_max_concurrence()
    }}.

handle_redis(Connection, Action, State) ->
    case parse_command(Action, State) of
        {ok, Type, KeyBin, Command} ->
            stat_request(Type),
            StartTime = redis_proxy_util:get_millisec(),

            handle_key_command(Connection, Type, KeyBin, Command, State, 0, []),

            stat_latency(Type, redis_proxy_util:get_millisec() - StartTime);
        {ok, c, Command} ->
            handle_control_command(Connection, Command, State);
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
        TryTimes, _TriedNodes) when TryTimes >= MaxTryTimes ->
    ok = reply(Connection, {error, <<"ERR all replicas are unavailable">>});
handle_key_command(Connection, Type, KeyBin, Command, State, TryTimes, TriedNodes) ->
    case request_replicas(Type, KeyBin, Command, State, TriedNodes) of
        {ok, RequestNodes, Response} ->
            case parse_response(Type, Command, Response, State) of
                {ok, Response2} ->
                    stat_response(Type),
                    ok = reply(Connection, Response2);
                {error, Reason} ->
                    ok = reply(Connection, {error, Reason});
                try_again ->
                    handle_key_command(Connection, Type, KeyBin, Command, State, TryTimes + 1, lists:append(RequestNodes, TriedNodes))
            end;
        {error, Reason} ->
            ok = reply(Connection, {error, Reason})
    end.

handle_control_command(Connection, "dbsize", State) ->
    {ok, MyRing} = distributed_proxy_ring_manager:get_ring(),
    Owners = distributed_proxy_ring:get_owners(MyRing),
    DBSizeList = lists:map(
        fun ({Idx, GroupId}) ->
            Pos = distributed_proxy_ring:index2pos({Idx, GroupId}, MyRing),
            Nodes = distributed_proxy_ring:get_nodes(Pos, MyRing),
            case request_available_node(<<"">>, {Idx, Nodes}, [<<"dbsize">>], State, []) of
                {ok, _RequestNodes, [{ok, Result}]} ->
                    binary_to_integer(Result);
                _ ->
                    0
            end
        end, Owners),
    ok = reply(Connection, lists:sum(DBSizeList));
handle_control_command(Connection, _Command, _State) ->
    ok = reply(Connection, {error, <<"ERR not implemented">>}).

request_replicas(r, KeyBin, Command, State, TriedNodes) ->
    {Idx, Nodes} = redis_proxy_util:locate_key(KeyBin),
    request_available_node(KeyBin, {Idx, Nodes}, Command, State, TriedNodes);
request_replicas(mr, _, Command, State = #state{multi_op_max_concurrence = MaxP}, _TriedNodes) ->
    [NameBin | Keys] = Command,
    SeqKeys = redis_proxy_util:sequence(Keys),
    IdxKeys = redis_proxy_util:classify_keys(SeqKeys),
    Response = distributed_proxy_util:pmap(fun({{Idx, Nodes}, SubSeqKeys}) -> handle_each_for_multi_command(r, NameBin, {Idx, Nodes}, SubSeqKeys, State, 0, []) end, IdxKeys, MaxP),
    {_, SeqValues} = lists:unzip(Response),
    {_, Values} = lists:unzip(lists:keysort(1, lists:flatten(SeqValues))),
    {ok, [node()], Values};
request_replicas(w, KeyBin, Command, _State, _TriedNodes) ->
    {Idx, Nodes} = redis_proxy_util:locate_key(KeyBin),
    RequestNodes = redis_proxy_util:generate_apl(Nodes),
    Response = request_replica(RequestNodes, Idx, Command),
    {ok, Nodes, Response}.

parse_response(r, _Command, [{ok, Result}], _State) ->
    {ok, Result};
parse_response(r, _Command, [{error, temporarily_unavailable}], _State) ->
    try_again;
parse_response(r, _Command, [{error, refuse}], _State) ->
    {error, <<"ERR the replica refused">>};
parse_response(r, Command, [{error, Reason}], _State) ->
    lager:error("command ~p error ~p", [Command, Reason]),
    {error, <<"ERR response error">>};
parse_response(r, _Command, [{forward, Info}], _State) ->
    {error, Info};
parse_response(mr, _Command, Results, _State) ->
    {ok, Results};
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

stat_request(r) ->
    redis_proxy_status:stat_frontend_request(read);
stat_request(mr) ->
    redis_proxy_status:stat_frontend_request(read);
stat_request(w) ->
    redis_proxy_status:stat_frontend_request(write).

stat_response(r) ->
    redis_proxy_status:stat_frontend_response(read);
stat_response(mr) ->
    redis_proxy_status:stat_frontend_response(read);
stat_response(w) ->
    redis_proxy_status:stat_frontend_response(write).

stat_latency(r, Latency) ->
    redis_proxy_status:stat_latency(read, Latency);
stat_latency(mr, Latency) ->
    redis_proxy_status:stat_latency(multiple_read, Latency);
stat_latency(w, Latency) ->
    redis_proxy_status:stat_latency(write, Latency).

handle_each_for_multi_command(_Type, _NameBin, {Idx, _Nodes}, SubSeqKeys, #state{read_max_try_times = MaxTryTimes}, TryTimes, _TriedNodes) when TryTimes >= MaxTryTimes ->
    {Seq, _Keys} = lists:unzip(SubSeqKeys),
    Response = lists:duplicate(length(Seq), {error, <<"ERR all replicas are unavailable">>}),
    {Idx, lists:zip(Seq, Response)};
handle_each_for_multi_command(Type, NameBin, {Idx, Nodes}, SubSeqKeys, State, TryTimes, TriedNodes) ->
    {Seq, Keys} = lists:unzip(SubSeqKeys),
    RequestCommand = [NameBin | Keys],
    case request_available_node(<<"">>, {Idx, Nodes}, RequestCommand, State, TriedNodes) of
        {ok, RequestNodes, Response} ->
            case parse_response(Type, RequestCommand, Response, State) of
                {ok, Response2} ->
                    {Idx, lists:zip(Seq, Response2)};
                {error, Reason} ->
                    Response2 = lists:duplicate(length(Seq), {error, Reason}),
                    {Idx, lists:zip(Seq, Response2)};
                try_again ->
                    handle_each_for_multi_command(Type, NameBin, {Idx, Nodes}, SubSeqKeys, State, TryTimes + 1, lists:append(RequestNodes, TriedNodes))
            end;
        {error, Reason} ->
            Response2 = lists:duplicate(length(Seq), {error, Reason}),
            {Idx, lists:zip(Seq, Response2)}
    end.

request_available_node(KeyBin, {Idx, Nodes}, Command, #state{enable_read_forward = EnableReadForward}, TriedNodes) ->
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
    end.