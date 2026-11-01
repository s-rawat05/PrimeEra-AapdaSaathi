import 'package:latlong2/latlong.dart';

/// A polygon ring set: outer boundary and optional inner holes.
class PolygonRings {
  const PolygonRings(this.outer, this.holes);

  final List<LatLng> outer;
  final List<List<LatLng>> holes;
}

/// Converts a GeoJSON linear ring into Flutter Map coordinates.
///
/// GeoJSON uses [longitude, latitude], while LatLng uses
/// (latitude, longitude).
List<LatLng> _ring(Object? ring) {
  if (ring is! List) return const <LatLng>[];

  final points = <LatLng>[];
  for (final position in ring) {
    if (position is List &&
        position.length >= 2 &&
        position[0] is num &&
        position[1] is num) {
      final longitude = (position[0] as num).toDouble();
      final latitude = (position[1] as num).toDouble();

      if (latitude >= -90 &&
          latitude <= 90 &&
          longitude >= -180 &&
          longitude <= 180) {
        points.add(LatLng(latitude, longitude));
      }
    }
  }

  return points;
}

PolygonRings? _polygon(Object? coordinates) {
  if (coordinates is! List || coordinates.isEmpty) return null;

  final outer = _ring(coordinates.first);
  if (outer.length < 3) return null;

  final holes = <List<LatLng>>[];
  for (final rawHole in coordinates.skip(1)) {
    final hole = _ring(rawHole);
    if (hole.length >= 3) holes.add(hole);
  }

  return PolygonRings(outer, holes);
}

/// Parses GeoJSON Polygon, MultiPolygon, or a Feature containing either.
///
/// Unsupported or malformed geometries return an empty list instead of
/// throwing, so a bad ward boundary does not break the complete map.
List<PolygonRings> parseGeoJsonPolygons(Map<String, dynamic>? geometry) {
  if (geometry == null) return const <PolygonRings>[];

  final type = geometry['type'];
  if (type == 'Feature') {
    final rawGeometry = geometry['geometry'];
    if (rawGeometry is Map) {
      return parseGeoJsonPolygons(Map<String, dynamic>.from(rawGeometry));
    }
    return const <PolygonRings>[];
  }

  final coordinates = geometry['coordinates'];

  if (type == 'Polygon') {
    final polygon = _polygon(coordinates);
    return polygon == null ? const <PolygonRings>[] : <PolygonRings>[polygon];
  }

  if (type == 'MultiPolygon' && coordinates is List) {
    final polygons = <PolygonRings>[];
    for (final rawPolygon in coordinates) {
      final polygon = _polygon(rawPolygon);
      if (polygon != null) polygons.add(polygon);
    }
    return polygons;
  }

  return const <PolygonRings>[];
}
