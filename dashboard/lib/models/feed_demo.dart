import 'admin.dart';
import 'auth.dart';
import 'json.dart';

class FeedHealth {
  const FeedHealth({
    required this.url,
    required this.healthy,
    required this.lastFetchAt,
    required this.lastSuccessAt,
    required this.lastStatusCode,
    required this.lastError,
    required this.consecutiveFailures,
    required this.nextFetchAt,
    required this.itemsSeen,
    required this.etag,
  });

  final String url;
  final bool healthy;
  final DateTime? lastFetchAt;
  final DateTime? lastSuccessAt;
  final int? lastStatusCode;
  final String? lastError;
  final int consecutiveFailures;
  final DateTime? nextFetchAt;
  final int itemsSeen;
  final String? etag;

  factory FeedHealth.fromJson(Json j) => FeedHealth(
        url: reqString(j, 'url'),
        healthy: reqBool(j, 'healthy'),
        lastFetchAt: optDate(j, 'last_fetch_at'),
        lastSuccessAt: optDate(j, 'last_success_at'),
        lastStatusCode: optInt(j, 'last_status_code'),
        lastError: optString(j, 'last_error'),
        consecutiveFailures: intOr(j, 'consecutive_failures', 0),
        nextFetchAt: optDate(j, 'next_fetch_at'),
        itemsSeen: intOr(j, 'items_seen', 0),
        etag: optString(j, 'etag'),
      );
}

class FeedStatus {
  const FeedStatus({required this.pollingEnabled, required this.notifyRealResidents, required this.feeds});

  final bool pollingEnabled;
  final bool notifyRealResidents;
  final List<FeedHealth> feeds;

  bool get allHealthy => feeds.isNotEmpty && feeds.every((f) => f.healthy);

  factory FeedStatus.fromJson(Json j) => FeedStatus(
        pollingEnabled: reqBool(j, 'polling_enabled'),
        notifyRealResidents: reqBool(j, 'notify_real_residents'),
        feeds: asJsonList(j['feeds']).map(FeedHealth.fromJson).toList(),
      );
}

class CapMessage {
  const CapMessage({
    required this.id,
    required this.identifier,
    required this.sender,
    required this.sent,
    required this.status,
    required this.msgType,
    required this.event,
    required this.severity,
    required this.urgency,
    required this.certainty,
    required this.onset,
    required this.expires,
    required this.headline,
    required this.areaDesc,
    required this.officialUrl,
    required this.isValid,
    required this.validationErrors,
    required this.isFixture,
    required this.supersededBy,
    required this.fetchedAt,
    required this.incidentIds,
  });

  final String id;
  final String identifier;
  final String? sender;
  final DateTime? sent;
  final String? status;
  final String? msgType;
  final String? event;
  final String? severity;
  final String? urgency;
  final String? certainty;
  final DateTime? onset;
  final DateTime? expires;
  final String? headline;
  final String? areaDesc;
  final String? officialUrl;
  final bool isValid;
  final List<String> validationErrors;
  final bool isFixture;
  final String? supersededBy;
  final DateTime fetchedAt;
  final List<String> incidentIds;

  factory CapMessage.fromJson(Json j) => CapMessage(
        id: reqString(j, 'id'),
        identifier: reqString(j, 'identifier'),
        sender: optString(j, 'sender'),
        sent: optDate(j, 'sent'),
        status: optString(j, 'status'),
        msgType: optString(j, 'msg_type'),
        event: optString(j, 'event'),
        severity: optString(j, 'severity'),
        urgency: optString(j, 'urgency'),
        certainty: optString(j, 'certainty'),
        onset: optDate(j, 'onset'),
        expires: optDate(j, 'expires'),
        headline: optString(j, 'headline'),
        areaDesc: optString(j, 'area_desc'),
        officialUrl: optString(j, 'official_url'),
        isValid: reqBool(j, 'is_valid'),
        validationErrors: stringList(j, 'validation_errors'),
        isFixture: reqBool(j, 'is_fixture'),
        supersededBy: optString(j, 'superseded_by'),
        fetchedAt: reqDate(j, 'fetched_at'),
        incidentIds: stringList(j, 'incident_ids'),
      );
}

/// One entry of `POST /feed/poll` (shape varies: skipped / 304 / 200 / failure).
class FeedPollResult {
  const FeedPollResult(this.raw);

  final Json raw;

