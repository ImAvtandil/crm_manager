%%%-------------------------------------------------------------------
%%% @author S@nR
%%% @copyright (C) 2014, RIA.com
%%% @doc
%%%
%%% @end
%%% Created : $fulldate
%%%  {"status":1,
%%%   "data":
%%%          {"type":"outgoing",
%%%           "number":380969476359,
%%%           "client_name":"o.lishchinskiy-tets Lishchinskiy",
%%%           "client_type":"contact",
%%%           "client_id":"28c08ad5-bc65-0114-8b09-51484d96c55f",
%%%           "call_id":"9b24491b-ec49-a0ee-4a05-52e10be48447"
%%%          }
%%%  }
%%%-------------------------------------------------------------------
-module(number_handler).

-behaviour(gen_fsm).

%% API
-export([start_link/4]).
%-export([get_property/1]).
-export([ringing/1,
		 ringing/3,
         idle/1,
         idle/3,
         busy/1,
         busy/3,
         get_status/1
        ]).

%% gen_fsm callbacks
-export([init/1,
         state_name/2,
         state_name/3,
         handle_event/3,
         handle_sync_event/4,
         handle_info/3,
         terminate/3,
         code_change/4]).

-define(SERVER, ?MODULE).

-record(state, {
		number,
		manager_id,
		create_missed_calls,
		call_id,
		bridge_time,
		call_pid,
		call_info,
		client_info,
		ref,
		group
        }).

%%%===================================================================
%%% API
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc
%% Creates a gen_fsm process which calls Module:init/1 to
%% initialize. To ensure a synchronized start-up procedure, this
%% function does not return until Module:init/1 has returned.
%%
%% @spec start_link() -> {ok, Pid} | ignore | {error, Error}
%% @end
%%--------------------------------------------------------------------
start_link(Number, ManagerId, CreateMissedCalls, Group) ->
        gen_fsm:start_link(
        {local, list_to_atom(integer_to_list(Number))}, 
        ?MODULE, [Number, ManagerId, CreateMissedCalls, Group], []).

%%%===================================================================
%%% gen_fsm callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Whenever a gen_fsm is started using gen_fsm:start/[3,4] or
%% gen_fsm:start_link/[3,4], this function is called by the new
%% process to initialize.
%%
%% @spec init(Args) -> {ok, StateName, State} |
%%                     {ok, StateName, State, Timeout} |
%%                     ignore |
%%                     {stop, StopReason}
%% @end
%%--------------------------------------------------------------------
init([Number, ManagerId, CreateMissedCalls, Group]) ->
     put(state, idle),
     put(number, Number),
     put(manager_id, ManagerId),
     put(create_missed_calls, CreateMissedCalls),
     put(group, Group),
     {ok, idle, #state{
                        number=Number,
                        manager_id=ManagerId,
                        create_missed_calls = CreateMissedCalls,
                        group = Group
                      }}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% There should be one instance of this function for each possible
%% state name. Whenever a gen_fsm receives an event sent using
%% gen_fsm:send_event/2, the instance of this function with the same
%% name as the current state name StateName is called to handle
%% the event. It is also called if a timeout occurs.
%%
%% @spec state_name(Event, State) ->
%%                   {next_state, NextStateName, NextState} |
%%                   {next_state, NextStateName, NextState, Timeout} |
%%                   {stop, Reason, NewState}
%% @end
%%--------------------------------------------------------------------
state_name(_Event, State) ->
        {next_state, state_name, State}.



%idle(_Event, State)->
%     {next_state, idle, State}.
     
ringing(Number)->
	 gen_fsm:sync_send_event(list_to_atom(integer_to_list(Number)), {ringing}).
	 
idle(Number)->	 
     gen_fsm:sync_send_event(list_to_atom(integer_to_list(Number)), {idle}).
     
busy(Number)->	 
     gen_fsm:sync_send_event(list_to_atom(integer_to_list(Number)), {busy}).

get_status(Number)->
     gen_fsm:sync_send_event(list_to_atom(integer_to_list(Number)), {get_status}).
%%--------------------------------------------------------------------
%% @private
%% @doc
%% There should be one instance of this function for each possible
%% state name. Whenever a gen_fsm receives an event sent using
%% gen_fsm:sync_send_event/[2,3], the instance of this function with
%% the same name as the current state name StateName is called to
%% handle the event.
%%
%% @spec state_name(Event, From, State) ->
%%                   {next_state, NextStateName, NextState} |
%%                   {next_state, NextStateName, NextState, Timeout} |
%%                   {reply, Reply, NextStateName, NextState} |
%%                   {reply, Reply, NextStateName, NextState, Timeout} |
%%                   {stop, Reason, NewState} |
%%                   {stop, Reason, Reply, NewState}
%% @end
%%--------------------------------------------------------------------
state_name(_Event, _From, State) ->
        Reply = ok,
        {reply, Reply, state_name, State}.

