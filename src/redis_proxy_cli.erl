%%%-------------------------------------------------------------------
%%% @author zy
%%% @copyright (C) 2016, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 08. 三月 2016 10:45 AM
%%%-------------------------------------------------------------------
-module(redis_proxy_cli).
-author("zy").

-behaviour(clique_handler).

%% API
-export([register_cli/0, command/1]).

register_cli() ->
    register_all_usage(),
    register_all_commands().

command(Cmd) ->
    clique:run(Cmd).

register_all_usage() ->
    clique:register_usage(["rp-admin"], usage()),
    clique:register_usage(["rp-admin", "status"], status_usage()),
    clique:register_usage(["rp-admin", "replica"], replica_usage()),
    clique:register_usage(["rp-admin", "locate"], locate_usage()).

register_all_commands() ->
    lists:foreach(fun(Args) -> apply(clique, register_command, Args) end,
        [status_register(), replica_register(), locate_register()]).

usage() ->
    [
        "rp-admin <sub-command>\n\n",
        "  Display status and settings.\n\n",
        "  Sub-commands:\n",
        "    status           Display a summary of node status\n",
        "    replica          Display a replica status on the specific node\n",
        "    locate           Display values about the specific key\n",
        "  Use --help after a sub-command for more details.\n"
    ].

status_usage() ->
    ["rp-admin status\n\n",
        "  Display a summary of node status information.\n"].

status_register() ->
    [["rp-admin", "status"],      % Cmd
        [],                       % KeySpecs
        [],                       % FlagSpecs
        fun status/3].            % Implementation callback.

status(_CmdBase, [], []) ->
    case redis_proxy_config:enable_stat() of
        true ->
            {ok, [{value, CountReadRequest}]} = redis_proxy_status:count_frontend_request(read),
            {ok, [{value, CountReadResponse}]} = redis_proxy_status:count_frontend_response(read),
            {ok, [{value, CountWriteRequest}]} = redis_proxy_status:count_frontend_request(write),
            {ok, [{value, CountWriteResponse}]} = redis_proxy_status:count_frontend_response(write),

            OpsRows = [
                [{type, read}, {operator, request}, {count, CountReadRequest}],
                [{type, read}, {operator, response}, {count, CountReadResponse}],
                [{type, write}, {operator, request}, {count, CountWriteRequest}],
                [{type, write}, {operator, response}, {count, CountWriteResponse}]
            ],

            OpsTable = clique_status:table(OpsRows),

            {ok, [{value, LatencyRead}]} = redis_proxy_status:sample_latency(read),
            {ok, [{value, LatencyMultipleRead}]} = redis_proxy_status:sample_latency(multiple_read),
            {ok, [{value, LatencyWrite}]} = redis_proxy_status:sample_latency(write),

            LatencyRows = [
                [{type, read}, {latency_ms, LatencyRead}],
                [{type, multiple_read}, {latency_ms, LatencyMultipleRead}],
                [{type, write}, {latency_ms, LatencyWrite}]
            ],

            LatencyTable = clique_status:table(LatencyRows),

            T0 = clique_status:text("---- Node Stats ----"),
            [T0, OpsTable, LatencyTable];
        false ->
            []
    end.

replica_usage() ->
    ["rp-admin replica --replica replica_id --node node\n\n",
        "  Display a replica status on the specific node.\n"].

replica_register() ->
    [["rp-admin", "replica"],              % Cmd
        [],                                           % KeySpecs
        [
            {replica, [{shortname, "r"}, {longname, "replica"},
                {typecast,
                    fun list_to_integer/1}]},
            {node, [{shortname, "n"}, {longname, "node"},
                {typecast,
                    fun clique_typecast:to_node/1}]}
        ],    % FlagSpecs
        fun replica/3].                              % Implementation callback

replica(_CmdBase, [], [{replica, Replica}, {node, Node}]) ->
    replica_output(Node, Replica);
replica(_CmdBase, [], [{replica, Replica}]) ->
    replica_output(node(), Replica).