  String get url => raw['url']?.toString() ?? '';

  String get summary {
    if (raw['skipped'] == true) return 'Skipped (next fetch ${raw['next_fetch_at'] ?? '—'})';
    final status = raw['status'];
    if (status == 304) return 'HTTP 304 — not modified (ETag matched)';
    if (status == 200) {
      final errors = (raw['errors'] is List) ? (raw['errors'] as List).length : 0;
      return 'HTTP 200 — ${raw['items'] ?? 0} items, ${raw['new'] ?? 0} new'
          '${errors > 0 ? ', $errors parse errors' : ''}';
    }
    final err = raw['error'] ?? raw['last_error'];
    return err != null ? 'Failed: $err' : raw.toString();
  }
}

class SmsResult {
  const SmsResult({required this.result, required this.action, required this.deliveryId, required this.taskId, required this.detail});

  final String result;
  final String? action;
  final String? deliveryId;
  final String? taskId;
  final String? detail;

  factory SmsResult.fromJson(Json j) => SmsResult(
        result: reqString(j, 'result'),
        action: optString(j, 'action'),
        deliveryId: optString(j, 'delivery_id'),
        taskId: optString(j, 'task_id'),
        detail: optString(j, 'detail'),
      );
}

class OutboxItem {
  const OutboxItem({
    required this.id,
    required this.channel,
    required this.recipientKind,
    required this.recipientPhone,
    required this.title,
    required this.body,
    required this.status,
    required this.provider,
    required this.error,
    required this.round,
    required this.createdAt,
    required this.sentAt,
  });

  final String id;
  final String channel;
  final String recipientKind;
  final String? recipientPhone;
  final String? title;
  final String? body;
  final String status;
  final String? provider;
  final String? error;
  final String round;
  final DateTime createdAt;
  final DateTime? sentAt;

  factory OutboxItem.fromJson(Json j) => OutboxItem(
        id: reqString(j, 'id'),
        channel: reqString(j, 'channel'),
        recipientKind: reqString(j, 'recipient_kind'),
        recipientPhone: optString(j, 'recipient_phone'),
        title: optString(j, 'title'),
        body: optString(j, 'body'),
        status: reqString(j, 'status'),
        provider: optString(j, 'provider'),
        error: optString(j, 'error'),
        round: reqString(j, 'round'),
        createdAt: reqDate(j, 'created_at'),
        sentAt: optDate(j, 'sent_at'),
      );
}

class DemoStatus {
  const DemoStatus({
    required this.demoModeEnabled,
    required this.notifyRealResidents,
    required this.demoWards,
    required this.demoResidents,
    required this.activeDemoIncidents,
    required this.escalationIntervalSeconds,
    required this.fixtures,
    required this.personas,
  });

  final bool demoModeEnabled;
  final bool notifyRealResidents;
  final List<WardOut> demoWards;
  final int demoResidents;
  final int activeDemoIncidents;
  final int escalationIntervalSeconds;
  final List<String> fixtures;
  final List<DemoPersona> personas;

  factory DemoStatus.fromJson(Json j) => DemoStatus(
        demoModeEnabled: reqBool(j, 'demo_mode_enabled'),
        notifyRealResidents: reqBool(j, 'notify_real_residents'),
        demoWards: asJsonList(j['demo_wards']).map(WardOut.fromJson).toList(),
        demoResidents: reqInt(j, 'demo_residents'),
        activeDemoIncidents: reqInt(j, 'active_demo_incidents'),
        escalationIntervalSeconds: reqInt(j, 'escalation_interval_seconds'),
        fixtures: stringList(j, 'fixtures'),
        personas: asJsonList(j['personas']).map(DemoPersona.fromJson).toList(),
      );
}

class DemoResetOut {
  const DemoResetOut({
    required this.incidentsRemoved,
    required this.smsRemoved,
    required this.volunteersReset,
    required this.realDataUntouched,
  });

  final int incidentsRemoved;
  final int smsRemoved;
  final int volunteersReset;
  final bool realDataUntouched;

  factory DemoResetOut.fromJson(Json j) => DemoResetOut(
        incidentsRemoved: reqInt(j, 'incidents_removed'),
        smsRemoved: reqInt(j, 'sms_removed'),
        volunteersReset: reqInt(j, 'volunteers_reset'),
        realDataUntouched: reqBool(j, 'real_data_untouched'),
      );
}
