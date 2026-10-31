/// A failed API call. Mirrors the backend error envelope `{"error": {"code", "message"}}`.
class ApiException implements Exception {
  const ApiException({required this.code, required this.message, this.statusCode});

  /// The request never got a response (no network, DNS failure, timeout, server down).
  const ApiException.network([this.message = 'Could not reach the AapdaSaathi server.'])
      : code = networkCode,
        statusCode = null;

  static const networkCode = 'network_error';

  final String code;
  final String message;
  final int? statusCode;

  bool get isNetwork => code == networkCode;
  bool get isUnauthorized => statusCode == 401;

  /// Worth retrying later (offline queue): network errors, rate limits and server errors.
  bool get isRetryable => isNetwork || statusCode == 429 || (statusCode != null && statusCode! >= 500);

  @override
  String toString() => 'ApiException($code${statusCode != null ? ', $statusCode' : ''}): $message';
}
