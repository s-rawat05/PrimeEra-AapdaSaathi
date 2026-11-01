import 'dart:async';

import 'package:flutter/foundation.dart';

import '../accessibility/alert_effects.dart';
import '../accessibility/voice_input.dart';
import '../accessibility/modes.dart';
import '../core/api_client.dart';
import '../core/api_exception.dart';
import '../core/config.dart';
import '../l10n/strings.dart';
import '../models/models.dart';
import '../repositories/alert_repository.dart';
import '../repositories/responder_repository.dart';
import '../services/connectivity_service.dart';
import '../services/device_services.dart';
import '../services/notification_service.dart';
import '../services/offline_queue.dart';
import '../services/push_service.dart';
import '../services/realtime_service.dart';
import '../services/session_store.dart';
import '../services/supabase_auth.dart';

enum AuthStage { loading, signedOut, signedIn }

/// Where an emergency notification should take the user.
sealed class EmergencyTarget {
  const EmergencyTarget();
}

class AlertTarget extends EmergencyTarget {
  const AlertTarget(this.deliveryId);
  final String deliveryId;
}

class TaskTarget extends EmergencyTarget {
  const TaskTarget(this.taskId);
  final String taskId;
}

class CheckTarget extends EmergencyTarget {
  const CheckTarget(this.taskId);
  final String taskId;
}

class CaregiverTarget extends EmergencyTarget {
  const CaregiverTarget();
}

/// App-wide state: session, profile, language, live data for the signed-in role, and the
/// realtime/polling loop that detects new alerts and tasks.
class AppController extends ChangeNotifier {
  AppController({
    required this.config,
    required this.api,
    required this.session,
    required this.queue,
    required this.alerts,
    required this.connectivity,
    required this.notifier,
    required this.effects,
    required this.location,
    required this.permissions,
    required this.launcher,
    this.push,
    this.supabase,
    this.voice,
    this.enableLiveUpdates = true,
    this.enableMapTiles = true,
  }) : responders = ResponderRepository(api),
       _lang = session.language {
    connectivity.onBackOnline = _onBackOnline;
    queue.onDelivered = (_, _) => _scheduleRefresh();
    connectivity.addListener(notifyListeners);
    queue.addListener(notifyListeners);
  }

  final AppConfig config;
  final AapdaApi api;
  final SessionStore session;
  final OfflineQueue queue;
  final AlertRepository alerts;
  final ResponderRepository responders;
  final ConnectivityService connectivity;
  final EmergencyNotifier notifier;
  final AlertEffects effects;
  final LocationProvider location;
  final PermissionGateway permissions;
  final ExternalLauncher launcher;
  final PushService? push;
  final SupabaseAuth? supabase;

  /// Speech recognition for hands-free SAFE/HELP (vision profile). Null where unavailable.
  final VoiceInput? voice;
  final bool enableLiveUpdates;

  /// OSM tiles on the evacuation map (disabled in widget tests, which have no network).
  final bool enableMapTiles;

  /// Set by the UI layer: opens the right screen for an emergency.
  void Function(EmergencyTarget target)? onEmergency;

  AuthStage stage = AuthStage.loading;
  MeOut? me;
  bool meFromCache = false;

  String _lang;
  String get lang => _lang;
  Strings get s => Strings(_lang);

  // resident
  List<AlertOut> activeAlerts = const [];
  bool alertsFromCache = false;
  String? alertsError;

  // responders
  VolunteerOut? volunteer;
  List<TaskOut> volunteerTasks = const [];
  List<TaskOut> neighbourChecks = const [];
  List<CaregiverResidentOut> caregiverResidents = const [];
  String? responderError;

  DateTime? get lastSync => session.lastSync;

  Timer? _poll;
  Timer? _debounce;
  RealtimeService? _realtime;
  bool _refreshing = false;

  UserRole get role => me?.user.role ?? UserRole.unknown;

  /// Accessibility modes derived from the resident's declared needs (before any alert arrives).
  AlertModes get profileModes => AlertModes.fromNeeds(me?.resident?.needs ?? const []);

  /// Union of the alert's modes and the profile's modes.
  AlertModes modesFor(AlertOut? a) => a == null ? profileModes : AlertModes(a.accessibilityModes).union(profileModes);

