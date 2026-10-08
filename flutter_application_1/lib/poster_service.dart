import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'gtfs_data.dart';

class PosterService {
  static Future<void> printStop({
    required TransitStop stop,
    required List<TransitRoute> routes,
    required String agencyName,
  }) async {
    final document = pw.Document();
    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(38),
        header: (context) => _header(agencyName),
        footer: (context) => _footer(context),
        build: (context) => [
          _eyebrow('STOP INFORMATION'),
          pw.SizedBox(height: 8),
          pw.Text(
            stop.name,
            style: pw.TextStyle(
              fontSize: 30,
              fontWeight: pw.FontWeight.bold,
              color: PdfColor.fromHex('#102A43'),
            ),
          ),
          if (stop.code.isNotEmpty)
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 7),
              child: pw.Text(
                'Stop code  ${stop.code}',
                style: pw.TextStyle(
                  fontSize: 11,
                  color: PdfColor.fromHex('#526777'),
                ),
              ),
            ),
          pw.SizedBox(height: 24),
          _sectionTitle('Routes serving this stop', routes.length),
          pw.SizedBox(height: 10),
          if (routes.isEmpty)
            _emptyMessage('No routes are listed for this stop.')
          else
            pw.Table(
              border: pw.TableBorder(
                horizontalInside: pw.BorderSide(
                  color: PdfColor.fromHex('#E5EBEF'),
                  width: 0.7,
                ),
              ),
              columnWidths: {
                0: const pw.FixedColumnWidth(90),
                1: const pw.FlexColumnWidth(2),
                2: const pw.FlexColumnWidth(1),
              },
              children: [
                _tableHeader(['ROUTE', 'DESTINATION / NAME', 'SERVICE']),
                for (final route in routes)
                  pw.TableRow(
                    verticalAlignment: pw.TableCellVerticalAlignment.middle,
                    children: [
                      _tableCell(
                        route.shortName.isEmpty ? route.id : route.shortName,
                        bold: true,
                      ),
                      _tableCell(
                        route.longName.isEmpty
                            ? route.description
                            : route.longName,
                      ),
                      _tableCell(_routeType(route.type)),
                    ],
                  ),
              ],
            ),
        ],
      ),
    );
    await Printing.layoutPdf(
      name: 'stop-${_safeName(stop.name)}.pdf',
      onLayout: (_) => document.save(),
    );
  }

  static Future<void> printRoute({
    required TransitRoute route,
    required List<TransitStop> stops,
    required String agencyName,
  }) async {
    final document = pw.Document();
    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(38),
        header: (context) => _header(agencyName),
        footer: (context) => _footer(context),
        build: (context) {
          final firstStops = stops.where(
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
                color: PdfColor.fromHex('#102A43'),
              ),
            ),
            if (route.longName.isNotEmpty && route.longName != route.shortName)
              pw.Padding(
                padding: const pw.EdgeInsets.only(top: 4),
                child: pw.Text(
                  route.longName,
                  style: pw.TextStyle(
                    fontSize: 15,
                    color: PdfColor.fromHex('#526777'),
                  ),
                ),
              ),
            pw.SizedBox(height: 21),
            _sectionTitle('Stops along this route', stops.length),
            pw.SizedBox(height: 10),
          ];
          if (stops.isEmpty) {
            content.add(_emptyMessage('No stops are listed for this route.'));
          } else {
            content.add(
              pw.Table(
                border: pw.TableBorder(
                  horizontalInside: pw.BorderSide(
                    color: PdfColor.fromHex('#E5EBEF'),
                    width: 0.7,
                  ),
                ),
                columnWidths: {
                  0: const pw.FixedColumnWidth(40),
                  1: const pw.FlexColumnWidth(1),
                  2: const pw.FixedColumnWidth(100),
                },
                children: [
                  _tableHeader(['#', 'STOP', 'STOP CODE']),
                  for (var index = 0; index < stops.length; index++)
                    pw.TableRow(
                      verticalAlignment: pw.TableCellVerticalAlignment.middle,
                      children: [
                        _tableCell('${index + 1}', muted: true),
                        _tableCell(stops[index].name, bold: index == 0),
                        _tableCell(stops[index].code, muted: true),
                      ],
                    ),
                ],
              ),
            );
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
                    color: PdfColor.fromHex('#718492'),
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
                    'Service ID · ${service.key}',
                    style: pw.TextStyle(
                      fontSize: 10,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColor.fromHex('#526777'),
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
    await Printing.layoutPdf(
      name:
          'route-${_safeName(route.shortName.isEmpty ? route.id : route.shortName)}.pdf',
      onLayout: (_) => document.save(),
    );
  }

  static pw.Widget _header(String agencyName) => pw.Container(
    padding: const pw.EdgeInsets.only(bottom: 11),
    margin: const pw.EdgeInsets.only(bottom: 24),
    decoration: pw.BoxDecoration(
      border: pw.Border(
        bottom: pw.BorderSide(color: PdfColor.fromHex('#DDE5E9')),
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
            color: PdfColor.fromHex('#147D5A'),
            letterSpacing: 1.1,
          ),
        ),
        pw.Text(
          'SERVICE INFORMATION',
          style: pw.TextStyle(fontSize: 8, color: PdfColor.fromHex('#718492')),
        ),
      ],
    ),
  );

  static pw.Widget _footer(pw.Context context) => pw.Container(
    alignment: pw.Alignment.centerRight,
    padding: const pw.EdgeInsets.only(top: 10),
    margin: const pw.EdgeInsets.only(top: 18),
    decoration: pw.BoxDecoration(
      border: pw.Border(top: pw.BorderSide(color: PdfColor.fromHex('#DDE5E9'))),
    ),
    child: pw.Text(
      'PAGE ${context.pageNumber}  ·  PRINT AT A4 SIZE',
      style: pw.TextStyle(fontSize: 8, color: PdfColor.fromHex('#718492')),
    ),
  );

  static pw.Widget _eyebrow(String text) => pw.Text(
    text,
    style: pw.TextStyle(
      fontSize: 9,
      fontWeight: pw.FontWeight.bold,
      color: PdfColor.fromHex('#147D5A'),
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
            color: PdfColor.fromHex('#102A43'),
          ),
        ),
      ),
      pw.Text(
        '$count ${count == 1 ? 'ITEM' : 'ITEMS'}',
        style: pw.TextStyle(
          fontSize: 8,
          fontWeight: pw.FontWeight.bold,
          color: PdfColor.fromHex('#718492'),
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
              color: PdfColor.fromHex('#718492'),
            ),
          ),
        ),
    ],
  );

  static pw.Widget _tableCell(
    String text, {
    bool bold = false,
    bool muted = false,
  }) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 10, horizontal: 7),
    child: pw.Text(
      text,
      style: pw.TextStyle(
        fontSize: 10,
        fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
        color: PdfColor.fromHex(muted ? '#718492' : '#102A43'),
      ),
    ),
  );

  static pw.Widget _emptyMessage(String text) => pw.Container(
    width: double.infinity,
    padding: const pw.EdgeInsets.all(16),
    decoration: pw.BoxDecoration(
      color: PdfColor.fromHex('#F2F6F5'),
      borderRadius: pw.BorderRadius.circular(7),
    ),
    child: pw.Text(
      text,
      style: pw.TextStyle(fontSize: 10, color: PdfColor.fromHex('#526777')),
    ),
  );

  static pw.Widget _departureCell(String time) => pw.Padding(
    padding: const pw.EdgeInsets.only(right: 6, bottom: 6),
    child: pw.Container(
      height: 34,
      decoration: pw.BoxDecoration(
        color: PdfColor.fromHex('#E9F6F1'),
        borderRadius: pw.BorderRadius.circular(6),
      ),
      child: pw.Center(
        child: pw.Text(
          time,
          style: pw.TextStyle(
            fontSize: 11,
            fontWeight: pw.FontWeight.bold,
            color: PdfColor.fromHex('#147D5A'),
          ),
        ),
      ),
    ),
  );

  static String _routeType(String type) => switch (type) {
    '0' => 'Tram',
    '1' => 'Metro',
    '2' => 'Rail',
    '3' => 'Bus',
    '4' => 'Ferry',
    '5' => 'Cable tram',
    '6' => 'Gondola',
    '7' => 'Funicular',
    _ => 'Other service',
  };

  static String _safeName(String value) =>
      value.replaceAll(RegExp(r'[^a-zA-Z0-9_-]+'), '-');
}
