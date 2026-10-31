import 'package:latlong2/latlong.dart';

/// A polygon ring set: outer ring + holes, in map coordinates.
class PolygonRings {
  const PolygonRings(this.outer, this.holes);

  final List<LatLng> outer;
  final List<List<LatLng>> holes;
}

List<LatLng> _ring(Object? ring) {
  if (ring is! List) return const [];
  final out = <LatLng>[];
  for (final p in ring) {
    // GeoJSON positions are [longitude, latitude].
    if (p is List && p.length >= 2 && p[0] is num && p[1] is num) {
      out.add(LatLng((p[1] as num).toDouble(), (p[0] as num).toDouble()));
    }
  }
  return out;
}

PolygonRings? _polygon(Object? coords) {
  if (coords is! List || coords.isEmpty) return null;
  final outer = _ring(coords.first);
  if (outer.length < 3) return null;
  return PolygonRings(outer, [for (final h in coords.skip(1)) _ring(h)].where((r) => r.length >= 3).toList());
}

/// Parses a GeoJSON Polygon / MultiPolygon geometry (or a Feature wrapping one).
List<PolygonRings> parseGeoJsonPolygons(Map<String, dynamic>? geometry) {
  if (geometry == null) return const [];
  final type = geometry['type'];
  if (type == 'Feature') {
    final g = geometry['geometry'];
    return g is Map<String, dynamic> ? parseGeoJsonPolygons(g) : const [];
  }
  final coords = geometry['coordinates'];
  if (type == 'Polygon') {
    final p = _polygon(coords);
    return p == null ? const [] : [p];
  }
  if (type == 'MultiPolygon' && coords is List) {
    return [for (final c in coords) _polygon(c)].whereType<PolygonRings>().toList();
  }
  return const [];
}
