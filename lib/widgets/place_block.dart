import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/generated/app_localizations.dart';
import '../theme/app_theme.dart';

/// A small, interactive OpenStreetMap preview with separate in-app expansion
/// and external directions actions. Places without coordinates remain
/// identifiable and can still be opened by address in the navigation app.
class PlaceBlock extends StatelessWidget {
  const PlaceBlock({
    required this.name,
    required this.address,
    required this.latitude,
    required this.longitude,
    super.key,
  });

  final String? name;
  final String? address;
  final double? latitude;
  final double? longitude;

  bool get hasCoordinates => latitude != null && longitude != null;

  @override
  Widget build(BuildContext context) {
    final strings = AppLocalizations.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (name != null || address != null) ...[
        if (name != null)
          Text(name!, style: Theme.of(context).textTheme.titleMedium),
        if (address != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.x1),
            child:
                Text(address!, style: Theme.of(context).textTheme.bodyMedium),
          ),
        const SizedBox(height: AppSpacing.x2),
      ],
      if (hasCoordinates)
        _PlaceMap(latitude: latitude!, longitude: longitude!, height: 176)
      else
        Container(
          height: 112,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(AppRadius.card),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.map_outlined),
            const SizedBox(height: AppSpacing.x1),
            Text(strings.mapNotAvailable),
          ]),
        ),
      Padding(
        padding: const EdgeInsets.only(top: AppSpacing.x2),
        child:
            Wrap(spacing: AppSpacing.x2, runSpacing: AppSpacing.x1, children: [
          if (hasCoordinates)
            OutlinedButton.icon(
              onPressed: () => _expand(context),
              icon: const Icon(Icons.open_in_full),
              label: Text(strings.expandMap),
            ),
          OutlinedButton.icon(
            onPressed: _openDirections,
            icon: const Icon(Icons.directions_outlined),
            label: Text(strings.directions),
          ),
        ]),
      ),
    ]);
  }

  Future<void> _expand(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 900,
            maxHeight: MediaQuery.sizeOf(context).height * .85,
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.x4),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Row(children: [
                Expanded(
                    child: Text(name ?? address ?? '',
                        style: Theme.of(context).textTheme.titleMedium)),
                IconButton(
                    tooltip: AppLocalizations.of(context).close,
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close)),
              ]),
              const SizedBox(height: AppSpacing.x2),
              Expanded(
                  child: _PlaceMap(
                      latitude: latitude!,
                      longitude: longitude!,
                      height: null)),
            ]),
          ),
        ),
      ),
    );
  }

  Future<void> _openDirections() async {
    final destination = hasCoordinates
        ? '${latitude!},${longitude!}'
        : (address ?? name ?? '').trim();
    if (destination.isEmpty) return;
    final uri = Uri.https('www.google.com', '/maps/dir/', {
      'api': '1',
      'destination': destination,
    });
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

class _PlaceMap extends StatefulWidget {
  const _PlaceMap(
      {required this.latitude, required this.longitude, required this.height});
  final double latitude;
  final double longitude;
  final double? height;

  @override
  State<_PlaceMap> createState() => _PlaceMapState();
}

class _PlaceMapState extends State<_PlaceMap> {
  bool _failed = false;
  int _attempt = 0;

  @override
  Widget build(BuildContext context) {
    final point = LatLng(widget.latitude, widget.longitude);
    final strings = AppLocalizations.of(context);
    return SizedBox(
      height: widget.height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: Stack(children: [
          FlutterMap(
            options: MapOptions(initialCenter: point, initialZoom: 15),
            children: [
              TileLayer(
                key: ValueKey(_attempt),
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.together_date_planner',
                errorTileCallback: (_, __, ___) {
                  if (mounted && !_failed) setState(() => _failed = true);
                },
              ),
              MarkerLayer(markers: [
                Marker(
                    point: point,
                    width: 48,
                    height: 48,
                    child: Icon(Icons.location_pin,
                        size: 44, color: Theme.of(context).colorScheme.primary))
              ]),
            ],
          ),
          if (_failed)
            Positioned.fill(
                child: ColoredBox(
              color:
                  Theme.of(context).colorScheme.surface.withValues(alpha: .92),
              child: Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(strings.mapNotAvailable),
                TextButton.icon(
                  onPressed: () => setState(() {
                    _failed = false;
                    _attempt++;
                  }),
                  icon: const Icon(Icons.refresh),
                  label: Text(strings.retryMap),
                ),
              ])),
            )),
          Positioned(
            right: AppSpacing.x1,
            bottom: AppSpacing.x1,
            child: DecoratedBox(
              decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .surface
                      .withValues(alpha: .9),
                  borderRadius: BorderRadius.circular(AppRadius.small)),
              child: const Padding(
                padding: EdgeInsets.symmetric(
                    horizontal: AppSpacing.x2, vertical: AppSpacing.x1),
                child: Text('© OpenStreetMap contributors'),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}
