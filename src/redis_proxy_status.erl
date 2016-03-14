%%%-------------------------------------------------------------------
%%% @author zy
%%% @copyright (C) 2016, <COMPANY>
%%% @doc
%%%
%%% @end
%%% Created : 07. 三月 2016 2:14 PM
%%%-------------------------------------------------------------------
-module(redis_proxy_status).
-author("zy").

-behaviour(gen_server).

%% API
-export([start_link/0,
    sample_latency/1, stat_latency/2,
    count_frontend_request/1, count_frontend_response/1,
    stat_frontend_request/1, stat_frontend_response/1,
    count_backend_request/2,
    register_backend_request/2, stat_backend_request/2, unregister_backend_request/2,
    register/3, update/2, unregister/1]).

%% gen_server callbacks
-export([init/1,
    handle_call/3,
    handle_cast/2,
    handle_info/2,
    terminate/2,
    code_change/3]).

-define(SERVER, ?MODULE).

-define(LATENCY_NAME, latency).
-define(FRONTEND_REQUEST_NAME, frontend_request).
-define(FRONTEND_RESPONSE_NAME, frontend_response).
-define(BACKEND_REQUEST_NAME, backend_request).
-define(BACKEND_RESPONSE_NAME, backend_response).

-record(state, {
    enable,
    report_interval
}).

%%%===================================================================
%%% API
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc
%% Starts the server
%%
%% @end
%%--------------------------------------------------------------------
-spec(start_link() ->
    {ok, Pid :: pid()} | ignore | {error, Reason :: term()}).
start_link() ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

sample_latency(read) ->
    exometer:get_value([?LATENCY_NAME, read], value);
sample_latency(write) ->
    exometer:get_value([?LATENCY_NAME, write], value).

stat_latency(read, Latency) ->
    update([?LATENCY_NAME, read], Latency);
stat_latency(multiple_read, Latency) ->
    update([?LATENCY_NAME, multiple_read], Latency);
stat_latency(write, Latency) ->
    update([?LATENCY_NAME, write], Latency).

count_frontend_request(read) ->
    exometer:get_value([?FRONTEND_REQUEST_NAME, read], value);
count_frontend_request(write) ->
    exometer:get_value([?FRONTEND_REQUEST_NAME, write], value).

count_frontend_response(read) ->
    exometer:get_value([?FRONTEND_RESPONSE_NAME, read], value);
count_frontend_response(write) ->
    exometer:get_value([?FRONTEND_RESPONSE_NAME, write], value).

stat_frontend_request(read) ->
    update([?FRONTEND_REQUEST_NAME, read], 1);
stat_frontend_request(write) ->
    update([?FRONTEND_REQUEST_NAME, write], 1).

stat_frontend_response(read) ->
    update([?FRONTEND_RESPONSE_NAME, read], 1);
stat_frontend_response(write) ->
    update([?FRONTEND_RESPONSE_NAME, write], 1).

count_backend_request(SlotIndex, ReplicaIndex) ->
    exometer:get_value([?BACKEND_REQUEST_NAME, SlotIndex, ReplicaIndex], value).

register_backend_request(SlotIndex, ReplicaIndex) ->
    register([?BACKEND_REQUEST_NAME, SlotIndex, ReplicaIndex], counter, [{slot, {from_name, 2}}, {replica, {from_name, 3}}]).

stat_backend_request(SlotIndex, ReplicaIndex) ->
    update([?BACKEND_REQUEST_NAME, SlotIndex, ReplicaIndex], 1).

unregister_backend_request(SlotIndex, ReplicaIndex) ->
    ?MODULE:unregister([?BACKEND_REQUEST_NAME, SlotIndex, ReplicaIndex]).

-spec(register(Name :: list(), Type :: atom(), Extra :: list()) -> ok).
register(Name, Type, Extra) ->
    gen_server:call(?MODULE, {register, Name, Type, Extra}).

-spec(update(Name :: list(), Value :: any()) -> ok).
update(Name, Value) ->
    exometer:update(Name, Value),
    ok.

-spec(unregister(Name :: list()) -> ok).
unregister(Name) ->
    gen_server:cast(?MODULE, {unregister, Name}).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Initializes the server
