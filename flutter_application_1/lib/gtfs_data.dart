import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:csv/csv.dart';
import 'package:flutter/foundation.dart';

typedef GtfsColumnMappings = Map<String, Map<String, int>>;

class GtfsFeedPreview {
  const GtfsFeedPreview(this.headersByFile);

  final Map<String, List<String>> headersByFile;
}

class TransitStop {
  const TransitStop({
    required this.id,
    required this.name,
    this.code = '',
    this.description = '',
    this.latitude,
    this.longitude,
  });

  final String id;
  final String name;
  final String code;
  final String description;
  final double? latitude;
  final double? longitude;
}

class RouteStopSequence {
  const RouteStopSequence({
    required this.startStopId,
    required this.endStopId,
    required this.stopIds,
    this.tripCount = 1,
  });

  final String startStopId;
  final String endStopId;
  final List<String> stopIds;
  final int tripCount;
}

class StopServiceOperatingTimes {
  const StopServiceOperatingTimes({
    this.firstArrivalSeconds,
    this.latestScheduledDepartureSeconds,
    this.latestScheduledTravelSeconds,
    this.firstFrequencyDepartureSeconds,
    this.lastFrequencyDepartureSeconds,
    this.frequencyTravelSeconds,
    this.minimumFrequencyHeadwaySeconds,
    this.maximumFrequencyHeadwaySeconds,
    this.headwayIsEstimated = false,
  });

  final int? firstArrivalSeconds;
  final int? latestScheduledDepartureSeconds;
  final int? latestScheduledTravelSeconds;
  final int? firstFrequencyDepartureSeconds;
  final int? lastFrequencyDepartureSeconds;
  final int? frequencyTravelSeconds;
  final int? minimumFrequencyHeadwaySeconds;
  final int? maximumFrequencyHeadwaySeconds;
  final bool headwayIsEstimated;
}

class TransitRoute {
  const TransitRoute({
    required this.id,
    required this.shortName,
    required this.longName,
    required this.type,
    required this.stopIds,
    required this.stopSequences,
    required this.firstStopId,
    required this.departureTimesByServiceId,
    required this.serviceDaysByServiceId,
    required this.stopOperatingTimesByStopId,
    required this.hasEstimatedFrequencyDepartures,
    required this.hasFrequencyTripsWithoutStopTimes,
    this.description = '',
    this.color,
    this.textColor,
  });

  final String id;
  final String shortName;
  final String longName;
  final String description;
  final String type;
  final String? color;
  final String? textColor;
  final List<String> stopIds;
  final List<RouteStopSequence> stopSequences;
  final String firstStopId;
  final Map<String, List<String>> departureTimesByServiceId;
  final Map<String, String> serviceDaysByServiceId;
  final Map<String, Map<String, Map<String, StopServiceOperatingTimes>>>
  stopOperatingTimesByStopId;
  final bool hasEstimatedFrequencyDepartures;
  final bool hasFrequencyTripsWithoutStopTimes;

  List<String> get departureTimes => [
    for (final times in departureTimesByServiceId.values) ...times,
  ];

  String get displayName {
    if (shortName.isEmpty) return longName.isEmpty ? id : longName;
    if (longName.isEmpty || longName == shortName) return shortName;
    return '$shortName · $longName';
  }
}

class GtfsDataset {
  const GtfsDataset({
    required this.stops,
    required this.routes,
    required this.routeIdsByStopId,
    required this.agencyName,
    required this.sourceName,
  });

  final List<TransitStop> stops;
  final List<TransitRoute> routes;
  final Map<String, List<String>> routeIdsByStopId;
  final String agencyName;
  final String sourceName;

  static Future<GtfsDataset> fromZip(
    List<int> bytes, {
    required String sourceName,
    GtfsColumnMappings columnMappings = const {},
  }) {
    return compute(
      _parseZipInBackground,
      _GtfsZipImportRequest(
        bytes: bytes,
        sourceName: sourceName,
        columnMappings: columnMappings,
      ),
    );
  }

  static Future<GtfsFeedPreview> inspectZip(List<int> bytes) {
    return compute(_inspectZipInBackground, bytes);
  }

