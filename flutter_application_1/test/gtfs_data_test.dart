import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_1/gtfs_data.dart';

void main() {
  const files = {
    'routes.txt':
        'route_id,route_short_name,route_long_name,route_type\r\n'
        'r1,7,"Harbour, North",3\r\n',
    'stops.txt':
        'stop_id,stop_name,stop_code,stop_lat,stop_lon\r\n'
        's1,"Central, Station",C1,1.25,2.5\r\n'
        's2,Market Street,M2,1.5,2.75\r\n',
    'trips.txt':
        'route_id,service_id,trip_id\r\n'
        'r1,weekday,t1\r\n'
        'r1,weekday,t2\r\n',
    'stop_times.txt':
        'trip_id,arrival_time,departure_time,stop_id,stop_sequence\r\n'
        't1,08:00:00,08:01:00,s1,1\r\n'
        't1,08:15:00,08:15:00,s2,2\r\n'
        't2,09:00:00,09:00:00,s1,1\r\n'
        't2,09:10:00,09:10:00,s2,2\r\n',
    'agency.txt':
        'agency_name,agency_url,agency_timezone\r\n'
        'City Transit,https://example.test,Etc/UTC\r\n',
  };

  test('parses quoted CSV fields, route stops, and ordered departures', () {
    final dataset = GtfsDataset.fromFiles(files, sourceName: 'city.zip');

    expect(dataset.agencyName, 'City Transit');
    expect(dataset.stops.first.name, 'Central, Station');
    expect(dataset.routes.single.displayName, '7 · Harbour, North');
    expect(dataset.routes.single.stopIds, ['s1', 's2']);
    expect(dataset.routes.single.firstStopId, 's1');
    expect(dataset.routes.single.departureTimes, ['08:01:00', '09:00:00']);
    expect(dataset.routes.single.departureTimesByServiceId, {
      'weekday': ['08:01:00', '09:00:00'],
    });
    expect(dataset.routeIdsByStopId['s2'], ['r1']);
  });

  test('orders stops using the most common trip direction sequence', () {
    final directionalFiles = {
      ...files,
      'stops.txt':
          'stop_id,stop_name,stop_code\r\n'
          'z,First stop,Z\r\n'
          'a,Second stop,A\r\n',
      'trips.txt':
          'route_id,service_id,trip_id\r\n'
          'r1,weekday,outbound-1\r\n'
          'r1,weekday,outbound-2\r\n'
          'r1,weekday,inbound\r\n',
      'stop_times.txt':
          'trip_id,arrival_time,departure_time,stop_id,stop_sequence\r\n'
          'outbound-1,08:00:00,08:00:00,z,1\r\n'
          'outbound-1,08:10:00,08:10:00,a,2\r\n'
          'outbound-2,09:00:00,09:00:00,z,1\r\n'
          'outbound-2,09:10:00,09:10:00,a,2\r\n'
          'inbound,10:00:00,10:00:00,a,1\r\n'
          'inbound,10:10:00,10:10:00,z,2\r\n',
    };

    final dataset = GtfsDataset.fromFiles(
      directionalFiles,
      sourceName: 'directions.zip',
    );

    expect(dataset.routes.single.stopIds, ['z', 'a']);
    expect(dataset.routes.single.firstStopId, 'z');
  });

  test(
    'combines scheduled and frequency-based departures without duplicates',
    () {
      final filesWithFrequencies = {
        ...files,
        'trips.txt':
            'route_id,service_id,trip_id\r\n'
            'r1,weekday,t1\r\n'
            'r1,weekday,t2\r\n'
            'r1,weekday,t3\r\n'
            'r1,weekday,frequency-trip\r\n',
        'stop_times.txt':
            'trip_id,arrival_time,departure_time,stop_id,stop_sequence\r\n'
            't1,08:00:00,08:01:00,s1,1\r\n'
            't1,08:15:00,08:15:00,s2,2\r\n'
            't2,09:00:00,09:00:00,s1,1\r\n'
            't2,09:10:00,09:10:00,s2,2\r\n'
            't3,10:10:00,10:10:00,s1,1\r\n'
            't3,10:20:00,10:20:00,s2,2\r\n'
            'frequency-trip,10:05:00,10:05:00,s1,1\r\n'
            'frequency-trip,10:15:00,10:15:00,s2,2\r\n',
        'frequencies.txt':
            'trip_id,start_time,end_time,headway_secs,exact_times\r\n'
            'frequency-trip,10:00:00,10:30:00,600,0\r\n',
      };

      final dataset = GtfsDataset.fromFiles(
        filesWithFrequencies,
        sourceName: 'frequencies.zip',
      );

      expect(dataset.routes.single.departureTimes, [
        '08:01:00',
        '09:00:00',
        '10:00:00',
        '10:10:00',
        '10:20:00',
      ]);
      expect(dataset.routes.single.hasEstimatedFrequencyDepartures, isTrue);
    },
  );

  test('keeps scheduled and frequency departures grouped by service ID', () {
    final serviceFiles = {
      ...files,
      'trips.txt':
          'route_id,service_id,trip_id\r\n'
          'r1,weekday,weekday-trip\r\n'
          'r1,weekend,weekend-trip\r\n',
      'stop_times.txt':
          'trip_id,arrival_time,departure_time,stop_id,stop_sequence\r\n'
          'weekday-trip,08:00:00,08:00:00,s1,1\r\n'
          'weekday-trip,08:10:00,08:10:00,s2,2\r\n'
          'weekend-trip,09:00:00,09:00:00,s1,1\r\n'
          'weekend-trip,09:10:00,09:10:00,s2,2\r\n',
      'frequencies.txt':
          'trip_id,start_time,end_time,headway_secs,exact_times\r\n'
          'weekday-trip,08:00:00,08:31:00,600,1\r\n'
          'weekend-trip,09:00:00,09:21:00,600,1\r\n',
    };

    final dataset = GtfsDataset.fromFiles(
      serviceFiles,
      sourceName: 'services.zip',
    );

    expect(dataset.routes.single.departureTimesByServiceId, {
      'weekday': ['08:00:00', '08:10:00', '08:20:00', '08:30:00'],
      'weekend': ['09:00:00', '09:10:00', '09:20:00'],
    });
  });

  test('frequency end time is exclusive and supports times after midnight', () {
    final overnightFiles = {
      ...files,
      'trips.txt': 'route_id,service_id,trip_id\r\nr1,weekday,overnight\r\n',
      'stop_times.txt':
          'trip_id,arrival_time,departure_time,stop_id,stop_sequence\r\n'
          'overnight,23:50:00,23:50:00,s1,1\r\n'
          'overnight,24:00:00,24:00:00,s2,2\r\n',
      'frequencies.txt':
          'trip_id,start_time,end_time,headway_secs\r\n'
          'overnight,23:50:00,24:30:00,600\r\n',
    };

    final dataset = GtfsDataset.fromFiles(
      overnightFiles,
      sourceName: 'overnight.zip',
    );

    expect(dataset.routes.single.departureTimes, [
      '23:50:00',
      '24:00:00',
      '24:10:00',
      '24:20:00',
    ]);
  });

  test('rejects invalid frequency headways', () {
    final invalidFiles = {
      ...files,
      'frequencies.txt':
          'trip_id,start_time,end_time,headway_secs\r\n'
          't1,10:00:00,11:00:00,0\r\n',
    };

    expect(
      () => GtfsDataset.fromFiles(invalidFiles, sourceName: 'invalid.zip'),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('headway_secs'),
        ),
      ),
    );
  });

  test('imports frequency trips that have no stop_times rows', () {
    final filesWithMissingFrequencyStopTimes = {
      ...files,
      'trips.txt':
          'route_id,service_id,trip_id\r\n'
          'r1,weekday,t1\r\n'
          'r1,weekday,t2\r\n'
          'r1,weekday,frequency-only\r\n',
      'frequencies.txt':
          'trip_id,start_time,end_time,headway_secs,exact_times\r\n'
          'frequency-only,11:00:00,11:31:00,900,1\r\n',
    };

    final dataset = GtfsDataset.fromFiles(
      filesWithMissingFrequencyStopTimes,
      sourceName: 'frequency-only-trip.zip',
    );

    expect(dataset.routes.single.departureTimes, [
      '08:01:00',
      '09:00:00',
      '11:00:00',
      '11:15:00',
      '11:30:00',
    ]);
    expect(dataset.routes.single.firstStopId, 's1');
    expect(dataset.routes.single.hasEstimatedFrequencyDepartures, isFalse);
  });

  test('imports frequency-based routes when stop_times.txt is absent', () {
    final frequencyOnlyFiles = {
      'routes.txt': files['routes.txt']!,
      'stops.txt': files['stops.txt']!,
      'trips.txt':
          'route_id,service_id,trip_id\r\n'
          'r1,weekday,frequency-only\r\n',
      'frequencies.txt':
          'trip_id,start_time,end_time,headway_secs\r\n'
          'frequency-only,12:00:00,12:21:00,600\r\n',
    };

    final dataset = GtfsDataset.fromFiles(
      frequencyOnlyFiles,
      sourceName: 'frequency-only-feed.zip',
    );

    expect(dataset.routes.single.stopIds, isEmpty);
    expect(dataset.routes.single.firstStopId, isEmpty);
    expect(dataset.routes.single.departureTimes, [
      '12:00:00',
      '12:10:00',
      '12:20:00',
    ]);
    expect(dataset.routes.single.hasEstimatedFrequencyDepartures, isTrue);
  });

  test('reads GTFS files nested under a folder in a ZIP', () async {
    final archive = Archive();
    final nestedFeed = {
      ...files,
      'frequencies.txt':
          'trip_id,start_time,end_time,headway_secs\r\n'
          't1,08:01:00,08:21:00,600\r\n',
    };
    for (final entry in nestedFeed.entries) {
      final content = utf8.encode(entry.value);
      archive.addFile(
        ArchiveFile('feed/${entry.key}', content.length, content),
      );
    }
    final bytes = ZipEncoder().encode(archive);

    final dataset = await GtfsDataset.fromZip(bytes, sourceName: 'nested.zip');

    expect(dataset.sourceName, 'nested.zip');
    expect(dataset.stops, hasLength(2));
    expect(dataset.routes.single.departureTimes, [
      '08:01:00',
      '08:11:00',
      '09:00:00',
    ]);
  });

  test('reports missing required GTFS tables clearly', () {
    expect(
      () => GtfsDataset.fromFiles({
        'routes.txt': files['routes.txt']!,
      }, sourceName: 'incomplete.zip'),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('stops.txt'),
        ),
      ),
    );
  });

  test(
    'reports missing required columns before building incomplete routes',
    () {
      final invalidFiles = {
        ...files,
        'stop_times.txt':
            'trip_id,arrival_time,departure_time,stop_id\r\n'
            't1,08:00:00,08:01:00,s1\r\n',
      };

      expect(
        () => GtfsDataset.fromFiles(invalidFiles, sourceName: 'invalid.zip'),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('stop_sequence'),
          ),
        ),
      );
    },
  );
}
