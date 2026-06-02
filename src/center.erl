%% ===========================================================================
%% INTEGRATIVE ACTIVITY 6.2 - DISTRIBUTED PROGRAMMING IN ERLANG
%% ALUMNO: Desideiro Iván Ortegón Morton  Matrícula: A00840591
%% PROFESOR: Santiago Conant
%% ARCHIVO: center.erl (Nodo de la Central)
%% ===========================================================================
-module(center).
-export([open_center/1, close_center/0, taxi_list/0, travelers_list/0, completed_trips/0]).
-export([init/1]).

open_center(AirportLocation) ->
    io:format("Sends: opening dispatch center at ~p~n", [AirportLocation]),
    Pid = spawn(?MODULE, init, [AirportLocation]),
    global:register_name(center, Pid),
    {ok, Pid}.

close_center() ->
    io:format("Sends: closing dispatch center~n"),
    global:send(center, {close_center, self()}),
    ok.

taxi_list() ->
    io:format("Sends: requesting taxi list~n"),
    global:send(center, {taxi_list, self()}),
    receive {reply, List} -> List end.

travelers_list() ->
    io:format("Sends: requesting travelers list~n"),
    global:send(center, {travelers_list, self()}),
    receive {reply, List} -> List end.

completed_trips() ->
    io:format("Sends: requesting completed trips~n"),
    global:send(center, {completed_trips, self()}),
    receive {reply, Total} -> Total end.

init(AirportLocation) ->
    loop(AirportLocation, [], [], [], 0).

loop(AirportLocation, Taxis, ActiveTrips, CompletedTrips, TripCounter) ->
    receive
        {register_taxi, TaxiId, TaxiPid, Location} ->
            io:format("Receives: registration request from ~p at ~p~n", [TaxiId, Location]),
            erlang:monitor(process, TaxiPid),
            loop(AirportLocation, [{TaxiId, TaxiPid} | Taxis], ActiveTrips, CompletedTrips, TripCounter);

        {request_taxi, Traveler, Origin, TravelerPid} ->
            io:format("Receives: taxi request from ~p at ~p~n", [Traveler, Origin]),
            AvailableTaxis = query_taxis_status(Taxis),
            case AvailableTaxis of
                [] -> 
                    TravelerPid ! {error, unavailable},
                    loop(AirportLocation, Taxis, ActiveTrips, CompletedTrips, TripCounter);
                _ ->
                    SortedTaxis = sort_taxis_by_dist(Origin, AvailableTaxis),
                    TempTripId = TripCounter + 1,
                    dispatch_proposal(TempTripId, Traveler, Origin, TravelerPid, SortedTaxis, AirportLocation, Taxis, ActiveTrips, CompletedTrips, TripCounter)
            end;

        {accept_trip, TaxiId, TripId, TaxiPid} ->
            io:format("Receives: trip acceptance from ~p for Trip ~p~n", [TaxiId, TripId]),
            case lists:keytake(TripId, 1, ActiveTrips) of
                {value, {TripId, TaxiId, Traveler, Origin, TravelerPid, proposing, _}, UtterRest} ->
                    NewCounter = TripCounter + 1,
                    NewActive = [{NewCounter, TaxiId, Traveler, Origin, assigned} | UtterRest],
                    TravelerPid ! {ok, TaxiId, NewCounter},
                    TaxiPid ! {confirm_assignment, NewCounter},
                    loop(AirportLocation, Taxis, NewActive, CompletedTrips, NewCounter);
                _ -> loop(AirportLocation, Taxis, ActiveTrips, CompletedTrips, TripCounter)
            end;

        {reject_trip, TaxiId, TripId} ->
            io:format("Receives: trip rejection from ~p for Trip ~p~n", [TaxiId, TripId]),
            case lists:keytake(TripId, 1, ActiveTrips) of
                {value, {TripId, TaxiId, Traveler, Origin, TravelerPid, proposing, SortedRest}, UtterRest} ->
                    dispatch_proposal(TripId, Traveler, Origin, TravelerPid, SortedRest, AirportLocation, Taxis, UtterRest, CompletedTrips, TripCounter);
                _ -> loop(AirportLocation, Taxis, ActiveTrips, CompletedTrips, TripCounter)
            end;

        {service_started, TaxiId} ->
            io:format("Receives: service started notification from ~p~n", [TaxiId]),
            NewActive = lists:map(fun({TripId, TId, Trav, Orig, assigned}) when TId == TaxiId ->
                                        {TripId, TId, Trav, Orig, in_trip};
                                     (Other) -> Other
                                  end, ActiveTrips),
            loop(AirportLocation, Taxis, NewActive, CompletedTrips, TripCounter);

        {service_completed, TaxiId} ->
            io:format("Receives: service completed notification from ~p~n", [TaxiId]),
            case lists:keytake(TaxiId, 2, ActiveTrips) of
                {value, {TripId, TaxiId, Traveler, Origin, in_trip}, RestActive} ->
                    NewCompleted = [{TripId, TaxiId, Traveler, Origin} | CompletedTrips],
                    case lists:keyfind(TaxiId, 1, Taxis) of
                        {TaxiId, TPid} -> TPid ! {airport_location, AirportLocation};
                        false -> ok
                    end,
                    loop(AirportLocation, Taxis, RestActive, NewCompleted, TripCounter);
                _ -> loop(AirportLocation, Taxis, ActiveTrips, CompletedTrips, TripCounter)
            end;

        {taxi_list, From} ->
            io:format("Receives: taxi list request~n"),
            io:format("~n--- LISTA DE TAXIS ACTIVOS ---~n"),
            lists:foreach(fun({Id, Pid}) -> io:format("Taxi ID: ~p | PID: ~p~n", [Id, Pid]) end, Taxis),
            From ! {reply, ok},
            loop(AirportLocation, Taxis, ActiveTrips, CompletedTrips, TripCounter);
            
        {travelers_list, From} ->
            io:format("Receives: travelers list request~n"),
            io:format("~n--- PASAJEROS EN VIAJE ACTIVO ---~n"),
            lists:foreach(fun({TripId, TaxiId, Traveler, Origin, Status}) -> 
                            io:format("Trip: ~p | Pasajero: ~p | Taxi: ~p | Status: ~p~n", [TripId, Traveler, TaxiId, Status]) 
                          end, ActiveTrips),
            From ! {reply, ok},
            loop(AirportLocation, Taxis, ActiveTrips, CompletedTrips, TripCounter);

        {completed_trips, From} ->
            io:format("Receives: completed trips request~n"),
            io:format("~n--- HISTORIAL DE VIAJES COMPLETADOS ---~n"),
            lists:foreach(fun({TripId, TaxiId, Traveler, Origin}) -> 
                            io:format("Trip ID: ~p | Taxi: ~p | Pasajero: ~p | Origen: ~p~n", [TripId, TaxiId, Traveler, Origin]) 
                          end, CompletedTrips),
            From ! {reply, length(CompletedTrips)},
            loop(AirportLocation, Taxis, ActiveTrips, CompletedTrips, TripCounter);

        {'DOWN', _Ref, process, Pid, _Reason} ->
            NewTaxis = lists:filter(fun({_, P}) -> P /= Pid end, Taxis),
            loop(AirportLocation, NewTaxis, ActiveTrips, CompletedTrips, TripCounter);

        {close_center, From} ->
            io:format("Receives: Shutting down center... terminating taxis~n"),
            lists:foreach(fun({_, Pid}) -> exit(Pid, shutdown) end, Taxis),
            From ! {reply, center_closed},
            exit(normal)
    end.

