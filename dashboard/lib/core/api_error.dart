import 'dart:convert';

/// Error returned by the backend as `{"error": {"code": "...", "message": "..."}}`,
/// or a transport failure (statusCode 0).
class ApiException implements Exception {
  const ApiException({required this.statusCode, required this.code, required this.message});

  final int statusCode;
  final String code;
  final String message;

  bool get isUnauthorized => statusCode == 401;
  bool get isForbidden => statusCode == 403;
  bool get isConflict => statusCode == 409;
  bool get isNetwork => statusCode == 0;

  factory ApiException.fromResponse(int statusCode, String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded['error'] is Map) {
        final e = decoded['error'] as Map;
        return ApiException(
          statusCode: statusCode,
          code: (e['code'] ?? 'error').toString(),
          message: (e['message'] ?? 'Request failed').toString(),
        );
      }
      if (decoded is Map && decoded['detail'] != null) {
        return ApiException(statusCode: statusCode, code: 'error', message: decoded['detail'].toString());
      }
    } catch (_) {
      // Fall through to a generic error below.
    }
    return ApiException(
      statusCode: statusCode,
      code: 'http_$statusCode',
      message: body.isNotEmpty && body.length < 300 ? body : 'Request failed (HTTP $statusCode)',
    );
  }

  factory ApiException.network(Object error) => ApiException(
        statusCode: 0,
        code: 'network_error',
        message: 'Cannot reach the AapdaSaathi server. Check the connection and API_BASE_URL. ($error)',
      );

  /// User-facing text, e.g. `409 · Dispatch is no longer safe: …`.
  String get display => statusCode == 0 ? message : message;

  @override
  String toString() => 'ApiException($statusCode, $code): $message';
}

/// Client-side validation failure raised inside form submit handlers.
class InputError implements Exception {
  const InputError(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Converts any thrown object into a message suitable for a snackbar/banner.
String errorText(Object error) {
  if (error is ApiException) return error.display;
  if (error is FormatException) return 'Unexpected response from server: ${error.message}';
  return error.toString();
}
