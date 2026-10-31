/// Small, strict-but-forgiving JSON readers shared by the model classes.
typedef Json = Map<String, dynamic>;

String reqStr(Json j, String k) {
  final v = j[k];
  if (v == null) throw FormatException('Missing field "$k"');
  return v.toString();
}

String? optStr(Json j, String k) => j[k]?.toString();

bool reqBool(Json j, String k, {bool fallback = false}) {
  final v = j[k];
  if (v is bool) return v;
  return fallback;
}

double? optDouble(Json j, String k) {
  final v = j[k];
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v);
  return null;
}

double reqDouble(Json j, String k) {
  final v = optDouble(j, k);
  if (v == null) throw FormatException('Missing number "$k"');
  return v;
}

int optInt(Json j, String k, {int fallback = 0}) {
  final v = j[k];
  if (v is num) return v.toInt();
  return fallback;
}

DateTime? optDate(Json j, String k) {
  final v = j[k];
  if (v is String && v.isNotEmpty) return DateTime.tryParse(v)?.toUtc();
  return null;
}

List<String> strList(Json j, String k) {
  final v = j[k];
  if (v is List) return v.map((e) => e.toString()).toList();
  return const [];
}

List<T> objList<T>(Json j, String k, T Function(Json) f) {
  final v = j[k];
  if (v is List) return v.whereType<Map>().map((e) => f(Map<String, dynamic>.from(e))).toList();
  return <T>[];
}

Json? optObj(Json j, String k) {
  final v = j[k];
  if (v is Map) return Map<String, dynamic>.from(v);
  return null;
}
