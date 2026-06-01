-module(taxi).
-behaviour(gen_server).

-export([register_taxi/2, current_location/2, consult_taxi/1, accept_trip/2, reject_trip/2, service_started/1, service_completed/1, propose_taxi/2]).
-export([start_link/2, init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

-record(state, {
    taxi_id,
    location = {0, 0},
    status = disponible,
    pending_trip = undefined,
    current_trip = undefined
}).

register_taxi(TaxiId, InitialLocation) ->
    case is_atom(TaxiId) of
        false ->
            {error, invalid_taxi_id};
        true ->
            
            case whereis(TaxiId) of
                undefined ->
                    case start_link(TaxiId, InitialLocation) of
                        {ok, Pid} ->
                            case center:add_taxi(TaxiId) of
                                ok ->
                                    {ok, Pid};
                                Error ->
                                    gen_server:stop(Pid),
                                    Error
                            end;
                        Error ->
                            Error
                    end;
                _Pid ->
                    {error, already_registered}
            end
    end.

current_location(TaxiId, Location) ->
    case is_atom(TaxiId) of
        true ->
            
            gen_server:call(TaxiId, {current_location, Location});
        false ->
            {error, invalid_taxi_id}
    end.

consult_taxi(TaxiId) ->
    case is_atom(TaxiId) of
        true ->
            
            case whereis(TaxiId) of
                undefined ->
                    {error, not_found};
                _Pid ->
                    gen_server:call(TaxiId, consult)
            end;
        false ->
            {error, invalid_taxi_id}
    end.

accept_trip(TaxiId, TripId) ->
    case is_atom(TaxiId) of
        true ->
            
            gen_server:call(TaxiId, {accept_trip, TripId});
        false ->
            {error, invalid_taxi_id}
    end.

reject_trip(TaxiId, TripId) ->
    case is_atom(TaxiId) of
        true ->
            
            gen_server:call(TaxiId, {reject_trip, TripId});
        false ->
            {error, invalid_taxi_id}
    end.

service_started(TaxiId) ->
    case is_atom(TaxiId) of
        true ->
            gen_server:call(TaxiId, service_started);
        false ->
            {error, invalid_taxi_id}
    end.

service_completed(TaxiId) ->
    case is_atom(TaxiId) of
        true ->
            gen_server:call(TaxiId, service_completed);
        false ->
            {error, invalid_taxi_id}
    end.

propose_taxi(TaxiId, Proposal) ->
    case is_atom(TaxiId) of
        true ->
            gen_server:cast(TaxiId, {proposal, Proposal});
        false ->
            {error, invalid_taxi_id}
    end.

start_link(TaxiId, InitialLocation) ->
    gen_server:start_link({local, TaxiId}, ?MODULE, {TaxiId, InitialLocation}, []).

init({TaxiId, InitialLocation}) ->
    process_flag(trap_exit, true),
    {ok, #state{taxi_id = TaxiId, location = InitialLocation}}.

handle_call({current_location, Location}, _From, State) ->
    
    {reply, ok, State#state{location = Location}};
handle_call({accept_trip, TripId}, _From, State = #state{taxi_id = TaxiId, status = disponible, pending_trip = {Traveler, Origin, TripId}}) ->
    
    {reply, {ok, {TaxiId, TripId}}, State#state{status = ocupado, current_trip = {Traveler, Origin, TripId}, pending_trip = undefined}};
handle_call({accept_trip, TripId}, _From, State) ->
    
    {reply, {error, busy}, State};
handle_call({reject_trip, TripId}, _From, State = #state{pending_trip = {_, _, TripId}}) ->
    
    {reply, {ok, rejected}, State#state{pending_trip = undefined}};
handle_call({reject_trip, TripId}, _From, State) ->
    
    {reply, {ok, rejected}, State};
handle_call(service_started, _From, State = #state{current_trip = {Traveler, Origin, TripId}, taxi_id = TaxiId}) ->
    center:complete_trip({started, TripId, TaxiId, Traveler, Origin}),
    {reply, ok, State#state{status = ocupado, location = Origin}};
handle_call(service_started, _From, State) ->
    
    {reply, {error, no_active_trip}, State};
handle_call(service_completed, _From, State = #state{current_trip = {Traveler, _Origin, TripId}, taxi_id = TaxiId}) ->
    case center:get_state() of
        {state, AirportLocation, _Taxis, _Passengers, _Trips, _TripCount} ->
            center:complete_trip({completed, TripId, TaxiId, Traveler, AirportLocation}),
            center:remove_passenger(Traveler),
            {reply, ok, State#state{status = disponible, location = AirportLocation, current_trip = undefined, pending_trip = undefined}};
        _Other ->
            {reply, ok, State#state{status = disponible, current_trip = undefined, pending_trip = undefined}}
    end;
handle_call(service_completed, _From, State) ->
    
    {reply, {error, no_active_trip}, State};
handle_call(consult, _From, State = #state{status = Status, location = Location}) ->
    {reply, {ok, {Status, Location}}, State};
handle_call(Request, _From, State) ->
    {reply, {error, unknown_request}, State}.

handle_cast({proposal, Proposal}, State) ->
    {noreply, State#state{pending_trip = Proposal}};
handle_cast(Msg, State) ->
    {noreply, State}.

handle_info(Info, State) ->
    {noreply, State}.

terminate(_Reason, #state{taxi_id = TaxiId, status = disponible}) ->
    catch center:remove_taxi(TaxiId),
    ok;
terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.
