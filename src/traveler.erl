%% ===========================================================================
%% INTEGRATIVE ACTIVITY 6.2 - DISTRIBUTED PROGRAMMING IN ERLANG
%% ALUMNO: Desideiro Iván Ortegón Morton  Matrícula: A00840591 y Pablo Carrera Dollero || A00843410
%% ARCHIVO: traveler.erl (Nodo de Pasajeros)
%% ===========================================================================
-module(traveler).
-export([request_taxi/2, cancel_taxi/1]).

request_taxi(Traveler, Origin) ->
    io:format("Sends: ~p requests taxi from ~p~n", [Traveler, Origin]),
    global:send(center, {request_taxi, Traveler, Origin, self()}),
    receive
        {ok, AssignedTaxiId, TripId} ->
            io:format("Receives: taxi request accepted. Assigned Taxi: ~p, Trip ID: ~p~n", [AssignedTaxiId, TripId]),
            {ok, {AssignedTaxiId, TripId}};
        {error, Reason} ->
            io:format("Receives: taxi request rejected. Reason: ~p~n", [Reason]),
            {error, Reason}
    end.

cancel_taxi(Traveler) ->
    io:format("Sends: traveler ~p requests cancellation~n", [Traveler]),
    global:send(center, {cancel_taxi, Traveler}),
    ok.