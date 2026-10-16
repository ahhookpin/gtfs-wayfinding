import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'column_mapping_page.dart';
import 'gtfs_data.dart';
import 'poster_service.dart';

void main() => runApp(const TransitDeskApp());

class TransitDeskApp extends StatelessWidget {
  const TransitDeskApp({super.key});

  @override
  Widget build(BuildContext context) {
    const ink = Color(0xFF173442);
    const canvas = Color(0xFFF5F7F6);
    return MaterialApp(
      title: 'Wayfinder · Transit Studio',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: canvas,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF23785C),
          surface: Colors.white,
        ),
        textTheme: const TextTheme(
          headlineMedium: TextStyle(
            color: ink,
            fontWeight: FontWeight.w800,
            letterSpacing: -1.3,
          ),
          headlineSmall: TextStyle(
            color: ink,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.7,
          ),
          titleLarge: TextStyle(color: ink, fontWeight: FontWeight.w700),
          titleMedium: TextStyle(color: ink, fontWeight: FontWeight.w600),
          bodyLarge: TextStyle(color: ink),
          bodyMedium: TextStyle(color: Color(0xFF61747D)),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 15,
            vertical: 15,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFE0E7E4)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFE0E7E4)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF23785C), width: 1.5),
          ),
        ),
      ),
      home: const TransitHomePage(),
    );
  }
}

enum BrowseSection { stops, routes }

class TransitHomePage extends StatefulWidget {
  const TransitHomePage({super.key});

  @override
  State<TransitHomePage> createState() => _TransitHomePageState();
}

class _TransitHomePageState extends State<TransitHomePage> {
  GtfsDataset? _dataset;
  BrowseSection _section = BrowseSection.stops;
  TransitStop? _selectedStop;
  TransitRoute? _selectedRoute;
  bool _isLoading = false;
  bool _isGeneratingPoster = false;

  Future<void> _importFeed() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['zip'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final file = result.files.single;
      final bytes = file.bytes;
      if (bytes == null) {
        throw const FormatException('The selected ZIP file could not be read.');
      }
      setState(() => _isLoading = true);
      final preview = await GtfsDataset.inspectZip(bytes);
      if (!mounted) return;
      setState(() => _isLoading = false);
      final columnMappings = await Navigator.of(context).push<GtfsColumnMappings>(
        MaterialPageRoute(
          builder: (context) => GtfsColumnMappingPage(
            sourceName: file.name,
            headersByFile: preview.headersByFile,
          ),
        ),
      );
      if (!mounted || columnMappings == null) return;
      setState(() => _isLoading = true);
      final dataset = await GtfsDataset.fromZip(
        bytes,
        sourceName: file.name,
        columnMappings: columnMappings,
      );
      if (!mounted) return;
      setState(() {
        _dataset = dataset;
        _selectedStop = null;
        _selectedRoute = null;
        _section = BrowseSection.stops;
        _isLoading = false;
      });
      _showMessage(
        'Feed imported · ${dataset.stops.length} stops and ${dataset.routes.length} routes',
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showMessage('Could not import GTFS feed: $error', isError: true);
    }
  }

