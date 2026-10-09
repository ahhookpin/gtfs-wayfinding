import 'package:flutter/material.dart';

import 'gtfs_data.dart';

class GtfsColumnMappingPage extends StatefulWidget {
  const GtfsColumnMappingPage({
    required this.sourceName,
    required this.headersByFile,
    super.key,
  });

  final String sourceName;
  final Map<String, List<String>> headersByFile;

  @override
  State<GtfsColumnMappingPage> createState() => _GtfsColumnMappingPageState();
}

class _GtfsColumnMappingPageState extends State<GtfsColumnMappingPage> {
  late final GtfsColumnMappings _mappings = _initialMappings();

  static const _fieldsByFile = <String, List<_ColumnField>>{
    'routes.txt': [
      _ColumnField('route_id', 'Route ID', required: true),
      _ColumnField('route_type', 'Route type', required: true),
      _ColumnField('route_short_name', 'Route name', required: true),
    ],
    'stops.txt': [
      _ColumnField('stop_id', 'Stop ID', required: true),
      _ColumnField('stop_name', 'Stop name', required: true),
      _ColumnField('stop_code', 'Stop code'),
    ],
    'trips.txt': [
      _ColumnField('route_id', 'Route ID', required: true),
      _ColumnField('service_id', 'Service ID', required: true),
      _ColumnField('trip_id', 'Trip ID', required: true),
    ],
    'stop_times.txt': [
      _ColumnField('trip_id', 'Trip ID', required: true),
      _ColumnField('stop_id', 'Stop ID', required: true),
      _ColumnField('stop_sequence', 'Stop sequence', required: true),
      _ColumnField(
        'departure_time',
        'Departure or arrival time',
        required: true,
      ),
    ],
    'frequencies.txt': [
      _ColumnField('trip_id', 'Trip ID', required: true),
      _ColumnField('start_time', 'Start time', required: true),
      _ColumnField('end_time', 'End time', required: true),
      _ColumnField('headway_secs', 'Headway (seconds)', required: true),
    ],
    'calendar.txt': [
      _ColumnField('service_id', 'Service ID', required: true),
      _ColumnField('monday', 'Monday', required: true),
      _ColumnField('tuesday', 'Tuesday', required: true),
      _ColumnField('wednesday', 'Wednesday', required: true),
      _ColumnField('thursday', 'Thursday', required: true),
      _ColumnField('friday', 'Friday', required: true),
      _ColumnField('saturday', 'Saturday', required: true),
      _ColumnField('sunday', 'Sunday', required: true),
    ],
  };

  GtfsColumnMappings _initialMappings() {
    final mappings = <String, Map<String, int>>{};
    for (final entry in widget.headersByFile.entries) {
      final fileMappings = <String, int>{};
      for (final field in _fieldsByFile[entry.key] ?? const <_ColumnField>[]) {
        final candidates = switch ((entry.key, field.name)) {
          ('routes.txt', 'route_short_name') => [
            'route_short_name',
            'route_long_name',
          ],
          ('stop_times.txt', 'departure_time') => [
            'departure_time',
            'arrival_time',
          ],
          _ => [field.name],
        };
        for (final candidate in candidates) {
          final index = entry.value.indexWhere(
            (header) => header.toLowerCase() == candidate,
          );
          if (index >= 0) {
            fileMappings[field.name] = index;
            break;
          }
        }
      }
      mappings[entry.key] = fileMappings;
    }
    return mappings;
  }

  bool get _isValid {
    if (!_fieldsByFile.keys.any(widget.headersByFile.containsKey)) return false;
    if (!widget.headersByFile.containsKey('stop_times.txt') &&
        !widget.headersByFile.containsKey('frequencies.txt')) {
      return false;
    }
    bool has(String file, String field) => _mappings[file]?[field] != null;

    for (final entry in _fieldsByFile.entries) {
      if (!widget.headersByFile.containsKey(entry.key)) continue;
      for (final field in entry.value.where((field) => field.required)) {
        if (!has(entry.key, field.name)) return false;
      }
    }
    if (widget.headersByFile.containsKey('routes.txt') &&
        !has('routes.txt', 'route_short_name')) {
      return false;
    }
    if (widget.headersByFile.containsKey('stop_times.txt') &&
        !has('stop_times.txt', 'departure_time')) {
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final availableFiles = _fieldsByFile.keys
        .where(widget.headersByFile.containsKey)
        .toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Map feed columns'),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
                    children: [
                      Text(
                        widget.sourceName,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Map the fields Wayfinder needs to find routes, stops, '
                        'and schedules. Standard headers are preselected when '
                        'they match.',
                      ),
                      const SizedBox(height: 18),
                      for (final filename in availableFiles) ...[
                        _fileSection(filename),
                        const SizedBox(height: 14),
                      ],
                      if (availableFiles.isEmpty)
                        const Text('No supported GTFS tables were found.'),
                    ],
                  ),
                ),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(24, 14, 24, 20),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    border: Border(top: BorderSide(color: Color(0xFFE0E7E4))),
                  ),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (!_isValid)
                          const Padding(
                            padding: EdgeInsets.only(bottom: 8),
                            child: Text(
                              'Map each required field, including a schedule '
                              'table, to continue.',
                              style: TextStyle(color: Color(0xFF9E4037)),
                            ),
                          ),
                        FilledButton.icon(
                          onPressed: _isValid
                              ? () => Navigator.of(context).pop(_mappings)
                              : null,
                          icon: const Icon(Icons.arrow_forward_rounded),
                          label: const Text('Map columns & import'),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _fileSection(String filename) {
    final fields = _fieldsByFile[filename] ?? const <_ColumnField>[];
    final headers = widget.headersByFile[filename] ?? const <String>[];
    return Card(
      color: Colors.white,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(filename, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            for (final field in fields) ...[
              DropdownButtonFormField<int>(
                value: _mappings[filename]?[field.name],
                decoration: InputDecoration(
                  labelText:
                      '${field.label} · ${field.required ? 'required' : 'optional'}',
                  isDense: true,
                ),
                items: [
                  const DropdownMenuItem<int>(
                    value: null,
                    child: Text('Not mapped'),
                  ),
                  for (var i = 0; i < headers.length; i++)
                    DropdownMenuItem(
                      value: i,
                      child: Text(
                        '${i + 1}: ${headers[i].isEmpty ? '(blank header)' : headers[i]}',
                      ),
                    ),
                ],
                onChanged: (value) {
                  setState(() {
                    final fileMappings = _mappings.putIfAbsent(
                      filename,
                      () => {},
                    );
                    if (value == null) {
                      fileMappings.remove(field.name);
                    } else {
                      fileMappings[field.name] = value;
                    }
                  });
                },
              ),
              const SizedBox(height: 10),
            ],
          ],
        ),
      ),
    );
  }
}

class _ColumnField {
  const _ColumnField(this.name, this.label, {this.required = false});

  final String name;
  final String label;
  final bool required;
}
