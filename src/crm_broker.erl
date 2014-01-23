-module(crm_broker).

-behaviour(gen_server).
-include_lib("stdlib/include/ms_transform.hrl").

%% API
-export([start_link/0]).
-export([crm_request/3, 
         get_crm_url/0,
         get_session_key/0,
         find_or_create_client/2,
         
         entry_list_to_kv/1,
         get_contact/1,
         get_lead/1,
         create_call/5,
         modify_call/2,
         create_lead/2,
         
         get_managers/1,
         get_crm_contact/2,
         stop/1,
         get_broker/0
        ]).

%% gen_server callbacks
-export([init/1,
         handle_call/3,
         handle_cast/2,
         handle_info/2,
         terminate/2,
         code_change/3]).

-define(CLIENTS_TABLE, crm_clients).

-define(RELOGIN_TIME, 600000).

-record(state, {
    crm_user,
    crm_passwd_hash,
    session_key,
    crm_rest_server
}).

-record(entry, {
    client_number,
    ref,
    pid
}).

-include("ast_mgr.hrl").

%%%===================================================================
%%% API
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc
%% Starts the server
%%
%% @spec start_link() -> {ok, Pid} | ignore | {error, Error}
%% @end
%%--------------------------------------------------------------------
start_link() ->
    {ok, CrmServer}       = application:get_env(crm_rest_server),
    {ok, CrmUser}         = application:get_env(crm_user),
    {ok, CrmPassword}     = application:get_env(crm_password),
	gen_server:start_link(
	 %{local, ?MODULE},
	 ?MODULE, [CrmServer, CrmUser, CrmPassword], []
	 ).

stop(Pid)->
   gen_server:call(Pid, stop_broker).

get_broker()->
    crm_manager_sup:create_crm_broker().
   
crm_request(Url, Method, RestData) ->
	Data = [
			{"method", Method}, 
			{"input_type", "JSON"}, 
			{"response_type", "JSON"}, 
			{"rest_data", binary_to_list(iolist_to_binary(mochijson2:encode(RestData)))}
		   ],
    log4erl:debug(rest, "Rest data:~n~p", [Data]),
    %Resp = rest_client:request(post, Url, Data),
    Resp = case rest_client:request(post, Url, Data) of 
        {ok, Payload} ->
            Payload;
        {undefined, _Payload} ->
            mochijson2:decode(_Payload, [{format, proplist}]);
        {timeout, _Payload}->
            mochijson2:decode(_Payload, [{format, proplist}]);
        {error, Message} ->
            log4erl:debug(rest, "Error_rest:~n~p", [Message]),
            log4erl:debug(rest, "New Requet:~n"),
            io:format("CRM Request error~n"),
            io:format(Message),
            io:format("~n"),
            timer:sleep(100),
            crm_request(Url, Method, RestData)
            
    end,
    log4erl:debug(rest, "Rest response:~n~p", [Resp]),
    Resp.

%% -----------------------------------------------------------------------------
%% @spec get_contact(ClientNumber::integer()) -> {ok, client_info()}|{fail, Reasone::string()}
%% @doc
%% Search contact in crm
%% @end
%% -----------------------------------------------------------------------------
get_crm_contact(Pid, ClientNumber)->
	 gen_server:call(Pid, {get_crm_contact, ClientNumber}).

