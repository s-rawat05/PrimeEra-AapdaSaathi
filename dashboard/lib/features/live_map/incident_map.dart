import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/models.dart';
import '../../services/app_scope.dart';
import '../../theme/app_theme.dart';
import 'geo.dart';

const _osmUrl = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

/// OSM base layer + mandatory attribution. Tiles are skipped in widget tests.
List<Widget> baseLayers(BuildContext context) {
  final tiles = context.services.config.mapTilesEnabled;
  return [
    if (tiles) TileLayer(urlTemplate: _osmUrl, userAgentPackageName: 'org.aapdasaathi.command', maxZoom: 19),
  ];
}

Widget osmAttribution() => RichAttributionWidget(
      alignment: AttributionAlignment.bottomRight,
      showFlutterMapAttribution: false,
      attributions: [
        TextSourceAttribution(
          'OpenStreetMap contributors',
          onTap: () => launchUrl(Uri.parse('https://www.openstreetmap.org/copyright')),
        ),
      ],
    );

List<Polygon> wardPolygons(List<WardOut> wards, {Color? color}) {
  final out = <Polygon>[];
  for (final w in wards) {
    final c = color ??
        switch (w.accessStatus) {
          'blocked' => AppColors.help,
          'restricted' => AppColors.noReply,
          _ => AppColors.info,
        };
    for (final p in parseGeoJsonPolygons(w.boundaryGeojson)) {
      out.add(Polygon(
        points: p.outer,
        holePointsList: p.holes.isEmpty ? null : p.holes,
        color: c.withValues(alpha: 0.08),
        borderColor: c,
        borderStrokeWidth: 2.5,
        label: w.code,
        labelStyle: TextStyle(color: c, fontWeight: FontWeight.w800, fontSize: 12),
      ));
    }
  }
  return out;
}

CameraFit? fitFor(List<LatLng> points) {
  if (points.isEmpty) return null;
  if (points.length == 1) return null;
  final bounds = LatLngBounds.fromPoints(points);
  if (bounds.north == bounds.south && bounds.east == bounds.west) return null;
  return CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(36), maxZoom: 17);
}

/// Incident map: ward polygons, residents (coloured by status), volunteers and relief posts.
class IncidentMapView extends StatefulWidget {
  const IncidentMapView({super.key, required this.data, required this.onOpenCase, this.height = 440});

  final IncidentMap data;
  final ValueChanged<String> onOpenCase;
  final double height;

  @override
  State<IncidentMapView> createState() => _IncidentMapViewState();
}

/// Wheel-zoom is disabled so scrolling the page never gets trapped by the map; zoom with the buttons,
/// double-click or pinch.
const mapInteraction = InteractionOptions(
  flags: InteractiveFlag.all & ~InteractiveFlag.rotate & ~InteractiveFlag.scrollWheelZoom,
);

class MapZoomButtons extends StatelessWidget {
  const MapZoomButtons({super.key, required this.controller, this.fit});

  final MapController controller;
  final CameraFit? fit;

  @override
  Widget build(BuildContext context) {
    Widget btn(IconData icon, String tip, VoidCallback onTap) => Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Material(
            color: Colors.white,
            elevation: 2,
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: onTap,
              child: Tooltip(message: tip, child: Padding(padding: const EdgeInsets.all(6), child: Icon(icon, size: 20))),
            ),
          ),
        );
    void zoom(double d) {
      final cam = controller.camera;
      controller.move(cam.center, (cam.zoom + d).clamp(3, 19).toDouble());
    }

    return Column(mainAxisSize: MainAxisSize.min, children: [
      btn(Icons.add, 'Zoom in', () => zoom(1)),
      btn(Icons.remove, 'Zoom out', () => zoom(-1)),
      if (fit != null) btn(Icons.fit_screen, 'Fit incident area', () => controller.fitCamera(fit!)),
    ]);
  }
}

class _IncidentMapViewState extends State<IncidentMapView> {
  final _controller = MapController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final onOpenCase = widget.onOpenCase;
    final height = widget.height;
    final polygons = wardPolygons(data.wards);
    final allPoints = <LatLng>[
      for (final p in polygons) ...p.points,
      for (final m in data.markers) LatLng(m.lat, m.lng),
      for (final s in data.shelters) LatLng(s.lat, s.lng),
    ];
    final fallback = data.wards.isNotEmpty
        ? LatLng(data.wards.first.centroidLat, data.wards.first.centroidLng)
        : (allPoints.isNotEmpty ? allPoints.first : const LatLng(29.35, 79.56));
    final precision = data.markers.isNotEmpty ? data.markers.first.precision : '~110 m grid';

    // Markers sorted so HELP / high priority render on top.
    final markers = [...data.markers]..sort((a, b) => a.priority.compareTo(b.priority));