query_taxis_status(Taxis) ->
    lists:filtermap(fun({TaxiId, Pid}) ->
        Pid ! {query_status, self()},
        receive
            {status_reply, TaxiId, Location, available} -> {true, {TaxiId, Pid, Location}};
            {status_reply, _, _, _} -> false
        after 1000 -> false
        end
    end, Taxis).

sort_taxis_by_dist({X1, Y1}, AvailableTaxis) ->
    lists:sort(fun({_, _, {Xa, Ya}}, {_, _, {Xb, Yb}}) ->
        math:sqrt((Xa - X1)*(Xa - X1) + (Ya - Y1)*(Ya - Y1)) =< 
        math:sqrt((Xb - X1)*(Xb - X1) + (Yb - Y1)*(Yb - Y1))
    end, AvailableTaxis).

dispatch_proposal(TripId, Traveler, Origin, TravelerPid, [], AirportLocation, Taxis, ActiveTrips, CompletedTrips, TripCounter) ->
    TravelerPid ! {error, unavailable},
    loop(AirportLocation, Taxis, ActiveTrips, CompletedTrips, TripCounter);
dispatch_proposal(TripId, Traveler, Origin, TravelerPid, [{BestTaxiId, BestTaxiPid, _} | Rest], AirportLocation, Taxis, ActiveTrips, CompletedTrips, TripCounter) ->
    io:format("Sends: center proposes Trip ~p to ~p~n", [TripId, BestTaxiId]),
    BestTaxiPid ! {propose_trip, TripId, Traveler, Origin},
    NewActive = [{TripId, BestTaxiId, Traveler, Origin, TravelerPid, proposing, Rest} | ActiveTrips],
    loop(AirportLocation, Taxis, NewActive, CompletedTrips, TripCounter).