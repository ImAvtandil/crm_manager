
-module(crm_manager_sup).

-behaviour(supervisor).

%% API
-export([start_link/0]).
-export([create_crm_broker/0]).

%% Supervisor callbacks
-export([init/1]).

%% Helper macro for declaring children of supervisor
-define(CHILD(I, Type), {I, {I, start_link, []}, permanent, 5000, Type, [I]}).

%% ===================================================================
%% API functions
%% ===================================================================

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).
    
create_crm_broker() ->
    %{ok, CrmServer}       = application:get_env(crm_rest_server),
    %{ok, CrmUser}         = application:get_env(crm_user),
    %{ok, CrmPassword}     = application:get_env(crm_password),
	supervisor:start_child(crm_broker_sup, []).
    

%% ===================================================================
%% Supervisor callbacks
%% ===================================================================
init([crm_broker])->
        Children =
                [
					{   undefined,                                   % Id       = internal id
                        {crm_broker, start_link, []},            % StartFun = {M, F, A}
                        temporary,                               % Restart  = permanent | transient | temporary
                        2000,                                    % Shutdown = brutal_kill | int() >= 0 | infinity
                        worker,                                  % Type     = worker | supervisor
                        []                                       % Modules  = [Module] | dynamic
					}
                ],
    {ok, {{simple_one_for_one, 1000, 1000}, Children}};


init([]) ->
	%{ok, CrmServer}       = application:get_env(crm_rest_server),
    %{ok, CrmUser}         = application:get_env(crm_user),
    %{ok, CrmPassword}     = application:get_env(crm_password),
	Children =[ 
	            %{crm_broker,
                %          {crm_broker, start_link, [CrmServer, CrmUser, CrmPassword]},
                %          temporary,
                %          1000,
                %          worker,
                %          [crm_broker]
                %},
                {crm_broker_recorder,
                          {crm_broker_recorder, start_link, []},
                          permanent,
                          1000,
                          worker,
                          [crm_broker_recorder]
                }
                ,{
                  crm_broker_sup,
                         {supervisor, start_link, [{local, crm_broker_sup}, ?MODULE, [crm_broker]]},
                         permanent,                               % Restart  = permanent | transient | temporary
                         infinity,                                % Shutdown = brutal_kill | int() >= 0 | infinity
                         supervisor,                              % Type     = worker | supervisor
                         []                                       % Modules  = [Module] | dynamic
                }
                ,{number_handler_sup,
				    {number_handler_sup, start_link, []},
					permanent,                               % Restart  = permanent | transient | temporary
					infinity,                                % Shutdown = brutal_kill | int() >= 0 | infinity
					supervisor,                              % Type     = worker | supervisor
					[number_handler_sup]                     % Modules  = [Module] | dynamic
				}
               ],
    {ok, { {one_for_one, 5, 10}, Children} }.

