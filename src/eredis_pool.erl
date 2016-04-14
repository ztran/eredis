%% @author Tran Hoan


-module(eredis_pool).
-behaviour(gen_server).

-include("logger.hrl").

-export([init/1,
		 handle_call/3,
		 handle_cast/2,
		 handle_info/2,
		 terminate/2,
		 code_change/3
]).

-export([start_link/1,
		 get_connection/1,
		 set_size/2,
		 set_t_reconnect/2
		]).

-record(eredis_pool_st,{
	type		::	db | pubsub,
	args		::	tuple(),
	psize		::	non_neg_integer(),
	ptr  = 1	::	non_neg_integer(),
	t_reconnect	::	timeout(),
	conns  = [] ::	list()
}).

-spec start_link({Name,Type,Params,Opts}) -> Result when
	Name :: atom(), Type :: normal | sub, Params :: {Host, Port, Db, Password},
	Opts :: list(),Host :: list(), Port :: inet:port_number(), Db :: list(), Password :: list(),
	Result :: {ok,pid()} | {error, any()}.

start_link({Name,Type,Params,Opts}) ->
	gen_server:start_link({local,Name}, ?MODULE,{Type,Params,Opts}, []).

%% init/1
%% ====================================================================
%% @doc <a href="http://www.erlang.org/doc/man/gen_server.html#Module:init-1">gen_server:init/1</a>
-spec init(Args :: term()) -> Result when
	Result :: {ok, State}
			| {ok, State, Timeout}
			| {ok, State, hibernate}
			| {stop, Reason :: term()}
			| ignore,
	State :: term(),
	Timeout :: non_neg_integer() | infinity.
