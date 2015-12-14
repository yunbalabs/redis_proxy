%%%-------------------------------------------------------------------
%%% @author zy
%%% @copyright (C) 2015, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 11. 十二月 2015 8:19 PM
%%%-------------------------------------------------------------------
-module(redis_protocol).
-author("zy").

%% API
-export([start/1, start/3]).
%% callbacks
-export([start_link/4]).
%% private functions
-export([handle_new_connection/5]).
%% behavior
-export([behaviour_info/1]).

%% helper
-export([answer/2]).

-record(connection, {
    socket,
    transport,
    module,
    module_state
}).

-include_lib("eredis/include/eredis.hrl").

%% @doc Start the redis_protocol server.
start(Options) ->
    Port = redis_proxy_config:redis_port(),
    start(Port, redis_handler, Options).

%% Options
%%  timeout, default 30000 (30 seconds) connection timeout
%%  state, [], default state
start(Port, Mod, Options) ->
    {ok, _} = ranch:start_listener(
        ?MODULE, 10,
        ranch_tcp, [{port, Port}],
        ?MODULE, {Mod, Options}),
    ok.

behaviour_info(callbacks) -> [{init, 1}, {handle_redis, 3}, {handle_info, 3}, {terminate, 1}];
behaviour_info(_) -> undefined.

%% @private Spawn a process to handle a new connection.
start_link(ListenerPid, Socket, Transport, {Mod, Options}) ->
    Pid = spawn_link(?MODULE, handle_new_connection, [ListenerPid, Socket, Transport, Mod, Options]),
    {ok, Pid}.

%% @private Handle a new connection.
handle_new_connection(ListenterPid, Socket, Transport, Mod, Options) ->
    {ok, ModState} = Mod:init(Options),
    ok = ranch:accept_ack(ListenterPid),
    Parser = eredis_parser:init(),
    lager:debug("Redis connection ~p coming", [Socket]),

    Connection = read_line(#connection{
        socket = Socket,
        transport = Transport,
        module = Mod, module_state = ModState}, Parser, <<>>),

    lager:debug("Redis connection ~p close", [Socket]),
    Transport:close(Socket),
    Mod:terminate(Connection#connection.module_state).

read_line(#connection{socket=Socket, transport=Transport} = Connection, Parser, Rest) ->
    ok = Transport:setopts(Socket, [binary, {active, once}]),
    handle_message(Connection, Parser, Rest).

handle_message(#connection{socket=Socket, transport=Transport, module=Mod, module_state = ModState} = Connection, Parser, Rest) ->
    receive
        {tcp, Socket, Line} ->
            case parse(Connection, Parser, <<Rest/binary, Line/binary>>) of
                {ok, ConnectionState, NewState} ->
                    read_line(Connection#connection{module_state = ConnectionState}, NewState, <<>>);
                {continue, NewState} ->
                    read_line(Connection, NewState, Rest);
                Oups ->
                    lager:error("Oups le readline. : ~p~p~n", [Oups, Line]),
                    Connection
            end;
        {tcp_closed, _Socket} ->
            lager:debug("TCP connection ~p close", [Socket]),
            Connection;
        ModMsg ->
            case Mod:handle_info({Socket, Transport}, ModMsg, ModState) of
                {continue, ModState2} ->
                    handle_message(Connection#connection{module_state = ModState2}, Parser, Rest);
                {stop, ModState2} ->
                    Connection#connection{module_state = ModState2}
            end
    end.

parse(#connection{socket = Socket, transport=Transport, module_state=HandleState, module=Mod} = Connection, State, Data) ->
    case eredis_parser:parse(State, Data) of
        {ok, Return, NewParserState} ->
            {ok, ConnectionState} = Mod:handle_redis({Socket, Transport}, Return, HandleState),
            {ok, ConnectionState, NewParserState};
        {ok, Return, Rest, NewParserState} ->
            {ok, ConnectionState} = Mod:handle_redis({Socket, Transport}, Return, HandleState),
            parse(Connection#connection{module_state=ConnectionState}, NewParserState, Rest);
        {continue, NewParserState} ->
            {continue, NewParserState};
        {error,unknown_response} -> %% Handling painful old syntax, without prefix
            case get_newline_pos(Data) of
                undefined ->
                    {continue, State};
                Pos ->
                    <<Value:Pos/binary, ?NL, Rest/binary>> = Data,
                    {ok, ConnectionState} = Mod:handle_redis({Socket, Transport}, binary:split(Value, <<$ >>), State),
                    case Rest of
                        <<>> ->
                            {ok, ConnectionState, State};
                        _ ->
                            parse(Connection#connection{module_state=ConnectionState}, State, Rest)
                    end
            end;
        Error ->
            lager:error("Error ~p~n", [Error]),
            {error, Error}
    end.

answer({Socket, Transport}, Answer) ->
    Transport:send(Socket, redis_protocol_encoder:encode(Answer)).


get_newline_pos(B) ->
    case re:run(B, ?NL) of
        {match, [{Pos, _}]} -> Pos;
        nomatch -> undefined
    end.
