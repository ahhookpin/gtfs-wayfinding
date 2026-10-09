import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/column_mapping_page.dart';

void main() {
  testWidgets('renders variable column counts and repeated headers safely', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: GtfsColumnMappingPage(
          sourceName: 'feed.zip',
          headersByFile: {
            'routes.txt': [
              'route_id',
              'route_type',
              'route_short_name',
              '',
              'extra',
              'extra',
            ],
            'stops.txt': ['stop_id', 'stop_name'],
            'trips.txt': ['route_id', 'service_id', 'trip_id', 'extra'],
            'stop_times.txt': [
              'trip_id',
              'stop_id',
              'stop_sequence',
              'arrival_time',
              'departure_time',
              'extra',
              'extra',
            ],
          },
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    await tester.tap(find.byType(DropdownButtonFormField<int>).first);
    await tester.pumpAndSettle();

    expect(find.text('5: extra'), findsWidgets);
    expect(find.text('6: extra'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows only fields needed for core app behavior', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: GtfsColumnMappingPage(
          sourceName: 'feed.zip',
          headersByFile: {
            'routes.txt': [
              'route_id',
              'route_type',
              'route_long_name',
              'route_color',
            ],
            'stops.txt': ['stop_id', 'stop_name', 'stop_code'],
            'trips.txt': ['route_id', 'service_id', 'trip_id'],
            'stop_times.txt': [
              'trip_id',
              'stop_id',
              'stop_sequence',
              'arrival_time',
            ],
            'agency.txt': ['agency_name'],
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Route ID · required'), findsOneWidget);
    expect(find.text('Route name · required'), findsOneWidget);
    expect(find.text('Stop code · optional'), findsOneWidget);
    expect(find.text('Route color · optional'), findsNothing);
    expect(find.text('Agency name · required'), findsNothing);

    await tester.scrollUntilVisible(
      find.text('Departure or arrival time · required'),
      250,
      scrollable: find.byType(Scrollable).first,
    );

    expect(find.text('Departure or arrival time · required'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