  void _showMessage(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: isError
              ? const Color(0xFF9E4037)
              : const Color(0xFF173442),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  Future<void> _printStop(GtfsDataset dataset, TransitStop stop) async {
    if (_isGeneratingPoster) return;
    try {
      final routeIds = dataset.routeIdsByStopId[stop.id] ?? const <String>[];
      final routes = dataset.routes
          .where((route) => routeIds.contains(route.id))
          .toList();
      final layout = await showDialog<StopPosterLayout>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Stop poster layout'),
          content: const Text(
            'Choose a combined guide, separate route pages, or a view that '
            'shows only this stop and the stops ahead.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            OutlinedButton(
              onPressed: () =>
                  Navigator.of(context).pop(StopPosterLayout.combined),
              child: const Text('Combined routes'),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.of(context).pop(StopPosterLayout.separateRoutes),
              child: const Text('Separate by route'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(context).pop(StopPosterLayout.currentAndNext),
              child: const Text('Current + next stops'),
            ),
          ],
        ),
      );
      if (layout == null || !mounted) return;
      await _runWithPosterProgress(
        (onPdfGenerated) => PosterService.printStop(
          stop: stop,
          routes: routes,
          allStops: dataset.stops,
          agencyName: dataset.agencyName,
          layout: layout,
          onPdfGenerated: onPdfGenerated,
        ),
      );
    } catch (error) {
      if (mounted) {
        _showMessage('Could not create stop poster: $error', isError: true);
      }
    }
  }

  Future<void> _printRoute(GtfsDataset dataset, TransitRoute route) async {
    if (_isGeneratingPoster) return;
    try {
      await _runWithPosterProgress(
        (onPdfGenerated) => PosterService.printRoute(
          route: route,
          allStops: dataset.stops,
          agencyName: dataset.agencyName,
          onPdfGenerated: onPdfGenerated,
        ),
      );
    } catch (error) {
      if (mounted) {
        _showMessage('Could not create route poster: $error', isError: true);
      }
    }
  }

  Future<void> _runWithPosterProgress(
    Future<void> Function(Future<void> Function()) generateAndPrint,
  ) async {
    setState(() => _isGeneratingPoster = true);
    var progressDialogOpen = true;
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => const PopScope(
          canPop: false,
          child: AlertDialog(
            content: Row(
              children: [
                SizedBox.square(
                  dimension: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 16),
                Expanded(child: Text('Generating poster PDF…')),
              ],
            ),
          ),
        ),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));
    try {
      await generateAndPrint(() async {
        if (!progressDialogOpen || !mounted) return;
        progressDialogOpen = false;
        Navigator.of(context, rootNavigator: true).pop();
        await Future<void>.delayed(Duration.zero);
      });
    } finally {
      if (progressDialogOpen && mounted) {
        progressDialogOpen = false;
        Navigator.of(context, rootNavigator: true).pop();
      }
      if (mounted) setState(() => _isGeneratingPoster = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dataset = _dataset;
    final compactAppBar = MediaQuery.sizeOf(context).width < 650;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        titleSpacing: compactAppBar ? 12 : 24,
        title: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: const Color(0xFFE6F2EC),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.alt_route_rounded,
                color: Color(0xFF23785C),
                size: 21,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              'wayfinder',
              style: TextStyle(
                color: Color(0xFF173442),
                fontSize: 19,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.8,
              ),
            ),
            if (!compactAppBar) ...[
              const SizedBox(width: 8),
              const Text(
                'TRANSIT STUDIO',
                style: TextStyle(
                  color: Color(0xFF81918D),
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.1,
                ),
              ),
            ],
          ],
        ),
        actions: [
          if (!compactAppBar && dataset != null && !_isLoading)
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Center(child: _FeedPill(name: dataset.sourceName)),
            ),
          if (compactAppBar)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _isLoading
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : IconButton(
                      onPressed: _importFeed,
                      tooltip: dataset == null ? 'Import GTFS' : 'Replace feed',
                      icon: const Icon(Icons.upload_file_rounded),
                      color: const Color(0xFF23785C),
                    ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(right: 24),
              child: FilledButton.icon(
                onPressed: _isLoading ? null : _importFeed,
                icon: _isLoading
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.upload_file_rounded, size: 18),
                label: Text(
                  _isLoading
                      ? 'Reading feed…'
                      : dataset == null
                      ? 'Import GTFS'
                      : 'Replace feed',
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF23785C),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
              ),
            ),
        ],
      ),
      body: dataset == null
          ? _WelcomeView(onImport: _importFeed, isLoading: _isLoading)
          : _buildWorkspace(dataset),
    );
  }

  Widget _buildWorkspace(GtfsDataset dataset) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 850;
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1280),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 18 : 36,
                vertical: 27,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _WorkspaceHeading(dataset: dataset),
                  const SizedBox(height: 24),
                  _SummaryRow(dataset: dataset),
                  const SizedBox(height: 24),
                  SegmentedButton<BrowseSection>(
                    segments: [
                      ButtonSegment(
                        value: BrowseSection.stops,
                        icon: const Icon(Icons.place_outlined, size: 18),
                        label: Text('Stops  ${dataset.stops.length}'),
                      ),
                      ButtonSegment(
                        value: BrowseSection.routes,
                        icon: const Icon(Icons.alt_route_rounded, size: 18),
                        label: Text('Routes  ${dataset.routes.length}'),
                      ),
                    ],
                    selected: {_section},
                    onSelectionChanged: (selection) =>
                        setState(() => _section = selection.first),
                    style: SegmentedButton.styleFrom(
                      selectedBackgroundColor: const Color(0xFFE6F2EC),
                      selectedForegroundColor: const Color(0xFF23785C),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: _section == BrowseSection.stops
                        ? _StopsWorkspace(
                            key: const ValueKey('stops-workspace'),
                            dataset: dataset,
                            selectedStop: _selectedStop,
                            compact: compact,
                            onSelected: (stop) =>
                                setState(() => _selectedStop = stop),
                            onPrint: (stop) => _printStop(dataset, stop),
                          )
                        : _RoutesWorkspace(
                            key: const ValueKey('routes-workspace'),
                            dataset: dataset,
                            selectedRoute: _selectedRoute,
                            compact: compact,
                            onSelected: (route) =>
                                setState(() => _selectedRoute = route),
                            onPrint: (route) => _printRoute(dataset, route),
                          ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _WelcomeView extends StatelessWidget {
  const _WelcomeView({required this.onImport, required this.isLoading});

  final VoidCallback onImport;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFE6F2EC),
                  borderRadius: BorderRadius.circular(30),
                ),
                child: const Text(
                  'YOUR TRANSIT DATA, READY TO EXPLORE',
                  style: TextStyle(
                    color: Color(0xFF23785C),
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1,
                  ),
                ),
              ),
              const SizedBox(height: 22),
              Text(
                'A clearer view of\nevery journey.',
                style: Theme.of(context).textTheme.headlineMedium
                    ?.copyWith(fontSize: 50, height: 1.08),
              ),
              const SizedBox(height: 15),
              const SizedBox(
                width: 520,
                child: Text(
                  'Bring your GTFS schedule to life. Find stops, trace routes, '
                  'check departures and print clear A4 service guides.',
                  style: TextStyle(
                    color: Color(0xFF61747D),
                    fontSize: 16,
                    height: 1.65,
                  ),
                ),
              ),
              const SizedBox(height: 27),
              FilledButton.icon(
                onPressed: isLoading ? null : onImport,
                icon: isLoading
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.folder_open_rounded, size: 19),
                label: Text(
                  isLoading ? 'Reading your feed…' : 'Choose GTFS ZIP',
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF23785C),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 16,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Select a .zip containing routes.txt, stops.txt, trips.txt and stop_times.txt',
                style: TextStyle(color: Color(0xFF81918D), fontSize: 11),
              ),
              const SizedBox(height: 38),
              const Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _FeatureTile(
                    icon: Icons.place_outlined,
                    title: 'Explore stops',
                    description:
                        'Search stops and see every route that serves them.',
                  ),
                  _FeatureTile(
                    icon: Icons.alt_route_rounded,
                    title: 'Trace routes',
                    description:
                        'See the stop sequence and first-stop departures.',
                  ),
                  _FeatureTile(
                    icon: Icons.print_outlined,
                    title: 'Print a guide',
                    description:
                        'Create clean, print-ready A4 service posters.',
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FeatureTile extends StatelessWidget {
  const _FeatureTile({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 218,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE6EBE8)),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: const Color(0xFF23785C)),
          const SizedBox(height: 13),
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 5),
          Text(
            description,
            style: const TextStyle(
              color: Color(0xFF71817D),
              height: 1.45,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _WorkspaceHeading extends StatelessWidget {
  const _WorkspaceHeading({required this.dataset});

  final GtfsDataset dataset;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'NETWORK EXPLORER',
          style: TextStyle(
            color: Color(0xFF23785C),
            fontSize: 10,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.3,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          dataset.agencyName.isEmpty ? 'Your network' : dataset.agencyName,
          style: Theme.of(context).textTheme.headlineSmall
              ?.copyWith(fontSize: 27),
        ),
        const SizedBox(height: 4),
        const Text(
          'Find a stop or route, then create a service guide to print.',
          style: TextStyle(color: Color(0xFF71817D), fontSize: 13),
        ),
      ],
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.dataset});

  final GtfsDataset dataset;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _SummaryCard(
            icon: Icons.place_outlined,
            label: 'STOPS',
            value: _formatCount(dataset.stops.length),
            accent: const Color(0xFF23785C),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _SummaryCard(
            icon: Icons.alt_route_rounded,
            label: 'ROUTES',
            value: _formatCount(dataset.routes.length),
            accent: const Color(0xFF5874A3),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _SummaryCard(
            icon: Icons.schedule_rounded,
            label: 'TIMED ROUTES',
            value: _formatCount(
              dataset.routes
                  .where((route) => route.departureTimes.isNotEmpty)
                  .length,
            ),
            accent: const Color(0xFFD58A41),
          ),
        ),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.accent,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE6EBE8)),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Row(
        children: [
          Icon(icon, color: accent, size: 20),
          const SizedBox(width: 12),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF81918D),
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  style: const TextStyle(
                    color: Color(0xFF173442),
                    fontSize: 21,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StopsWorkspace extends StatelessWidget {
  const _StopsWorkspace({
    super.key,
    required this.dataset,
    required this.selectedStop,
    required this.compact,
    required this.onSelected,
    required this.onPrint,
  });

  final GtfsDataset dataset;
  final TransitStop? selectedStop;
  final bool compact;
  final ValueChanged<TransitStop> onSelected;
  final ValueChanged<TransitStop> onPrint;

  @override
  Widget build(BuildContext context) {
    final selected = selectedStop;
    final left = _BrowseList<TransitStop>(
      title: 'All stops',
      count: dataset.stops.length,
      searchLabel: 'Search stops by name or code',
      emptyMessage: 'No stops match your search.',
      items: dataset.stops,
      selectedId: selected?.id,
      itemId: (stop) => stop.id,
      displayName: (stop) => stop.name,
      subtitle: (stop) =>
          stop.code.isEmpty ? 'Stop ${stop.id}' : 'Code ${stop.code}',
      onSelected: onSelected,
    );
    final detail = selected == null
        ? const _SelectionPlaceholder(
            icon: Icons.place_outlined,
            title: 'Choose a stop',
            message: 'Select a stop from the list or search by name to see its routes.',
          )
        : _StopDetails(
            dataset: dataset,
            stop: selected,
            onPrint: () => onPrint(selected),
          );
    if (compact) {
      return Column(
        children: [
          SizedBox(height: 290, child: left),
          const SizedBox(height: 14),
          Expanded(child: detail),
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(width: 355, child: left),
        const SizedBox(width: 16),
        Expanded(child: detail),
      ],
    );
  }
}

class _RoutesWorkspace extends StatelessWidget {
  const _RoutesWorkspace({
    super.key,
    required this.dataset,
    required this.selectedRoute,
    required this.compact,
    required this.onSelected,
    required this.onPrint,
  });

  final GtfsDataset dataset;
  final TransitRoute? selectedRoute;
  final bool compact;
  final ValueChanged<TransitRoute> onSelected;
  final ValueChanged<TransitRoute> onPrint;

  @override
  Widget build(BuildContext context) {
    final selected = selectedRoute;
    final left = _BrowseList<TransitRoute>(
      title: 'All routes',
      count: dataset.routes.length,
      searchLabel: 'Search routes by number or name',
      emptyMessage: 'No routes match your search.',
      items: dataset.routes,
      selectedId: selected?.id,
      itemId: (route) => route.id,
      displayName: (route) => route.displayName,
      subtitle: (route) => _routeTypeLabel(route.type),
      onSelected: onSelected,
      leadingBuilder: (route) => _RouteBadge(route: route),
    );
    final detail = selected == null
        ? const _SelectionPlaceholder(
            icon: Icons.alt_route_rounded,
            title: 'Choose a route',
            message: 'Select a route from the list or search by number to see its stops and departures.',
          )
        : _RouteDetails(
            dataset: dataset,
            route: selected,
            onPrint: () => onPrint(selected),
          );
    if (compact) {
      return Column(
        children: [
          SizedBox(height: 290, child: left),
          const SizedBox(height: 14),
          Expanded(child: detail),
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(width: 355, child: left),
        const SizedBox(width: 16),
        Expanded(child: detail),
      ],
    );
  }
}

class _BrowseList<T extends Object> extends StatefulWidget {
  const _BrowseList({
    required this.title,
    required this.count,
    required this.searchLabel,
    required this.emptyMessage,
    required this.items,
    required this.selectedId,
    required this.itemId,
    required this.displayName,
    required this.subtitle,
    required this.onSelected,
    this.leadingBuilder,
  });

  final String title;
  final int count;
  final String searchLabel;
  final String emptyMessage;
  final List<T> items;
  final String? selectedId;
  final String Function(T item) itemId;
  final String Function(T item) displayName;
  final String Function(T item) subtitle;
  final ValueChanged<T> onSelected;
  final Widget Function(T item)? leadingBuilder;

  @override
  State<_BrowseList<T>> createState() => _BrowseListState<T>();
}

class _BrowseListState<T extends Object> extends State<_BrowseList<T>> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final filtered = widget.items.where((item) {
      final query = _query.toLowerCase();
      return widget.displayName(item).toLowerCase().contains(query) ||
          widget.subtitle(item).toLowerCase().contains(query) ||
          widget.itemId(item).toLowerCase().contains(query);
    }).toList();
    return Container(
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(17, 16, 17, 11),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.title,
                    style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(fontSize: 14),
                  ),
                ),
                _CountPill(count: widget.count),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(13, 0, 13, 11),
            child: Autocomplete<T>(
              displayStringForOption: widget.displayName,
              optionsBuilder: (value) {
                final query = value.text.trim().toLowerCase();
                if (query.isEmpty) return const Iterable.empty();
                return widget.items
                    .where(
                      (item) =>
                          widget
                              .displayName(item)
                              .toLowerCase()
                              .contains(query) ||
                          widget.subtitle(item).toLowerCase().contains(query) ||
                          widget.itemId(item).toLowerCase().contains(query),
                    )
                    .take(8);
              },
              onSelected: (item) {
                setState(() => _query = '');
                widget.onSelected(item);
              },
              fieldViewBuilder: (context, controller, focusNode, onSubmit) =>
                  TextField(
                    key: ValueKey(widget.searchLabel),
                    controller: controller,
                    focusNode: focusNode,
                    onChanged: (value) => setState(() => _query = value),
                    decoration: InputDecoration(
                      hintText: widget.searchLabel,
                      hintStyle: const TextStyle(fontSize: 12),
                      prefixIcon: const Icon(Icons.search_rounded, size: 19),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 11,
                        vertical: 13,
                      ),
                    ),
                  ),
              optionsViewBuilder: (context, onSelected, options) => Align(
                alignment: Alignment.topLeft,
                child: Material(
                  elevation: 6,
                  borderRadius: BorderRadius.circular(12),
                  clipBehavior: Clip.antiAlias,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxHeight: 280,
                      maxWidth: 340,
                    ),
                    child: ListView(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      shrinkWrap: true,
                      children: [
                        for (final item in options)
                          ListTile(
                            dense: true,
                            title: Text(
                              widget.displayName(item),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xFF173442),
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: Text(
                              widget.subtitle(item),
                              style: const TextStyle(fontSize: 11),
                            ),
                            onTap: () => onSelected(item),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          const Divider(height: 1, color: Color(0xFFE8EDEA)),
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text(
                        widget.emptyMessage,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Color(0xFF81918D),
                          fontSize: 12,
                        ),
                      ),
                    ),
                  )
                : ListView.separated(
                    itemCount: filtered.length,
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    separatorBuilder: (_, _) =>
                        const Divider(height: 1, indent: 62, endIndent: 12),
                    itemBuilder: (context, index) {
                      final item = filtered[index];
                      final isSelected =
                          widget.itemId(item) == widget.selectedId;
                      return Material(
                        color: isSelected
                            ? const Color(0xFFF0F7F3)
                            : Colors.transparent,
                        child: InkWell(
                          onTap: () => widget.onSelected(item),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            child: Row(
                              children: [
                                if (widget.leadingBuilder != null) ...[
                                  widget.leadingBuilder!(item),
                                  const SizedBox(width: 11),
                                ] else
                                  Container(
                                    width: 32,
                                    height: 32,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFE6F2EC),
                                      borderRadius: BorderRadius.circular(9),
                                    ),
                                    child: const Icon(
                                      Icons.place_outlined,
                                      color: Color(0xFF23785C),
                                      size: 18,
                                    ),
                                  ),
                                if (widget.leadingBuilder == null)
                                  const SizedBox(width: 11),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        widget.displayName(item),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: const Color(0xFF173442),
                                          fontSize: 12,
                                          fontWeight: isSelected
                                              ? FontWeight.w700
                                              : FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        widget.subtitle(item),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: Color(0xFF81918D),
                                          fontSize: 10,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (isSelected)
                                  const Icon(
                                    Icons.arrow_forward_ios_rounded,
                                    color: Color(0xFF23785C),
                                    size: 13,
                                  ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _StopDetails extends StatelessWidget {
  const _StopDetails({
    required this.dataset,
    required this.stop,
    required this.onPrint,
  });

  final GtfsDataset dataset;
  final TransitStop stop;
  final VoidCallback onPrint;

  @override
  Widget build(BuildContext context) {
    final routeIds = dataset.routeIdsByStopId[stop.id] ?? const <String>[];
    final routes = dataset.routes
        .where((route) => routeIds.contains(route.id))
        .toList();
    return Container(
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _DetailHeader(
            eyebrow: 'STOP DETAILS',
            title: stop.name,
            subtitle: [
              if (stop.code.isNotEmpty) 'Stop code ${stop.code}',
              'ID ${stop.id}',
            ].join('  ·  '),
            trailing: _PrintButton(onPressed: onPrint),
          ),
          const Divider(height: 1, color: Color(0xFFE8EDEA)),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 17, 20, 11),
            child: Row(
              children: [
                Text(
                  'Routes serving this stop',
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontSize: 13),
                ),
                const SizedBox(width: 8),
                _CountPill(count: routes.length),
              ],
            ),
          ),
          Expanded(
            child: routes.isEmpty
                ? const _InlineEmpty(
                    message: 'No routes in this feed serve this stop.',
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                    itemCount: routes.length,
                    separatorBuilder: (_, _) =>
                        const Divider(height: 1, indent: 52),
                    itemBuilder: (context, index) {
                      final route = routes[index];
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 3,
                        ),
                        leading: _RouteBadge(route: route, size: 34),
                        title: Text(
                          route.displayName,
                          style: const TextStyle(
                            color: Color(0xFF173442),
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                        subtitle: Text(
                          route.description.isNotEmpty
                              ? route.description
                              : _routeTypeLabel(route.type),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF81918D),
                          ),
                        ),
                        trailing: const Icon(
                          Icons.directions_bus_outlined,
                          size: 18,
                          color: Color(0xFF81918D),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _RouteDetails extends StatelessWidget {
  const _RouteDetails({
    required this.dataset,
    required this.route,
    required this.onPrint,
  });

  final GtfsDataset dataset;
  final TransitRoute route;
  final VoidCallback onPrint;

  @override
  Widget build(BuildContext context) {
    final stopsById = {for (final stop in dataset.stops) stop.id: stop};
    final stopSequences = route.stopSequences.isEmpty
        ? [
            [
              for (final stopId in route.stopIds)
                if (stopsById[stopId] case final stop?) stop,
            ],
          ]
        : [
            for (final sequence in route.stopSequences)
              [
                for (final stopId in sequence.stopIds)
                  if (stopsById[stopId] case final stop?) stop,
              ],
          ];
    final firstStops = dataset.stops.where(
      (stop) => stop.id == route.firstStopId,
    );
    final firstStopName = firstStops.isEmpty ? '' : firstStops.first.name;
    return Container(
      decoration: _cardDecoration(),
      child: Column(
        children: [
          _DetailHeader(
            eyebrow:
                'ROUTE DETAILS  ·  ${_routeTypeLabel(route.type).toUpperCase()}',
            title: route.displayName,
            subtitle: route.id,
            leading: _RouteBadge(route: route, size: 42),
            trailing: _PrintButton(onPressed: onPrint),
          ),
          const Divider(height: 1, color: Color(0xFFE8EDEA)),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final narrow = constraints.maxWidth < 540;
                final stopsPanel = _StopsPanel(stopSequences: stopSequences);
                final departuresPanel = _DeparturesPanel(
                  route: route,
                  firstStopName: firstStopName,
                );
                if (narrow) {
                  return ListView(
                    padding: const EdgeInsets.all(17),
                    children: [
                      SizedBox(height: 370, child: stopsPanel),
                      const SizedBox(height: 18),
                      departuresPanel,
                    ],
                  );
                }
                return Padding(
                  padding: const EdgeInsets.all(18),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 6, child: stopsPanel),
                      const SizedBox(width: 19),
                      Expanded(flex: 4, child: departuresPanel),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _StopsPanel extends StatelessWidget {
  const _StopsPanel({required this.stopSequences});

  final List<List<TransitStop>> stopSequences;

  @override
  Widget build(BuildContext context) {
    final count = stopSequences.fold<int>(
      0,
      (total, sequence) => total + sequence.length,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _PanelHeading(title: 'Stops by direction', count: count),
        const SizedBox(height: 12),
        Expanded(
          child: stopSequences.every((sequence) => sequence.isEmpty)
              ? const _InlineEmpty(
                  message: 'No stops are listed for this route.',
                )
              : ListView(
                  children: [
                    for (
                      var sequenceIndex = 0;
                      sequenceIndex < stopSequences.length;
                      sequenceIndex++
                    ) ...[
                      if (stopSequences.length > 1)
                        Padding(
                          padding: const EdgeInsets.only(
                            top: 5,
                            bottom: 10,
                          ),
                          child: Text(
                            '${stopSequences[sequenceIndex].first.name} → '
                            '${stopSequences[sequenceIndex].last.name}',
                            style: const TextStyle(
                              color: Color(0xFF61747D),
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      for (
                        var index = 0;
                        index < stopSequences[sequenceIndex].length;
                        index++
                      )
                        _stopRow(
                          stopSequences[sequenceIndex][index],
                          index: index,
                          isLast:
                              index ==
                              stopSequences[sequenceIndex].length - 1,
                        ),
                      if (sequenceIndex < stopSequences.length - 1)
                        const Divider(height: 22),
                    ],
                  ],
                ),
        ),
      ],
    );
  }

  Widget _stopRow(
    TransitStop stop, {
    required int index,
    required bool isLast,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 30,
          child: Column(
            children: [
              Container(
                width: 25,
                height: 25,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: index == 0
                      ? const Color(0xFF23785C)
                      : const Color(0xFFEAF0ED),
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '${index + 1}',
                  style: TextStyle(
                    color: index == 0
                        ? Colors.white
                        : const Color(0xFF61747D),
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (!isLast)
                Container(
                  margin: const EdgeInsets.only(top: 3),
                  width: 1,
                  height: 13,
                  color: const Color(0xFFDDE5E1),
                ),
            ],
          ),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  stop.name,
                  style: const TextStyle(
                    color: Color(0xFF173442),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (stop.code.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      'Code ${stop.code}',
                      style: const TextStyle(
                        color: Color(0xFF81918D),
                        fontSize: 9,
                      ),
                    ),
                  ),
                if (isLast)
                  const Text(
                    'LAST STOP',
                    style: TextStyle(
                      color: Color(0xFF81918D),
                      fontSize: 8,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

class _DeparturesPanel extends StatelessWidget {
  const _DeparturesPanel({required this.route, required this.firstStopName});

  final TransitRoute route;
  final String firstStopName;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _PanelHeading(
          title: firstStopName.isEmpty
              ? 'First-stop departures'
              : 'Departures · $firstStopName',
          count: route.departureTimes.length,
        ),
        const SizedBox(height: 5),
        Text(
          route.hasFrequencyTripsWithoutStopTimes
              ? route.hasEstimatedFrequencyDepartures
                    ? 'Includes estimated frequency times without stop details'
                    : 'Includes frequency times without stop details'
              : route.hasEstimatedFrequencyDepartures
              ? 'Includes estimated frequency-based departures'
              : 'Scheduled times in local service time',
          style: TextStyle(color: Color(0xFF81918D), fontSize: 10),
        ),
        const SizedBox(height: 12),
        if (route.departureTimes.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: _InlineEmpty(message: 'No departures listed in this feed.'),
          )
        else
          for (final service in route.departureTimesByServiceId.entries) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: Text(
                route.serviceDaysByServiceId[service.key] ??
                    'Service ID · ${service.key}',
                style: const TextStyle(
                  color: Color(0xFF526777),
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 13),
              child: Wrap(
                spacing: 7,
                runSpacing: 7,
                children: [
                  for (final time in service.value)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE9F6F1),
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: Text(
                        time,
                        style: const TextStyle(
                          color: Color(0xFF147D5A),
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
      ],
    );
  }
}

class _DetailHeader extends StatelessWidget {
  const _DetailHeader({
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    required this.trailing,
    this.leading,
  });

  final String eyebrow;
  final String title;
  final String subtitle;
  final Widget trailing;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 17, 16),
      child: Row(
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: 13)],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  eyebrow,
                  style: const TextStyle(
                    color: Color(0xFF23785C),
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge
                      ?.copyWith(fontSize: 18, height: 1.2),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF81918D),
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          trailing,
        ],
      ),
    );
  }
}

class _PrintButton extends StatelessWidget {
  const _PrintButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: const Icon(Icons.print_outlined, size: 17),
      label: const Text('Print A4'),
      style: OutlinedButton.styleFrom(
        foregroundColor: const Color(0xFF23785C),
        side: const BorderSide(color: Color(0xFFCFE2D6)),
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 11),
        textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _PanelHeading extends StatelessWidget {
  const _PanelHeading({required this.title, required this.count});

  final String title;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontSize: 13),
          ),
        ),
        _CountPill(count: count),
      ],
    );
  }
}

class _SelectionPlaceholder extends StatelessWidget {
  const _SelectionPlaceholder({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: _cardDecoration(),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(30),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: const Color(0xFFEAF2EE),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, color: const Color(0xFF23785C), size: 24),
              ),
              const SizedBox(height: 13),
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 270),
                child: Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFF81918D),
                    fontSize: 12,
                    height: 1.5,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InlineEmpty extends StatelessWidget {
  const _InlineEmpty({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F7F6),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        message,
        style: const TextStyle(
          color: Color(0xFF81918D),
          fontSize: 11,
          height: 1.5,
        ),
      ),
    );
  }
}

class _CountPill extends StatelessWidget {
  const _CountPill({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F3F1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        _formatCount(count),
        style: const TextStyle(
          color: Color(0xFF61747D),
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _FeedPill extends StatelessWidget {
  const _FeedPill({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 190),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F4F2),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_circle, size: 13, color: Color(0xFF23785C)),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              name,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF526777),
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RouteBadge extends StatelessWidget {
  const _RouteBadge({required this.route, this.size = 36});

  final TransitRoute route;
  final double size;

  @override
  Widget build(BuildContext context) {
    final background = _routeColor(route.color);
    final foreground =
        _routeColor(route.textColor) ??
        (background == null || background.computeLuminance() > 0.42
            ? const Color(0xFF173442)
            : Colors.white);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: background ?? const Color(0xFFE8F0ED),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        route.shortName.isEmpty ? '•' : route.shortName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: foreground,
          fontSize: size < 36 ? 11 : 10,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

BoxDecoration _cardDecoration() => BoxDecoration(
  color: Colors.white,
  border: Border.all(color: const Color(0xFFE5EBE8)),
  borderRadius: BorderRadius.circular(14),
);

String _formatCount(int value) =>
    value >= 1000 ? '${(value / 1000).toStringAsFixed(1)}k' : '$value';

String _routeTypeLabel(String type) => switch (type) {
  '0' => 'Tram / light rail',
  '1' => 'Metro / subway',
  '2' => 'Rail',
  '3' => 'Bus',
  '4' => 'Ferry',
  '5' => 'Cable tram',
  '6' => 'Gondola',
  '7' => 'Funicular',
  _ => 'Transit service',
};

Color? _routeColor(String? hex) {
  if (hex == null || !RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(hex)) return null;
  return Color(int.parse('FF$hex', radix: 16));
}
