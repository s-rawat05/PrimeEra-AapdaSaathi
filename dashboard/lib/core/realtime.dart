import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'api.dart';

enum RealtimeState { offline, connecting, live, reconnecting }

/// A realtime event. Events are *hints to refetch* — the REST API stays the source of truth.
class RealtimeEvent {
  const RealtimeEvent(this.type, this.data);

  final String type;
  final Map<String, dynamic> data;

  String? get incidentId => data['incident_id']?.toString();

  /// Event types that should make the command centre refetch its views.
  bool get isRefreshHint =>
      type == 'delivery.updated' ||
      type == 'task.updated' ||
      type == 'incident.updated' ||
      type == 'notification.created' ||
      type.startsWith('feed.') ||
      type == 'demo.reset';
}

/// Interface so widget tests can use a no-op hub.
abstract class RealtimeHub {
  ValueListenable<RealtimeState> get state;
  Stream<RealtimeEvent> get events;
  DateTime? get lastEventAt;
  void start();
  void stop();
  void dispose();
}

/// WebSocket client: `POST /realtime/ticket` → `ws://host/api/v1/realtime?ticket=…`,
/// reconnecting with exponential backoff (1 s → 30 s, jittered).
class WebSocketRealtimeHub implements RealtimeHub {
  WebSocketRealtimeHub(this.api);

  final AapdaApi api;
  final _state = ValueNotifier<RealtimeState>(RealtimeState.offline);
  final _events = StreamController<RealtimeEvent>.broadcast();
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _sub;
  Timer? _retry;
  Timer? _watchdog;
  int _attempt = 0;
  bool _running = false;
  final _rand = Random();

  @override
  DateTime? lastEventAt;

  @override
  ValueListenable<RealtimeState> get state => _state;

  @override
  Stream<RealtimeEvent> get events => _events.stream;

  @override
  void start() {
    if (_running) return;
    _running = true;
    _connect();
  }

  Future<void> _connect() async {
    if (!_running) return;
    _state.value = _attempt == 0 ? RealtimeState.connecting : RealtimeState.reconnecting;
    try {
      final ticket = await api.realtimeTicket();
      if (!_running) return;
      final channel = WebSocketChannel.connect(api.realtimeUri(ticket));
      _channel = channel;
      await channel.ready;
      if (!_running) {
        await channel.sink.close();
        return;
      }
      _attempt = 0;
      _state.value = RealtimeState.live;
      _armWatchdog();
      _sub = channel.stream.listen(
        _onMessage,
        onError: (Object _) => _scheduleReconnect(),
        onDone: _scheduleReconnect,
        cancelOnError: true,
      );
    } catch (_) {
      _scheduleReconnect();
    }
  }

  void _onMessage(dynamic raw) {
    lastEventAt = DateTime.now();
    _armWatchdog();
    try {
      final decoded = jsonDecode(raw is String ? raw : utf8.decode(raw as List<int>));
      if (decoded is Map) {
        final data = decoded.map((k, v) => MapEntry(k.toString(), v));
        final type = data['type']?.toString() ?? 'unknown';
        if (type != 'ping') _events.add(RealtimeEvent(type, data));
      }
    } catch (_) {
      // Ignore malformed frames; polling covers us.
    }
  }

  /// The server pings every 25 s; if we hear nothing for 60 s the socket is considered dead.
  void _armWatchdog() {
    _watchdog?.cancel();
    _watchdog = Timer(const Duration(seconds: 60), _scheduleReconnect);
  }

  void _scheduleReconnect() {
    _watchdog?.cancel();
    _sub?.cancel();
    _sub = null;
    _channel?.sink.close();
    _channel = null;
    if (!_running) return;
    _retry?.cancel();
    _attempt++;
    final base = min(30, pow(2, min(_attempt, 5)).toInt());
    final delay = Duration(milliseconds: base * 1000 + _rand.nextInt(800));
    _state.value = RealtimeState.reconnecting;
    _retry = Timer(delay, _connect);
  }

  @override
  void stop() {
    _running = false;
    _retry?.cancel();
    _watchdog?.cancel();
    _sub?.cancel();
    _sub = null;
    _channel?.sink.close();
    _channel = null;
    _attempt = 0;
    _state.value = RealtimeState.offline;
  }

  @override
  void dispose() {
    stop();
    _events.close();
  }
}