  /// Extra text scale for an alert screen on top of the profile scale applied app-wide.
  double extraTextScaleFor(AlertOut a) =>
      AlertModes(a.accessibilityModes).largeText && !profileModes.largeText ? 1.3 : 1.0;

  AlertOut? get primaryAlert {
    if (activeAlerts.isEmpty) return null;
    return activeAlerts.firstWhere((a) => a.awaitingReply, orElse: () => activeAlerts.first);
  }

  AlertOut? alertById(String id) {
    for (final a in activeAlerts) {
      if (a.deliveryId == id) return a;
    }
    return null;
  }

  /// Shown on the UI after a reply could not be delivered at all.
  String? get queueError => queue.lastPermanentError;
  void clearQueueError() {
    queue.lastPermanentError = null;
    notifyListeners();
  }

  // ------------------------------------------------------------------ API wrapper
  /// Runs an API call and feeds the result into the connection status.
  Future<T> call<T>(Future<T> Function(AapdaApi api) f) async {
    try {
      final r = await f(api);
      connectivity.reportRequest(true);
      return r;
    } on ApiException catch (e) {
      connectivity.reportRequest(!e.isNetwork);
      if (e.isUnauthorized && stage == AuthStage.signedIn) {
        unawaited(logout());
      }
      rethrow;
    }
  }

  // ------------------------------------------------------------------ lifecycle
  Future<void> bootstrap() async {
    await notifier.init(onTap: _onNotificationTap);
    await push?.init();
    await supabase?.init();
    push?.onMessage = _scheduleRefresh;

    final token = session.token;
    if (token == null) {
      stage = AuthStage.signedOut;
      notifyListeners();
      return;
    }
    api.token = token;
    await _loadMe(allowCache: true);
    if (stage == AuthStage.signedIn) {
      final cached = alerts.cachedActive();
      if (cached != null) {
        activeAlerts = cached.alerts;
        alertsFromCache = true;
      }
      _afterSignIn();
      final payload = await notifier.launchPayload();
      if (payload != null) _onNotificationTap(payload);
    }
  }

  Future<void> _loadMe({bool allowCache = false}) async {
    try {
      final m = await call((a) => a.me());
      me = m;
      meFromCache = false;
      await session.setCachedMe(m.raw);
      await session.setLastDemoMode(m.demoMode);
      if (!session.languageChosen) {
        _lang = m.user.language == 'hi' ? 'hi' : 'en';
        await session.setLanguage(_lang);
      }
      stage = AuthStage.signedIn;
    } on ApiException catch (e) {
      if (e.isUnauthorized) {
        await _clearLocalSession();
        stage = AuthStage.signedOut;
      } else if (allowCache && session.cachedMe != null) {
        try {
          me = MeOut.fromJson(session.cachedMe!);
          meFromCache = true;
          stage = AuthStage.signedIn;
        } catch (_) {
          stage = AuthStage.signedOut;
        }
      } else if (allowCache) {
        // Offline with no cached profile: keep the token and show the sign-in gate with the error.
        stage = AuthStage.signedOut;
      } else {
        rethrow;
      }
    }
    notifyListeners();
  }

  Future<void> reloadMe() => _loadMe(allowCache: true);

  /// Completes sign-in with a backend token (OTP, demo login or Supabase).
  Future<void> signIn(String token) async {
    api.token = token;
    await session.setToken(token);
    await _loadMe();
    if (stage == AuthStage.signedIn) _afterSignIn();
  }

  bool get languageChosen => session.languageChosen;

  void _afterSignIn() {
    // Language picked before sign-in (on the login screen) is pushed to the server profile.
    if (session.languageChosen && me != null && me!.user.language != _lang) {
      unawaited(call((a) => a.patchMe(language: _lang)).then((_) {}, onError: (_) {}));
    }
    unawaited(_flushQueue());
    unawaited(refresh());
    if (push != null) unawaited(push!.registerWith(api));
    startLive();
  }

  Future<void> logout() async {
    stopLive();
    await effects.stop();
    await supabase?.signOut();
    await _clearLocalSession();
    stage = AuthStage.signedOut;
    notifyListeners();
  }

  Future<void> _clearLocalSession() async {
    api.token = null;
    me = null;
    activeAlerts = const [];
    volunteerTasks = const [];
    neighbourChecks = const [];
    caregiverResidents = const [];
    volunteer = null;
    await session.clearSession();
    await alerts.clearCache();
    await queue.clear();
  }

