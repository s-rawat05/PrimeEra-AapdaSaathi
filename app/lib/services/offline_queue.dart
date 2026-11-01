import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../core/api_client.dart';
import '../core/api_exception.dart';
import '../models/models.dart';
import 'local_store.dart';

/// A SAFE/HELP reply that has not reached the server yet.
///
/// The [idempotencyKey] is generated once, when the user taps, and reused on every retry, so the
/// server records the reply exactly once even if an earlier attempt actually got through.
class QueuedReply {
  QueuedReply({
    required this.idempotencyKey,
    required this.deliveryId,
    required this.status,
    required this.createdAt,
    this.attempts = 0,
    this.lastError,
    this.note,
  });

  factory QueuedReply.fromJson(Map<String, dynamic> j) => QueuedReply(
    idempotencyKey: j['key'] as String,
    deliveryId: j['delivery_id'] as String,
    status: j['status'] as String,
    createdAt: DateTime.parse(j['created_at'] as String),
    attempts: (j['attempts'] as num?)?.toInt() ?? 0,
    lastError: j['last_error'] as String?,
    note: j['note'] as String?,
  );

  final String idempotencyKey;
  final String deliveryId;
  final String status;
  final DateTime createdAt;
  int attempts;
  String? lastError;

  /// Optional note for operators (e.g. "Confirmed by voice").
  final String? note;

  Map<String, dynamic> toJson() => {
    'key': idempotencyKey,
    'delivery_id': deliveryId,
    'status': status,
    'created_at': createdAt.toUtc().toIso8601String(),
    'attempts': attempts,
    'last_error': lastError,
    if (note != null) 'note': note,
  };
}

/// Outcome of sending a reply: delivered (with the server's answer) or queued on this device.
class SendResult {
  SendResult.delivered(RespondOut this.response) : queued = null;
  SendResult.queued(QueuedReply this.queued) : response = null;

  final RespondOut? response;
  final QueuedReply? queued;

  bool get isDelivered => response != null;
}

/// Persistent queue of resident replies (Hive-backed). Survives app restarts.
class OfflineQueue extends ChangeNotifier {
  OfflineQueue(this._box);

  final LocalBox _box;
  bool _flushing = false;

  /// Last non-retryable failure while flushing (e.g. the incident was closed), for the UI.
  String? lastPermanentError;

  /// Called after each successful flush of an item.
  void Function(QueuedReply item, RespondOut out)? onDelivered;

  List<QueuedReply> get items {
    final out = <QueuedReply>[];
    for (final k in _box.keys) {
      final s = _box.get(k);
      if (s == null) continue;
      try {
        out.add(QueuedReply.fromJson(Map<String, dynamic>.from(jsonDecode(s) as Map)));
      } catch (_) {
        // Corrupt entry: drop it rather than crash.
        _box.delete(k);
      }
    }
    out.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return out;
  }

  bool get isEmpty => _box.keys.isEmpty;
  int get length => _box.keys.length;

  /// Latest queued status for a delivery (what the user last asked for), if any.
  QueuedReply? pendingFor(String deliveryId) {
    QueuedReply? last;
    for (final q in items) {
      if (q.deliveryId == deliveryId) last = q;
    }
    return last;
  }

  Future<void> add(QueuedReply r) async {
    // A newer reply for the same alert supersedes older queued ones (SAFE → HELP changes of mind).
    for (final q in items.where((q) => q.deliveryId == r.deliveryId)) {
      await _box.delete(q.idempotencyKey);
    }
    await _box.put(r.idempotencyKey, jsonEncode(r.toJson()));
    notifyListeners();
  }

  /// Try to send immediately; on a retryable failure, queue it. Other errors are rethrown.
  Future<SendResult> send(AapdaApi api, String deliveryId, String status, String idempotencyKey, {String? note}) async {
    try {
      final out = await api.respond(deliveryId, status, idempotencyKey: idempotencyKey, note: note);
      // A delivered reply supersedes anything still queued for this alert.
      for (final q in items.where((q) => q.deliveryId == deliveryId)) {
        await _box.delete(q.idempotencyKey);
      }
      notifyListeners();
      return SendResult.delivered(out);
    } on ApiException catch (e) {
      if (!e.isRetryable) rethrow;
      final q = QueuedReply(
        idempotencyKey: idempotencyKey,
        deliveryId: deliveryId,
        status: status,
        createdAt: DateTime.now().toUtc(),
        attempts: 1,
        lastError: e.message,
        note: note,
      );
      await add(q);
      return SendResult.queued(q);
    }
  }

  /// Send everything queued, oldest first. Stops at the first network failure.
  Future<int> flush(AapdaApi api) async {
    if (_flushing) return 0;
    _flushing = true;
    var sent = 0;
    try {
      for (final q in items) {
        try {
          final out = await api.respond(q.deliveryId, q.status, idempotencyKey: q.idempotencyKey, note: q.note);
          await _box.delete(q.idempotencyKey);
          sent++;
          onDelivered?.call(q, out);
        } on ApiException catch (e) {
          if (e.isRetryable) {
            q.attempts++;
            q.lastError = e.message;
            await _box.put(q.idempotencyKey, jsonEncode(q.toJson()));
            break;
          }
          // Permanent failure (e.g. 404/409/403): the reply can never be delivered — surface it.
          lastPermanentError = e.message;
          await _box.delete(q.idempotencyKey);
        }
      }
    } finally {
      _flushing = false;
      notifyListeners();
    }
    return sent;
  }

  Future<void> clear() async {
    for (final k in _box.keys) {
      await _box.delete(k);
    }
    notifyListeners();
  }
}