  static GtfsDataset fromFiles(
    Map<String, String> files, {
    required String sourceName,
    GtfsColumnMappings columnMappings = const {},
  }) {
    for (final name in ['routes.txt', 'stops.txt', 'trips.txt']) {
      if (!files.containsKey(name)) {
        throw FormatException('This feed is missing the required $name file.');
      }
    }
    if (!files.containsKey('stop_times.txt') &&
        !files.containsKey('frequencies.txt')) {
      throw const FormatException(
        'This feed needs stop_times.txt or frequencies.txt to provide schedules.',
      );
    }

    final routeRows = _readCsv(
      files['routes.txt']!,
      'routes.txt',
      columnMappings['routes.txt'] ?? const {},
    );
    final stopRows = _readCsv(
      files['stops.txt']!,
      'stops.txt',
      columnMappings['stops.txt'] ?? const {},
    );
    final tripRows = _readCsv(
      files['trips.txt']!,
      'trips.txt',
      columnMappings['trips.txt'] ?? const {},
    );
    final stopTimeRows = files['stop_times.txt'] == null
        ? <Map<String, String>>[]
        : _readCsv(
            files['stop_times.txt']!,
            'stop_times.txt',
            columnMappings['stop_times.txt'] ?? const {},
          );
    final frequencyRows = files['frequencies.txt'] == null
        ? <Map<String, String>>[]
        : _readCsv(
            files['frequencies.txt']!,
            'frequencies.txt',
            columnMappings['frequencies.txt'] ?? const {},
          );
    final calendarRows = files['calendar.txt'] == null
        ? <Map<String, String>>[]
        : _readCsv(
            files['calendar.txt']!,
            'calendar.txt',
            columnMappings['calendar.txt'] ?? const {},
          );
    final serviceDaysByServiceId = <String, String>{};
    for (final row in calendarRows) {
      final serviceId = row['service_id'] ?? '';
      if (serviceId.isEmpty) continue;
      final activeDays = <String>[];
      for (final day in _calendarDays) {
        final value = row[day.$1] ?? '';
        if (value != '0' && value != '1') {
          throw FormatException(
            'calendar.txt has an invalid ${day.$1} value for service $serviceId.',
          );
        }
        if (value == '1') activeDays.add(day.$2);
      }
      serviceDaysByServiceId[serviceId] = _formatServiceDays(activeDays);
    }
    final routes = <String, _RouteRecord>{};
    for (final row in routeRows) {
      final id = row['route_id'] ?? '';
      if (id.isEmpty) continue;
      routes[id] = _RouteRecord(
        id: id,
        shortName: row['route_short_name'] ?? '',
        longName: row['route_long_name'] ?? '',
        description: row['route_desc'] ?? '',
        type: row['route_type'] ?? '',
        color: row['route_color'],
        textColor: row['route_text_color'],
      );
    }
    if (routes.isEmpty) {
      throw const FormatException('No valid routes were found in routes.txt.');
    }

    final stops = <String, TransitStop>{};
    for (final row in stopRows) {
      final id = row['stop_id'] ?? '';
      final name = row['stop_name'] ?? '';
      if (id.isEmpty || name.isEmpty) continue;
      stops[id] = TransitStop(
        id: id,
        name: name,
        code: row['stop_code'] ?? '',
        description: row['stop_desc'] ?? '',
        latitude: double.tryParse(row['stop_lat'] ?? ''),
        longitude: double.tryParse(row['stop_lon'] ?? ''),
      );
    }
    if (stops.isEmpty) {
      throw const FormatException('No valid stops were found in stops.txt.');
    }

    final routeIdByTripId = <String, String>{};
    final serviceIdByTripId = <String, String>{};
    for (final row in tripRows) {
      final tripId = row['trip_id'] ?? '';
      final routeId = row['route_id'] ?? '';
      if (tripId.isNotEmpty && routes.containsKey(routeId)) {
        routeIdByTripId[tripId] = routeId;
        serviceIdByTripId[tripId] = row['service_id'] ?? '';
      }
    }

    final frequenciesByTripId = <String, List<_FrequencyRecord>>{};
    for (final row in frequencyRows) {
      final tripId = row['trip_id'] ?? '';
      if (!routeIdByTripId.containsKey(tripId)) {
        throw FormatException(
          'frequencies.txt references an unknown trip_id: $tripId.',
        );
      }
      final startSeconds = _timeInSeconds(row['start_time'] ?? '');
      final endSeconds = _timeInSeconds(row['end_time'] ?? '');
      final headwaySeconds = int.tryParse(row['headway_secs'] ?? '');
      if (startSeconds == null || endSeconds == null) {
        throw FormatException(
          'frequencies.txt has an invalid time range for trip $tripId.',
        );
      }
      if (endSeconds <= startSeconds) {
        throw FormatException(
          'frequencies.txt end_time must be later than start_time for trip $tripId.',
        );
      }
      if (headwaySeconds == null || headwaySeconds <= 0) {
        throw FormatException(
          'frequencies.txt has an invalid headway_secs for trip $tripId.',
        );
      }
      final exactTimes = row['exact_times'] ?? '0';
      if (exactTimes != '0' && exactTimes != '1') {
        throw FormatException(
          'frequencies.txt has an invalid exact_times value for trip $tripId.',
        );
      }
      frequenciesByTripId
          .putIfAbsent(tripId, () => [])
          .add(
            _FrequencyRecord(
              startSeconds: startSeconds,
              endSeconds: endSeconds,
              headwaySeconds: headwaySeconds,
              isEstimated: exactTimes != '1',
            ),
          );
    }

    final stopTimesByTrip = <String, List<_StopTimeRecord>>{};
    for (final row in stopTimeRows) {
      final tripId = row['trip_id'] ?? '';
      final stopId = row['stop_id'] ?? '';
      if (!routeIdByTripId.containsKey(tripId) || !stops.containsKey(stopId)) {
        continue;
      }
      final sequence = int.tryParse(row['stop_sequence'] ?? '');
      if (sequence == null || sequence < 0) {
        throw FormatException(
          'stop_times.txt has an invalid stop_sequence for trip $tripId.',
        );
      }
      stopTimesByTrip
          .putIfAbsent(tripId, () => [])
          .add(
            _StopTimeRecord(
              stopId: stopId,
              sequence: sequence,
              departureTime: row['departure_time'] ?? '',
              arrivalTime: row['arrival_time'] ?? '',
            ),
          );
    }

    final stopSequenceByRoute = <String, Map<String, int>>{};
    final stopSequenceByRouteAndFirstStop =
        <String, Map<String, Map<String, int>>>{};
    final startCountsByRoute = <String, Map<String, int>>{};
    final stopSequencesByRoute = <String, Map<String, RouteStopSequence>>{};
    final tripCountsBySequenceKey = <String, Map<String, int>>{};
    final departuresByRoute = <String, List<_DepartureRecord>>{};
    final routeIdsByStopId = <String, Set<String>>{};
    for (final entry in stopTimesByTrip.entries) {
      final routeId = routeIdByTripId[entry.key]!;
      final orderedTimes = entry.value
        ..sort((a, b) => a.sequence.compareTo(b.sequence));
      if (orderedTimes.isEmpty) continue;
      final firstStop = orderedTimes.first.stopId;
      final tripStopIds = orderedTimes.map((time) => time.stopId).toList();
      final sequenceKey = tripStopIds.join('\u001f');
      stopSequencesByRoute
          .putIfAbsent(routeId, () => {})
          .putIfAbsent(
            sequenceKey,
            () => RouteStopSequence(
              startStopId: tripStopIds.first,
              endStopId: tripStopIds.last,
              stopIds: tripStopIds,
            ),
          );
      tripCountsBySequenceKey
          .putIfAbsent(routeId, () => {})
          .update(sequenceKey, (count) => count + 1, ifAbsent: () => 1);
      final sequence = stopSequenceByRoute.putIfAbsent(routeId, () => {});
      final sequenceByFirstStop = stopSequenceByRouteAndFirstStop
          .putIfAbsent(routeId, () => {})
          .putIfAbsent(firstStop, () => {});
      for (final stopTime in orderedTimes) {
        sequence.update(
          stopTime.stopId,
          (previous) =>
              previous < stopTime.sequence ? previous : stopTime.sequence,
          ifAbsent: () => stopTime.sequence,
        );
        sequenceByFirstStop.update(
          stopTime.stopId,
          (previous) =>
              previous < stopTime.sequence ? previous : stopTime.sequence,
          ifAbsent: () => stopTime.sequence,
        );
        routeIdsByStopId.putIfAbsent(stopTime.stopId, () => {}).add(routeId);
      }
      startCountsByRoute
          .putIfAbsent(routeId, () => {})
          .update(firstStop, (count) => count + 1, ifAbsent: () => 1);
      final departureTime = orderedTimes.first.departureTime.isNotEmpty
          ? orderedTimes.first.departureTime
          : orderedTimes.first.arrivalTime;
      if (departureTime.isNotEmpty &&
          !frequenciesByTripId.containsKey(entry.key)) {
        departuresByRoute
            .putIfAbsent(routeId, () => [])
            .add(
              _DepartureRecord(
                stopId: firstStop,
                serviceId: serviceIdByTripId[entry.key]!,
                time: departureTime,
                seconds: _timeInSeconds(departureTime),
              ),
            );
      }
    }

    final routesWithEstimatedFrequencies = <String>{};
    final routesWithFrequencyTripsWithoutStopTimes = <String>{};
    for (final entry in frequenciesByTripId.entries) {
      final routeId = routeIdByTripId[entry.key]!;
      final tripStopTimes = stopTimesByTrip[entry.key];
      tripStopTimes?.sort((a, b) => a.sequence.compareTo(b.sequence));
      final firstStop = tripStopTimes == null || tripStopTimes.isEmpty
          ? ''
          : tripStopTimes.first.stopId;
      if (firstStop.isEmpty) {
        routesWithFrequencyTripsWithoutStopTimes.add(routeId);
      }
      for (final frequency in entry.value) {
        if (frequency.isEstimated) {
          routesWithEstimatedFrequencies.add(routeId);
        }
        for (
          var seconds = frequency.startSeconds;
          seconds <= frequency.endSeconds;
          seconds += frequency.headwaySeconds
        ) {
          departuresByRoute
              .putIfAbsent(routeId, () => [])
              .add(
                _DepartureRecord(
                  stopId: firstStop,
                  serviceId: serviceIdByTripId[entry.key]!,
                  time: _formatGtfsTime(seconds),
                  seconds: seconds,
                  isFrequency: true,
                ),
              );
        }
      }
    }

    final transitRoutes = <TransitRoute>[];
    for (final route in routes.values) {
      final routeStopSequence = stopSequenceByRoute[route.id] ?? {};
      final startCounts = startCountsByRoute[route.id] ?? {};
      String? primaryFirstStop;
      for (final entry in startCounts.entries) {
        if (primaryFirstStop == null ||
            entry.value > startCounts[primaryFirstStop]! ||
            (entry.value == startCounts[primaryFirstStop] &&
                entry.key.compareTo(primaryFirstStop) < 0)) {
          primaryFirstStop = entry.key;
        }
      }
      final primarySequence =
          stopSequenceByRouteAndFirstStop[route.id]?[primaryFirstStop] ?? {};
      final orderedStopIds = routeStopSequence.keys.toList()
        ..sort((a, b) {
          final aPrimarySequence = primarySequence[a];
          final bPrimarySequence = primarySequence[b];
          if (aPrimarySequence != null && bPrimarySequence != null) {
            final sequenceComparison = aPrimarySequence.compareTo(
              bPrimarySequence,
            );
            if (sequenceComparison != 0) return sequenceComparison;
          } else if (aPrimarySequence != null) {
            return -1;
          } else if (bPrimarySequence != null) {
            return 1;
          }
          final sequenceComparison = routeStopSequence[a]!.compareTo(
            routeStopSequence[b]!,
          );
          return sequenceComparison != 0 ? sequenceComparison : a.compareTo(b);
        });
      final departures =
          (departuresByRoute[route.id] ?? [])
              .where(
                (departure) =>
                    departure.stopId.isEmpty ||
                    primaryFirstStop == null ||
                    departure.stopId == primaryFirstStop,
              )
              .toList()
            ..sort((a, b) {
              if (a.seconds != null && b.seconds != null) {
                return a.seconds!.compareTo(b.seconds!);
              }
              return a.time.compareTo(b.time);
            });
      final departureTimesByServiceId = <String, List<String>>{};
      final seenDepartureTimesByServiceId = <String, Set<String>>{};
      for (final departure in departures) {
        final seenTimes = seenDepartureTimesByServiceId.putIfAbsent(
          departure.serviceId,
          () => <String>{},
        );
        if (seenTimes.add(departure.time)) {
          departureTimesByServiceId
              .putIfAbsent(departure.serviceId, () => [])
              .add(departure.time);
        }
      }
      final orderedDepartureTimesByServiceId = {
        for (final serviceId in departureTimesByServiceId.keys.toList()..sort())
          serviceId: departureTimesByServiceId[serviceId]!,
      };
      final stopOperatingTimesByStopId = _stopOperatingTimesForRoute(
        routeId: route.id,
        stopTimesByTrip: stopTimesByTrip,
        routeIdByTripId: routeIdByTripId,
        serviceIdByTripId: serviceIdByTripId,
        frequenciesByTripId: frequenciesByTripId,
        departures: departuresByRoute[route.id] ?? const [],
      );
      transitRoutes.add(
        TransitRoute(
          id: route.id,
          shortName: route.shortName,
          longName: route.longName,
          description: route.description,
          type: route.type,
          color: route.color,
          textColor: route.textColor,
          stopIds: orderedStopIds,
          stopSequences:
              (stopSequencesByRoute[route.id]?.values.map((sequence) {
                      final sequenceKey = sequence.stopIds.join('\u001f');
                      return RouteStopSequence(
                        startStopId: sequence.startStopId,
                        endStopId: sequence.endStopId,
                        stopIds: sequence.stopIds,
                        tripCount:
                            tripCountsBySequenceKey[route.id]?[sequenceKey] ??
                            1,
                      );
                    }).toList() ??
                    [])
                ..sort((a, b) {
                  if (a.startStopId == primaryFirstStop &&
                      b.startStopId != primaryFirstStop) {
                    return -1;
                  }
                  if (b.startStopId == primaryFirstStop &&
                      a.startStopId != primaryFirstStop) {
                    return 1;
                  }
                  final startComparison = a.startStopId.compareTo(
                    b.startStopId,
                  );
                  if (startComparison != 0) return startComparison;
                  return a.endStopId.compareTo(b.endStopId);
                }),
          firstStopId:
              primaryFirstStop ??
              (orderedStopIds.isEmpty ? '' : orderedStopIds.first),
          departureTimesByServiceId: orderedDepartureTimesByServiceId,
          serviceDaysByServiceId: {
            for (final serviceId in orderedDepartureTimesByServiceId.keys)
              if (serviceDaysByServiceId.containsKey(serviceId))
                serviceId: serviceDaysByServiceId[serviceId]!,
          },
          stopOperatingTimesByStopId: stopOperatingTimesByStopId,
          hasEstimatedFrequencyDepartures: routesWithEstimatedFrequencies
              .contains(route.id),
          hasFrequencyTripsWithoutStopTimes:
              routesWithFrequencyTripsWithoutStopTimes.contains(route.id),
        ),
      );
    }

    transitRoutes.sort((a, b) {
      final nameComparison = a.displayName.toLowerCase().compareTo(
        b.displayName.toLowerCase(),
      );
      return nameComparison != 0 ? nameComparison : a.id.compareTo(b.id);
    });
    final sortedStops = stops.values.toList()
      ..sort((a, b) {
        final nameComparison = a.name.toLowerCase().compareTo(
          b.name.toLowerCase(),
        );
        return nameComparison != 0 ? nameComparison : a.id.compareTo(b.id);
      });
    final agencyRows = files['agency.txt'] == null
        ? <Map<String, String>>[]
        : _readCsv(
            files['agency.txt']!,
            'agency.txt',
            columnMappings['agency.txt'] ?? const {},
          );
    final agencyName = agencyRows.isEmpty
        ? ''
        : (agencyRows.first['agency_name'] ?? '').trim();

    return GtfsDataset(
      stops: sortedStops,
      routes: transitRoutes,
      routeIdsByStopId: {
        for (final entry in routeIdsByStopId.entries)
          entry.key: entry.value.toList()..sort(),
      },
      agencyName: agencyName,
      sourceName: sourceName,
    );
  }
}

