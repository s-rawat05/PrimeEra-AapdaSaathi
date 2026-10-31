import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:aapda_command/core/api.dart';
import 'package:aapda_command/core/api_error.dart';
import 'package:aapda_command/core/config.dart';
import 'package:aapda_command/core/realtime.dart';
import 'package:aapda_command/core/session_store.dart';
import 'package:aapda_command/models/models.dart';
import 'package:aapda_command/services/app_scope.dart';
import 'package:aapda_command/services/auth_controller.dart';
import 'package:flutter/foundation.dart';

/// Real responses captured from the backend (see test/fixtures/live/).
dynamic fixture(String name) => jsonDecode(File('test/fixtures/live/$name.json').readAsStringSync());

Json fixtureObj(String name) => asJson(fixture(name));

/// Fake API: serves captured backend JSON through the real model parsers and records calls.
class FakeApi implements AapdaApi {
  FakeApi({this.role = 'operator'});

  /// Role returned by `GET /me`.
  String role;
  final List<String> calls = [];
  ApiException? failNext;

  @override
  String? token;

  @override
  void Function()? onUnauthorized;

  Future<T> _r<T>(String call, T Function() f) async {
    calls.add(call);
    final e = failNext;
    if (e != null) {
      failNext = null;
      throw e;
    }
    return f();
  }

  bool called(String prefix) => calls.any((c) => c.startsWith(prefix));

  @override
  Future<TokenOut> login(String identifier, String password) => _r('login:$identifier', () {
        final j = fixtureObj('token');
        (j['user'] as Map)['role'] = role;
        return TokenOut.fromJson(j);
      });

  @override
  Future<List<DemoPersona>> demoPersonas() =>
      _r('demoPersonas', () => asJsonList(fixture('demo_personas')).map(DemoPersona.fromJson).toList());

  @override
  Future<TokenOut> demoLogin(String userId) => _r('demoLogin:$userId', () => TokenOut.fromJson(fixtureObj('token')));

  @override
  Future<MeOut> me() => _r('me', () {
        final j = fixtureObj('me');
        (j['user'] as Map)['role'] = role;
        return MeOut.fromJson(j);
      });

  @override
  Future<String> realtimeTicket() => _r('ticket', () => 'ticket');

  @override
  Uri realtimeUri(String ticket) => const AppConfig(apiBaseUrl: 'http://test').realtimeUri(ticket);

  @override
  Future<PageOf<Incident>> listIncidents({String? status, bool? demo, int limit = 50, int offset = 0}) =>
      _r('listIncidents', () => PageOf.fromJson(fixtureObj('incidents'), Incident.fromJson));

  @override
  Future<Incident> getIncident(String id) => _r('getIncident:$id', () => Incident.fromJson(fixtureObj('incident')));

  @override
  Future<List<PriorityItem>> priority(String incidentId) =>
      _r('priority', () => asJsonList(fixture('priority')).map(PriorityItem.fromJson).toList());

  @override
  Future<IncidentMap> incidentMap(String incidentId) => _r('map', () => IncidentMap.fromJson(fixtureObj('map')));

  @override
  Future<List<TimelineEvent>> incidentTimeline(String incidentId, {int limit = 200}) =>
      _r('timeline', () => asJsonList(fixture('timeline')).map(TimelineEvent.fromJson).toList());

  @override
  Future<List<TaskOut>> incidentTasks(String incidentId) =>
      _r('tasks', () => asJsonList(fixture('tasks')).map(TaskOut.fromJson).toList());

  @override
  Future<IncidentReport> report(String incidentId) =>
      _r('report:$incidentId', () => IncidentReport.fromJson(fixtureObj('report')));

  @override
  Future<String> reportCsv(String incidentId) => _r('reportCsv:$incidentId', () => 'a,b\n1,2\n');

  @override
  Future<FeedStatus> feedStatus() => _r('feedStatus', () => FeedStatus.fromJson(fixtureObj('feed_status')));

  @override
  Future<PageOf<CapMessage>> feedMessages({bool includeFixtures = false, int limit = 50, int offset = 0}) =>
      _r('feedMessages', () => PageOf.fromJson(fixtureObj('feed_messages'), CapMessage.fromJson));

  @override
  Future<DemoStatus> demoStatus() => _r('demoStatus', () => DemoStatus.fromJson(fixtureObj('demo_status')));

  @override
  Future<List<OutboxItem>> smsOutbox({String? phone, int limit = 100}) =>
      _r('outbox', () => asJsonList(fixture('outbox')).map(OutboxItem.fromJson).toList());

  @override
  Future<List<TimelineEvent>> deliveryTimeline(String deliveryId) =>
      _r('deliveryTimeline', () => asJsonList(fixture('delivery_timeline')).map(TimelineEvent.fromJson).toList());

  @override
  Future<List<CandidateOut>> candidates(String deliveryId) =>
      _r('candidates', () => asJsonList(fixture('candidates')).map(CandidateOut.fromJson).toList());

  @override
  Future<PriorityItem> overrideStatus(String deliveryId, {required String status, required String reason}) =>
      _r('override:$deliveryId:$status:$reason', () => PriorityItem.fromJson(asJsonList(fixture('priority')).first));

  TaskOut _task(String id, String status) {
    final j = asJsonList(fixture('tasks')).firstWhere((t) => t['id'] == id);
    return TaskOut.fromJson({...j, 'status': status});
  }

  @override
  Future<TaskOut> approveTask(String taskId) => _r('approve:$taskId', () => _task(taskId, 'ASSIGNED'));

  @override
  Future<TaskOut> rejectTask(String taskId, String reason) =>
      _r('reject:$taskId:$reason', () => _task(taskId, 'REJECTED'));

  @override
  dynamic noSuchMethod(Invocation invocation) {
    calls.add('unimplemented:${invocation.memberName}');
    return Future<Never>.error(UnimplementedError('FakeApi: ${invocation.memberName}'));
  }
}

class FakeRealtimeHub implements RealtimeHub {
  final _state = ValueNotifier<RealtimeState>(RealtimeState.offline);
  final _events = StreamController<RealtimeEvent>.broadcast();

  @override
  DateTime? lastEventAt;

  @override
  ValueListenable<RealtimeState> get state => _state;

  @override
  Stream<RealtimeEvent> get events => _events.stream;

  void emit(RealtimeEvent e) => _events.add(e);

  @override
  void start() => _state.value = RealtimeState.live;

  @override
  void stop() => _state.value = RealtimeState.offline;

  @override
  void dispose() => _events.close();
}

AppServices fakeServices(FakeApi api, {String? token}) => AppServices(
      config: const AppConfig(apiBaseUrl: 'http://test', mapTilesEnabled: false),
      api: api,
      auth: AuthController(api: api, store: MemorySessionStore(token)),
      realtime: FakeRealtimeHub(),
    );
