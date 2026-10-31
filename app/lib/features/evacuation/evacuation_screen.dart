import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../models/models.dart';
import '../../services/device_services.dart';
import '../../state/app_scope.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../../widgets/sos_button.dart';

enum _PosSource { device, registry, none }

/// Evacuation & relief post: OSM map with the resident's position, the relief post registered by the
/// authority, and a dashed straight line that is explicitly NOT a verified route. Instructions shown
/// are only the official instruction and AapdaSaathi's easy-read steps from the API.
class EvacuationScreen extends StatefulWidget {
  const EvacuationScreen({super.key, this.standalone = false});

  /// True when pushed as its own route (adds an app bar and the floating SOS).
  final bool standalone;

  @override
  State<EvacuationScreen> createState() => _EvacuationScreenState();
}

class _EvacuationScreenState extends State<EvacuationScreen> {
  LatLng? _pos;
  _PosSource _src = _PosSource.none;
  bool _locating = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _locate());
  }

  Future<void> _locate() async {
    final app = context.appRead;
    setState(() => _locating = true);
    final p = await app.location.current();
    if (!mounted) return;
    if (p != null) {
      setState(() {
        _pos = LatLng(p.lat, p.lng);
        _src = _PosSource.device;
        _locating = false;
      });
      return;
    }
    // Fall back to the registered home location (only returned to the resident themself).
    try {
      final loc = await app.call((api) => api.myLocation());
      if (!mounted) return;
      setState(() {
        if (loc != null) {
          _pos = LatLng(loc.lat, loc.lng);
          _src = _PosSource.registry;
        }
      });
    } catch (_) {/* offline: map shows the relief post only */}
    if (mounted) setState(() => _locating = false);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final s = app.s;
    final alert = app.primaryAlert;
    final shelter = alert?.nearestShelter;

    Widget body;
    if (alert == null) {
      body = ListView(padding: const EdgeInsets.all(16), children: [
        EmptyState(icon: Icons.map_outlined, text: s.noAlertForEvacuation),
      ]);
    } else if (shelter == null) {
      body = ListView(padding: const EdgeInsets.all(16), children: [
        SectionCard(
          color: AppColors.amberSoft,
          child: Row(children: [
            const Icon(Icons.info_outline, color: AppColors.amber),
            const SizedBox(width: 12),
            Expanded(child: Text(s.noReliefPost, key: const Key('no-relief-post'), style: const TextStyle(fontSize: 16))),
          ]),
        ),
        const SizedBox(height: 16),
        _InstructionList(alert: alert),
      ]);
    } else {
      body = Stack(children: [
        Positioned.fill(bottom: 220, child: _Map(pos: _pos, shelter: shelter, tiles: app.enableMapTiles)),
        DraggableScrollableSheet(
          initialChildSize: 0.45,
          minChildSize: 0.3,
          maxChildSize: 0.95,
          builder: (context, controller) => _Sheet(
            controller: controller,
            alert: alert,
            shelter: shelter,
            pos: _pos,
            src: _src,
            locating: _locating,
          ),
        ),
      ]);
    }

    return Scaffold(
      appBar: widget.standalone ? AppBar(title: Text(s.evacuationTitle)) : null,
      floatingActionButton: widget.standalone ? const SosFab() : null,
      body: SafeArea(top: !widget.standalone, child: body),
    );
  }
}

class _Map extends StatelessWidget {
  const _Map({required this.pos, required this.shelter, required this.tiles});
  final LatLng? pos;
  final ShelterOut shelter;
  final bool tiles;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final target = LatLng(shelter.lat, shelter.lng);
    final points = [target, ?pos];
    return Stack(children: [
      FlutterMap(
        options: MapOptions(
          initialCenter: target,
          initialZoom: 16,
          initialCameraFit: points.length > 1
              ? CameraFit.coordinates(coordinates: points, padding: const EdgeInsets.all(64), maxZoom: 17)
              : null,
        ),
        children: [
          if (tiles)
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'in.primeera.aapda_saathi',
            ),
          if (pos != null)
            PolylineLayer(polylines: [
              Polyline(
                points: [pos!, target],
                color: AppColors.red,
                strokeWidth: 5,
                pattern: StrokePattern.dashed(segments: const [14, 10]),
              ),
            ]),
          MarkerLayer(markers: [
            Marker(
              point: target,
              width: 56,
              height: 56,
              child: Semantics(
                label: '${s.reliefPost}: ${shelter.name}',
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.red, width: 3),
                  ),
                  child: const Icon(Icons.night_shelter, color: AppColors.red, size: 30),
                ),
              ),
            ),
            if (pos != null)
              Marker(
                point: pos!,
                width: 48,
                height: 48,
                child: Semantics(
                  label: s.yourPosition,
                  child: Container(
                    decoration: const BoxDecoration(color: AppColors.red, shape: BoxShape.circle, boxShadow: [
                      BoxShadow(color: Color(0x66E53935), blurRadius: 18, spreadRadius: 8),
                    ]),
                    child: const Icon(Icons.navigation, color: Colors.white, size: 26),
                  ),
                ),
              ),
          ]),
          // OSM tile usage requires visible attribution.
          Align(
            alignment: Alignment.bottomRight,
            child: Container(
              color: Colors.white.withValues(alpha: 0.85),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              child: const Text('© OpenStreetMap contributors', style: TextStyle(fontSize: 11)),
            ),
          ),
        ],
      ),
      if (pos != null)
        Positioned(
          left: 12,
          top: 12,
          right: 140,
          child: Semantics(
            label: s.directionOnly,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.95),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.amber),
              ),
              child: Text(
                s.directionOnly,
                key: const Key('direction-only'),
                style: const TextStyle(color: AppColors.amber, fontWeight: FontWeight.w700, fontSize: 12),
              ),
            ),
          ),
        ),
    ]);
  }
}

