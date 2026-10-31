import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/models.dart';
import 'api_exception.dart';
import 'config.dart';
import 'json.dart';

/// Everything the app needs from the AapdaSaathi backend (`/api/v1`).
///
/// Widget tests inject a fake implementation; production uses [HttpAapdaApi].
abstract class AapdaApi {
  /// Bearer token used for authenticated calls (null = signed out).
  String? get token;
  set token(String? value);

  // auth
  Future<OtpRequestOut> requestOtp(String phone);
  Future<TokenOut> verifyOtp(String phone, String code, {String? fullName});
  Future<List<DemoPersona>> demoPersonas();
  Future<TokenOut> demoLogin(String userId);
  Future<MeOut> me();
  Future<UserOut> patchMe({String? language, String? fullName});
  Future<void> registerDevice(String fcmToken, String platform);
  Future<String> realtimeTicket();

  // resident
  Future<List<WardOut>> publicWards();
  Future<ResidentOut> register(RegistrationIn body);
  Future<ResidentOut> patchResident(Json patch);
  Future<ExactLocationOut?> myLocation();
  Future<ResidentOut> withdrawConsent();
  Future<ResidentOut> renewConsent();
  Future<List<AlertOut>> activeAlerts();
  Future<PageOut<AlertOut>> alertHistory({int limit = 50, int offset = 0});
  Future<AlertOut> alert(String deliveryId);
  Future<RespondOut> respond(String deliveryId, String status, {required String idempotencyKey});

  // caregiver
  Future<List<CaregiverResidentOut>> caregiverResidents();
  Future<RespondOut> caregiverRespond(String deliveryId, String status, {String? note});

  // neighbour
  Future<List<TaskOut>> neighbourChecks({bool includeClosed = false});
  Future<TaskOut> neighbourRespond(String taskId, String outcome, {String? note});

  // volunteer
  Future<VolunteerOut> volunteerMe();
  Future<VolunteerOut> setAvailability(bool available);
  Future<List<TaskOut>> volunteerTasks({bool includeClosed = false});
  Future<TaskDetailOut> taskDetail(String taskId);
  Future<TaskOut> acceptTask(String taskId);
  Future<TaskOut> cantGo(String taskId, String reason, {String? note});
  Future<TaskOut> reached(String taskId, String outcome, {String? note});
}

/// Real HTTP implementation.
class HttpAapdaApi implements AapdaApi {
  HttpAapdaApi(this.config, {http.Client? client, this.timeout = const Duration(seconds: 15)})
      : _client = client ?? http.Client();

  final AppConfig config;
  final http.Client _client;
  final Duration timeout;

  /// Called after every request: true when a response arrived, false on a network failure.
  void Function(bool reachable)? onReachability;

  @override
  String? token;

  Uri _uri(String path, [Map<String, String>? query]) {
    final u = Uri.parse('${config.apiRoot}$path');
    return query == null ? u : u.replace(queryParameters: query);
  }

  Future<dynamic> _send(
    String method,
    String path, {
    Object? body,
    Map<String, String>? query,
    Map<String, String>? headers,
    bool auth = true,
  }) async {
    final req = http.Request(method, _uri(path, query));
    req.headers['Accept'] = 'application/json';
    if (body != null) {
      req.headers['Content-Type'] = 'application/json';
      req.body = jsonEncode(body);
    }
    if (auth && token != null) req.headers['Authorization'] = 'Bearer $token';
    if (headers != null) req.headers.addAll(headers);

    http.Response res;
    try {
      final streamed = await _client.send(req).timeout(timeout);
      res = await http.Response.fromStream(streamed).timeout(timeout);
    } on TimeoutException {
      onReachability?.call(false);
      throw const ApiException.network('The server took too long to answer.');
    } catch (e) {
      onReachability?.call(false);
      throw const ApiException.network();
    }
    onReachability?.call(true);

    final text = utf8.decode(res.bodyBytes);
    dynamic decoded;
    if (text.isNotEmpty) {
      try {
        decoded = jsonDecode(text);
      } catch (_) {
        decoded = null;
      }
    }
    if (res.statusCode >= 200 && res.statusCode < 300) return decoded;

    var code = 'http_${res.statusCode}';
    var message = 'Request failed (${res.statusCode}).';
    if (decoded is Map && decoded['error'] is Map) {
      final err = decoded['error'] as Map;
      code = err['code']?.toString() ?? code;
      message = err['message']?.toString() ?? message;
    } else if (decoded is Map && decoded['detail'] != null) {
      message = decoded['detail'].toString();
    }
    throw ApiException(code: code, message: message, statusCode: res.statusCode);
  }

