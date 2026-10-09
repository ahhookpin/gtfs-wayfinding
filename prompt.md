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

-----

10 Oct 2026 3:58 PM

1. instead of filling cells in grey, just changed text colour to light grey for passed stops (no cell colour filling)

2. need alternative for cell colour filling for current stop to... to save ink 

3. for stop codes, instead of changing font size, increase stop code column width/decrease stop column width

4. implement a generating message pop up to avoid user trying to click around the app and the app hanging while PDF generates 

5.a. parsing the stop_times for list of stops and sequence has issue - last stop not pulling through 

5.b. parse through the stop_times for list of stops but keep in consideration trip_id to split list of stops depending on direction of travel. 