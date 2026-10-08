# Wayfinder · Transit Studio

Wayfinder is a Flutter app for exploring a transit network from a GTFS Static ZIP
feed and printing stop or route information as an A4 PDF.

## Import a feed

Choose **Import GTFS** and select the feed's ZIP file. The ZIP can contain the
GTFS text files at its root or inside a folder. The following tables are required:

- `routes.txt`
- `stops.txt`
- `trips.txt`

At least one of `stop_times.txt` or `frequencies.txt` must be present.
`agency.txt` is optional. First-stop departures combine
scheduled times from `stop_times.txt` with the generated time slots from
`frequencies.txt`; trips represented in `frequencies.txt` use its headway
interval instead of their template departure time. Frequency-based estimates
are identified as estimates unless `exact_times` is set to `1`. Import is
performed locally in the app. A feed with
missing required files or invalid ZIP/CSV data displays an error instead of
replacing the currently loaded feed.

Frequency trips with no matching `stop_times.txt` rows still contribute their
generated departure times. If no stop-time data exists for the route, its route
view shows the timings without listing stops or a first stop.

## Explore and print

- Search stops by name, stop code, or ID to see the routes serving each stop.
- Search routes by short name, long name, or ID to see their stops in sequence
  and scheduled departure times from the route's most common first stop,
  grouped by the `service_id` associated with each trip in `trips.txt`. Stop
  order follows `stop_sequence` from trips starting at that first stop, so
  reverse-direction trips do not scramble the displayed order.
- Choose **Print A4** on a stop or route to open the platform print/PDF dialog.
  Large schedules and stop lists flow onto additional A4 pages.

## Run

```sh
flutter pub get
flutter run
```

## Test

```sh
flutter test
```
