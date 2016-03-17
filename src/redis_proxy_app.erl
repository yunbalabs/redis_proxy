-module(redis_proxy_app).

-behaviour(application).

%% Application callbacks
-export([start/2, stop/1]).

%% ===================================================================
%% Application callbacks
%% ===================================================================

start(_StartType, _StartArgs) ->
    CommandTypes = [{"get", r}, {"set", w}, {"mget", mr}, {"dbsize", c}],

    ok = redis_protocol:start([CommandTypes]),
    clique:register([redis_proxy_cli]),
    redis_proxy_sup:start_link().

stop(_State) ->
    ok.