  Json _obj(dynamic v) {
    if (v is Map) return Map<String, dynamic>.from(v);
    throw const ApiException(code: 'bad_response', message: 'Unexpected response from the server.');
  }

  List<Json> _list(dynamic v) {
    if (v is List) return v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    throw const ApiException(code: 'bad_response', message: 'Unexpected response from the server.');
  }

  T _parse<T>(T Function() f) {
    try {
      return f();
    } on FormatException catch (e) {
      throw ApiException(code: 'bad_response', message: 'Could not read server response: ${e.message}');
    } on TypeError catch (e) {
      throw ApiException(code: 'bad_response', message: 'Could not read server response: $e');
    }
  }

  // ------------------------------------------------------------------ auth
  @override
  Future<OtpRequestOut> requestOtp(String phone) async {
    final j = await _send('POST', '/auth/otp/request', body: {'phone': phone}, auth: false);
    return _parse(() => OtpRequestOut.fromJson(_obj(j)));
  }

  @override
  Future<TokenOut> verifyOtp(String phone, String code, {String? fullName}) async {
    final j = await _send('POST', '/auth/otp/verify',
        body: {'phone': phone, 'code': code, if (fullName != null && fullName.isNotEmpty) 'full_name': fullName},
        auth: false);
    return _parse(() => TokenOut.fromJson(_obj(j)));
  }

  @override
  Future<List<DemoPersona>> demoPersonas() async {
    final j = await _send('GET', '/auth/demo-personas', auth: false);
    return _parse(() => _list(j).map(DemoPersona.fromJson).toList());
  }

  @override
  Future<TokenOut> demoLogin(String userId) async {
    final j = await _send('POST', '/auth/demo-login', body: {'user_id': userId}, auth: false);
    return _parse(() => TokenOut.fromJson(_obj(j)));
  }

  @override
  Future<MeOut> me() async {
    final j = await _send('GET', '/me');
    return _parse(() => MeOut.fromJson(_obj(j)));
  }

  @override
  Future<UserOut> patchMe({String? language, String? fullName}) async {
    final j = await _send('PATCH', '/me', body: {
      'language': ?language,
      'full_name': ?fullName,
    });
    return _parse(() => UserOut.fromJson(_obj(j)));
  }

  @override
  Future<void> registerDevice(String fcmToken, String platform) async {
    await _send('POST', '/me/devices', body: {'fcm_token': fcmToken, 'platform': platform});
  }

  @override
  Future<String> realtimeTicket() async {
    final j = _obj(await _send('POST', '/realtime/ticket'));
    return _parse(() => reqStr(j, 'ticket'));
  }

  // ------------------------------------------------------------------ resident
  @override
  Future<List<WardOut>> publicWards() async {
    final j = await _send('GET', '/wards/public');
    return _parse(() => _list(j).map(WardOut.fromJson).toList());
  }

  @override
  Future<ResidentOut> register(RegistrationIn body) async {
    final j = await _send('POST', '/residents/me/registration', body: body.toJson());
    return _parse(() => ResidentOut.fromJson(_obj(j)));
  }

  @override
  Future<ResidentOut> patchResident(Json patch) async {
    final j = await _send('PATCH', '/residents/me', body: patch);
    return _parse(() => ResidentOut.fromJson(_obj(j)));
  }

  @override
  Future<ExactLocationOut?> myLocation() async {
    final j = await _send('GET', '/residents/me/location');
    if (j == null) return null;
    return _parse(() => ExactLocationOut.fromJson(_obj(j)));
  }

  @override
  Future<ResidentOut> withdrawConsent() async {
    final j = await _send('POST', '/residents/me/consent/withdraw');
    return _parse(() => ResidentOut.fromJson(_obj(j)));
  }

  @override
  Future<ResidentOut> renewConsent() async {
    final j = await _send('POST', '/residents/me/consent/renew');
    return _parse(() => ResidentOut.fromJson(_obj(j)));
  }

  @override
  Future<List<AlertOut>> activeAlerts() async {
    final j = await _send('GET', '/alerts/active');
    return _parse(() => _list(j).map(AlertOut.fromJson).toList());
  }