List<Map<String, String>> _readCsv(
  String source,
  String filename, [
  Map<String, int> columnMappings = const {},
]) {
  try {
    final rows = _convertCsv(source);
    if (rows.isEmpty) {
      throw const FormatException('The file is empty.');
    }
    final sourceHeaders = rows.first
        .map((value) => value.toString().replaceFirst('\uFEFF', '').trim())
        .toList();
    final fieldIndexes = <String, int>{};
    for (final entry in columnMappings.entries) {
      if (entry.value < 0 || entry.value >= sourceHeaders.length) {
        throw FormatException(
          '$filename has no column ${entry.value + 1} for ${entry.key}.',
        );
      }
      fieldIndexes[entry.key] = entry.value;
    }
    for (final field in _usedHeaders(filename)) {
      fieldIndexes.putIfAbsent(field, () => sourceHeaders.indexOf(field));
    }
    final requiredHeaders = _requiredHeaders(filename);
    final missingHeaders = requiredHeaders
        .where((header) => (fieldIndexes[header] ?? -1) < 0)
        .toList();
    if (missingHeaders.isNotEmpty) {
      throw FormatException(
        '$filename is missing required column(s): ${missingHeaders.join(', ')}.',
      );
    }
    if (filename == 'routes.txt' &&
        (fieldIndexes['route_short_name'] ?? -1) < 0 &&
        (fieldIndexes['route_long_name'] ?? -1) < 0) {
      throw const FormatException(
        'routes.txt must include route_short_name or route_long_name.',
      );
    }
    if (filename == 'stop_times.txt' &&
        (fieldIndexes['arrival_time'] ?? -1) < 0 &&
        (fieldIndexes['departure_time'] ?? -1) < 0) {
      throw const FormatException(
        'stop_times.txt must include arrival_time or departure_time.',
      );
    }
    return [
      for (final row in rows.skip(1))
        if (row.any((value) => value.toString().trim().isNotEmpty))
          {
            for (final entry in fieldIndexes.entries)
              if (entry.value >= 0 && entry.value < row.length)
                entry.key: row[entry.value].toString().trim(),
          },
    ];
  } on FormatException {
    rethrow;
  } catch (error) {
    throw FormatException('Could not parse $filename: $error');
  }
}

