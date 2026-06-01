-module(traveler).

-export([request_taxi/2, cancel_taxi/1]).

request_taxi(Traveler, Origin) ->
    center:request_taxi(Traveler, Origin).

cancel_taxi(Traveler) ->
    center:remove_passenger(Traveler).