-module(center).
-behaviour(gen_server).

-export([open_center/1, close_center/0]).
-export([start_link/1, stop/0]).
-export([add_taxi/1, remove_taxi/1, add_passenger/1, remove_passenger/1, complete_trip/1, request_taxi/2, taxi_list/0, travelers_list/0, completed_trips/0, get_state/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

-record(state, {
    airport_location,
    taxis = [],
    taxi_monitors = [],
    passengers = [],
    trips = [],
    trip_count = 0
}).

open_center(AirportLocation) ->
    start_link(AirportLocation).

close_center() ->
    stop().

start_link(AirportLocation) ->
    gen_server:start_link({local, center}, ?MODULE, AirportLocation, []).

stop() ->
    case whereis(center) of
        undefined ->
            {error, not_running};
        _Pid ->
            gen_server:call(center, stop)
    end.

add_taxi(TaxiPid) ->
    gen_server:call(center, {add_taxi, TaxiPid}).

remove_taxi(TaxiPid) ->
    gen_server:call(center, {remove_taxi, TaxiPid}).

add_passenger(Passenger) ->
    gen_server:call(center, {add_passenger, Passenger}).

remove_passenger(Passenger) ->
    gen_server:call(center, {remove_passenger, Passenger}).

complete_trip(Trip) ->
    gen_server:call(center, {complete_trip, Trip}).

request_taxi(Traveler, Origin) ->
    gen_server:call(center, {request_taxi, Traveler, Origin}).

taxi_list() ->
    gen_server:call(center, taxi_list).

travelers_list() ->
    gen_server:call(center, travelers_list).

completed_trips() ->
    gen_server:call(center, completed_trips).

get_state() ->
    gen_server:call(center, get_state).

init(AirportLocation) ->
    process_flag(trap_exit, true),
    {ok, #state{airport_location = AirportLocation}}.

handle_call({add_taxi, TaxiId}, _From, State = #state{taxis = Taxis, taxi_monitors = Monitors}) ->
    
    case taxi_pid(TaxiId) of
        undefined ->
            {reply, {error, not_found}, State};
        Pid ->
            Ref = erlang:monitor(process, Pid),
            UpdatedTaxis = lists:usort([TaxiId | Taxis]),
            UpdatedMonitors = lists:keystore(TaxiId, 1, Monitors, {TaxiId, Pid, Ref}),
            {reply, ok, State#state{taxis = UpdatedTaxis, taxi_monitors = UpdatedMonitors}}
    end;
handle_call({remove_taxi, TaxiId}, _From, State = #state{taxis = Taxis, taxi_monitors = Monitors}) ->
    
    case taxi_status(TaxiId) of
        disponible ->
            case lists:keytake(TaxiId, 1, Monitors) of
                {value, {_TaxiId, _Pid, Ref}, RemainingMonitors} ->
                    erlang:demonitor(Ref, [flush]),
                    {reply, ok, State#state{taxis = lists:delete(TaxiId, Taxis), taxi_monitors = RemainingMonitors}};
                false ->
                    {reply, ok, State#state{taxis = lists:delete(TaxiId, Taxis)}}
            end;
        ocupado ->
            {reply, {error, busy}, State};
        undefined ->
            case lists:keytake(TaxiId, 1, Monitors) of
                {value, {_TaxiId, _Pid, Ref}, RemainingMonitors} ->
                    erlang:demonitor(Ref, [flush]),
                    {reply, ok, State#state{taxis = lists:delete(TaxiId, Taxis), taxi_monitors = RemainingMonitors}};
                false ->
                    {reply, ok, State#state{taxis = lists:delete(TaxiId, Taxis)}}
            end
    end;
handle_call({add_passenger, Passenger}, _From, State = #state{passengers = Passengers}) ->
    
    {reply, ok, State#state{passengers = lists:usort([Passenger | Passengers])}};
handle_call({remove_passenger, Passenger}, _From, State = #state{passengers = Passengers}) ->
    
    {reply, ok, State#state{passengers = lists:delete(Passenger, Passengers)}};
handle_call({complete_trip, {started, _TripId, _TaxiId, _Traveler, _Origin} = Trip}, _From, State = #state{trips = Trips, trip_count = Count}) ->
    {reply, ok, State#state{trips = [Trip | Trips], trip_count = Count}};
handle_call({complete_trip, {completed, _TripId, _TaxiId, _Traveler, _AirportLocation} = Trip}, _From, State = #state{trips = Trips, trip_count = Count}) ->
    {reply, ok, State#state{trips = [Trip | Trips], trip_count = Count + 1}};
handle_call({complete_trip, Trip}, _From, State = #state{trips = Trips}) ->
    {reply, ok, State#state{trips = [Trip | Trips]}};
handle_call({request_taxi, Traveler, Origin}, _From, State = #state{taxis = Taxis, passengers = Passengers}) ->
    
    TripId = erlang:unique_integer([monotonic, positive]),
    State1 = State#state{passengers = lists:usort([Traveler | Passengers])},
    case negotiate_taxi(sort_taxis_by_distance(Taxis, Origin), Traveler, Origin, TripId) of
        {ok, TaxiId} ->
            {reply, {ok, {TaxiId, TripId}}, State1};
        {error, no_available_taxi} ->
            {reply, {error, no_available_taxi}, State#state{passengers = lists:delete(Traveler, Passengers)}}
    end;
handle_call(taxi_list, _From, State = #state{taxis = Taxis}) ->
    Formatted = format_taxi_list(Taxis),
    io:format("~s~n", [Formatted]),
    {reply, {ok, Taxis}, State};
handle_call(travelers_list, _From, State = #state{passengers = Passengers}) ->
    Formatted = format_travelers_list(Passengers),
    io:format("~s~n", [Formatted]),
    {reply, {ok, Passengers}, State};
handle_call(completed_trips, _From, State = #state{trips = Trips}) ->
    Formatted = format_completed_trips(Trips),
    io:format("~s~n", [Formatted]),
    {reply, {ok, Trips}, State};
handle_call(get_state, _From, State) ->
    {reply, State, State};
handle_call(stop, _From, State) ->
    {stop, normal, ok, State};
handle_call(_Request, _From, State) ->
    {reply, {error, unknown_request}, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info({'DOWN', Ref, process, Pid, Reason}, State = #state{taxis = Taxis, taxi_monitors = Monitors}) ->
    case lists:keytake(Pid, 2, Monitors) of
        {value, {TaxiId, Pid, Ref}, RemainingMonitors} ->
            {noreply, State#state{taxis = lists:delete(TaxiId, Taxis), taxi_monitors = RemainingMonitors}};
        false ->
            {noreply, State}
    end;
handle_info({'EXIT', _FromPid, _Reason}, State) ->
    {noreply, State};
handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, #state{taxis = Taxis}) ->
    lists:foreach(fun(TaxiPid) ->
        case taxi_pid(TaxiPid) of
            undefined ->
                ok;
            Pid ->
                catch exit(Pid, shutdown)
        end
    end, Taxis),
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

taxi_pid(TaxiId) when is_pid(TaxiId) ->
    TaxiId;
taxi_pid(TaxiId) ->
    whereis(TaxiId).

taxi_status(TaxiId) ->
    case taxi:consult_taxi(TaxiId) of
        {ok, {Status, _Location}} ->
            Status;
        {error, _Reason} ->
            undefined
    end.

taxi_location(TaxiId) ->
    case taxi:consult_taxi(TaxiId) of
        {ok, {_Status, Location}} ->
            Location;
        {error, _Reason} ->
            undefined
    end.

sort_taxis_by_distance(Taxis, Origin) ->
    AvailableTaxis = [
        {TaxiId, euclidean_distance(Location, Origin)}
        || TaxiId <- Taxis,
           {ok, {disponible, Location}} <- [taxi:consult_taxi(TaxiId)]
    ],
    [TaxiId || {TaxiId, _Distance} <- lists:sort(fun({_, D1}, {_, D2}) -> D1 =< D2 end, AvailableTaxis)].

negotiate_taxi([], _Traveler, _Origin, _TripId) ->
    {error, no_available_taxi};
negotiate_taxi([TaxiId | Rest], Traveler, Origin, TripId) ->
    taxi:propose_taxi(TaxiId, {Traveler, Origin, TripId}),
    case taxi:accept_trip(TaxiId, TripId) of
        {ok, {TaxiId, TripId}} ->
            {ok, TaxiId};
        {error, busy} ->
            taxi:reject_trip(TaxiId, TripId),
            negotiate_taxi(Rest, Traveler, Origin, TripId);
        {error, _Reason} ->
            
            negotiate_taxi(Rest, Traveler, Origin, TripId)
    end.

euclidean_distance({X1, Y1}, {X2, Y2}) ->
    math:sqrt(math:pow(X2 - X1, 2) + math:pow(Y2 - Y1, 2)).

format_taxi_list(Taxis) ->
    Entries = [io_lib:format("- ~p", [TaxiId]) || TaxiId <- Taxis],
    lists:flatten(["Taxis activos:", lists:join("\n", Entries)]).

format_travelers_list(Passengers) ->
    Entries = [io_lib:format("- ~p", [Passenger]) || Passenger <- Passengers],
    lists:flatten(["Viajeros activos:", lists:join("\n", Entries)]).

format_completed_trips(Trips) ->
    CompletedTrips = [Trip || Trip = {completed, _, _, _, _} <- lists:reverse(Trips)],
    Entries = [io_lib:format("- ~p", [Trip]) || Trip <- CompletedTrips],
    lists:flatten(["Viajes completados:", lists:join("\n", Entries)]).