Map<String, String> _decodeZipFiles(List<int> bytes) {
  final files = <String, String>{};
  try {
    final archive = ZipDecoder().decodeBytes(bytes);
    for (final file in archive.files) {
      if (!file.isFile) continue;
      final name = file.name.replaceAll('\\', '/').split('/').last;
      if (const {
        'agency.txt',
        'calendar.txt',
        'routes.txt',
        'stops.txt',
        'trips.txt',
        'stop_times.txt',
        'frequencies.txt',
      }.contains(name)) {
        files[name] = utf8.decode(file.content, allowMalformed: false);
      }
    }
  } on FormatException {
    rethrow;
  } catch (error) {
    throw FormatException('Could not read this ZIP file: $error');
  }
  return files;
}

List<String> _csvHeaders(String source, String filename) {
  try {
    final rows = _convertCsv(_firstCsvRecord(source));
    if (rows.isEmpty) return const [];
    return rows.first
        .map((value) => value.toString().replaceFirst('\uFEFF', '').trim())
        .toList();
  } on FormatException {
    rethrow;
  } catch (error) {
    throw FormatException('Could not inspect $filename: $error');
  }
}

List<List<dynamic>> _convertCsv(String source) {
  final normalizedSource = source
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n');
  return const CsvToListConverter(
    shouldParseNumbers: false,
    eol: '\n',
  ).convert(normalizedSource);
}

