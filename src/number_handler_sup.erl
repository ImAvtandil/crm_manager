-module(number_handler_sup).

-behaviour(supervisor).


%% API
-export([start_link/0]).


%% Supervisor callbacks
-export([init/1]).


%% Helper macro for declaring children of supervisor
-define(CHILD(I, Type), {I, {I, start_link, []}, permanent, 5000, Type, [I]}).

%% ===================================================================
%% API functions
%% ===================================================================

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).
    
    
init([]) ->
      {ok, CRMBrokerPid} = crm_broker:get_broker(),
      Children = [ child_spec(Item) || Item <- crm_broker:get_managers(CRMBrokerPid) ], 
      crm_broker:stop(CRMBrokerPid),
      {ok, { {one_for_one, 5, 10}, Children} }.   


child_spec(Manager) ->
    {<<"asterisk_ext_c">>, NumberBin} = lists:keyfind(<<"asterisk_ext_c">>, 1, Manager),
    {<<"id">>, ManagerId} = lists:keyfind(<<"id">>, 1, Manager),
    CreateMissedCalls = case lists:keyfind(<<"asterisk_missed_calls_c">>, 1, Manager) of
        {<<"asterisk_missed_calls_c">>, MissedCallsFlag} ->
            case MissedCallsFlag of
                <<"0">> ->
                    false;
                _ ->
                    true
            end;
        _ ->
            true
        end,
    Group = case lists:keyfind(<<"asterisk_call_group_c">>, 1, Manager) of
                {<<"asterisk_call_group_c">>, GroupName} ->
                        case GroupName of
                                <<"0">> ->
                                        none;
                                Var ->
                                        list_to_atom(binary_to_list(Var))
                        end;
                _ ->
                    none
    end,
    Number = list_to_integer(binary_to_list(NumberBin)),
        {{number, Number},
                {number_handler, start_link, [Number, ManagerId, CreateMissedCalls, Group]},
                permanent,
                1000,
                worker,
                []
        }.
