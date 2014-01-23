-module(crm_manager_app).

-behaviour(application).

%% Application callbacks
-export([start/0]).
-export([start/2, stop/1]).

%% ===================================================================
%% Application callbacks
%% ===================================================================

start()->
  ok = application:start(log4erl),
  log4erl:conf("priv/l4e.conf"), 
  sync:go(),
  ok = inets:start(),
  ok = application:start(crm_manager).

start(_StartType, _StartArgs) ->
    crm_manager_sup:start_link().

stop(_State) ->
    ok.
