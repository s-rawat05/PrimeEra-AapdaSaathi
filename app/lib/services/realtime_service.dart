import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../core/api_client.dart';
import '../core/config.dart';

/// Realtime hints over the backend WebSocket. Events only mean "refetch"; the API stays the source
/// of truth. Reconnects with backoff. Polling (in the controller) covers the gaps.
class RealtimeService {
  RealtimeService(this.config, this.api, {required this.onEvent});

  final AppConfig config;
  final AapdaApi api;
  final void Function(Map<String, dynamic> event) onEvent;

  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  Timer? _retry;
  bool _running = false;
  int _attempt = 0;
  bool connected = false;

  void start() {
    if (_running) return;
    _running = true;
    _connect();
  }

  Future<void> _connect() async {
    if (!_running) return;
    try {
      final ticket = await api.realtimeTicket();
      if (!_running) return;
      final channel = WebSocketChannel.connect(config.realtimeUri(ticket));
      _channel = channel;
      await channel.ready;
      connected = true;
      _attempt = 0;
      _sub = channel.stream.listen(
        (data) {
          try {
            final ev = jsonDecode(data is String ? data : utf8.decode(data as List<int>));
            if (ev is Map) {
              final m = Map<String, dynamic>.from(ev);
              final type = m['type'];
              if (type != 'ping' && type != 'hello') onEvent(m);
            }
          } catch (_) {/* ignore malformed frames */}
        },
        onDone: _scheduleReconnect,
        onError: (_) => _scheduleReconnect(),
        cancelOnError: true,
      );
    } catch (_) {
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    connected = false;
    _sub?.cancel();
    _sub = null;
    _channel = null;
    if (!_running) return;
    _retry?.cancel();
    _attempt = (_attempt + 1).clamp(1, 6);
    // 2, 4, 8, 16, 32, 60 s
    final secs = (_attempt >= 6) ? 60 : (1 << _attempt);
    _retry = Timer(Duration(seconds: secs), _connect);
  }

  void stop() {
    _running = false;
    connected = false;
    _retry?.cancel();
    _sub?.cancel();
    _channel?.sink.close();
    _channel = null;
  }
}
