Use this base Flutter/Dart project to build an app that

1. Requests user for GTFS Static data via ZIP folder

2. Parse through GTFS Static

3. Display list of stops 

3.1 Give user option to select 1 of the stops (user input via text box with auto complete suggestions)

3.1.1 For user selected stop, display list of routes served by the stop.

3.1.2 Print function - generate an A4 poster usable for physical print presenting information from 3.1.1

4. Display list of routes

4.1 Give user option to select 1 of the routes (user input via text box with auto complete suggestions)

4.1.1 For user selected route, display list of stops served by the route + list of departure timings from 1st stop.

4.1.2 Print function - generate an A4 poster usable for physical print presenting information from 4.1.1


-----

OUTSTANDING ISSUES:

(1) last possible timing from frequency not included - missing timings

(2) wayfinding poster - rework concept so that it prints next stops from the selected stop

(3) wayfinding poster - include starting stop at the end of route

FUTURE IMPLEMENTATION:

(1) track which stop have/have not printed for. save data as exportable csv and import user data each app launch? 