  @override
  Future<PageOut<AlertOut>> alertHistory({int limit = 50, int offset = 0}) async {
    final j = await _send('GET', '/alerts/history', query: {'limit': '$limit', 'offset': '$offset'});
    return _parse(() => PageOut.fromJson(_obj(j), AlertOut.fromJson));
  }

  @override
  Future<AlertOut> alert(String deliveryId) async {
    final j = await _send('GET', '/alerts/${Uri.encodeComponent(deliveryId)}');
    return _parse(() => AlertOut.fromJson(_obj(j)));
  }

  @override
  Future<RespondOut> respond(String deliveryId, String status, {required String idempotencyKey}) async {
    final j = await _send('POST', '/alerts/${Uri.encodeComponent(deliveryId)}/respond',
        body: {'status': status, 'client_request_id': idempotencyKey},
        headers: {'Idempotency-Key': idempotencyKey});
    return _parse(() => RespondOut.fromJson(_obj(j)));
  }

  // ------------------------------------------------------------------ caregiver
  @override
  Future<List<CaregiverResidentOut>> caregiverResidents() async {
    final j = await _send('GET', '/caregiver/residents');
    return _parse(() => _list(j).map(CaregiverResidentOut.fromJson).toList());
  }

  @override
  Future<RespondOut> caregiverRespond(String deliveryId, String status, {String? note}) async {
    final j = await _send('POST', '/caregiver/alerts/${Uri.encodeComponent(deliveryId)}/respond',
        body: {'status': status, if (note != null && note.isNotEmpty) 'note': note});
    return _parse(() => RespondOut.fromJson(_obj(j)));
  }

  // ------------------------------------------------------------------ neighbour
  @override
  Future<List<TaskOut>> neighbourChecks({bool includeClosed = false}) async {
    final j = await _send('GET', '/neighbour/checks', query: {'include_closed': '$includeClosed'});
    return _parse(() => _list(j).map(TaskOut.fromJson).toList());
  }

  @override
  Future<TaskOut> neighbourRespond(String taskId, String outcome, {String? note}) async {
    final j = await _send('POST', '/neighbour/checks/${Uri.encodeComponent(taskId)}/respond',
        body: {'outcome': outcome, if (note != null && note.isNotEmpty) 'note': note});
    return _parse(() => TaskOut.fromJson(_obj(j)));
  }

  // ------------------------------------------------------------------ volunteer
  @override
  Future<VolunteerOut> volunteerMe() async {
    final j = await _send('GET', '/volunteer/me');
    return _parse(() => VolunteerOut.fromJson(_obj(j)));
  }

  @override
  Future<VolunteerOut> setAvailability(bool available) async {
    final j = await _send('PUT', '/volunteer/me/availability', body: {'is_available': available});
    return _parse(() => VolunteerOut.fromJson(_obj(j)));
  }

  @override
  Future<List<TaskOut>> volunteerTasks({bool includeClosed = false}) async {
    final j = await _send('GET', '/volunteer/tasks', query: {'include_closed': '$includeClosed'});
    return _parse(() => _list(j).map(TaskOut.fromJson).toList());
  }

  @override
  Future<TaskDetailOut> taskDetail(String taskId) async {
    final j = await _send('GET', '/tasks/${Uri.encodeComponent(taskId)}');
    return _parse(() => TaskDetailOut.fromJson(_obj(j)));
  }

  @override
  Future<TaskOut> acceptTask(String taskId) async {
    final j = await _send('POST', '/volunteer/tasks/${Uri.encodeComponent(taskId)}/accept');
    return _parse(() => TaskOut.fromJson(_obj(j)));
  }

  @override
  Future<TaskOut> cantGo(String taskId, String reason, {String? note}) async {
    final j = await _send('POST', '/volunteer/tasks/${Uri.encodeComponent(taskId)}/cant-go',
        body: {'reason': reason, if (note != null && note.isNotEmpty) 'note': note});
    return _parse(() => TaskOut.fromJson(_obj(j)));
  }

  @override
  Future<TaskOut> reached(String taskId, String outcome, {String? note}) async {
    final j = await _send('POST', '/volunteer/tasks/${Uri.encodeComponent(taskId)}/reached',
        body: {'outcome': outcome, if (note != null && note.isNotEmpty) 'note': note});
    return _parse(() => TaskOut.fromJson(_obj(j)));
  }
}