class _Sheet extends StatelessWidget {
  const _Sheet({
    required this.controller,
    required this.alert,
    required this.shelter,
    required this.pos,
    required this.src,
    required this.locating,
  });

  final ScrollController controller;
  final AlertOut alert;
  final ShelterOut shelter;
  final LatLng? pos;
  final _PosSource src;
  final bool locating;

  @override
  Widget build(BuildContext context) {
    final app = context.app;
    final s = app.s;

    // Distance: from this phone's GPS when available (straight line), otherwise the server's figure
    // (from the registered home location). Walk time uses the server's own estimate model.
    double? dist = shelter.distanceM;
    double? walk = shelter.estWalkMinutes;
    if (src == _PosSource.device && pos != null) {
      final d = const Distance().as(LengthUnit.Meter, pos!, LatLng(shelter.lat, shelter.lng));
      if (shelter.distanceM != null && shelter.distanceM! > 0 && shelter.estWalkMinutes != null) {
        walk = d * shelter.estWalkMinutes! / shelter.distanceM!;
      } else {
        walk = null;
      }
      dist = d;
    }

    final srcText = switch (src) {
      _PosSource.device => s.positionFromDevice,
      _PosSource.registry => s.positionFromRegistry,
      _PosSource.none => s.positionUnknown,
    };

    return Material(
      color: Colors.white,
      elevation: 8,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: ListView(controller: controller, padding: const EdgeInsets.fromLTRB(20, 8, 20, 120), children: [
        Center(
          child: Container(
            width: 44,
            height: 5,
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(color: AppColors.outline, borderRadius: BorderRadius.circular(3)),
          ),
        ),
        Text.rich(
          TextSpan(children: [
            TextSpan(
              text: '${alert.official.severity.toUpperCase()} ',
              style: const TextStyle(color: AppColors.red, fontWeight: FontWeight.w800, letterSpacing: 2),
            ),
            TextSpan(text: '• ${alert.official.event}'),
          ]),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          s.evacuateTo(shelter.name),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 4),
        Text(shelter.address, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.gray)),
        if (shelter.isDemo) const Center(child: Padding(padding: EdgeInsets.only(top: 6), child: DemoBadge())),
        const SizedBox(height: 12),
        Text(
          fmtDistance(dist),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w900),
        ),
        Text(s.fromYourLocation, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.gray)),
        if (walk != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              s.walkEstimate(fmtMinutes(walk)),
              key: const Key('walk-estimate'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.amber, fontWeight: FontWeight.w700),
            ),
          ),
        const SizedBox(height: 4),
        Text(locating ? s.loading : srcText,
            textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: AppColors.gray)),
        Text(s.directionOnly,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, color: AppColors.amber, fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),
        FilledButton.icon(
          key: const Key('open-in-maps'),
          onPressed: () async {
            final ok = await app.launcher.open(Links.mapsDirections(shelter.lat, shelter.lng));
            if (!ok && context.mounted) showSnack(context, s.couldNotOpen, error: true);
          },
          icon: const Icon(Icons.directions),
          label: Text(s.openInMaps),
        ),
        const SizedBox(height: 4),
        Text(s.designatedBy(shelter.source),
            textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: AppColors.gray)),
        const SizedBox(height: 16),
        _InstructionList(alert: alert),
      ]),
    );
  }
}

/// Instruction rows: the official instruction verbatim, then the API's easy-read steps.
class _InstructionList extends StatelessWidget {
  const _InstructionList({required this.alert});
  final AlertOut alert;

  @override
  Widget build(BuildContext context) {
    final s = context.s;
    final steps = alert.presentation.easyReadSteps;
    return Card(
      child: Column(children: [
        _InstructionRow(
          icon: Icons.account_balance,
          color: AppColors.official,
          title: s.officialInstruction,
          body: alert.official.instruction ?? s.noInstruction,
          caption: alert.official.sender,
        ),
        for (final step in steps) ...[
          const Divider(height: 1, indent: 72),
          _InstructionRow(icon: stepIcon(step), color: AppColors.red, title: s.aapdaSteps, body: step),
        ],
      ]),
    );
  }
}

class _InstructionRow extends StatelessWidget {
  const _InstructionRow({required this.icon, required this.color, required this.title, required this.body, this.caption});
  final IconData icon;
  final Color color;
  final String title;
  final String body;
  final String? caption;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(14),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Pictogram(icon, size: 44, color: color),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: TextStyle(fontWeight: FontWeight.w800, color: color)),
              const SizedBox(height: 2),
              Text(body, style: const TextStyle(fontSize: 15)),
              if (caption != null) Text(caption!, style: const TextStyle(fontSize: 12, color: AppColors.gray)),
            ]),
          ),
        ]),
      );
}