    return SizedBox(
      height: height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(children: [
          FlutterMap(
            mapController: _controller,
            options: MapOptions(
              initialCenter: fallback,
              initialZoom: 15,
              initialCameraFit: fitFor(allPoints),
              interactionOptions: mapInteraction,
            ),
            children: [
              ...baseLayers(context),
              PolygonLayer(polygons: polygons),
              MarkerLayer(markers: [
                for (final s in data.shelters)
                  Marker(
                    point: LatLng(s.lat, s.lng),
                    width: 34,
                    height: 34,
                    child: Tooltip(
                      message: 'Relief post: ${s.name}\n${s.address}\nSource: ${s.source}',
                      child: const _MapIcon(icon: Icons.house_rounded, color: AppColors.safe, square: true),
                    ),
                  ),
                for (final v in data.volunteers)
                  Marker(
                    point: LatLng(v.lat, v.lng),
                    width: 32,
                    height: 32,
                    child: Tooltip(
                      message: 'Volunteer: ${v.name}\n'
                          '${!v.isAvailable ? 'Unavailable' : v.busy ? 'Busy (on a task)' : 'Available'}',
                      child: _MapIcon(
                        icon: Icons.directions_walk,
                        color: !v.isAvailable
                            ? AppColors.unreachable
                            : v.busy
                                ? AppColors.info
                                : AppColors.safe,
                        square: true,
                      ),
                    ),
                  ),
                for (final m in markers)
                  Marker(
                    key: ValueKey('marker-${m.deliveryId}'),
                    point: LatLng(m.lat, m.lng),
                    width: m.status == 'HELP' ? 38 : 30,
                    height: m.status == 'HELP' ? 38 : 30,
                    child: Tooltip(
                      message: '${m.residentFirstName} · ${statusLabel(m.status)} · priority ${m.priority}\n'
                          'Location: ${m.precision} (approximate)',
                      child: MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: GestureDetector(
                          onTap: () => onOpenCase(m.deliveryId),
                          child: _MapIcon(icon: statusIcon(m.status), color: AppColors.status(m.status)),
                        ),
                      ),
                    ),
                  ),
              ]),
              osmAttribution(),
            ],
          ),
          Positioned(left: 8, top: 8, child: _Legend(precision: precision)),
          Positioned(right: 8, top: 8, child: MapZoomButtons(controller: _controller, fit: fitFor(allPoints))),
        ]),
      ),
    );
  }
}

class _MapIcon extends StatelessWidget {
  const _MapIcon({required this.icon, required this.color, this.square = false});

  final IconData icon;
  final Color color;
  final bool square;

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: color,
          shape: square ? BoxShape.rectangle : BoxShape.circle,
          borderRadius: square ? BorderRadius.circular(8) : null,
          border: Border.all(color: Colors.white, width: 2),
          boxShadow: const [BoxShadow(color: Color(0x55000000), blurRadius: 4, offset: Offset(0, 1))],
        ),
        child: FittedBox(child: Padding(padding: const EdgeInsets.all(4), child: Icon(icon, color: Colors.white))),
      );
}

class _Legend extends StatelessWidget {
  const _Legend({required this.precision});

  final String precision;

  @override
  Widget build(BuildContext context) {
    Widget dot(Color c, String l, {bool square = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 1.5),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: c,
                shape: square ? BoxShape.rectangle : BoxShape.circle,
                borderRadius: square ? BorderRadius.circular(2) : null,
              ),
            ),
            const SizedBox(width: 6),
            Text(l, style: const TextStyle(fontSize: 11)),
          ]),
        );
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        dot(AppColors.safe, 'Safe'),
        dot(AppColors.help, 'Help'),
        dot(AppColors.noReply, 'No reply'),
        dot(AppColors.unreachable, 'Unreachable'),
        dot(AppColors.safe, 'Volunteer available / relief post', square: true),
        dot(AppColors.info, 'Volunteer busy', square: true),
        const SizedBox(height: 4),
        Text('Residents shown on a $precision', style: const TextStyle(fontSize: 10, color: AppColors.muted)),
      ]),
    );
  }
}

/// Small ward-only map used by the admin wards page.
class WardMapPreview extends StatelessWidget {
  const WardMapPreview({super.key, required this.wards, this.shelters = const [], this.height = 380});

  final List<WardOut> wards;
  final List<ShelterOut> shelters;
  final double height;

  @override
  Widget build(BuildContext context) {
    final polygons = wardPolygons(wards);
    final points = [for (final p in polygons) ...p.points, for (final s in shelters) LatLng(s.lat, s.lng)];
    final center = wards.isNotEmpty ? LatLng(wards.first.centroidLat, wards.first.centroidLng) : const LatLng(29.35, 79.56);
    return SizedBox(
      height: height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: FlutterMap(
          options: MapOptions(
            initialCenter: center,
            initialZoom: 13,
            initialCameraFit: fitFor(points),
            interactionOptions: mapInteraction,
          ),
          children: [
            ...baseLayers(context),
            PolygonLayer(polygons: polygons),
            MarkerLayer(markers: [
              for (final s in shelters)
                Marker(
                  point: LatLng(s.lat, s.lng),
                  width: 30,
                  height: 30,
                  child: Tooltip(
                    message: '${s.name}\nSource: ${s.source}',
                    child: const _MapIcon(icon: Icons.house_rounded, color: AppColors.safe, square: true),
                  ),
                ),
            ]),
            osmAttribution(),
          ],
        ),
      ),
    );
  }
}
