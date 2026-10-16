import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'gtfs_data.dart';

enum StopPosterLayout { combined, separateRoutes, currentAndNext }

class PosterService {
  static Future<void> printStop({
    required TransitStop stop,
    required List<TransitRoute> routes,
    required List<TransitStop> allStops,
    required String agencyName,
    required StopPosterLayout layout,
    required Future<void> Function() onPdfGenerated,
  }) async {
    final document = pw.Document();
    final stopById = {for (final item in allStops) item.id: item};
    final sharedRoutesByStopId = _sharedRoutesByStopId(routes);

    if (routes.isEmpty) {
      document.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(38),
          //header: (context) => _header(agencyName),
          footer: (context) => _footer(context),
          build: (context) => [
            ..._stopHeading(stop),
            _emptyMessage('No routes are listed for this stop.'),
          ],
        ),
      );
    } else if (layout == StopPosterLayout.combined) {
      document.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(38),
          //header: (context) => _header(agencyName),
          footer: (context) => _footer(context),
          build: (context) => [
            ..._stopHeading(stop),
            _eyebrow('COMBINED ROUTE GUIDE · ${routes.length} ROUTES'),
            pw.SizedBox(height: 12),
            for (final route in routes) ...[
              ..._routeHeading(route),
              for (final sequence in _sequencesForRoute(
                route,
                stopById,
                currentStopId: stop.id,
              )) ...[
                _directionHeading(sequence),
                _routeStopsTable(
                  sequence,
                  currentStopId: stop.id,
                  sharedRoutesByStopId: sharedRoutesByStopId,
                ),
                pw.SizedBox(height: 12),
              ],
            ],
          ],
        ),
      );
    } else if (layout == StopPosterLayout.currentAndNext) {
      for (final route in routes) {
        final sequences = _sequencesForRoute(
          route,
          stopById,
          currentStopId: stop.id,
        );
        document.addPage(
          pw.MultiPage(
            pageFormat: PdfPageFormat.a4,
            margin: const pw.EdgeInsets.all(38),
            footer: (context) => _footer(context),
            build: (context) => [
              ..._stopHeading(stop),
              ..._routeHeading(route),
              for (final sequence in sequences)
                ..._currentAndNextSequence(
                  route: route,
                  sequence: sequence,
                  currentStopId: stop.id,
                  sharedRoutesByStopId: sharedRoutesByStopId,
                ),
            ],
          ),
        );
      }
    } else {
      for (final route in routes) {
        document.addPage(
          pw.MultiPage(
            pageFormat: PdfPageFormat.a4,
            margin: const pw.EdgeInsets.all(38),
            //header: (context) => _header(agencyName),
            footer: (context) => _footer(context),
            build: (context) => [
              ..._stopHeading(stop),
              ..._routeHeading(route),
              for (final sequence in _sequencesForRoute(
                route,
                stopById,
                currentStopId: stop.id,
              )) ...[
                _directionHeading(sequence),
                _routeStopsTable(
                  sequence,
                  currentStopId: stop.id,
                  sharedRoutesByStopId: sharedRoutesByStopId,
                ),
              ],
            ],
          ),
        );
      }
    }
    final pdfBytes = await document.save();
    await onPdfGenerated();
    await Printing.layoutPdf(
      name: 'stop-${_safeName(stop.name)}-routes.pdf',
      onLayout: (_) async => pdfBytes,
    );
  }

  static Future<void> printRoute({
    required TransitRoute route,
    required List<TransitStop> allStops,
    required String agencyName,
    required Future<void> Function() onPdfGenerated,
  }) async {
    final document = pw.Document();
    final stopById = {for (final stop in allStops) stop.id: stop};
    final sequences = _sequencesForRoute(route, stopById);
    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(38),
        //header: (context) => _header(agencyName),
        footer: (context) => _footer(context),
        build: (context) {
          final firstStops = allStops.where(
            (stop) => stop.id == route.firstStopId,
          );
          final firstStopName = firstStops.isEmpty
              ? 'first stop'
              : firstStops.first.name;
          final content = <pw.Widget>[
            _eyebrow('ROUTE GUIDE'),
            pw.SizedBox(height: 8),
            pw.Text(
              route.shortName.isEmpty ? route.longName : route.shortName,
              style: pw.TextStyle(
                fontSize: 34,
                fontWeight: pw.FontWeight.bold,
                color: PdfColor.fromHex('#000000'),
              ),
            ),
            if (route.longName.isNotEmpty && route.longName != route.shortName)
              pw.Padding(
                padding: const pw.EdgeInsets.only(top: 4),
                child: pw.Text(
                  route.longName,
                  style: pw.TextStyle(
                    fontSize: 15,
                    color: PdfColor.fromHex('#444444'),
                  ),
                ),
              ),
            pw.SizedBox(height: 21),
            _sectionTitle(
              'Stops along this route',
              sequences.fold<int>(
                0,
                (count, sequence) => count + sequence.length,
              ),
            ),
            pw.SizedBox(height: 10),
          ];
          if (sequences.isEmpty) {
            content.add(_emptyMessage('No stops are listed for this route.'));
          } else {
            for (final sequence in sequences) {
              content
                ..add(_directionHeading(sequence))
                ..add(
                  _routeStopsTable(
                    sequence,
                    currentStopId: null,
                    sharedRoutesByStopId: const {},
                  ),
                )
                ..add(pw.SizedBox(height: 12));
            }
          }
          content.addAll([
            pw.SizedBox(height: 24),
            _sectionTitle(
              'Departures from $firstStopName',
              route.departureTimes.length,
            ),
            if (route.hasEstimatedFrequencyDepartures ||
                route.hasFrequencyTripsWithoutStopTimes)
              pw.Padding(
                padding: const pw.EdgeInsets.only(top: 5),
                child: pw.Text(
                  route.hasFrequencyTripsWithoutStopTimes
                      ? 'Includes frequency departures without stop-time stop details.'
                      : 'Includes estimated frequency-based departure times.',
                  style: pw.TextStyle(
                    fontSize: 9,
                    color: PdfColor.fromHex('#555555'),
                  ),
                ),
              ),
            pw.SizedBox(height: 11),
          ]);
          if (route.departureTimes.isEmpty) {
            content.add(
              _emptyMessage('No departure times are available in this feed.'),
            );
          } else {
            for (final service in route.departureTimesByServiceId.entries) {
              content.addAll([
                pw.Padding(
                  padding: const pw.EdgeInsets.only(bottom: 7),
                  child: pw.Text(
                    route.serviceDaysByServiceId[service.key] ??
                        'Service ID · ${service.key}',
                    style: pw.TextStyle(
                      fontSize: 10,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColor.fromHex('#444444'),
                    ),
                  ),
                ),
                pw.Table(
                  children: [
                    for (
                      var index = 0;
                      index < service.value.length;
                      index += 5
                    )
                      pw.TableRow(
                        children: [
                          for (var slot = index; slot < index + 5; slot++)
                            if (slot < service.value.length)
                              _departureCell(service.value[slot])
                            else
                              pw.SizedBox(height: 34),
                        ],
                      ),
                  ],
                ),
                pw.SizedBox(height: 12),
              ]);
            }
          }
          return content;
        },
      ),
    );
    final pdfBytes = await document.save();
    await onPdfGenerated();
    await Printing.layoutPdf(
      name:
          'route-${_safeName(route.shortName.isEmpty ? route.id : route.shortName)}.pdf',
      onLayout: (_) async => pdfBytes,
    );
  }

  static List<pw.Widget> _stopHeading(TransitStop stop) => [
    pw.SizedBox(height: 8),
    pw.Text(
      stop.name,
      style: pw.TextStyle(fontSize: 28, fontWeight: pw.FontWeight.bold),
    ),
    if (stop.code.isNotEmpty)
      pw.Padding(
        padding: const pw.EdgeInsets.only(top: 4),
        child: pw.Text(
          //'STOP CODE · ${stop.code}',
          '${stop.code}',
          style: pw.TextStyle(fontSize: 10, color: PdfColor.fromHex('#555555')),
        ),
      ),
  ];

  static List<pw.Widget> _routeHeading(TransitRoute route) => [
    pw.SizedBox(height: 8),
    pw.Text(
      route.shortName.isEmpty ? route.displayName : route.shortName,
      style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
    ),
    /*
    if (route.longName.isNotEmpty && route.longName != route.shortName)
      pw.Padding(
        padding: const pw.EdgeInsets.only(top: 2, bottom: 7),
        child: pw.Text(
          route.longName,
          style: pw.TextStyle(fontSize: 10, color: PdfColor.fromHex('#444444')),
        ),
      ),
    */
  ];

  static List<List<TransitStop>> _sequencesForRoute(
    TransitRoute route,
    Map<String, TransitStop> stopById, {
    String? currentStopId,
  }) {
    final routeSequences = route.stopSequences;
    final matchingSequences =
        routeSequences
            .where((sequence) => sequence.stopIds.contains(currentStopId))
            .toList()
          ..sort((a, b) => b.tripCount.compareTo(a.tripCount));
    final selectedSequences = currentStopId == null
        ? routeSequences
        : matchingSequences;
    final sequences = routeSequences.isEmpty
        ? [route.stopIds]
        : currentStopId != null && selectedSequences.isNotEmpty
        ? [selectedSequences.first.stopIds]
        : currentStopId != null
        ? [route.stopIds]
        : routeSequences.map((sequence) => sequence.stopIds).toList();
    return [
      for (final sequence in sequences)
        [
          for (final stopId in sequence)
            if (stopById[stopId] case final stop?) stop,
        ],
    ];
  }

  static List<pw.Widget> _currentAndNextSequence({
    required TransitRoute route,
    required List<TransitStop> sequence,
    required String currentStopId,
    required Map<String, String> sharedRoutesByStopId,
  }) {
    final currentIndex = sequence.indexWhere(
      (stop) => stop.id == currentStopId,
    );
    final forwardStops = currentIndex < 0
        ? <TransitStop>[]
        : sequence.skip(currentIndex).toList();
    return [
      _directionHeading(forwardStops),
      _posterSectionHeading('Estimated operating hours from here'),
      _routeOperatingHoursTable(
        route,
        currentStopId,
        sequence.isEmpty ? null : sequence.first.id,
      ),
      pw.SizedBox(height: 10),
      _posterSectionHeading('Stops'),
      _routeStopsTable(
        forwardStops,
        currentStopId: currentStopId,
        sharedRoutesByStopId: sharedRoutesByStopId,
      ),
      pw.SizedBox(height: 12),
    ];
  }

  static pw.Widget _posterSectionHeading(String title) => pw.Container(
    width: double.infinity,
    padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 7),
    margin: const pw.EdgeInsets.only(bottom: 2),
    color: PdfColor.fromHex('#F3F4F4'),
    child: pw.Text(
      title,
      style: pw.TextStyle(
        fontSize: 9,
        fontWeight: pw.FontWeight.bold,
        color: PdfColor.fromHex('#333333'),
      ),
    ),
  );

  static pw.Widget _routeOperatingHoursTable(
    TransitRoute route,
    String stopId,
    String? startingStopId,
  ) {
    final serviceTimes = startingStopId == null
        ? null
        : route.stopOperatingTimesByStopId[stopId]?[startingStopId];
    final services = serviceTimes?.entries.toList() ?? const [];
    return pw.Table(
      border: pw.TableBorder(
        horizontalInside: pw.BorderSide(
          color: PdfColor.fromHex('#BBBBBB'),
          width: 0.6,
        ),
      ),
      columnWidths: {
        0: const pw.FlexColumnWidth(2),
        1: const pw.FlexColumnWidth(1.2),
        2: const pw.FlexColumnWidth(1),
        3: const pw.FlexColumnWidth(1),
      },
      children: [
        _tableHeader(['', 'FREQUENCY', 'START TIME', 'END TIME']),
        if (services.isEmpty)
          _operatingHoursTableRow(
            'Not available in this feed',
            null,
            null,
            null,
            null,
            false,
          ),
        for (final service in services)
          () {
            final times = service.value;
            final lastHubDeparture =
                times.lastFrequencyDepartureSeconds ??
                times.latestScheduledDepartureSeconds;
            final travelTime = times.lastFrequencyDepartureSeconds == null
                ? times.latestScheduledTravelSeconds
                : times.latestScheduledTravelSeconds ??
                      times.frequencyTravelSeconds;
            final endTime = lastHubDeparture == null || travelTime == null
                ? null
                : lastHubDeparture + travelTime;
            return _operatingHoursTableRow(
              route.serviceDaysByServiceId[service.key] ??
                  'Service ID · ${service.key}',
              times.minimumFrequencyHeadwaySeconds,
              times.maximumFrequencyHeadwaySeconds,
              times.firstArrivalSeconds,
              endTime,
              times.headwayIsEstimated,
            );
          }(),
      ],
    );
  }

  static pw.TableRow _operatingHoursTableRow(
    String serviceName,
    int? minimumHeadwaySeconds,
    int? maximumHeadwaySeconds,
    int? startTime,
    int? endTime,
    bool headwayIsEstimated,
  ) => pw.TableRow(
    children: [
      for (final value in [
        serviceName,
        _formatHeadwayRange(
          minimumHeadwaySeconds,
          maximumHeadwaySeconds,
          isEstimated: headwayIsEstimated,
        ),
        startTime == null ? 'N/A' : _formatTime(startTime),
        endTime == null ? 'N/A' : _formatTime(endTime),
      ])
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 7),
          child: pw.Text(
            value,
            style: pw.TextStyle(
              fontSize: 9,
              color: PdfColor.fromHex('#333333'),
            ),
          ),
        ),
    ],
  );

  static String _formatHeadwayRange(
    int? minimumSeconds,
    int? maximumSeconds, {
    required bool isEstimated,
  }) {
    if (minimumSeconds == null || maximumSeconds == null) return 'N/A';
    final minimum = _formatHeadway(minimumSeconds);
    final range = minimumSeconds == maximumSeconds
        ? 'Every $minimum'
        : 'Every $minimum to ${_formatHeadway(maximumSeconds)}';
    return isEstimated ? '$range' : range;
  }

  static String _formatHeadway(int seconds) {
    if (seconds % 60 == 0) return '${seconds ~/ 60} min';
    return '$seconds sec';
  }

  static String _formatTime(int seconds) {
    final hours = seconds ~/ 3600;
    final minutes = seconds % 3600 ~/ 60;
    return '${hours.toString().padLeft(2, '0')}:'
        '${minutes.toString().padLeft(2, '0')}';
  }

  static pw.Widget _directionHeading(List<TransitStop> stops) {
    final destination = stops.isEmpty ? 'Unknown destination' : stops.last.name;
    return pw.Padding(
      padding: const pw.EdgeInsets.only(top: 5, bottom: 5),
      child: pw.Text(
        //'$origin to $destination',
        'to $destination',
        style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
      ),
    );
  }

  static Map<String, String> _sharedRoutesByStopId(List<TransitRoute> routes) {
    final routeNamesByStop = <String, Set<String>>{};
    for (final route in routes) {
      final routeName = route.shortName.isEmpty ? route.id : route.shortName;
      for (final sequence in route.stopSequences) {
        for (final stopId in sequence.stopIds) {
          routeNamesByStop.putIfAbsent(stopId, () => {}).add(routeName);
        }
      }
      if (route.stopSequences.isEmpty) {
        for (final stopId in route.stopIds) {
          routeNamesByStop.putIfAbsent(stopId, () => {}).add(routeName);
        }
      }
    }
    return {
      for (final entry in routeNamesByStop.entries)
        if (entry.value.length > 1)
          entry.key: (entry.value.toList()..sort()).join(', '),
    };
  }

  static pw.Table _routeStopsTable(
    List<TransitStop> stops, {
    required String? currentStopId,
    required Map<String, String> sharedRoutesByStopId,
  }) => pw.Table(
    border: pw.TableBorder(
      horizontalInside: pw.BorderSide(
        color: PdfColor.fromHex('#BBBBBB'),
        width: 0.6,
      ),
    ),
    columnWidths: {
      0: const pw.FixedColumnWidth(34),
      1: const pw.FlexColumnWidth(1),
      2: const pw.FixedColumnWidth(150),
    },
    children: _routeStopsTableRows(
      stops,
      currentStopId: currentStopId,
      sharedRoutesByStopId: sharedRoutesByStopId,
    ),
  );

  static List<pw.TableRow> _routeStopsTableRows(
    List<TransitStop> stops, {
    required String? currentStopId,
    required Map<String, String> sharedRoutesByStopId,
  }) {
    final currentIndex = stops.indexWhere((stop) => stop.id == currentStopId);
    return [
      _tableHeader(['#', 'STOP', 'STOP CODE']),
      for (var index = 0; index < stops.length; index++)
        _routeStopRow(
          stops[index],
          index: index,
          currentIndex: currentIndex,
          isLast: index == stops.length - 1,
          sharedRouteNames: sharedRoutesByStopId[stops[index].id] ?? '',
        ),
    ];
  }

  static pw.TableRow _routeStopRow(
    TransitStop stop, {
    required int index,
    required int currentIndex,
    required bool isLast,
    required String sharedRouteNames,
  }) {
    final isCurrent = index == currentIndex;
    final isPassed = currentIndex >= 0 && index < currentIndex;
    const background = PdfColor.fromInt(0xFFFFFFFF);
    final foreground = isPassed
        ? PdfColor.fromHex('#AAAAAA')
        : PdfColor.fromHex('#111111');
    return pw.TableRow(
      verticalAlignment: pw.TableCellVerticalAlignment.middle,
      children: [
        _routeStopCell(
          '${index + 1}',
          background: background,
          foreground: foreground,
          bold: isCurrent,
        ),
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(vertical: 7, horizontal: 6),
          decoration: pw.BoxDecoration(
            color: background,
            border: isCurrent
                ? pw.Border(
                    top: pw.BorderSide(
                      color: PdfColor.fromHex('#000000'),
                      width: 1.8,
                    ),
                    right: pw.BorderSide(
                      color: PdfColor.fromHex('#000000'),
                      width: 2,
                    ),
                    bottom: pw.BorderSide(
                      color: PdfColor.fromHex('#000000'),
                      width: 1.8,
                    ),
                    left: pw.BorderSide(
                      color: PdfColor.fromHex('#000000'),
                      width: 1.8,
                    ),
                  )
                : null,
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                stop.name,
                style: pw.TextStyle(
                  fontSize: 9,
                  fontWeight: isCurrent
                      ? pw.FontWeight.bold
                      : pw.FontWeight.normal,
                  color: foreground,
                ),
              ),
              if (isCurrent || isPassed)
                pw.Text(
                  isCurrent ? 'YOU ARE HERE' : 'PASSED',
                  style: pw.TextStyle(
                    fontSize: 7,
                    fontWeight: pw.FontWeight.bold,
                    color: foreground,
                  ),
                ),
              if (isLast)
                pw.Text(
                  isCurrent ? 'YOU ARE HERE · LAST STOP' : 'LAST STOP',
                  style: pw.TextStyle(
                    fontSize: 7,
                    fontWeight: pw.FontWeight.bold,
                    color: foreground,
                  ),
                ),
              if (sharedRouteNames.isNotEmpty)
                pw.Text(
                  'SHARED BY $sharedRouteNames',
                  style: pw.TextStyle(fontSize: 6, color: foreground),
                ),
            ],
          ),
        ),
        pw.Container(
          color: background,
          padding: const pw.EdgeInsets.symmetric(vertical: 7, horizontal: 4),
          alignment: pw.Alignment.centerLeft,
          child: pw.Text(
            stop.code,
            softWrap: true,
            style: pw.TextStyle(fontSize: 9, color: foreground),
          ),
        ),
      ],
    );
  }

  static pw.Widget _routeStopCell(
    String text, {
    required PdfColor background,
    required PdfColor foreground,
    bool bold = false,
  }) => pw.Container(
    color: background,
    padding: const pw.EdgeInsets.symmetric(vertical: 7, horizontal: 6),
    child: pw.Text(
      text,
      style: pw.TextStyle(
        fontSize: 9,
        fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
        color: foreground,
      ),
    ),
  );

  /*
  static pw.Widget _header(String agencyName) => pw.Container(
    padding: const pw.EdgeInsets.only(bottom: 11),
    margin: const pw.EdgeInsets.only(bottom: 24),
    decoration: pw.BoxDecoration(
      border: pw.Border(
        bottom: pw.BorderSide(color: PdfColor.fromHex('#777777')),
      ),
    ),
    child: pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(
          agencyName.isEmpty ? 'TRANSIT GUIDE' : agencyName.toUpperCase(),
          style: pw.TextStyle(
            fontSize: 9,
            fontWeight: pw.FontWeight.bold,
            color: PdfColor.fromHex('#000000'),
            letterSpacing: 1.1,
          ),
        ),
        pw.Text(
          'SERVICE INFORMATION',
          style: pw.TextStyle(fontSize: 8, color: PdfColor.fromHex('#555555')),
        ),
      ],
    ),
  );
  */

  static pw.Widget _footer(pw.Context context) {
    final generatedAt = DateTime.now();
    final generatedDate =
        '${generatedAt.day.toString().padLeft(2, '0')}/'
        '${generatedAt.month.toString().padLeft(2, '0')}/'
        '${generatedAt.year}';
    return pw.Container(
      alignment: pw.Alignment.centerRight,
      padding: const pw.EdgeInsets.only(top: 5), //originally 10
      margin: const pw.EdgeInsets.only(top: 5), // originally 18
      decoration: pw.BoxDecoration(
        border: pw.Border(
          top: pw.BorderSide(color: PdfColor.fromHex('#777777')),
        ),
      ),
      child: pw.Text(
        'Generated $generatedDate  ·  PAGE ${context.pageNumber}  ·  Guerilla Wayfinding',
        style: pw.TextStyle(fontSize: 8, color: PdfColor.fromHex('#555555')),
      ),
    );
  }

  static pw.Widget _eyebrow(String text) => pw.Text(
    text,
    style: pw.TextStyle(
      fontSize: 9,
      fontWeight: pw.FontWeight.bold,
      color: PdfColor.fromHex('#000000'),
      letterSpacing: 1.2,
    ),
  );

  static pw.Widget _sectionTitle(String text, int count) => pw.Row(
    children: [
      pw.Expanded(
        child: pw.Text(
          text,
          style: pw.TextStyle(
            fontSize: 17,
            fontWeight: pw.FontWeight.bold,
            color: PdfColor.fromHex('#000000'),
          ),
        ),
      ),
      pw.Text(
        '$count ${count == 1 ? 'ITEM' : 'ITEMS'}',
        style: pw.TextStyle(
          fontSize: 8,
          fontWeight: pw.FontWeight.bold,
          color: PdfColor.fromHex('#555555'),
        ),
      ),
    ],
  );

  static pw.TableRow _tableHeader(List<String> labels) => pw.TableRow(
    children: [
      for (final label in labels)
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 8, horizontal: 7),
          child: pw.Text(
            label,
            style: pw.TextStyle(
              fontSize: 8,
              fontWeight: pw.FontWeight.bold,
              color: PdfColor.fromHex('#555555'),
            ),
          ),
        ),
    ],
  );

  static pw.Widget _emptyMessage(String text) => pw.Container(
    width: double.infinity,
    padding: const pw.EdgeInsets.all(16),
    decoration: pw.BoxDecoration(
      color: PdfColor.fromHex('#EEEEEE'),
      borderRadius: pw.BorderRadius.circular(7),
    ),
    child: pw.Text(
      text,
      style: pw.TextStyle(fontSize: 10, color: PdfColor.fromHex('#333333')),
    ),
  );

  static pw.Widget _departureCell(String time) => pw.Padding(
    padding: const pw.EdgeInsets.only(right: 6, bottom: 6),
    child: pw.Container(
      height: 34,
      decoration: pw.BoxDecoration(
        color: PdfColor.fromHex('#FFFFFF'),
        border: pw.Border.all(color: PdfColor.fromHex('#000000'), width: 0.8),
      ),
      child: pw.Center(
        child: pw.Text(
          time,
          style: pw.TextStyle(
            fontSize: 11,
            fontWeight: pw.FontWeight.bold,
            color: PdfColor.fromHex('#000000'),
          ),
        ),
      ),
    ),
  );

  static String _safeName(String value) =>
      value.replaceAll(RegExp(r'[^a-zA-Z0-9_-]+'), '-');
}