%%
%% @spec init(Args) -> {ok, State} |
%%                     {ok, State, Timeout} |
%%                     ignore |
%%                     {stop, Reason}
%% @end
%%--------------------------------------------------------------------
-spec(init(Args :: term()) ->
    {ok, State :: #state{}} | {ok, State :: #state{}, timeout() | hibernate} |
    {stop, Reason :: term()} | ignore).
init([]) ->
    case redis_proxy_config:enable_stat() of
        true ->
            ReportInterval = redis_proxy_config:stat_interval(),

            ok = register_gauge_item([?LATENCY_NAME, read], ReportInterval, [{type, {from_name, 2}}]),
            ok = register_gauge_item([?LATENCY_NAME, multiple_read], ReportInterval, [{type, {from_name, 2}}]),
            ok = register_gauge_item([?LATENCY_NAME, write], ReportInterval, [{type, {from_name, 2}}]),
            ok = register_counter_item([?FRONTEND_REQUEST_NAME, read], ReportInterval, [{type, {from_name, 2}}]),
            ok = register_counter_item([?FRONTEND_REQUEST_NAME, write], ReportInterval, [{type, {from_name, 2}}]),
            ok = register_counter_item([?FRONTEND_RESPONSE_NAME, read], ReportInterval, [{type, {from_name, 2}}]),
            ok = register_counter_item([?FRONTEND_RESPONSE_NAME, write], ReportInterval, [{type, {from_name, 2}}]),

            {ok, #state{enable = true, report_interval = ReportInterval}};
        false ->
            {ok, #state{enable = false}}
    end.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling call messages
%%
%% @end
%%--------------------------------------------------------------------
-spec(handle_call(Request :: term(), From :: {pid(), Tag :: term()},
        State :: #state{}) ->
    {reply, Reply :: term(), NewState :: #state{}} |
    {reply, Reply :: term(), NewState :: #state{}, timeout() | hibernate} |
    {noreply, NewState :: #state{}} |
    {noreply, NewState :: #state{}, timeout() | hibernate} |
    {stop, Reason :: term(), Reply :: term(), NewState :: #state{}} |
    {stop, Reason :: term(), NewState :: #state{}}).
handle_call(_Request, _From, State = #state{enable = false}) ->
    {reply, ok, State};

handle_call({register, Name, counter, Extra}, _From, State = #state{report_interval = ReportInterval}) ->
    Result = register_counter_item(Name, ReportInterval, Extra),
    {reply, Result, State};

handle_call(_Request, _From, State) ->
    {reply, ok, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling cast messages
%%
%% @end
%%--------------------------------------------------------------------
-spec(handle_cast(Request :: term(), State :: #state{}) ->
    {noreply, NewState :: #state{}} |
    {noreply, NewState :: #state{}, timeout() | hibernate} |
    {stop, Reason :: term(), NewState :: #state{}}).
handle_cast(_Request, State = #state{enable = false}) ->
    {noreply, State};

handle_cast({unregister, Name}, State) ->
    exometer_report:unsubscribe_all(exometer_report_influxdb, Name),
    exometer:delete(Name),
    {noreply, State};

handle_cast(_Request, State) ->
    {noreply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling all non call/cast messages
%%
%% @spec handle_info(Info, State) -> {noreply, State} |
%%                                   {noreply, State, Timeout} |
%%                                   {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
-spec(handle_info(Info :: timeout() | term(), State :: #state{}) ->
    {noreply, NewState :: #state{}} |
    {noreply, NewState :: #state{}, timeout() | hibernate} |
    {stop, Reason :: term(), NewState :: #state{}}).
handle_info(_Info, State) ->
    {noreply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% This function is called by a gen_server when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any
%% necessary cleaning up. When it returns, the gen_server terminates
%% with Reason. The return value is ignored.
%%
%% @spec terminate(Reason, State) -> void()
%% @end
%%--------------------------------------------------------------------
-spec(terminate(Reason :: (normal | shutdown | {shutdown, term()} | term()),
        State :: #state{}) -> term()).
terminate(_Reason, _State) ->
    ok.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Convert process state when code is changed
%%
%% @spec code_change(OldVsn, State, Extra) -> {ok, NewState}
%% @end
%%--------------------------------------------------------------------
-spec(code_change(OldVsn :: term() | {down, term()}, State :: #state{},
        Extra :: term()) ->
    {ok, NewState :: #state{}} | {error, Reason :: term()}).
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================
register_gauge_item(Name, Interval, Extra) ->
    ok = exometer:re_register(Name, gauge, []),
    exometer_report:subscribe(exometer_report_influxdb, Name, value, Interval, Extra).

register_counter_item(Name, Interval, Extra) ->
    ok = exometer:re_register(Name, counter, []),
    exometer_report:subscribe(exometer_report_influxdb, Name, value, Interval, Extra).