String _firstCsvRecord(String source) {
  var insideQuotedField = false;
  for (var i = 0; i < source.length; i++) {
    final character = source[i];
    if (character == '"') {
      if (insideQuotedField && i + 1 < source.length && source[i + 1] == '"') {
        i++;
      } else {
        insideQuotedField = !insideQuotedField;
      }
    } else if (!insideQuotedField && (character == '\n' || character == '\r')) {
      return source.substring(0, i);
    }
  }
  return source;
}

GtfsFeedPreview _inspectZipInBackground(List<int> bytes) {
  final files = _decodeZipFiles(bytes);
  return GtfsFeedPreview({
    for (final entry in files.entries)
      entry.key: _csvHeaders(entry.value, entry.key),
  });
}

GtfsDataset _parseZipInBackground(_GtfsZipImportRequest request) {
  return GtfsDataset.fromFiles(
    _decodeZipFiles(request.bytes),
    sourceName: request.sourceName,
    columnMappings: request.columnMappings,
  );
}

class _GtfsZipImportRequest {
  const _GtfsZipImportRequest({
    required this.bytes,
    required this.sourceName,
    required this.columnMappings,
  });

  final List<int> bytes;
  final String sourceName;
  final GtfsColumnMappings columnMappings;
}

Set<String> _requiredHeaders(String filename) => switch (filename) {
  'routes.txt' => {'route_id', 'route_type'},
  'stops.txt' => {'stop_id', 'stop_name'},
  'trips.txt' => {'route_id', 'service_id', 'trip_id'},
  'stop_times.txt' => {'trip_id', 'stop_id', 'stop_sequence'},
  'frequencies.txt' => {'trip_id', 'start_time', 'end_time', 'headway_secs'},
  'calendar.txt' => {'service_id', for (final day in _calendarDays) day.$1},
  _ => {'agency_name'},
};

