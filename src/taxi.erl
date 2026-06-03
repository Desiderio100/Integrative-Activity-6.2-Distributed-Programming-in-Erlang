%% ===========================================================================
%% INTEGRATIVE ACTIVITY 6.2 - DISTRIBUTED PROGRAMMING IN ERLANG
%% ALUMNO: Desideiro Iván Ortegón Morton  Matrícula: A00840591 y Pablo Carrera Dollero || A00843410
%% ARCHIVO: taxi.erl (Nodo de Vehículos)
%% ===========================================================================
-module(taxi).
-export([register_taxi/2, current_location/2, accept_trip/2, reject_trip/2, remove_taxi/1, consult_taxi/1, service_started/1, service_completed/1]).
-export([taxi_loop/4]).

register_taxi(TaxiId, InitialLocation) ->
    io:format("Sends: ~p registering at location ~p~n", [TaxiId, InitialLocation]),
    Pid = spawn(?MODULE, taxi_loop, [TaxiId, InitialLocation, available, nil]),
    %% Intentar desregistrar el nombre local por si quedó colgado de ejecuciones anteriores
    catch unregister(TaxiId),
    register(TaxiId, Pid),
    global:send(center, {register_taxi, TaxiId, Pid, InitialLocation}),
    ok.

current_location(TaxiId, Location) ->
    io:format("Sends: ~p updating location to ~p~n", [TaxiId, Location]),
    TaxiId ! {update_location, Location},
    ok.

accept_trip(TaxiId, TripId) ->
    io:format("Sends: ~p accepts Trip ~p~n", [TaxiId, TripId]),
    TaxiId ! {user_accept, TripId},
    ok.

reject_trip(TaxiId, TripId) ->
    io:format("Sends: ~p rejects Trip ~p~n", [TaxiId, TripId]),
    TaxiId ! {user_reject, TripId},
    ok.

remove_taxi(TaxiId) ->
    io:format("Sends: ~p requesting removal~n", [TaxiId]),
    TaxiId ! {user_remove, self()},
    receive {reply, Res} -> Res end.

consult_taxi(TaxiId) ->
    io:format("Sends: consulting status for ~p~n", [TaxiId]),
    TaxiId ! {consult, self()},
    receive {reply, State} -> State end.

service_started(TaxiId) ->
    io:format("Sends: ~p notifies service started~n", [TaxiId]),
    TaxiId ! {user_started},
    ok.

service_completed(TaxiId) ->
    io:format("Sends: ~p notifies service completed~n", [TaxiId]),
    TaxiId ! {user_completed},
    ok.

taxi_loop(TaxiId, Location, Status, CurrentTrip) ->
    receive
        {query_status, CenterPid} ->
            CenterPid ! {status_reply, TaxiId, Location, Status},
            taxi_loop(TaxiId, Location, Status, CurrentTrip);
        {propose_trip, TripId, Traveler, Origin} ->
            io:format("Receives: trip proposal for Trip ~p from ~p at ~p~n", [TripId, Traveler, Origin]),
            taxi_loop(TaxiId, Location, offered, {TripId, Traveler, Origin});
        {user_accept, TripId} ->
            global:send(center, {accept_trip, TaxiId, TripId, self()}),
            taxi_loop(TaxiId, Location, offered, CurrentTrip);
        {user_reject, TripId} ->
            global:send(center, {reject_trip, TaxiId, TripId}),
            taxi_loop(TaxiId, Location, available, nil);
        {confirm_assignment, _ConfirmedTripId} ->
            io:format("Receives: assignment confirmed for Trip ~p~n", [_ConfirmedTripId]),
            taxi_loop(TaxiId, Location, assigned, CurrentTrip);
        {user_started} ->
            global:send(center, {service_started, TaxiId}),
            {_, _, PassengerOrigin} = CurrentTrip,
            taxi_loop(TaxiId, PassengerOrigin, occupied, CurrentTrip);
        {user_completed} ->
            global:send(center, {service_completed, TaxiId}),
            receive {airport_location, AirportLocation} -> taxi_loop(TaxiId, AirportLocation, available, nil) end;
        {consult, From} ->
            From ! {reply, {Status, Location}},
            taxi_loop(TaxiId, Location, Status, CurrentTrip);
        {user_remove, From} ->
            global:send(center, {remove_taxi, TaxiId}),
            From ! {reply, ok}
    end.