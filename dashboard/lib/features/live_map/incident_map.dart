import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/models.dart';
import '../../services/app_scope.dart';
import '../../theme/app_theme.dart';
import 'geo.dart';

const _osmUrl = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

/// OpenStreetMap base layer with the required attribution.
List<Widget> baseLayers(BuildContext context) {
  final tilesEnabled = context.services.config.mapTilesEnabled;

  return [
    if (tilesEnabled)
      TileLayer(
        urlTemplate: _osmUrl,
        userAgentPackageName: 'org.aapdasaathi.command',
        maxZoom: 19,
      ),
  ];
}

Widget osmAttribution() {
  return RichAttributionWidget(
    alignment: AttributionAlignment.bottomRight,
    showFlutterMapAttribution: false,
    attributions: [
      TextSourceAttribution(
        'OpenStreetMap contributors',
        onTap: () => launchUrl(
          Uri.parse('https://www.openstreetmap.org/copyright'),
        ),
      ),
    ],
  );
}

/// Converts ward GeoJSON boundaries into coloured map polygons.
List<Polygon> wardPolygons(
  List<WardOut> wards, {
  Color? color,
}) {
  final polygons = <Polygon>[];

  for (final ward in wards) {
    final wardColor = color ??
        switch (ward.accessStatus) {
          'blocked' => AppColors.help,
          'restricted' => AppColors.noReply,
          _ => AppColors.info,
        };

    for (final ringSet in parseGeoJsonPolygons(ward.boundaryGeojson)) {
      polygons.add(
        Polygon(
          points: ringSet.outer,
          holePointsList:
              ringSet.holes.isEmpty ? null : ringSet.holes,
          color: wardColor.withValues(alpha: 0.10),
          borderColor: wardColor,
          borderStrokeWidth: 2.5,
          label: ward.code,
          labelStyle: TextStyle(
            color: wardColor,
            fontWeight: FontWeight.w800,
            fontSize: 12,
          ),
        ),
      );
    }
  }

  return polygons;
}

/// Creates a camera fit for a group of points.
///
/// A single point does not need a bounds fit; the map's initial center
/// handles that case.
CameraFit? fitFor(List<LatLng> points) {
  if (points.length < 2) return null;

  final bounds = LatLngBounds.fromPoints(points);
  if (bounds.north == bounds.south &&
      bounds.east == bounds.west) {
    return null;
  }

  return CameraFit.bounds(
    bounds: bounds,
    padding: const EdgeInsets.all(48),
    maxZoom: 17,
  );
}

/// Scrolling the page should not be trapped by the map.
/// Users can zoom with buttons, double-click, or pinch.
const mapInteraction = InteractionOptions(
  flags: InteractiveFlag.all &
      ~InteractiveFlag.rotate &
      ~InteractiveFlag.scrollWheelZoom,
);

class MapZoomButtons extends StatelessWidget {
  const MapZoomButtons({
    super.key,
    required this.controller,
    this.fit,
  });

  final MapController controller;
  final CameraFit? fit;

  @override
  Widget build(BuildContext context) {
    Widget button(
      IconData icon,
      String tooltip,
      VoidCallback onPressed,
    ) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Material(
          color: Colors.white,
          elevation: 2,
          borderRadius: BorderRadius.circular(9),
          child: InkWell(
            borderRadius: BorderRadius.circular(9),
            onTap: onPressed,
            child: Tooltip(
              message: tooltip,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Icon(icon, size: 20),
              ),
            ),
          ),
        ),
      );
    }

    void zoom(double difference) {
      final camera = controller.camera;
      controller.move(
        camera.center,
        (camera.zoom + difference).clamp(3.0, 19.0).toDouble(),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        button(Icons.add, 'Zoom in', () => zoom(1)),
        button(Icons.remove, 'Zoom out', () => zoom(-1)),
        if (fit != null)
          button(
            Icons.fit_screen,
            'Fit incident area',
            () => controller.fitCamera(fit!),
          ),
      ],
    );
  }
}

class IncidentMapView extends StatefulWidget {
  const IncidentMapView({
    super.key,
    required this.data,
    required this.onOpenCase,
    this.height = 440,
  });

  final IncidentMap data;
  final ValueChanged<String> onOpenCase;
  final double height;

  @override
  State<IncidentMapView> createState() => _IncidentMapViewState();
}

class _IncidentMapViewState extends State<IncidentMapView> {
  final MapController _controller = MapController();

  bool _showWards = true;
  bool _showResidents = true;
  bool _showVolunteers = true;
  bool _showShelters = true;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;

    final allWardPolygons = wardPolygons(data.wards);
    final visiblePolygons =
        _showWards ? allWardPolygons : <Polygon>[];