Set<String> _usedHeaders(String filename) => switch (filename) {
  'routes.txt' => {
    'route_id',
    'route_short_name',
    'route_long_name',
    'route_desc',
    'route_type',
    'route_color',
    'route_text_color',
  },
  'stops.txt' => {
    'stop_id',
    'stop_name',
    'stop_code',
    'stop_desc',
    'stop_lat',
    'stop_lon',
  },
  'trips.txt' => {'route_id', 'service_id', 'trip_id'},
  'stop_times.txt' => {
    'trip_id',
    'stop_id',
    'stop_sequence',
    'arrival_time',
    'departure_time',
  },
  'frequencies.txt' => {
    'trip_id',
    'start_time',
    'end_time',
    'headway_secs',
    'exact_times',
  },
  'calendar.txt' => {'service_id', for (final day in _calendarDays) day.$1},
  _ => {'agency_name'},
};

const _calendarDays = [
  ('monday', 'Monday'),
  ('tuesday', 'Tuesday'),
  ('wednesday', 'Wednesday'),
  ('thursday', 'Thursday'),
  ('friday', 'Friday'),
  ('saturday', 'Saturday'),
  ('sunday', 'Sunday'),
];

String _formatServiceDays(List<String> days) {
  if (days.length == 7) return 'Every day';
  if (days.length == 5 &&
      days.take(5).join(', ') ==
          const [
            'Monday',
            'Tuesday',
            'Wednesday',
            'Thursday',
            'Friday',
          ].join(', ')) {
    return 'Monday to Friday';
  }
  if (days.length == 2 && days.join(', ') == 'Saturday, Sunday') {
    return 'Saturday and Sunday';
  }
  return days.isEmpty ? 'No days scheduled' : days.join(', ');
}