get_contact(ClientNumber) ->
    {ok, SessionKey} = crm_broker:get_session_key(),
    {ok, Url} = crm_broker:get_crm_url(),
    NumBin = list_to_binary(integer_to_list(ClientNumber)),
    RestData = [
    {<<"session">>,SessionKey},
    {<<"module_name">>,<<"Contacts">>},
    {<<"query">>,  <<"contacts.phone_home=", NumBin/binary, 
    " or contacts.phone_mobile=", NumBin/binary,
    " or contacts.phone_work=", NumBin/binary,
    " or contacts.phone_other=", NumBin/binary,
    " or contacts.phone_fax=", NumBin/binary>>},
    {<<"order_by">>,null},
    {<<"offset">>,0},
    {<<"select_fields">>,[<<"id">>,<<"name">>]},
    {<<"link_name_to_fields_array">>,[]},
    {<<"max_results">>,20},
    {<<"deleted">>,<<"FALSE">>}
    ],
    Resp = crm_broker:crm_request(Url, "get_entry_list", RestData),
    case lists:keyfind(<<"entry_list">>, 1, Resp) of
		false ->
			{fail, no_entry_list};
        {<<"entry_list">>,[]} -> 
            {fail, empty_entry_list};
        {<<"entry_list">>, [First|_]} -> 
            {<<"name_value_list">>, Values} = lists:keyfind(<<"name_value_list">>, 1, First),
            Name = extract_from_name_value_list(<<"name">>, Values),
            Id = extract_from_name_value_list(<<"id">>, Values),
            {ok, #client_info{client_id = Id, client_name = Name, client_type = contact}}
	end.



create_lead(ClientNumber, Manager_id) ->
    {ok, SessionKey} = crm_broker:get_session_key(),
    {ok, Url} = crm_broker:get_crm_url(),
    NumBin = list_to_binary(integer_to_list(ClientNumber)),
    RestData = [
    {<<"session">>,SessionKey},
    {<<"module_name">>,<<"Leads">>},
    {<<"name_value_list">>, 
        {struct,
         [
          {<<"assigned_user_id">>,Manager_id},
          {<<"first_name">>, <<"Новый предв. контакт">>},
          {<<"phone_work">>,NumBin}
         ]
        }
    }],
    crm_broker:crm_request(Url, "set_entry", RestData).
%%--------------------------------------------------------------------
%% @doc
%% Starts the server
%%
%% @spec start_link() -> {ok, Pid} | ignore | {error, Error}
%% @end
%%--------------------------------------------------------------------	
get_lead(ClientNumber) ->
    {ok, SessionKey} = crm_broker:get_session_key(),
    {ok, Url} = crm_broker:get_crm_url(),
    NumBin = list_to_binary(integer_to_list(ClientNumber)),
    RestData = [
    {<<"session">>,SessionKey},
    {<<"module_name">>,<<"Leads">>},
    {<<"query">>,  <<"leads.phone_home=", NumBin/binary, 
    " or leads.phone_mobile=", NumBin/binary,
    " or leads.phone_work=", NumBin/binary,
    " or leads.phone_other=", NumBin/binary,
    " or leads.phone_fax=", NumBin/binary>>},
    {<<"order_by">>,null},
    {<<"offset">>,0},
    {<<"select_fields">>,[<<"id">>,<<"name">>]},
    {<<"link_name_to_fields_array">>,[]},
    {<<"max_results">>,20},
    {<<"deleted">>,<<"FALSE">>}
    ],
    Resp = crm_broker:crm_request(Url, "get_entry_list", RestData),
    case lists:keyfind(<<"entry_list">>, 1, Resp) of
		false ->
			{fail, no_entry_list};
        {<<"entry_list">>,[]} -> 
            {fail, empty_entry_list};
        {<<"entry_list">>, [First|_]} -> 
            {<<"name_value_list">>, Values} = lists:keyfind(<<"name_value_list">>, 1, First),
            Name = extract_from_name_value_list(<<"name">>, Values),
            Id = extract_from_name_value_list(<<"id">>, Values),
            {ok, #client_info{client_id = Id, client_name = Name, client_type = lead}}
	end.

%% -----------------------------------------------------------------------------
%% @spec create_call(CallInfo::call_info(), ClientInfo::client_info(), ManagerId::binary(), DateTime::datetime(), Status::status()) -> {ok, client_info()}|{fail, Reasone::string()}
%% status() = missed | held
%% @doc
%% 
%% @end
%% -----------------------------------------------------------------------------
create_call(#call_info{type = CallType, client_number = ClientNumber}, 
            #client_info{client_id = ClientId, client_type = ClientType}, 
            ManagerId, CallDate, Status) ->
    {ok, SessionKey} = crm_broker:get_session_key(),
    {ok, Url} = crm_broker:get_crm_url(),
    NumBin = list_to_binary(integer_to_list(ClientNumber)),
    CallDateFormated = list_to_binary(dh_date:format("Y-m-d H:i:s", CallDate)),
    CallDirection = case CallType of
        outgoing ->
            <<"Outbound">>;
        incoming ->
            <<"Inbound">>
    end,
    {CallName, CallStatus} = case Status of
        missed ->
            case CallType of
				outgoing ->
					{<<"Непринятый звонок">>, <<"Not Held">>};
				incoming ->
				    {<<"Пропущеный звонок">>, <<"Missed">>}
			end;
        held ->
            {<<"Успешный звонок">>, <<"In Limbo">>}
    end,
    ParentType = case ClientType of
        contact ->
            <<"Contacts">>;
        lead ->
            <<"Leads">>
    end,
    RestData = [
            {<<"session">>, SessionKey},
            {<<"module_name">>, <<"Calls">>},
            {<<"name_value_list">>, 
             {struct, [
                        {<<"name">>, CallName},
                        {<<"date_start">>, CallDateFormated},
                        {<<"duration_hours">>, <<"0">>},
                        {<<"duration_minutes">>, <<"0">>},
                        {<<"assigned_user_id">>, ManagerId},
                        {<<"direction">>, CallDirection},
                        {<<"status">>, CallStatus},
                        {<<"update_vcal">>, <<"false">>},
                        {<<"asterisk_caller_id_c">>, NumBin},
                        {<<"parent_type">>, ParentType},
                        {<<"parent_id">>, ClientId}
                      ]
             }
            }],  
    log4erl:debug("Try create call ~p", [RestData]),
    {<<"id">>, CallId} = lists:keyfind(<<"id">>, 1, crm_broker:crm_request(Url, "set_entry", RestData)),
    log4erl:debug("Success create call ~p", [CallId]),
    Rel1RestData = [
            {<<"session">>, SessionKey},
            {<<"module_name">>, ParentType},
            {<<"module_id">>, ClientId},
            {<<"link_field_name">>, <<"calls">>},
            {<<"related_ids">>, CallId}
    ],
    log4erl:debug("Try relate call ~p to ~p id ~p", [CallId, ParentType, ClientId]),
    crm_broker:crm_request(Url, "set_relationship", Rel1RestData),
    log4erl:debug("Success relate call ~p to ~p id ~p", [CallId, ParentType, ClientId]),
    Rel2RestData = [
            {<<"session">>, SessionKey},
            {<<"module_name">>, <<"Users">>},
            {<<"module_id">>, ManagerId},
            {<<"link_field_name">>, <<"calls">>},
            {<<"related_ids">>, CallId}
    ],
    log4erl:debug("Try relate call ~p to manager ~p", [CallId, ManagerId]),
    crm_broker:crm_request(Url, "set_relationship", Rel2RestData),
    log4erl:debug("Success relate call ~p to manager ~p", [CallId, ManagerId]),
    {ok, CallId}.

modify_call(CallId, {_, {Hours, Minutes, _}}) ->
    {ok, SessionKey} = crm_broker:get_session_key(),
    {ok, Url} = crm_broker:get_crm_url(),
    HoursBin = list_to_binary(integer_to_list(Hours)),
    MinutesBin = list_to_binary(integer_to_list(Minutes)),
    RestData = [
            {<<"session">>, SessionKey},
            {<<"module_name">>, <<"Calls">>},
            {<<"name_value_list">>, 
             {struct, [
                        {<<"id">>, CallId},
                        {<<"duration_hours">>, HoursBin},
                        {<<"duration_minutes">>, MinutesBin},
                        {<<"status">>, <<"Held">>},
                        {<<"update_vcal">>, <<"false">>}
                      ]
             }
            }],
    {<<"id">>, CallId} = lists:keyfind(<<"id">>, 1, crm_broker:crm_request(Url, "set_entry", RestData)).
            
%% crm_manager:get_managers().
get_managers(Pid)->
   gen_server:call(Pid, {get_managers}).


%% crm_manager:find_or_create_client(380932791745).
find_or_create_client(ClientNumber, ManagerId) ->
    {ok,Pid_} = case ets:lookup(?CLIENTS_TABLE, ClientNumber) of
        [] -> 
            gen_server:call(?MODULE, {find_or_create_client, ClientNumber, ManagerId});
        [#entry{pid = Pid}] -> 
            {ok, Pid}
    end,
    {ok, Pid_}.

get_crm_url() ->
    gen_server:call(?MODULE, get_crm_url).
    
get_session_key() ->
    gen_server:call(?MODULE, get_session_key).
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
init([CrmServer, CrmUser, CrmPassword]) ->
    put(crm_server, CrmServer),
    self() ! login,
    timer:send_interval(?RELOGIN_TIME, login),
    {ok, #state{crm_user = CrmUser, crm_passwd_hash = md5:md5_hex(CrmPassword), crm_rest_server = CrmServer}}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling call messages
%%
%% @spec handle_call(Request, From, State) ->
%%                                   {reply, Reply, State} |
%%                                   {reply, Reply, State, Timeout} |
%%                                   {noreply, State} |
%%                                   {noreply, State, Timeout} |
%%                                   {stop, Reason, Reply, State} |
%%                                   {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------	
handle_call(get_crm_url, _From, #state{crm_rest_server = CrmUrl} = State) ->
    {reply, {ok, CrmUrl}, State};
handle_call(get_session_key, _From, #state{session_key = SessionKey} = State) ->
    {reply, {ok, SessionKey}, State};

handle_call({find_or_create_client, ClientNumber, ManagerId}, _From, State) ->
	Pid = case ets:lookup(?CLIENTS_TABLE, ClientNumber) of
	[] ->
		{ok, Pid_} = ast_manager_sup:create_client(ClientNumber, ManagerId),
		Ref = erlang:monitor(process, Pid_),
		ets:insert(?CLIENTS_TABLE, #entry{client_number = ClientNumber, ref = Ref, pid = Pid_}),
		Pid_;
	[#entry{pid = Pid_}] ->
		Pid_
	end,
	{reply, {ok, Pid}, State};

handle_call({get_crm_contact, ClientNumber}, _From, #state{crm_rest_server = Url, session_key = SessionKey} = State) ->
    put(client_number, ClientNumber),
    NumBin = list_to_binary(integer_to_list(ClientNumber)),
    RestData = [
    {<<"session">>,SessionKey},
    {<<"module_name">>,<<"Contacts">>},
    {<<"query">>,  <<"contacts.phone_home=", NumBin/binary, 
    " or contacts.phone_mobile=", NumBin/binary,
    " or contacts.phone_work=", NumBin/binary,
    " or contacts.phone_other=", NumBin/binary,
    " or contacts.phone_fax=", NumBin/binary>>},
    {<<"order_by">>,null},
    {<<"offset">>,0},
    {<<"select_fields">>,[<<"id">>,<<"name">>]},
    {<<"link_name_to_fields_array">>,[]},
    {<<"max_results">>,20},
    {<<"deleted">>,<<"FALSE">>}
    ],
    Resp = crm_request(Url, "get_entry_list", RestData),
    Reply = case lists:keyfind(<<"entry_list">>, 1, Resp) of
	   false ->
	         case lists:keyfind(error, 1, Resp) of
				false->  
					{fail, no_entry_list};
				error->
					{fail, error}
			 end;
       {<<"entry_list">>,[]} -> 
           {fail, empty_entry_list};
       {<<"entry_list">>, [First|_]} -> 
            {<<"name_value_list">>, Values} = lists:keyfind(<<"name_value_list">>, 1, First),
            Name = extract_from_name_value_list(<<"name">>, Values),
            Id = extract_from_name_value_list(<<"id">>, Values),
            {ok, #client_info{client_id = Id, client_name = Name, client_type = contact}}
	end,
    %Reply = Resp,
    {reply, Reply, State};


handle_call({get_managers}, _From, #state{crm_rest_server = Url, session_key = SessionKey} = State) ->
    RestData = [
    {<<"session">>,SessionKey},
    {<<"module_name">>,<<"Users">>},
    {<<"query">>,  <<"asterisk_ext_c!='' AND asterisk_inbound_c=1 AND asterisk_call_group_c='testing'">>},
    {<<"order_by">>,<<"asterisk_ext_c DESC">>},
    {<<"offset">>,0},
    {<<"select_fields">>,[<<"id">>,<<"asterisk_ext_c">>,<<"asterisk_missed_calls_c">>, <<"asterisk_call_group_c">>]},
    {<<"link_name_to_fields_array">>,[]},
    {<<"max_results">>,100},
    {<<"deleted">>,<<"FALSE">>}
    ],
    Resp = crm_request(Url, "get_entry_list", RestData),
    Reply = case lists:keyfind(<<"entry_list">>, 1, Resp) of
		false ->
			{fail, no_entry_list};
        {<<"entry_list">>,[]} -> 
            {fail, empty_entry_list};
        {<<"entry_list">>, List} -> 
            entry_list_to_kv(List)
	end,
    {reply, Reply, State};
    
handle_call(stop_broker, _From, State) ->
    %io:format("Stop process ~p for call"),
    {stop, normal, ok, State};


handle_call(_Request, _From, State) ->
    Reply = ok,
    {reply, Reply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling cast messages
%%
%% @spec handle_cast(Msg, State) -> {noreply, State} |
%%                                  {noreply, State, Timeout} |
%%                                  {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
handle_cast(_Msg, State) ->
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
handle_info(login, #state{crm_user = CrmUser, crm_passwd_hash = PasswordHash, crm_rest_server = CrmServer} = State) ->
    RestData = [{<<"user_auth">>, 
        [{<<"user_name">>, CrmUser},
         {<<"password">>, PasswordHash}
        ]
     },
     {<<"name_value_list">>, 
        [
         [{<<"name">>,<<"notifyonsave">>},
          {<<"value">>,<<"true">>}
         ]
        ]
     }],
	case lists:keyfind(<<"id">>, 1, crm_request(CrmServer, "login", RestData)) of
		false ->
			{stop, {empty_session_id}, State};
        {<<"id">>, SessionKey} ->             
            put(session_key, SessionKey),
			{noreply, State#state{session_key = SessionKey}}
	end;
handle_info({'DOWN', _, process, Client, _Reason}, #state{} = State) ->
    ets:select_delete(?CLIENTS_TABLE, ets:fun2ms(fun(#entry{pid = Pid}) when Client == Pid -> true end)),
    {noreply, State};
     
handle_info(_Info, State) ->
    {stop, {unknown_message, _Info}, State}.

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
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================

entry_list_to_kv(List) ->
    to_kv_list(List, []).

to_kv_list([], Resp) ->
    Resp;
to_kv_list([First|Rest], Resp) ->
    {<<"name_value_list">>, Data} = lists:keyfind(<<"name_value_list">>, 1, First),
    
    to_kv_list(Rest, [[ entry_to_kv (Item) || Item <- Data ]|Resp]).

entry_to_kv({_Key, Values}) ->
    {<<"name">>, Key} = lists:keyfind(<<"name">>, 1, Values),
    {<<"value">>, Value} = lists:keyfind(<<"value">>, 1, Values),
    {Key, Value}.

extract_from_name_value_list(Key, NameValueList) ->
    Value = case lists:keyfind(Key, 1, NameValueList) of
        false ->
            false;
        {Key, KV} ->
            case lists:keyfind(<<"value">>, 1, KV) of
                false ->
                    false;
                {<<"value">>, V} ->
                    V
            end
    end,
    Value.