%% ====================================================================
init({Type,Params,Opts}) ->
	erlang:process_flag(trap_exit, true),
	Psize = get_opt(size, Opts, 1),
	Reconnect = get_opt(t_reconnect, Opts, 30000),
	self() ! check_psize,
    {ok, #eredis_pool_st{type = Type,args = Params,psize = Psize,t_reconnect = Reconnect}}.


%% handle_call/3
%% ====================================================================
%% @doc <a href="http://www.erlang.org/doc/man/gen_server.html#Module:handle_call-3">gen_server:handle_call/3</a>
-spec handle_call(Request :: term(), From :: {pid(), Tag :: term()}, State :: term()) -> Result when
	Result :: {reply, Reply, NewState}
			| {reply, Reply, NewState, Timeout}
			| {reply, Reply, NewState, hibernate}
			| {noreply, NewState}
			| {noreply, NewState, Timeout}
			| {noreply, NewState, hibernate}
			| {stop, Reason, Reply, NewState}
			| {stop, Reason, NewState},
	Reply :: term(),
	NewState :: term(),
	Timeout :: non_neg_integer() | infinity,
	Reason :: term().
%% ====================================================================
handle_call(get_connection,_From,#eredis_pool_st{conns = []} = State) ->
	{reply,{error,no_connection},State};
handle_call(get_connection,_From,#eredis_pool_st{conns = Cons,ptr = Ptr} = State) ->
	Ptr1 = if (Ptr + 1) > length(Cons) -> 1;
			  true -> Ptr + 1
		   end,
	{reply,{ok,lists:nth(Ptr,Cons)},State#eredis_pool_st{ptr = Ptr1}};
handle_call({set_size,Size},_From,State) ->
	{reply,ok,State#eredis_pool_st{psize = Size}};
handle_call({set_t_reconnect,Reconnect},_From,State) ->
	{reply,ok,State#eredis_pool_st{t_reconnect = Reconnect}};
handle_call(_Request, _From, State) ->
    {reply, {error,badarg}, State}.


%% handle_cast/2
%% ====================================================================
%% @doc <a href="http://www.erlang.org/doc/man/gen_server.html#Module:handle_cast-2">gen_server:handle_cast/2</a>
-spec handle_cast(Request :: term(), State :: term()) -> Result when
	Result :: {noreply, NewState}
			| {noreply, NewState, Timeout}
			| {noreply, NewState, hibernate}
			| {stop, Reason :: term(), NewState},
	NewState :: term(),
	Timeout :: non_neg_integer() | infinity.
%% ====================================================================
handle_cast(Msg, State) ->
	?NOTICE("drop unknown message ~p",[Msg]),
    {noreply, State}.


%% handle_info/2
%% ====================================================================
%% @doc <a href="http://www.erlang.org/doc/man/gen_server.html#Module:handle_info-2">gen_server:handle_info/2</a>
-spec handle_info(Info :: timeout | term(), State :: term()) -> Result when
	Result :: {noreply, NewState}
			| {noreply, NewState, Timeout}
			| {noreply, NewState, hibernate}
			| {stop, Reason :: term(), NewState},
	NewState :: term(),
	Timeout :: non_neg_integer() | infinity.
%% ====================================================================
handle_info(check_psize,#eredis_pool_st{type = Type,args = Args,conns = Cons,psize = Psize,t_reconnect = Reconnect} = State) ->
	N = Psize - length(Cons),
%% 	?DEBUG("checking pool size, try to create ~p ~p connection (~p)",[N,Type,Args]),
	L = create_connection(Type,Args,Cons,N),
	if length(L) < Psize ->
		   erlang:send_after(Reconnect,self(),check_psize);
	   true ->
		   ok
	end,
    {noreply,State#eredis_pool_st{conns = L}};

handle_info({'EXIT',Pid,_},#eredis_pool_st{conns = Cons,ptr = Ptr,t_reconnect = Reconnect} = State) ->
	?NOTICE("maybe connection ~p is dead",[Pid]),
	erlang:send_after(Reconnect,self(),check_psize),
	Cons1 = lists:delete(Pid,Cons),
	Ptr1 = if Ptr > length(Cons1) -> 1;
			  true -> Ptr
		   end,
	{noreply,State#eredis_pool_st{conns = Cons1,ptr = Ptr1}};

handle_info(Info, State) ->
	?NOTICE("drop unknown message ~p",[Info]),
    {noreply, State}.


%% terminate/2
%% ====================================================================
%% @doc <a href="http://www.erlang.org/doc/man/gen_server.html#Module:terminate-2">gen_server:terminate/2</a>
-spec terminate(Reason, State :: term()) -> Any :: term() when
	Reason :: normal
			| shutdown
			| {shutdown, term()}
			| term().
%% ====================================================================
terminate(Reason, _State) ->
	?DEBUG("reason => ~p",[Reason]),
    ok.


%% code_change/3
%% ====================================================================
%% @doc <a href="http://www.erlang.org/doc/man/gen_server.html#Module:code_change-3">gen_server:code_change/3</a>
-spec code_change(OldVsn, State :: term(), Extra :: term()) -> Result when
	Result :: {ok, NewState :: term()} | {error, Reason :: term()},
	OldVsn :: Vsn | {down, Vsn},
	Vsn :: term().
%% ====================================================================
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

get_opt(K,Opts,Def) ->
	case lists:keyfind(K,1,Opts) of
		false -> Def;
		{K,V} -> V
	end.
create_connection(pubsub,{Host,Port,Password}, Cons,N) when N > 0 ->
	case eredis_sub:start_link(Host,Port,Password) of
		{ok,Sub} ->
			create_connection(pubsub,{Host,Port,Password},[Sub|Cons],N - 1);
		_ ->
%% 			create_connection(pubsub,{Host,Port,Password},Cons,N - 1)
			Cons
	end;
create_connection(db,{Host,Port,Db,Password}, Cons,N) when N > 0 ->
	case eredis:start_link(Host,Port,Db,Password) of
		{ok,Sub} ->
			create_connection(db,{Host,Port,Db,Password},[Sub|Cons],N - 1);
		_ ->
%% 			create_connection(db,{Host,Port,Db,Password},Cons,N - 1)
			Cons
	end;
create_connection(_,_,Cons,_) -> Cons.

set_size(Pool,Size) ->
	case catch gen_server:call(Pool,{set_size,Size}) of
		{'EXIT',_} -> {error,crashed};
		Ret -> Ret
	end.

set_t_reconnect(Pool,Timeout) when Timeout > 1000 ->
	case catch gen_server:call(Pool,{set_t_reconnect,Timeout}) of
		{'EXIT',_} -> {error,crashed};
		Ret -> Ret
	end.

get_connection(Pool) ->
	case catch gen_server:call(Pool,get_connection) of
		{'EXIT',Reason} ->
			?ERROR("!EE crashed ~p",[Reason]),
			{error,crashed};
		Ret -> Ret
	end.