Map<String, Map<String, Map<String, StopServiceOperatingTimes>>>
_stopOperatingTimesForRoute({
  required String routeId,
  required Map<String, List<_StopTimeRecord>> stopTimesByTrip,
  required Map<String, String> routeIdByTripId,
  required Map<String, String> serviceIdByTripId,
  required Map<String, List<_FrequencyRecord>> frequenciesByTripId,
  required List<_DepartureRecord> departures,
}) {
  final timesByStopAndService =
      <String, Map<String, Map<String, _StopOperatingTimesBuilder>>>{};
  final frequencyDeparturesByHubAndService = <String, Map<String, List<int>>>{};
  final scheduledDeparturesByHubAndService = <String, Map<String, Set<int>>>{};
  for (final departure in departures) {
    if (!departure.isFrequency || departure.seconds == null) {
      continue;
    }
    frequencyDeparturesByHubAndService
        .putIfAbsent(departure.stopId, () => {})
        .putIfAbsent(departure.serviceId, () => [])
        .add(departure.seconds!);
  }

  for (final entry in stopTimesByTrip.entries) {
    if (routeIdByTripId[entry.key] != routeId) continue;
    final serviceId = serviceIdByTripId[entry.key] ?? '';
    final stopTimes = entry.value
      ..sort((a, b) => a.sequence.compareTo(b.sequence));
    if (stopTimes.isEmpty) continue;

    final firstStop = stopTimes.first;
    final startTime = firstStop.departureTime.isNotEmpty
        ? firstStop.departureTime
        : firstStop.arrivalTime;
    final startSeconds = _timeInSeconds(startTime);
    final isFrequencyTrip = frequenciesByTripId.containsKey(entry.key);
    for (final stopTime in stopTimes) {
      final builder = timesByStopAndService
          .putIfAbsent(stopTime.stopId, () => {})
          .putIfAbsent(firstStop.stopId, () => {})
          .putIfAbsent(serviceId, _StopOperatingTimesBuilder.new);
      final arrivalSeconds = _timeInSeconds(stopTime.arrivalTime);
      if (isFrequencyTrip) {
        if (startSeconds != null &&
            arrivalSeconds != null &&
            builder.frequencyTravelSeconds == null) {
          builder.frequencyTravelSeconds = stopTime.stopId == firstStop.stopId
              ? 0
              : arrivalSeconds - startSeconds;
        }
        for (final frequency in frequenciesByTripId[entry.key]!) {
          final currentMinimum = builder.minimumFrequencyHeadwaySeconds;
          final currentMaximum = builder.maximumFrequencyHeadwaySeconds;
          builder
            ..minimumFrequencyHeadwaySeconds =
                currentMinimum == null ||
                    frequency.headwaySeconds < currentMinimum
                ? frequency.headwaySeconds
                : currentMinimum
            ..maximumFrequencyHeadwaySeconds =
                currentMaximum == null ||
                    frequency.headwaySeconds > currentMaximum
                ? frequency.headwaySeconds
                : currentMaximum;
        }
        continue;
      }
      if (stopTime.stopId == firstStop.stopId && startSeconds != null) {
        scheduledDeparturesByHubAndService
            .putIfAbsent(firstStop.stopId, () => {})
            .putIfAbsent(serviceId, () => <int>{})
            .add(startSeconds);
      }
      if (arrivalSeconds != null &&
          (builder.firstArrivalSeconds == null ||
              arrivalSeconds < builder.firstArrivalSeconds!)) {
        builder.firstArrivalSeconds = arrivalSeconds;
      }
      if (startSeconds == null || arrivalSeconds == null) continue;
      if (builder.latestScheduledDepartureSeconds == null ||
          startSeconds > builder.latestScheduledDepartureSeconds!) {
        builder
          ..latestScheduledDepartureSeconds = startSeconds
          ..latestScheduledTravelSeconds = stopTime.stopId == firstStop.stopId
              ? 0
              : arrivalSeconds - startSeconds;
      }
    }
  }

  return {
    for (final stopEntry in timesByStopAndService.entries)
      stopEntry.key: {
        for (final hubEntry in stopEntry.value.entries)
          hubEntry.key: {
            for (final serviceEntry in hubEntry.value.entries)
              serviceEntry.key: () {
                final frequencyDepartures =
                    frequencyDeparturesByHubAndService[hubEntry
                        .key]?[serviceEntry.key] ??
                    const <int>[];
                final orderedFrequencyDepartures = frequencyDepartures.toList()
                  ..sort();
                final scheduledDepartures =
                    scheduledDeparturesByHubAndService[hubEntry
                            .key]?[serviceEntry.key]
                        ?.toList() ??
                    <int>[];
                scheduledDepartures.sort();
                final scheduledHeadways = [
                  for (
                    var index = 1;
                    index < scheduledDepartures.length;
                    index++
                  )
                    scheduledDepartures[index] - scheduledDepartures[index - 1],
                ]..removeWhere((headway) => headway <= 0);
                final inferredHeadway =
                    frequenciesByTripId.isEmpty && scheduledHeadways.isNotEmpty
                    ? (
                        minimum: scheduledHeadways.reduce(
                          (a, b) => a < b ? a : b,
                        ),
                        maximum: scheduledHeadways.reduce(
                          (a, b) => a > b ? a : b,
                        ),
                      )
                    : null;
                return StopServiceOperatingTimes(
                  firstArrivalSeconds:
                      serviceEntry.value.firstArrivalSeconds ??
                      (orderedFrequencyDepartures.isEmpty ||
                              serviceEntry.value.frequencyTravelSeconds == null
                          ? null
                          : orderedFrequencyDepartures.first +
                                serviceEntry.value.frequencyTravelSeconds!),
                  latestScheduledDepartureSeconds:
                      serviceEntry.value.latestScheduledDepartureSeconds,
                  latestScheduledTravelSeconds:
                      serviceEntry.value.latestScheduledTravelSeconds,
                  firstFrequencyDepartureSeconds:
                      orderedFrequencyDepartures.firstOrNull,
                  lastFrequencyDepartureSeconds:
                      orderedFrequencyDepartures.lastOrNull,
                  frequencyTravelSeconds:
                      serviceEntry.value.frequencyTravelSeconds,
                  minimumFrequencyHeadwaySeconds:
                      serviceEntry.value.minimumFrequencyHeadwaySeconds ??
                      inferredHeadway?.minimum,
                  maximumFrequencyHeadwaySeconds:
                      serviceEntry.value.maximumFrequencyHeadwaySeconds ??
                      inferredHeadway?.maximum,
                  headwayIsEstimated: inferredHeadway != null,
                );
              }(),
          },
      },
  };
}

