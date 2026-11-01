import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../core/api_client.dart';
import '../core/api_exception.dart';
import '../models/models.dart';
import '../services/local_store.dart';
import '../services/offline_queue.dart';

class AlertsSnapshot {
  AlertsSnapshot(this.alerts, {required this.fromCache, this.cachedAt});
  final List<AlertOut> alerts;
  final bool fromCache;
  final DateTime? cachedAt;
}

/// Resident alerts: live from the API, with a local copy for offline display.
///
/// The cache holds only the alert content (official text, framing, relief posts, status) —
/// no exact coordinates of the resident and no phone numbers.
class AlertRepository {
  AlertRepository(this._api, this._cache, this.queue);

  final AapdaApi _api;
  final LocalBox _cache;
  final OfflineQueue queue;
  static const _uuid = Uuid();

  static const _kActive = 'alerts.active';
  static const _kActiveAt = 'alerts.active_at';

  Future<AlertsSnapshot> loadActive() async {
    try {
      final alerts = await _api.activeAlerts();
      await _cache.put(_kActive, jsonEncode(alerts.map((a) => a.raw).toList()));
      await _cache.put(_kActiveAt, DateTime.now().toUtc().toIso8601String());
      return AlertsSnapshot(alerts, fromCache: false);
    } on ApiException catch (e) {
      if (!e.isNetwork) rethrow;
      final cached = cachedActive();
      if (cached == null) rethrow;
      return cached;
    }
  }

  AlertsSnapshot? cachedActive() {
    final s = _cache.get(_kActive);
    if (s == null) return null;
    try {
      final list = (jsonDecode(s) as List)
          .whereType<Map>()
          .map((m) => AlertOut.fromJson(Map<String, dynamic>.from(m)))
          .toList();
      final at = _cache.get(_kActiveAt);
      return AlertsSnapshot(list, fromCache: true, cachedAt: at == null ? null : DateTime.tryParse(at));
    } catch (_) {
      return null;
    }
  }

  Future<void> clearCache() async {
    await _cache.delete(_kActive);
    await _cache.delete(_kActiveAt);
  }

  Future<PageOut<AlertOut>> history({int limit = 50, int offset = 0}) =>
      _api.alertHistory(limit: limit, offset: offset);

  /// SAFE/HELP with a fresh idempotency key; queued on this device if the network is down.
  Future<SendResult> respond(String deliveryId, String status, {String? note}) =>
      queue.send(_api, deliveryId, status, _uuid.v4(), note: note);
}