    final allPoints = <LatLng>[
      for (final polygon in allWardPolygons) ...polygon.points,
      for (final marker in data.markers)
        LatLng(marker.lat, marker.lng),
      for (final shelter in data.shelters)
        LatLng(shelter.lat, shelter.lng),
      for (final volunteer in data.volunteers)
        LatLng(volunteer.lat, volunteer.lng),
    ];

    final fallback = data.wards.isNotEmpty
        ? LatLng(
            data.wards.first.centroidLat,
            data.wards.first.centroidLng,
          )
        : allPoints.isNotEmpty
            ? allPoints.first
            : const LatLng(29.35, 79.56);

    final precision = data.markers.isNotEmpty
        ? data.markers.first.precision
        : '~110 m grid';

    // Lower priority values are painted first, keeping urgent HELP
    // markers visible above lower-priority markers.
    final sortedResidents = [...data.markers]
      ..sort((a, b) => a.priority.compareTo(b.priority));

    return SizedBox(
      height: widget.height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Stack(
          children: [
            FlutterMap(
              mapController: _controller,
              options: MapOptions(
                initialCenter: fallback,
                initialZoom: 14,
                initialCameraFit: fitFor(allPoints),
                interactionOptions: mapInteraction,
              ),
              children: [
                ...baseLayers(context),
                if (visiblePolygons.isNotEmpty)
                  PolygonLayer(polygons: visiblePolygons),
                MarkerLayer(
                  markers: [
                    if (_showShelters)
                      for (final shelter in data.shelters)
                        Marker(
                          point: LatLng(shelter.lat, shelter.lng),
                          width: 36,
                          height: 36,
                          child: Tooltip(
                            message:
                                'Relief post: ${shelter.name}\n'
                                '${shelter.address}\n'
                                'Source: ${shelter.source}',
                            child: const _MapIcon(
                              icon: Icons.house_rounded,
                              color: AppColors.safe,
                              square: true,
                            ),
                          ),
                        ),
                    if (_showVolunteers)
                      for (final volunteer in data.volunteers)
                        Marker(
                          point: LatLng(
                            volunteer.lat,
                            volunteer.lng,
                          ),
                          width: 34,
                          height: 34,
                          child: Tooltip(
                            message:
                                'Volunteer: ${volunteer.name}\n'
                                '${!volunteer.isAvailable ? 'Unavailable' : volunteer.busy ? 'Busy (on a task)' : 'Available'}',
                            child: _MapIcon(
                              icon: Icons.volunteer_activism,
                              color: !volunteer.isAvailable
                                  ? AppColors.unreachable
                                  : volunteer.busy
                                      ? AppColors.info
                                      : AppColors.safe,
                              square: true,
                            ),
                          ),
                        ),
                    if (_showResidents)
                      for (final marker in sortedResidents)
                        Marker(
                          key: ValueKey(
                            'marker-${marker.deliveryId}',
                          ),
                          point: LatLng(
                            marker.lat,
                            marker.lng,
                          ),
                          width:
                              marker.status == 'HELP' ? 40 : 32,
                          height:
                              marker.status == 'HELP' ? 40 : 32,
                          child: Tooltip(
                            message:
                                '${marker.residentFirstName} · '
                                '${statusLabel(marker.status)} · '
                                'priority ${marker.priority}\n'
                                'Location: ${marker.precision} (approximate)',
                            child: MouseRegion(
                              cursor: SystemMouseCursors.click,
                              child: GestureDetector(
                                onTap: () =>
                                    widget.onOpenCase(marker.deliveryId),
                                child: _MapIcon(
                                  icon: statusIcon(marker.status),
                                  color: AppColors.status(
                                    marker.status,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                  ],
                ),
                osmAttribution(),
              ],
            ),

            // Map layer filters.
            Positioned(
              left: 8,
              top: 8,
              child: _MapLayerFilters(
                showWards: _showWards,
                showResidents: _showResidents,
                showVolunteers: _showVolunteers,
                showShelters: _showShelters,
                onChanged: (layer, value) {
                  setState(() {
                    switch (layer) {
                      case 'wards':
                        _showWards = value;
                        break;
                      case 'residents':
                        _showResidents = value;
                        break;
                      case 'volunteers':
                        _showVolunteers = value;
                        break;
                      case 'shelters':
                        _showShelters = value;
                        break;
                    }
                  });
                },
              ),
            ),

            Positioned(
              right: 8,
              top: 8,
              child: MapZoomButtons(
                controller: _controller,
                fit: fitFor(allPoints),
              ),
            ),

            Positioned(
              left: 8,
              bottom: 8,
              child: _MapLegend(precision: precision),
            ),
          ],
        ),
      ),
    );
  }
}

class _MapLayerFilters extends StatelessWidget {
  const _MapLayerFilters({
    required this.showWards,
    required this.showResidents,
    required this.showVolunteers,
    required this.showShelters,
    required this.onChanged,
  });

  final bool showWards;
  final bool showResidents;
  final bool showVolunteers;
  final bool showShelters;
  final void Function(String layer, bool value) onChanged;

  @override
  Widget build(BuildContext context) {
    Widget filter(String label, String key, bool value) {
      return InkWell(
        onTap: () => onChanged(key, !value),
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: 7,
            vertical: 4,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                value
                    ? Icons.check_box
                    : Icons.check_box_outline_blank,
                size: 16,
                color: value ? AppColors.info : AppColors.muted,
              ),
              const SizedBox(width: 5),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x18000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Wrap(
        spacing: 3,
        runSpacing: 2,
        children: [
          filter('Wards', 'wards', showWards),
          filter('Residents', 'residents', showResidents),
          filter('Volunteers', 'volunteers', showVolunteers),
          filter('Shelters', 'shelters', showShelters),
        ],
      ),
    );
  }
}

class _MapIcon extends StatelessWidget {
  const _MapIcon({
    required this.icon,
    required this.color,
    this.square = false,
  });

  final IconData icon;
  final Color color;
  final bool square;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: color,
        shape: square ? BoxShape.rectangle : BoxShape.circle,
        borderRadius: square ? BorderRadius.circular(9) : null,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: const [
          BoxShadow(
            color: Color(0x55000000),
            blurRadius: 4,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: FittedBox(
        child: Padding(
          padding: const EdgeInsets.all(5),
          child: Icon(icon, color: Colors.white),
        ),
      ),
    );
  }
}

class _MapLegend extends StatelessWidget {
  const _MapLegend({required this.precision});

  final String precision;

  @override
  Widget build(BuildContext context) {
    Widget item(
      Color color,
      String label, {
      bool square = false,
    }) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: color,
                shape: square
                    ? BoxShape.rectangle
                    : BoxShape.circle,
                borderRadius:
                    square ? BorderRadius.circular(2) : null,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(fontSize: 11),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'MAP LEGEND',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 4),
          item(AppColors.safe, 'Safe'),
          item(AppColors.help, 'Help required'),
          item(AppColors.noReply, 'No reply'),
          item(AppColors.unreachable, 'Unreachable'),
          item(
            AppColors.safe,
            'Volunteer / relief post',
            square: true,
          ),
          item(
            AppColors.info,
            'Volunteer busy',
            square: true,
          ),
          const SizedBox(height: 3),
          Text(
            'Resident location: $precision (approx.)',
            style: const TextStyle(
              fontSize: 9,
              color: AppColors.muted,
            ),
          ),
        ],
      ),
    );
  }
}