int? _timeInSeconds(String time) {
  final parts = time.split(':');
  if (parts.length != 3) return null;
  final hours = int.tryParse(parts[0]);
  final minutes = int.tryParse(parts[1]);
  final seconds = int.tryParse(parts[2]);
  if (hours == null ||
      minutes == null ||
      seconds == null ||
      hours < 0 ||
      minutes < 0 ||
      minutes > 59 ||
      seconds < 0 ||
      seconds > 59) {
    return null;
  }
  return hours * 3600 + minutes * 60 + seconds;
}

class _StopOperatingTimesBuilder {
  int? firstArrivalSeconds;
  int? latestScheduledDepartureSeconds;
  int? latestScheduledTravelSeconds;
  int? frequencyTravelSeconds;
  int? minimumFrequencyHeadwaySeconds;
  int? maximumFrequencyHeadwaySeconds;
  bool headwayIsEstimated = false;
}

String _formatGtfsTime(int seconds) {
  final hours = seconds ~/ 3600;
  final minutes = (seconds % 3600) ~/ 60;
  final remainingSeconds = seconds % 60;
  return '${hours.toString().padLeft(2, '0')}:'
      '${minutes.toString().padLeft(2, '0')}:'
      '${remainingSeconds.toString().padLeft(2, '0')}';
}

class _RouteRecord {
  const _RouteRecord({
    required this.id,
    required this.shortName,
    required this.longName,
    required this.description,
    required this.type,
    required this.color,
    required this.textColor,
  });

  final String id;
  final String shortName;
  final String longName;
  final String description;
  final String type;
  final String? color;
  final String? textColor;
}

class _StopTimeRecord {
  const _StopTimeRecord({
    required this.stopId,
    required this.sequence,
    required this.departureTime,
    required this.arrivalTime,
  });

  final String stopId;
  final int sequence;
  final String departureTime;
  final String arrivalTime;
}

class _DepartureRecord {
  const _DepartureRecord({
    required this.stopId,
    required this.serviceId,
    required this.time,
    required this.seconds,
    this.isFrequency = false,
  });

  final String stopId;
  final String serviceId;
  final String time;
  final int? seconds;
  final bool isFrequency;
}

class _FrequencyRecord {
  const _FrequencyRecord({
    required this.startSeconds,
    required this.endSeconds,
    required this.headwaySeconds,
    required this.isEstimated,
  });

  final int startSeconds;
  final int endSeconds;
  final int headwaySeconds;
  final bool isEstimated;
}
