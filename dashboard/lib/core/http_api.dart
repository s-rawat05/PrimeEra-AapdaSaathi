import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../models/models.dart';
import 'api.dart';
import 'api_error.dart';
import 'config.dart';

/// Real HTTP implementation of [AapdaApi].
class HttpAapdaApi implements AapdaApi {
  HttpAapdaApi(this.config, {http.Client? client}) : _client = client ?? http.Client();

  final AppConfig config;
  final http.Client _client;
  static const _timeout = Duration(seconds: 30);

  @override
  String? token;

  @override
  void Function()? onUnauthorized;

  Map<String, String> _headers({bool json = true}) => {
        if (json) 'Content-Type': 'application/json',
        'Accept': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };

  Future<http.Response> _send(String method, String path, {Map<String, String?>? query, Object? body}) async {
    final uri = config.apiUri(path, query);
    final req = http.Request(method, uri)..headers.addAll(_headers(json: body != null));
    if (body != null) req.body = jsonEncode(body);
    http.Response resp;
    try {
      resp = await http.Response.fromStream(await _client.send(req).timeout(_timeout));
    } on TimeoutException catch (e) {
      throw ApiException.network(e);
    } catch (e) {
      throw ApiException.network(e);
    }
    if (resp.statusCode == 401 && token != null) onUnauthorized?.call();
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw ApiException.fromResponse(resp.statusCode, utf8.decode(resp.bodyBytes, allowMalformed: true));
    }
    return resp;
  }

  Future<dynamic> _json(String method, String path, {Map<String, String?>? query, Object? body}) async {
    final resp = await _send(method, path, query: query, body: body);
    if (resp.bodyBytes.isEmpty) return null;
    return jsonDecode(utf8.decode(resp.bodyBytes));
  }

  Future<String> _text(String path) async {
    final resp = await _send('GET', path);
    return utf8.decode(resp.bodyBytes, allowMalformed: true);
  }

  Future<Json> _obj(String method, String path, {Map<String, String?>? query, Object? body}) async =>
      asJson(await _json(method, path, query: query, body: body));

  Future<List<Json>> _list(String path, {Map<String, String?>? query}) async =>
      asJsonList(await _json('GET', path, query: query));

  static String? _b(bool? v) => v?.toString();

  // ------------------------------------------------------------------ auth
  @override
  Future<TokenOut> login(String identifier, String password) async =>
      TokenOut.fromJson(await _obj('POST', '/auth/login', body: {'identifier': identifier, 'password': password}));

  @override
  Future<List<DemoPersona>> demoPersonas() async =>
      (await _list('/auth/demo-personas')).map(DemoPersona.fromJson).toList();

  @override
  Future<TokenOut> demoLogin(String userId) async =>
      TokenOut.fromJson(await _obj('POST', '/auth/demo-login', body: {'user_id': userId}));

  @override
  Future<MeOut> me() async => MeOut.fromJson(await _obj('GET', '/me'));

  @override
  Future<String> realtimeTicket() async => reqString(await _obj('POST', '/realtime/ticket'), 'ticket');

  @override
  Uri realtimeUri(String ticket) => config.realtimeUri(ticket);

  // ------------------------------------------------------------------ incidents
  @override
  Future<PageOf<Incident>> listIncidents({String? status, bool? demo, int limit = 50, int offset = 0}) async =>
      PageOf.fromJson(
        await _obj('GET', '/incidents',
            query: {'status': status, 'demo': _b(demo), 'limit': '$limit', 'offset': '$offset'}),
        Incident.fromJson,
      );

  @override
  Future<Incident> getIncident(String id) async => Incident.fromJson(await _obj('GET', '/incidents/$id'));

  @override
  Future<Incident> createIncident({
    required String title,
    required String hazardType,
    required List<String> wardIds,
    required String severity,
    required String urgency,
    int? onsetInMinutes,
    String? headline,
    String? instruction,
    required bool isDemo,
  }) async =>
      Incident.fromJson(await _obj('POST', '/incidents', body: {
        'title': title,
        'hazard_type': hazardType,
        'ward_ids': wardIds,
        'severity': severity,
        'urgency': urgency,
        'onset_in_minutes': onsetInMinutes,
        'headline': headline,
        'instruction': instruction,
        'is_demo': isDemo,
      }));

  @override
  Future<Incident> patchIncident(
    String id, {
    String? title,
    String? severity,
    int? onsetInMinutes,
    bool? requiresDispatchApproval,
    required String reason,
  }) async =>
      Incident.fromJson(await _obj('PATCH', '/incidents/$id', body: {
        'title': ?title,
        'severity': ?severity,
        'onset_in_minutes': ?onsetInMinutes,
        'requires_dispatch_approval': ?requiresDispatchApproval,
        'reason': reason,
      }));

  @override
  Future<Incident> closeIncident(String id, String note) async =>
      Incident.fromJson(await _obj('POST', '/incidents/$id/close', body: {'note': note}));

  @override
  Future<List<PriorityItem>> priority(String incidentId) async =>
      (await _list('/incidents/$incidentId/priority')).map(PriorityItem.fromJson).toList();

  @override
  Future<IncidentMap> incidentMap(String incidentId) async =>
      IncidentMap.fromJson(await _obj('GET', '/incidents/$incidentId/map'));

  @override
  Future<List<TimelineEvent>> incidentTimeline(String incidentId, {int limit = 200}) async =>
      (await _list('/incidents/$incidentId/timeline', query: {'limit': '$limit'}))
          .map(TimelineEvent.fromJson)
          .toList();

  @override
  Future<List<TaskOut>> incidentTasks(String incidentId) async =>
      (await _list('/incidents/$incidentId/tasks')).map(TaskOut.fromJson).toList();

  @override
  Future<IncidentReport> report(String incidentId) async =>
      IncidentReport.fromJson(await _obj('GET', '/incidents/$incidentId/report'));

  @override
  Future<String> reportCsv(String incidentId) => _text('/incidents/$incidentId/report.csv');

  // ------------------------------------------------------------------ deliveries
  @override
  Future<List<TimelineEvent>> deliveryTimeline(String deliveryId) async =>
      (await _list('/deliveries/$deliveryId/timeline')).map(TimelineEvent.fromJson).toList();

  @override
  Future<PriorityItem> resend(String deliveryId) async =>
      PriorityItem.fromJson(await _obj('POST', '/deliveries/$deliveryId/resend'));

  @override
  Future<PriorityItem> overrideStatus(String deliveryId, {required String status, required String reason}) async =>
      PriorityItem.fromJson(
          await _obj('POST', '/deliveries/$deliveryId/override', body: {'status': status, 'reason': reason}));

  @override
  Future<TaskOut?> dispatchNow(String deliveryId) async {
    final j = await _json('POST', '/deliveries/$deliveryId/dispatch');
    return j == null ? null : TaskOut.fromJson(asJson(j));
  }

  @override
  Future<List<CandidateOut>> candidates(String deliveryId) async =>
      (await _list('/deliveries/$deliveryId/candidates')).map(CandidateOut.fromJson).toList();

  @override
  Future<ExactLocationOut?> exactLocation(String deliveryId) async {
    final j = await _json('GET', '/deliveries/$deliveryId/location');
    return j == null ? null : ExactLocationOut.fromJson(asJson(j));
  }

  // ------------------------------------------------------------------ tasks
  @override
  Future<TaskOut> approveTask(String taskId) async => TaskOut.fromJson(await _obj('POST', '/tasks/$taskId/approve'));

  @override
  Future<TaskOut> rejectTask(String taskId, String reason) async =>
      TaskOut.fromJson(await _obj('POST', '/tasks/$taskId/reject', body: {'reason': reason}));

  @override
  Future<TaskOut?> reassignTask(String taskId, {String? toVolunteerId, required String reason}) async {
    final j = await _json('POST', '/tasks/$taskId/reassign',
        body: {'to_volunteer_id': toVolunteerId, 'reason': reason});
    return j == null ? null : TaskOut.fromJson(asJson(j));
  }

  // ------------------------------------------------------------------ feed
  @override
  Future<FeedStatus> feedStatus() async => FeedStatus.fromJson(await _obj('GET', '/feed/status'));

  @override
  Future<List<FeedPollResult>> feedPoll() async {
    final j = await _json('POST', '/feed/poll');
    return asJsonList(j).map(FeedPollResult.new).toList();
  }

  @override
  Future<PageOf<CapMessage>> feedMessages({bool includeFixtures = false, int limit = 50, int offset = 0}) async =>
      PageOf.fromJson(
        await _obj('GET', '/feed/messages',
            query: {'include_fixtures': '$includeFixtures', 'limit': '$limit', 'offset': '$offset'}),
        CapMessage.fromJson,
      );

  @override
  Future<String> feedMessageXml(String messageId) => _text('/feed/messages/$messageId/xml');

  @override
  Future<Incident> replayMessage(String messageId, {required int onsetInMinutes, List<String>? wardIds}) async =>
      Incident.fromJson(await _obj('POST', '/feed/messages/$messageId/replay',
          body: {'onset_in_minutes': onsetInMinutes, 'ward_ids': ?wardIds}));

  // ------------------------------------------------------------------ demo
  @override
  Future<DemoStatus> demoStatus() async => DemoStatus.fromJson(await _obj('GET', '/demo/status'));

  @override
  Future<Incident> simulate(String fixture, {required int onsetInMinutes, List<String>? wardIds}) async =>
      Incident.fromJson(await _obj('POST', '/demo/simulate',
          body: {'fixture': fixture, 'onset_in_minutes': onsetInMinutes, 'ward_ids': ?wardIds}));

  @override
  Future<DemoResetOut> demoReset() async => DemoResetOut.fromJson(await _obj('POST', '/demo/reset'));

  @override
  Future<Map<String, dynamic>> demoSeed() => _obj('POST', '/demo/seed');

  @override
  Future<SmsResult> smsInbound(String fromPhone, String body) async =>
      SmsResult.fromJson(await _obj('POST', '/demo/sms/inbound', body: {'from_phone': fromPhone, 'body': body}));

  @override
  Future<List<OutboxItem>> smsOutbox({String? phone, int limit = 100}) async =>
      (await _list('/demo/sms/outbox', query: {'phone': phone, 'limit': '$limit'})).map(OutboxItem.fromJson).toList();

  // ------------------------------------------------------------------ audit
  @override
  Future<PageOf<AuditOut>> audit(
          {String? entityType, String? entityId, String? action, int limit = 50, int offset = 0}) async =>
      PageOf.fromJson(
        await _obj('GET', '/audit', query: {
          'entity_type': entityType,
          'entity_id': entityId,
          'action': action,
          'limit': '$limit',
          'offset': '$offset',
        }),
        AuditOut.fromJson,
      );

  // ------------------------------------------------------------------ admin: wards & shelters
  @override
  Future<List<WardOut>> wards({bool withGeometry = false}) async =>
      (await _list('/admin/wards', query: {'with_geometry': '$withGeometry'})).map(WardOut.fromJson).toList();

  @override
  Future<GeoJsonUploadOut> uploadWardsGeojson(Uint8List bytes, String filename, {bool isDemo = false}) async {
    final uri = config.apiUri('/admin/wards/geojson', {'is_demo': '$isDemo'});
    final req = http.MultipartRequest('POST', uri)
      ..headers.addAll(_headers(json: false))
      ..files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename));
    http.Response resp;
    try {
      resp = await http.Response.fromStream(await _client.send(req).timeout(_timeout));
    } catch (e) {
      throw ApiException.network(e);
    }
    if (resp.statusCode == 401 && token != null) onUnauthorized?.call();
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw ApiException.fromResponse(resp.statusCode, utf8.decode(resp.bodyBytes, allowMalformed: true));
    }
    return GeoJsonUploadOut.fromJson(asJson(jsonDecode(utf8.decode(resp.bodyBytes))));
  }

  @override
  Future<WardOut> setWardAccess(String wardId, String accessStatus, String? note) async => WardOut.fromJson(
      await _obj('PUT', '/admin/wards/$wardId/access', body: {'access_status': accessStatus, 'note': note}));

  @override
  Future<List<ShelterOut>> shelters() async => (await _list('/admin/shelters')).map(ShelterOut.fromJson).toList();

  @override
  Future<ShelterOut> createShelter({
    required String wardId,
    required String name,
    required String address,
    required double lat,
    required double lng,
    required String source,
  }) async =>
      ShelterOut.fromJson(await _obj('POST', '/admin/shelters', body: {
        'ward_id': wardId,
        'name': name,
        'address': address,
        'lat': lat,
        'lng': lng,
        'source': source,
      }));

  @override
  Future<void> deleteShelter(String shelterId) => _send('DELETE', '/admin/shelters/$shelterId');

  // ------------------------------------------------------------------ admin: residents
  @override
  Future<PageOf<ResidentOut>> residents(
          {String? q, String? wardId, String? status, String? need, int limit = 50, int offset = 0}) async =>
      PageOf.fromJson(
        await _obj('GET', '/admin/residents', query: {
          'q': q,
          'ward_id': wardId,
          'status': status,
          'need': need,
          'limit': '$limit',
          'offset': '$offset',
        }),
        ResidentOut.fromJson,
      );

  @override
  Future<ResidentOut> registerResident(Map<String, dynamic> body) async =>
      ResidentOut.fromJson(await _obj('POST', '/admin/residents', body: body));

  @override
  Future<ResidentOut> reverifyResident(String residentId) async =>
      ResidentOut.fromJson(await _obj('POST', '/admin/residents/$residentId/reverify'));

  @override
  Future<ResidentOut> withdrawResident(String residentId, String reason) async =>
      ResidentOut.fromJson(await _obj('POST', '/admin/residents/$residentId/withdraw', body: {'reason': reason}));

  @override
  Future<void> eraseResident(String residentId, String reason) =>
      _send('DELETE', '/admin/residents/$residentId', query: {'reason': reason});

  // ------------------------------------------------------------------ admin: volunteers
  @override
  Future<List<VolunteerOut>> volunteers() async =>
      (await _list('/admin/volunteers')).map(VolunteerOut.fromJson).toList();

  @override
  Future<VolunteerOut> createVolunteer(Map<String, dynamic> body) async =>
      VolunteerOut.fromJson(await _obj('POST', '/admin/volunteers', body: body));

  @override
  Future<VolunteerOut> setVolunteerAvailability(String volunteerId, bool isAvailable) async => VolunteerOut.fromJson(
      await _obj('PUT', '/admin/volunteers/$volunteerId/availability', body: {'is_available': isAvailable}));

  @override
  Future<VolunteerOut> setVolunteerVerified(String volunteerId, bool verified) async => VolunteerOut.fromJson(
      await _obj('PUT', '/admin/volunteers/$volunteerId/verified', query: {'verified': '$verified'}));

  // ------------------------------------------------------------------ admin: neighbour links / helpers
  @override
  Future<List<NeighbourLinkOut>> neighbourLinks() async =>
      (await _list('/admin/neighbour-links')).map(NeighbourLinkOut.fromJson).toList();

  @override
  Future<NeighbourLinkOut> createNeighbourLink({
    required String residentId,
    required String neighbourUserId,
    required int priority,
    double? distanceM,
  }) async =>
      NeighbourLinkOut.fromJson(await _obj('POST', '/admin/neighbour-links', body: {
        'resident_id': residentId,
        'neighbour_user_id': neighbourUserId,
        'priority': priority,
        'distance_m': distanceM,
      }));

  @override
  Future<NeighbourLinkOut> setNeighbourLinkPriority(String linkId, int priority) async => NeighbourLinkOut.fromJson(
      await _obj('PATCH', '/admin/neighbour-links/$linkId', query: {'priority': '$priority'}));

  @override
  Future<void> deleteNeighbourLink(String linkId) => _send('DELETE', '/admin/neighbour-links/$linkId');

  @override
  Future<List<PreAssignedOut>> preAssigned() async =>
      (await _list('/admin/pre-assigned')).map(PreAssignedOut.fromJson).toList();

  @override
  Future<PreAssignedOut> createPreAssigned(
          {required String residentId, required String volunteerId, required int priority}) async =>
      PreAssignedOut.fromJson(await _obj('POST', '/admin/pre-assigned',
          body: {'resident_id': residentId, 'volunteer_id': volunteerId, 'priority': priority}));

  @override
  Future<void> deletePreAssigned(String id) => _send('DELETE', '/admin/pre-assigned/$id');

  // ------------------------------------------------------------------ admin: templates & users
  @override
  Future<List<TemplateOut>> templates() async => (await _list('/admin/templates')).map(TemplateOut.fromJson).toList();

  @override
  Future<TemplateOut> upsertTemplate(Map<String, dynamic> body) async =>
      TemplateOut.fromJson(await _obj('POST', '/admin/templates', body: body));

  @override
  Future<PageOf<UserAdminOut>> users({String? role, String? q, int limit = 50, int offset = 0}) async =>
      PageOf.fromJson(
        await _obj('GET', '/admin/users', query: {'role': role, 'q': q, 'limit': '$limit', 'offset': '$offset'}),
        UserAdminOut.fromJson,
      );

  @override
  Future<UserAdminOut> createUser(Map<String, dynamic> body) async =>
      UserAdminOut.fromJson(await _obj('POST', '/admin/users', body: body));

  @override
  Future<UserAdminOut> patchUser(String userId, {String? role, bool? isActive}) async => UserAdminOut.fromJson(
      await _obj('PATCH', '/admin/users/$userId', body: {'role': ?role, 'is_active': ?isActive}));
}
