import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

enum ConnectionStatus { online, offline, reconnecting }

/// Combines the OS network state (connectivity_plus) with the result of real API calls.
///
/// The OS can report "wifi" while the server is unreachable, so a failed request moves the state
/// to [ConnectionStatus.reconnecting] (or offline) until a request succeeds again.
class ConnectivityService extends ChangeNotifier {
  ConnectivityService({Stream<List<ConnectivityResult>>? platformChanges, bool listenToPlatform = true}) {
    if (!listenToPlatform) return;
    try {
      final stream = platformChanges ?? Connectivity().onConnectivityChanged;
      _sub = stream.listen(_onPlatform, onError: (_) {});
      if (platformChanges == null) {
        Connectivity().checkConnectivity().then(_onPlatform).catchError((_) {});
      }
    } catch (_) {
      // Plugin unavailable (tests / unsupported platform): rely on request results only.
    }
  }

  StreamSubscription<List<ConnectivityResult>>? _sub;
  ConnectionStatus _status = ConnectionStatus.online;
  bool _platformOffline = false;
  int _consecutiveFailures = 0;

  /// Fired when we move from a not-online state back to online (used to flush the queue).
  VoidCallback? onBackOnline;

  ConnectionStatus get status => _status;
  bool get isOnline => _status == ConnectionStatus.online;

  void _onPlatform(List<ConnectivityResult> results) {
    final offline = results.isEmpty || results.every((r) => r == ConnectivityResult.none);
    _platformOffline = offline;
    if (offline) {
      _set(ConnectionStatus.offline);
    } else if (_status == ConnectionStatus.offline) {
      // Network is back but the server has not answered yet.
      _set(ConnectionStatus.reconnecting);
      onBackOnline?.call();
    }
  }

  /// Report the outcome of a real request.
  void reportRequest(bool reachable) {
    if (reachable) {
      _consecutiveFailures = 0;
      _set(ConnectionStatus.online);
    } else {
      _consecutiveFailures++;
      _set(_platformOffline || _consecutiveFailures >= 3 ? ConnectionStatus.offline : ConnectionStatus.reconnecting);
    }
  }

  void _set(ConnectionStatus s) {
    if (s == _status) return;
    final wasOnline = _status == ConnectionStatus.online;
    _status = s;
    notifyListeners();
    if (!wasOnline && s == ConnectionStatus.online) onBackOnline?.call();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