replica_output(Node, Replica) ->
    {ok, MyRing} = distributed_proxy_ring_manager:get_ring(),
    Owners = distributed_proxy_ring:get_owners(MyRing),

    FetchFun =
        fun (Idx, GroupIndex) ->
            case distributed_proxy_util:safe_rpc(Node, redis_proxy_status, count_backend_request, [Idx, GroupIndex], 10000) of
                {badrpc, _} -> node_down;
                {ok, [{value, CountRequest}]} ->
                    {ok, CountRequest};
                _ ->
                    not_found
            end
        end,

    case lists:keyfind(Replica, 1, Owners) of
        {Replica, GroupId} ->
            Pos = distributed_proxy_ring:index2pos({Replica, GroupId}, MyRing),
            NodeGroup = distributed_proxy_ring:get_nodes(Pos, MyRing),

            case distributed_proxy_util:index_of(Node, NodeGroup) of
                not_found ->
                    [clique_status:alert([clique_status:text("Cannot find the replica on the specific node.")])];
                GroupIndex ->
                    case FetchFun(Replica, GroupIndex) of
                        {ok, Count} ->
                            IndexBin = integer_to_binary(Replica),
                            GroupIndexBin = integer_to_binary(GroupIndex),
                            Proxy = distributed_proxy_util:replica_proxy_reg_name(<<IndexBin/binary, $_, GroupIndexBin/binary>>),
                            distributed_proxy_message:send({Proxy, Node}, [<<"dbsize">>]),
                            DBSize = case distributed_proxy_message:recv() of
                                         {temporarily_unavailable, _} ->
                                             {dbsize, temporarily_unavailable};
                                         {error, Reason} ->
                                             {dbsize, Reason};
                                         {ok, Result} ->
                                             {dbsize, Result}
                                     end,

                            Table = clique_status:table([[{request_count, Count}, DBSize]]),
                            [Table];
                        _ ->
                            []
                    end
            end;
        false ->
            [clique_status:alert([clique_status:text("Cannot find the replica.")])]
    end.

locate_usage() ->
    ["rp-admin locate --key key\n\n",
        "  Display values about the specific key.\n"].

locate_register() ->
    [["rp-admin", "locate"],                          % Cmd
        [],                                           % KeySpecs
        [
            {key, [{shortname, "k"}, {longname, "key"},
                {typecast,
                    fun list_to_binary/1}]}
        ],    % FlagSpecs
        fun locate/3].                               % Implementation callback

locate(_CmdBase, [], [{key, KeyBin}]) ->
    locate_output(KeyBin).

locate_output(KeyBin) ->
    {ok, Ring} = distributed_proxy_ring_manager:get_ring(),
    {Idx, Pos, _GroupId} = ring:locate_key(distributed_proxy_ring:get_chashbin(Ring), KeyBin),
    Nodes = distributed_proxy_ring:get_nodes(Pos, Ring),
    Rows = lists:map(
        fun (Node) ->
            GroupIndex = distributed_proxy_util:index_of(Node, Nodes),
            IndexBin = integer_to_binary(Idx),
            GroupIndexBin = integer_to_binary(GroupIndex),
            Proxy = distributed_proxy_util:replica_proxy_reg_name(<<IndexBin/binary, $_, GroupIndexBin/binary>>),
            {Ret, KeyType} = request_replica({Proxy, Node}, [<<"type">>, KeyBin]),
            {_, Values} = case Ret of
                ok ->
                    case KeyType of
                        <<"string">> ->
                            request_replica({Proxy, Node}, [<<"get">>, KeyBin]);
                        <<"none">> ->
                            {ok, <<"">>};
                        _ ->
                            {error, unknown}
                    end;
                _ ->
                    {error, unknown}
            end,
            [{node, Node}, {type, KeyType}, {values, Values}]
        end, Nodes),

    [clique_status:table(Rows)].

request_replica({Proxy, Node}, Command) ->
    distributed_proxy_message:send({Proxy, Node}, Command),
    case distributed_proxy_message:recv() of
        {temporarily_unavailable, _} ->
            {error, temporarily_unavailable};
        {error, Reason} ->
            {error, Reason};
        {ok, Result} ->
            {ok, Result}
    end.