%%----------------------------------------------------------------------
%% Idle state
%%----------------------------------------------------------------------
idle({ringing}, _From, State)->
      Reply = ok,
      put(state, ringing),
      {reply, Reply, ringing, State};
idle({get_status}, _From, State)->
      Status = {struct, [{status, 0}, {data, {struct, []}}]},
      Reply = iolist_to_binary(mochijson2:encode(Status)),
      {reply, Reply, idle, State};      
idle(_Event, _From, State)->
      Reply = {error, invalid_message},
      {reply, Reply, idle, State}.

%%----------------------------------------------------------------------
%% Ringing state
%%----------------------------------------------------------------------
ringing({idle}, _From, State)->
	  Reply = ok,
      put(state, idle),
      {reply, Reply, idle, State};
ringing({busy}, _From, State)->
	  Reply = ok,
      put(state, busy),
      {reply, Reply, busy, State};
ringing({get_status}, _From, 
      #state{
             call_id = CallId, 
             client_info = ClientInfo
             } = State
      )->
      Status = {struct, [{status, 1}, {data, {struct, [
                                                         {type, undefined},
                                                         {number, undefined},
                                                         {client_name, undefined},
                                                         {client_type, undefined},
                                                         {client_id, ClientInfo},
                                                         {call_id, CallId}
                                                       ]
                                                      }}]},
      Reply = iolist_to_binary(mochijson2:encode(Status)),
      {reply, Reply, ringing, State};      
ringing(_Event, _From, State)->
      Reply = {error, invalid_message},
      {reply, Reply, ringing, State}.

%%----------------------------------------------------------------------
%% Busy state
%%----------------------------------------------------------------------
busy({idle}, _From, State)->
	  Reply = ok,
      put(state, idle),
      {reply, Reply, idle, State};
busy({get_status}, _From, State)->
      Reply = busy,
      {reply, Reply, busy, State};      
busy(_Event, _From, State)->      
	  Reply = {error, invalid_message},
      {reply, Reply, busy, State}.      
      
      
%%--------------------------------------------------------------------
%% @private
%% @doc
%% Whenever a gen_fsm receives an event sent using
%% gen_fsm:send_all_state_event/2, this function is called to handle
%% the event.
%%
%% @spec handle_event(Event, StateName, State) ->
%%                   {next_state, NextStateName, NextState} |
%%                   {next_state, NextStateName, NextState, Timeout} |
%%                   {stop, Reason, NewState}
%% @end
%%--------------------------------------------------------------------
handle_event(_Event, StateName, State) ->
        {next_state, StateName, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Whenever a gen_fsm receives an event sent using
%% gen_fsm:sync_send_all_state_event/[2,3], this function is called
%% to handle the event.
%%
%% @spec handle_sync_event(Event, From, StateName, State) ->
%%                   {next_state, NextStateName, NextState} |
%%                   {next_state, NextStateName, NextState, Timeout} |
%%                   {reply, Reply, NextStateName, NextState} |
%%                   {reply, Reply, NextStateName, NextState, Timeout} |
%%                   {stop, Reason, NewState} |
%%                   {stop, Reason, Reply, NewState}
%% @end
%%--------------------------------------------------------------------
handle_sync_event(_Event, _From, StateName, State) ->
        Reply = ok,
        {reply, Reply, StateName, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% This function is called by a gen_fsm when it receives any
%% message other than a synchronous or asynchronous event
%% (or a system message).
%%
%% @spec handle_info(Info,StateName,State)->
%%                   {next_state, NextStateName, NextState} |
%%                   {next_state, NextStateName, NextState, Timeout} |
%%                   {stop, Reason, NewState}
%% @end
%%--------------------------------------------------------------------
%handle_info(get_status, StateName, State) ->
        
handle_info(_Info, StateName, State) ->
        {next_state, StateName, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% This function is called by a gen_fsm when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any
%% necessary cleaning up. When it returns, the gen_fsm terminates with
%% Reason. The return value is ignored.
%%
%% @spec terminate(Reason, StateName, State) -> void()
%% @end
%%--------------------------------------------------------------------
terminate(_Reason, _StateName, _State) ->
        ok.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Convert process state when code is changed
%%
%% @spec code_change(OldVsn, StateName, State, Extra) ->
%%                   {ok, StateName, NewState}
%% @end
%%--------------------------------------------------------------------
code_change(_OldVsn, StateName, State, _Extra) ->
        {ok, StateName, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================