/// Small ward-only map used on the admin wards page.
class WardMapPreview extends StatelessWidget {
  const WardMapPreview({
    super.key,
    required this.wards,
    this.shelters = const [],
    this.height = 380,
  });

  final List<WardOut> wards;
  final List<ShelterOut> shelters;
  final double height;

  @override
  Widget build(BuildContext context) {
    final polygons = wardPolygons(wards);
    final points = <LatLng>[
      for (final polygon in polygons) ...polygon.points,
      for (final shelter in shelters)
        LatLng(shelter.lat, shelter.lng),
    ];

    final center = wards.isNotEmpty
        ? LatLng(
            wards.first.centroidLat,
            wards.first.centroidLng,
          )
        : const LatLng(29.35, 79.56);

    return SizedBox(
      height: height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: FlutterMap(
          options: MapOptions(
            initialCenter: center,
            initialZoom: 13,
            initialCameraFit: fitFor(points),
            interactionOptions: mapInteraction,
          ),
          children: [
            ...baseLayers(context),
            if (polygons.isNotEmpty)
              PolygonLayer(polygons: polygons),
            MarkerLayer(
              markers: [
                for (final shelter in shelters)
                  Marker(
                    point: LatLng(
                      shelter.lat,
                      shelter.lng,
                    ),
                    width: 32,
                    height: 32,
                    child: Tooltip(
                      message:
                          '${shelter.name}\nSource: ${shelter.source}',
                      child: const _MapIcon(
                        icon: Icons.house_rounded,
                        color: AppColors.safe,
                        square: true,
                      ),
                    ),
                  ),
              ],
            ),
            osmAttribution(),
          ],
        ),
      ),
    );
  }
}
