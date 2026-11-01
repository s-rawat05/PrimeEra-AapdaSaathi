import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/api.dart';
import '../../core/api_error.dart';
import '../../core/realtime.dart';
import '../../models/models.dart';

/// State for the live command centre. Everything shown comes from the API;
/// realtime events only trigger refetches, and a 10 s poll covers socket outages.
class CommandCentreController extends ChangeNotifier {
  CommandCentreController({
    required this.api,
    required this.realtime,
    this.pollInterval = const Duration(seconds: 10),
  });

  final AapdaApi api;
  final RealtimeHub realtime;
  final Duration pollInterval;

  List<Incident> activeIncidents = const [];
  String? selectedId;
  Incident? incident;
  List<PriorityItem> priority = const [];
  IncidentMap? map;
  List<TaskOut> tasks = const [];
  List<TimelineEvent> timeline = const [];
  FeedStatus? feedStatus;
  DemoStatus? demoStatus;

  /// Errors by section: incidents, incident, priority, map, tasks, timeline, feed, demo.
  final Map<String, Object> errors = {};
  bool initialLoad = true;
  DateTime? lastRefresh;

  /// Bumped on events so self-loading panels (SACHET list, SMS inbox) refetch.
  int feedRevision = 0;
  int smsRevision = 0;

  Timer? _poll;
  Timer? _debounce;
  StreamSubscription<RealtimeEvent>? _sub;
  bool _disposed = false;
  bool _refreshing = false;
  final Set<String> _pendingKinds = {};

  void start() {
    _sub ??= realtime.events.listen(_onEvent);
    realtime.start();
    _poll ??= Timer.periodic(pollInterval, (_) => refreshAll(quiet: true));
    refreshAll();
  }

  void _onEvent(RealtimeEvent e) {
    if (!e.isRefreshHint) return;
    if (e.type.startsWith('feed.')) {
      _pendingKinds.add('feed');
    } else if (e.type == 'demo.reset') {
      _pendingKinds.add('all');
    } else {
      if (e.type == 'incident.updated') _pendingKinds.add('incidents');
      if (e.incidentId == null || e.incidentId == selectedId) _pendingKinds.add('incident');
      if (e.type == 'notification.created' || e.type == 'delivery.updated') _pendingKinds.add('sms');
    }
    // Coalesce bursts of events (an escalation round emits many) into one refetch.
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _flushEvents);
  }

  Future<void> _flushEvents() async {
    final kinds = Set<String>.of(_pendingKinds);
    _pendingKinds.clear();
    if (kinds.contains('all')) {
      feedRevision++;
      smsRevision++;
      await refreshAll(quiet: true);
      return;
    }
    if (kinds.contains('feed')) {
      feedRevision++;
      await _guard('feed', () async => feedStatus = await api.feedStatus());
    }
    if (kinds.contains('sms')) smsRevision++;
    if (kinds.contains('incidents')) await _loadIncidents();
    if (kinds.contains('incident')) await refreshIncident();
    _notify();
  }

  Future<void> _guard(String key, Future<void> Function() f) async {
    try {
      await f();
      errors.remove(key);
    } catch (e) {
      errors[key] = e;
    }
  }

  Future<void> _loadIncidents() => _guard('incidents', () async {
        final page = await api.listIncidents(status: 'active', limit: 100);
        activeIncidents = page.items;
      });

  /// Reloads everything. `quiet` = background poll (no spinner).
  Future<void> refreshAll({bool quiet = false}) async {
    if (_refreshing) return;
    _refreshing = true;
    try {
      await Future.wait([
        _loadIncidents(),
        _guard('feed', () async => feedStatus = await api.feedStatus()),
        _guard('demo', () async => demoStatus = await api.demoStatus()),
      ]);
      if (selectedId == null && activeIncidents.isNotEmpty) selectedId = activeIncidents.first.id;
      await refreshIncident();
      if (quiet) smsRevision++;
    } finally {
      _refreshing = false;
      initialLoad = false;
      lastRefresh = DateTime.now();
      _notify();
    }
  }

  /// Reloads the selected incident's views in parallel.
  Future<void> refreshIncident() async {
    final id = selectedId;
    if (id == null) {
      incident = null;
      priority = const [];
      map = null;
      tasks = const [];
      timeline = const [];
      _notify();
      return;
    }
    try {
      final inc = await api.getIncident(id);
      if (selectedId != id) return;
      incident = inc;
      errors.remove('incident');
    } on ApiException catch (e) {
      if (e.statusCode == 404) {
        // Incident removed (e.g. demo reset): fall back to the newest active incident.
        selectedId = activeIncidents.where((i) => i.id != id).map((i) => i.id).firstOrNull;
        incident = null;
        errors.remove('incident');
        if (selectedId != null) return refreshIncident();
        priority = const [];
        map = null;
        tasks = const [];
        timeline = const [];
        _notify();
        return;
      }
      errors['incident'] = e;
    } catch (e) {
      errors['incident'] = e;
    }
    await Future.wait([
      _guard('priority', () async {
        final r = await api.priority(id);
        if (selectedId == id) priority = r;
      }),
      _guard('map', () async {
        final r = await api.incidentMap(id);
        if (selectedId == id) map = r;
      }),
      _guard('tasks', () async {
        final r = await api.incidentTasks(id);
        if (selectedId == id) tasks = r;
      }),
      _guard('timeline', () async {
        final r = await api.incidentTimeline(id, limit: 200);
        if (selectedId == id) timeline = r;
      }),
    ]);
    lastRefresh = DateTime.now();
    _notify();
  }

  Future<void> refreshDemoStatus() async {
    await _guard('demo', () async => demoStatus = await api.demoStatus());
    _notify();
  }

  void select(String? id) {
    if (id == selectedId) return;
    selectedId = id;
    incident = null;
    priority = const [];
    map = null;
    tasks = const [];
    timeline = const [];
    _notify();
    refreshIncident();
  }

  /// After creating an incident (simulate / replay / manual), show it immediately.
  Future<void> focusIncident(Incident created) async {
    selectedId = created.id;
    incident = created;
    priority = const [];
    map = null;
    tasks = const [];
    timeline = const [];
    _notify();
    await Future.wait([_loadIncidents(), refreshIncident(), refreshDemoStatus()]);
    smsRevision++;
    _notify();
  }

  /// List for the selector: active incidents plus the selected one even if it was just closed.
  List<Incident> get selectableIncidents {
    final inc = incident;
    if (inc != null && !activeIncidents.any((i) => i.id == inc.id)) return [inc, ...activeIncidents];
    return activeIncidents;
  }

  PriorityItem? priorityFor(String deliveryId) => priority.where((p) => p.deliveryId == deliveryId).firstOrNull;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _poll?.cancel();
    _debounce?.cancel();
    _sub?.cancel();
    realtime.stop();
    super.dispose();
  }
}
