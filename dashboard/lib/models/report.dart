import 'incident.dart';
import 'json.dart';

class DurationStats {
  const DurationStats({required this.count, required this.medianSeconds, required this.p90Seconds, required this.maxSeconds});

  final int count;
  final double? medianSeconds;
  final double? p90Seconds;
  final double? maxSeconds;

  factory DurationStats.fromJson(Object? v) {
    final j = v == null ? <String, dynamic>{} : asJson(v);
    return DurationStats(
      count: intOr(j, 'count', 0),
      medianSeconds: optDouble(j, 'median_seconds'),
      p90Seconds: optDouble(j, 'p90_seconds'),
      maxSeconds: optDouble(j, 'max_seconds'),
    );
  }
}

class UnresolvedCase {
  const UnresolvedCase({
    required this.deliveryId,
    required this.residentName,
    required this.status,
    required this.needs,
    required this.priority,
    required this.needsRescue,
    required this.rescueReason,
    required this.escalationStep,
  });

  final String deliveryId;
  final String residentName;
  final String status;
  final List<String> needs;
  final int? priority;
  final bool needsRescue;
  final String? rescueReason;
  final String? escalationStep;

  factory UnresolvedCase.fromJson(Json j) => UnresolvedCase(
        deliveryId: reqString(j, 'delivery_id'),
        residentName: reqString(j, 'resident_name'),
        status: reqString(j, 'status'),
        needs: stringList(j, 'needs'),
        priority: optInt(j, 'priority'),
        needsRescue: boolOr(j, 'needs_rescue', false),
        rescueReason: optString(j, 'rescue_reason'),
        escalationStep: optString(j, 'escalation_step'),
      );
}

class ReportTaskItem {
  const ReportTaskItem({
    required this.id,
    required this.kind,
    required this.status,
    required this.assignee,
    required this.outcome,
    required this.cantGoReason,
    required this.attemptNo,
  });

  final String id;
  final String kind;
  final String status;
  final String? assignee;
  final String? outcome;
  final String? cantGoReason;
  final int attemptNo;

  factory ReportTaskItem.fromJson(Json j) => ReportTaskItem(
        id: reqString(j, 'id'),
        kind: reqString(j, 'kind'),
        status: reqString(j, 'status'),
        assignee: optString(j, 'assignee'),
        outcome: optString(j, 'outcome'),
        cantGoReason: optString(j, 'cant_go_reason'),
        attemptNo: intOr(j, 'attempt_no', 1),
      );
}

class ReportTasks {
  const ReportTasks({
    required this.total,
    required this.byKindStatus,
    required this.outcomes,
    required this.cantGoReasons,
    required this.timeToAccept,
    required this.timeToReach,
    required this.items,
  });

  final int total;
  final Map<String, int> byKindStatus;
  final Map<String, int> outcomes;
  final Map<String, int> cantGoReasons;
  final DurationStats timeToAccept;
  final DurationStats timeToReach;
  final List<ReportTaskItem> items;

  factory ReportTasks.fromJson(Json j) => ReportTasks(
        total: intOr(j, 'total', 0),
        byKindStatus: intMap(j['by_kind_status']),
        outcomes: intMap(j['outcomes']),
        cantGoReasons: intMap(j['cant_go_reasons']),
        timeToAccept: DurationStats.fromJson(j['time_to_accept']),
        timeToReach: DurationStats.fromJson(j['time_to_reach']),
        items: asJsonList(j['items']).map(ReportTaskItem.fromJson).toList(),
      );
}

class IncidentReport {
  const IncidentReport({
    required this.generatedAt,
    required this.incident,
    required this.counts,
    required this.safeRate,
    required this.alertToSafe,
    required this.alertToSafeByChannel,
    required this.unresolved,
    required this.tasks,
    required this.notificationsByChannelStatus,
    required this.blockedBySafetySwitch,
    required this.notes,
  });

  final DateTime generatedAt;
  final Incident incident;
  final Counts counts;
  final double? safeRate;
  final DurationStats alertToSafe;
  final Map<String, DurationStats> alertToSafeByChannel;
  final List<UnresolvedCase> unresolved;
  final ReportTasks tasks;
  final Map<String, int> notificationsByChannelStatus;
  final int blockedBySafetySwitch;
  final List<String> notes;

  factory IncidentReport.fromJson(Json j) {
    final byChannel = j['alert_to_safe_by_channel'];
    final notifications = j['notifications'] == null ? <String, dynamic>{} : asJson(j['notifications']);
    return IncidentReport(
      generatedAt: reqDate(j, 'generated_at'),
      incident: Incident.fromJson(asJson(j['incident'])),
      counts: Counts.fromJson(asJson(j['counts'])),
      safeRate: optDouble(j, 'safe_rate'),
      alertToSafe: DurationStats.fromJson(j['alert_to_safe']),
      alertToSafeByChannel: byChannel is Map
          ? {for (final e in byChannel.entries) e.key.toString(): DurationStats.fromJson(e.value)}
          : const {},
      unresolved: asJsonList(j['unresolved']).map(UnresolvedCase.fromJson).toList(),
      tasks: ReportTasks.fromJson(asJson(j['tasks'])),
      notificationsByChannelStatus: intMap(notifications['by_channel_status']),
      blockedBySafetySwitch: intOr(notifications, 'blocked_by_safety_switch', 0),
      notes: stringList(j, 'notes'),
    );
  }
}