  void startLive() {
    if (!enableLiveUpdates) return;
    _poll?.cancel();
    _poll = Timer.periodic(config.pollInterval, (_) => refresh());
    _realtime?.stop();
    _realtime = RealtimeService(config, api, onEvent: (_) => _scheduleRefresh())..start();
  }

  void stopLive() {
    _poll?.cancel();
    _poll = null;
    _realtime?.stop();
    _realtime = null;
  }

  bool get realtimeConnected => _realtime?.connected ?? false;

  void _scheduleRefresh() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), refresh);
  }

  void _onBackOnline() {
    unawaited(_flushQueue());
    _scheduleRefresh();
  }

  Future<void> _flushQueue() async {
    if (queue.isEmpty || stage != AuthStage.signedIn) return;
    final sent = await queue.flush(api);
    if (sent > 0) connectivity.reportRequest(true);
    notifyListeners();
  }

  // ------------------------------------------------------------------ language
  Future<void> setLanguage(String l, {bool syncServer = true, bool markChosen = true}) async {
    if (!Strings.supported.contains(l)) return;
    _lang = l;
    await session.setLanguage(l);
    if (markChosen) await session.setLanguageChosen(true);
    notifyListeners();
    if (syncServer && stage == AuthStage.signedIn) {
      try {
        await call((a) => a.patchMe(language: l));
        // Alerts are rendered server-side in the resident's language: refetch them.
        unawaited(refresh());
      } on ApiException {
        // Local switch already applied; the server copy updates next time.
      }
    }
  }

  // ------------------------------------------------------------------ refresh
  Future<void> refresh() async {
    if (stage != AuthStage.signedIn || _refreshing) return;
    _refreshing = true;
    try {
      if (meFromCache) {
        try {
          await _loadMe(allowCache: true);
        } catch (_) {}
      }
      switch (role) {
        case UserRole.resident:
          await _refreshResident();
        case UserRole.volunteer:
          await _refreshVolunteer();
        case UserRole.neighbour:
          await _refreshNeighbour();
        case UserRole.caregiver:
          await _refreshCaregiver();
        default:
          break;
      }
      if (!queue.isEmpty && connectivity.isOnline) await _flushQueue();
    } finally {
      _refreshing = false;
      notifyListeners();
    }
  }

  Future<void> _markSynced() async {
    await session.setLastSync(DateTime.now().toUtc());
  }

  Future<void> _refreshResident() async {
    try {
      final snap = await alerts.loadActive();
      connectivity.reportRequest(!snap.fromCache);
      activeAlerts = snap.alerts;
      alertsFromCache = snap.fromCache;
      alertsError = null;
      if (!snap.fromCache) {
        await _markSynced();
        await _announceAlerts();
      }
    } on ApiException catch (e) {
      connectivity.reportRequest(!e.isNetwork);
      if (e.isUnauthorized) {
        await logout();
        return;
      }
      alertsError = e.message;
    }
  }

  Future<void> _announceAlerts() async {
    final seen = session.announced;
    for (final a in activeAlerts) {
      final key = 'a:${a.deliveryId}';
      if (!a.isActiveIncident || !a.awaitingReply || seen.contains(key)) continue;
      if (queue.pendingFor(a.deliveryId) != null) continue;
      await session.addAnnounced(key);
      await notifier.show(
        id: a.deliveryId.hashCode & 0x7fffffff,
        title: a.presentation.title.isNotEmpty ? a.presentation.title : s.activeAlert,
        body: a.official.headline ?? s.newAlertNotification,
        payload: 'alert:${a.deliveryId}',
      );
      final modes = modesFor(a);
      await effects.start(modes, speech: speechFor(a), ttsLocale: s.ttsLocale);
      onEmergency?.call(AlertTarget(a.deliveryId));
      break; // one emergency screen at a time
    }
  }

  /// What text-to-speech reads for an alert: framing title/body, then the official instruction.
  List<String> speechFor(AlertOut a) => [
    a.presentation.title,
    a.presentation.body,
    if (a.presentation.easyReadSteps.isNotEmpty) ...a.presentation.easyReadSteps,
    if (modesFor(a).voicePrompts) '${s.areYouSafe} ${s.iAmSafe} / ${s.iNeedHelp}',
  ];

  Future<void> _refreshVolunteer() async {
    try {
      final v = await call((a) => a.volunteerMe());
      final tasks = await call((a) => a.volunteerTasks(includeClosed: true));
      volunteer = v;
      volunteerTasks = tasks;
      responderError = null;
      await _markSynced();
      await _announceTasks(tasks.where((t) => t.isAssigned), 't', s.newTaskTitle, (id) => TaskTarget(id));
    } on ApiException catch (e) {
      responderError = e.message;
    }
  }

  Future<void> _refreshNeighbour() async {
    try {
      final checks = await call((a) => a.neighbourChecks(includeClosed: true));
      neighbourChecks = checks;
      responderError = null;
      await _markSynced();
      await _announceTasks(checks.where((t) => t.isOpen), 'c', s.newCheckTitle, (id) => CheckTarget(id));
    } on ApiException catch (e) {
      responderError = e.message;
    }
  }

  Future<void> _refreshCaregiver() async {
    try {
      final rows = await call((a) => a.caregiverResidents());
      caregiverResidents = rows;
      responderError = null;
      await _markSynced();
      final seen = session.announced;
      for (final r in rows) {
        for (final al in r.activeAlerts) {
          final key = 'g:${al.deliveryId}:${al.status}';
          if (seen.contains(key) || (al.status != DeliveryStatus.noReply && al.status != DeliveryStatus.help)) continue;
          await session.addAnnounced(key);
          await notifier.show(
            id: key.hashCode & 0x7fffffff,
            title: '${r.resident.fullName}: ${s.statusName(al.status)}',
            body: s.caregiverTitle,
            payload: 'caregiver',
          );
        }
      }
    } on ApiException catch (e) {
      responderError = e.message;
    }
  }

  Future<void> _announceTasks(
    Iterable<TaskOut> tasks,
    String prefix,
    String title,
    EmergencyTarget Function(String id) target,
  ) async {
    final seen = session.announced;
    for (final t in tasks) {
      final key = '$prefix:${t.id}';
      if (seen.contains(key)) continue;
      await session.addAnnounced(key);
      await notifier.show(
        id: t.id.hashCode & 0x7fffffff,
        title: title,
        body: '${t.residentFirstName} — ${t.incidentTitle}',
        payload: '$prefix:${t.id}',
      );
      await effects.start(AlertModes(const ['vibrate']), speech: const [], ttsLocale: s.ttsLocale);
      onEmergency?.call(target(t.id));
      break;
    }
  }

  void _onNotificationTap(String payload) {
    final i = payload.indexOf(':');
    final kind = i < 0 ? payload : payload.substring(0, i);
    final id = i < 0 ? '' : payload.substring(i + 1);
    switch (kind) {
      case 'alert':
        onEmergency?.call(AlertTarget(id));
      case 't':
        onEmergency?.call(TaskTarget(id));
      case 'c':
        onEmergency?.call(CheckTarget(id));
      case 'caregiver':
        onEmergency?.call(const CaregiverTarget());
    }
  }

  // ------------------------------------------------------------------ resident actions
  /// SAFE or HELP. Delivered immediately when online; otherwise queued (never shown as delivered).
  Future<SendResult> respond(AlertOut a, String status, {String? note}) async {
    final result = await alerts.respond(a.deliveryId, status, note: note);
    connectivity.reportRequest(result.isDelivered);
    if (result.isDelivered) {
      await effects.stop();
      await _markSynced();
      unawaited(refresh());
    } else {
      await effects.stop();
    }
    notifyListeners();
    return result;
  }

  QueuedReply? pendingReplyFor(String deliveryId) => queue.pendingFor(deliveryId);

  void applyResident(ResidentOut r) {
    final m = me;
    if (m == null) return;
    final raw = Map<String, dynamic>.from(m.raw);
    // Keep the cached /me in step without another round trip.
    me = MeOut(
      user: m.user,
      resident: r,
      volunteer: m.volunteer,
      demoMode: m.demoMode,
      notifyRealResidents: m.notifyRealResidents,
      raw: raw,
    );
    notifyListeners();
    unawaited(reloadMe());
  }

  void applyVolunteer(VolunteerOut v) {
    volunteer = v;
    notifyListeners();
  }

  @override
  void dispose() {
    stopLive();
    _debounce?.cancel();
    connectivity.removeListener(notifyListeners);
    queue.removeListener(notifyListeners);
    super.dispose();
  }
}
