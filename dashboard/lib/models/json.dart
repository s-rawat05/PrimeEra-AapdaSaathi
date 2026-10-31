/// Small, strict-but-forgiving JSON helpers shared by every model.
///
/// The backend (FastAPI + Pydantic) is the source of truth. These helpers only
/// smooth over JSON representation details (ints vs doubles, missing optional
/// keys) — they never invent values for required fields.
library;

typedef Json = Map<String, dynamic>;

Json asJson(Object? v) {
  if (v is Map<String, dynamic>) return v;
  if (v is Map) return v.map((k, val) => MapEntry(k.toString(), val));
  throw FormatException('Expected a JSON object, got ${v.runtimeType}');
}

List<Json> asJsonList(Object? v) {
  if (v == null) return const [];
  if (v is! List) throw FormatException('Expected a JSON array, got ${v.runtimeType}');
  return v.map(asJson).toList();
}

String reqString(Json j, String key) {
  final v = j[key];
  if (v is String) return v;
  if (v == null) throw FormatException('Missing required field "$key"');
  return v.toString();
}

String? optString(Json j, String key) {
  final v = j[key];
  if (v == null) return null;
  return v is String ? v : v.toString();
}

bool reqBool(Json j, String key) {
  final v = j[key];
  if (v is bool) return v;
  throw FormatException('Missing/invalid boolean field "$key"');
}

bool boolOr(Json j, String key, bool fallback) {
  final v = j[key];
  return v is bool ? v : fallback;
}

int reqInt(Json j, String key) {
  final v = j[key];
  if (v is num) return v.toInt();
  throw FormatException('Missing/invalid integer field "$key"');
}

int intOr(Json j, String key, int fallback) {
  final v = j[key];
  return v is num ? v.toInt() : fallback;
}

int? optInt(Json j, String key) {
  final v = j[key];
  return v is num ? v.toInt() : null;
}

double reqDouble(Json j, String key) {
  final v = j[key];
  if (v is num) return v.toDouble();
  throw FormatException('Missing/invalid number field "$key"');
}

double? optDouble(Json j, String key) {
  final v = j[key];
  return v is num ? v.toDouble() : null;
}

DateTime reqDate(Json j, String key) {
  final v = j[key];
  if (v is String) return DateTime.parse(v);
  throw FormatException('Missing/invalid timestamp field "$key"');
}

DateTime? optDate(Json j, String key) {
  final v = j[key];
  if (v is String && v.isNotEmpty) return DateTime.tryParse(v);
  return null;
}

List<String> stringList(Json j, String key) {
  final v = j[key];
  if (v is List) return v.map((e) => e.toString()).toList();
  return const [];
}

Map<String, int> intMap(Object? v) {
  if (v is! Map) return const {};
  return {for (final e in v.entries) e.key.toString(): (e.value is num) ? (e.value as num).toInt() : 0};
}

Json? optJson(Json j, String key) {
  final v = j[key];
  if (v == null) return null;
  return asJson(v);
}

/// Paginated list: `{"items": [...], "total", "limit", "offset"}`.
class PageOf<T> {
  const PageOf({required this.items, required this.total, required this.limit, required this.offset});

  final List<T> items;
  final int total;
  final int limit;
  final int offset;

  factory PageOf.fromJson(Json j, T Function(Json) item) => PageOf(
        items: asJsonList(j['items']).map(item).toList(),
        total: reqInt(j, 'total'),
        limit: reqInt(j, 'limit'),
        offset: reqInt(j, 'offset'),
      );

  bool get hasNext => offset + items.length < total;
  bool get hasPrevious => offset > 0;
}
