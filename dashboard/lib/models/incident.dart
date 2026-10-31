import 'admin.dart';
import 'json.dart';

/// Delivery statuses, in the order the command centre shows them.
abstract final class DeliveryStatus {
  static const safe = 'SAFE';
  static const help = 'HELP';
  static const noReply = 'NO_REPLY';
  static const unreachable = 'UNREACHABLE';
  static const pending = 'PENDING';
  static const overridable = [safe, help, noReply, unreachable];
}

class WardMatchOut {
  const WardMatchOut({required this.wardId, required this.wardName, required this.matchMethod, required this.matchNote});

  final String wardId;
  final String wardName;
  final String matchMethod;
  final String? matchNote;

  factory WardMatchOut.fromJson(Json j) => WardMatchOut(
        wardId: reqString(j, 'ward_id'),
        wardName: reqString(j, 'ward_name'),
        matchMethod: reqString(j, 'match_method'),
        matchNote: optString(j, 'match_note'),
      );
}

class Counts {
  const Counts({
    this.safe = 0,
    this.help = 0,
    this.noReply = 0,
    this.unreachable = 0,
    this.pending = 0,
    this.total = 0,
  });

  final int safe;
  final int help;
  final int noReply;
  final int unreachable;
  final int pending;
  final int total;

  factory Counts.fromJson(Json j) => Counts(
        safe: intOr(j, 'SAFE', 0),
        help: intOr(j, 'HELP', 0),
        noReply: intOr(j, 'NO_REPLY', 0),
        unreachable: intOr(j, 'UNREACHABLE', 0),
        pending: intOr(j, 'PENDING', 0),
        total: intOr(j, 'total', 0),
      );
}

class Incident {
  const Incident({
    required this.id,
    required this.title,
    required this.hazardType,
    required this.source,
    required this.sourceLabel,
    required this.status,
    required this.isDemo,
    required this.severity,
    required this.urgency,
    required this.certainty,
    required this.sent,
    required this.effective,
    required this.onset,
    required this.expires,
    required this.onsetFallbackUsed,
    required this.onsetFallbackNote,
    required this.headline,
    required this.description,
    required this.instruction,
    required this.areaDesc,
    required this.officialUrl,
    required this.capIdentifier,
    required this.capSender,
    required this.escalationMode,
    required this.modeLabel,
    required this.requiresDispatchApproval,
    required this.createdAt,
    required this.closedAt,
    required this.closeNote,
    required this.wards,
    required this.counts,
    required this.pendingApprovals,
  });

  final String id;
  final String title;
  final String hazardType;
  final String source;
  final String sourceLabel;
  final String status;
  final bool isDemo;
  final String severity;
  final String urgency;
  final String certainty;
  final DateTime? sent;
  final DateTime? effective;
  final DateTime? onset;
  final DateTime? expires;
  final bool onsetFallbackUsed;
  final String? onsetFallbackNote;
  final String? headline;
  final String? description;
  final String? instruction;
  final String? areaDesc;
  final String? officialUrl;
  final String? capIdentifier;
  final String? capSender;
  final String escalationMode;
  final String modeLabel;
  final bool requiresDispatchApproval;
  final DateTime createdAt;
  final DateTime? closedAt;
  final String? closeNote;
  final List<WardMatchOut> wards;
  final Counts counts;
  final int pendingApprovals;

  bool get isActive => status == 'active';

  /// LIVE / REPLAY / SIMULATED / EXERCISE / MANUAL — short tag derived from the backend's `source`.
  String get sourceTag {
    switch (source) {
      case 'sachet':
      case 'live':
        return 'LIVE';
      case 'replay':
        return 'REPLAY';
      case 'simulated':
        return 'SIMULATED';
      case 'exercise':
        return 'EXERCISE';
      case 'manual':
        return 'MANUAL';
      default:
        return source.toUpperCase();
    }
  }

  factory Incident.fromJson(Json j) => Incident(
        id: reqString(j, 'id'),
        title: reqString(j, 'title'),
        hazardType: reqString(j, 'hazard_type'),
        source: reqString(j, 'source'),
        sourceLabel: reqString(j, 'source_label'),
        status: reqString(j, 'status'),
        isDemo: reqBool(j, 'is_demo'),
        severity: reqString(j, 'severity'),
        urgency: reqString(j, 'urgency'),
        certainty: reqString(j, 'certainty'),
        sent: optDate(j, 'sent'),
        effective: optDate(j, 'effective'),
        onset: optDate(j, 'onset'),
        expires: optDate(j, 'expires'),
        onsetFallbackUsed: reqBool(j, 'onset_fallback_used'),
        onsetFallbackNote: optString(j, 'onset_fallback_note'),
        headline: optString(j, 'headline'),
        description: optString(j, 'description'),
        instruction: optString(j, 'instruction'),
        areaDesc: optString(j, 'area_desc'),
        officialUrl: optString(j, 'official_url'),
        capIdentifier: optString(j, 'cap_identifier'),
        capSender: optString(j, 'cap_sender'),
        escalationMode: reqString(j, 'escalation_mode'),
        modeLabel: reqString(j, 'mode_label'),
        requiresDispatchApproval: reqBool(j, 'requires_dispatch_approval'),
        createdAt: reqDate(j, 'created_at'),
        closedAt: optDate(j, 'closed_at'),
        closeNote: optString(j, 'close_note'),
        wards: asJsonList(j['wards']).map(WardMatchOut.fromJson).toList(),
        counts: Counts.fromJson(asJson(j['counts'])),
        pendingApprovals: intOr(j, 'pending_approvals', 0),
      );
}

class TaskBrief {
  const TaskBrief({
    required this.id,
    required this.kind,
    required this.status,
    required this.assigneeName,
    required this.estWalkMinutes,
  });

  final String id;
  final String kind;
  final String status;
  final String? assigneeName;
  final double? estWalkMinutes;

  factory TaskBrief.fromJson(Json j) => TaskBrief(
        id: reqString(j, 'id'),
        kind: reqString(j, 'kind'),
        status: reqString(j, 'status'),
        assigneeName: optString(j, 'assignee_name'),
        estWalkMinutes: optDouble(j, 'est_walk_minutes'),
      );
}

class PriorityComponent {
  const PriorityComponent({required this.factor, required this.points});

  final String factor;
  final int points;

  factory PriorityComponent.fromJson(Json j) =>
      PriorityComponent(factor: reqString(j, 'factor'), points: reqInt(j, 'points'));
}

class PriorityItem {
  const PriorityItem({
    required this.deliveryId,
    required this.residentId,
    required this.residentName,
    required this.phoneMasked,
    required this.wardName,
    required this.needs,
    required this.livesAlone,
    required this.status,
    required this.priorityTotal,
    required this.priorityComponents,
    required this.alertedAt,
    required this.seenAt,
    required this.repliedAt,
    required this.replyChannel,
    required this.resolvedBy,
    required this.escalationLevel,
    required this.escalationStep,
    required this.nextActionAt,
    required this.needsOperator,
    required this.needsRescue,
    required this.rescueReason,
    required this.channels,
    required this.lat,
    required this.lng,
    required this.openTasks,
  });

  final String deliveryId;
  final String residentId;
  final String residentName;
  final String phoneMasked;
  final String wardName;
  final List<String> needs;
  final bool livesAlone;
  final String status;
  final int priorityTotal;
  final List<PriorityComponent> priorityComponents;
  final DateTime? alertedAt;
  final DateTime? seenAt;
  final DateTime? repliedAt;
  final String? replyChannel;
  final String? resolvedBy;
  final int escalationLevel;
  final String escalationStep;
  final DateTime? nextActionAt;
  final bool needsOperator;
  final bool needsRescue;
  final String? rescueReason;
  final List<String> channels;
  final double? lat;
  final double? lng;
  final List<TaskBrief> openTasks;

  factory PriorityItem.fromJson(Json j) => PriorityItem(
        deliveryId: reqString(j, 'delivery_id'),
        residentId: reqString(j, 'resident_id'),
        residentName: reqString(j, 'resident_name'),
        phoneMasked: reqString(j, 'phone_masked'),
        wardName: reqString(j, 'ward_name'),
        needs: stringList(j, 'needs'),
        livesAlone: reqBool(j, 'lives_alone'),
        status: reqString(j, 'status'),
        priorityTotal: reqInt(j, 'priority_total'),
        priorityComponents: asJsonList(j['priority_components']).map(PriorityComponent.fromJson).toList(),
        alertedAt: optDate(j, 'alerted_at'),
        seenAt: optDate(j, 'seen_at'),
        repliedAt: optDate(j, 'replied_at'),
        replyChannel: optString(j, 'reply_channel'),
        resolvedBy: optString(j, 'resolved_by'),
        escalationLevel: reqInt(j, 'escalation_level'),
        escalationStep: reqString(j, 'escalation_step'),
        nextActionAt: optDate(j, 'next_action_at'),
        needsOperator: reqBool(j, 'needs_operator'),
        needsRescue: reqBool(j, 'needs_rescue'),
        rescueReason: optString(j, 'rescue_reason'),
        channels: stringList(j, 'channels'),
        lat: optDouble(j, 'lat'),
        lng: optDouble(j, 'lng'),
        openTasks: asJsonList(j['open_tasks']).map(TaskBrief.fromJson).toList(),
      );
}

class TimelineEvent {
  const TimelineEvent({
    required this.id,
    required this.incidentId,
    required this.deliveryId,
    required this.residentId,
    required this.eventType,
    required this.message,
    required this.actorKind,
    required this.actorName,
    required this.createdAt,
  });

  final String id;
  final String incidentId;
  final String? deliveryId;
  final String? residentId;
  final String eventType;
  final String message;
  final String actorKind;
  final String? actorName;
  final DateTime createdAt;

  factory TimelineEvent.fromJson(Json j) => TimelineEvent(
        id: reqString(j, 'id'),
        incidentId: reqString(j, 'incident_id'),
        deliveryId: optString(j, 'delivery_id'),
        residentId: optString(j, 'resident_id'),
        eventType: reqString(j, 'event_type'),
        message: reqString(j, 'message'),
        actorKind: reqString(j, 'actor_kind'),
        actorName: optString(j, 'actor_name'),
        createdAt: reqDate(j, 'created_at'),
      );
}

class MapMarker {
  const MapMarker({
    required this.deliveryId,
    required this.residentFirstName,
    required this.status,
    required this.lat,
    required this.lng,
    required this.priority,
    required this.needs,
    required this.precision,
  });

  final String deliveryId;
  final String residentFirstName;
  final String status;
  final double lat;
  final double lng;
  final int priority;
  final List<String> needs;
  final String precision;

  factory MapMarker.fromJson(Json j) => MapMarker(
        deliveryId: reqString(j, 'delivery_id'),
        residentFirstName: reqString(j, 'resident_first_name'),
        status: reqString(j, 'status'),
        lat: reqDouble(j, 'lat'),
        lng: reqDouble(j, 'lng'),
        priority: reqInt(j, 'priority'),
        needs: stringList(j, 'needs'),
        precision: reqString(j, 'precision'),
      );
}

class MapVolunteer {
  const MapVolunteer({
    required this.volunteerId,
    required this.name,
    required this.lat,
    required this.lng,
    required this.isAvailable,
    required this.busy,
  });

  final String volunteerId;
  final String name;
  final double lat;
  final double lng;
  final bool isAvailable;
  final bool busy;

  factory MapVolunteer.fromJson(Json j) => MapVolunteer(
        volunteerId: reqString(j, 'volunteer_id'),
        name: reqString(j, 'name'),
        lat: reqDouble(j, 'lat'),
        lng: reqDouble(j, 'lng'),
        isAvailable: reqBool(j, 'is_available'),
        busy: reqBool(j, 'busy'),
      );
}

class IncidentMap {
  const IncidentMap({required this.wards, required this.markers, required this.volunteers, required this.shelters});

  final List<WardOut> wards;
  final List<MapMarker> markers;
  final List<MapVolunteer> volunteers;
  final List<ShelterOut> shelters;

  factory IncidentMap.fromJson(Json j) => IncidentMap(
        wards: asJsonList(j['wards']).map(WardOut.fromJson).toList(),
        markers: asJsonList(j['markers']).map(MapMarker.fromJson).toList(),
        volunteers: asJsonList(j['volunteers']).map(MapVolunteer.fromJson).toList(),
        shelters: asJsonList(j['shelters']).map(ShelterOut.fromJson).toList(),
      );
}

/// Task lifecycle: PENDING_APPROVAL → ASSIGNED → ACCEPTED → REACHED (plus CANT_GO, COMPLETED, CANCELLED, REJECTED).
abstract final class TaskStatus {
  static const pendingApproval = 'PENDING_APPROVAL';
  static const assigned = 'ASSIGNED';
  static const accepted = 'ACCEPTED';
  static const closed = {'REACHED', 'COMPLETED', 'CANT_GO', 'CANCELLED', 'REJECTED'};
}

class TaskOut {
  const TaskOut({
    required this.id,
    required this.incidentId,
    required this.incidentTitle,
    required this.hazardType,
    required this.isDemo,
    required this.deliveryId,
    required this.residentId,
    required this.residentFirstName,
    required this.residentNeeds,
    required this.kind,
    required this.status,
    required this.assigneeUserId,
    required this.assigneeName,
    required this.volunteerId,
    required this.reason,
    required this.outcome,
    required this.outcomeNote,
    required this.cantGoReason,
    required this.distanceM,
    required this.estWalkMinutes,
    required this.attemptNo,
    required this.createdAt,
    required this.approvedAt,
    required this.acceptedAt,
    required this.reachedAt,
    required this.closedAt,
  });

  final String id;
  final String incidentId;
  final String incidentTitle;
  final String hazardType;
  final bool isDemo;
  final String deliveryId;
  final String residentId;
  final String residentFirstName;
  final List<String> residentNeeds;
  final String kind;
  final String status;
  final String? assigneeUserId;
  final String? assigneeName;
  final String? volunteerId;
  final String reason;
  final String? outcome;
  final String? outcomeNote;
  final String? cantGoReason;
  final double? distanceM;
  final double? estWalkMinutes;
  final int attemptNo;
  final DateTime createdAt;
  final DateTime? approvedAt;
  final DateTime? acceptedAt;
  final DateTime? reachedAt;
  final DateTime? closedAt;

  bool get isVolunteerTask => kind == 'volunteer_assist';
  bool get isPendingApproval => status == TaskStatus.pendingApproval;
  bool get isOpen => !TaskStatus.closed.contains(status);
  bool get canReassign =>
      isVolunteerTask && (status == TaskStatus.assigned || status == TaskStatus.accepted || isPendingApproval);

  factory TaskOut.fromJson(Json j) => TaskOut(
        id: reqString(j, 'id'),
        incidentId: reqString(j, 'incident_id'),
        incidentTitle: reqString(j, 'incident_title'),
        hazardType: reqString(j, 'hazard_type'),
        isDemo: reqBool(j, 'is_demo'),
        deliveryId: reqString(j, 'delivery_id'),
        residentId: reqString(j, 'resident_id'),
        residentFirstName: reqString(j, 'resident_first_name'),
        residentNeeds: stringList(j, 'resident_needs'),
        kind: reqString(j, 'kind'),
        status: reqString(j, 'status'),
        assigneeUserId: optString(j, 'assignee_user_id'),
        assigneeName: optString(j, 'assignee_name'),
        volunteerId: optString(j, 'volunteer_id'),
        reason: reqString(j, 'reason'),
        outcome: optString(j, 'outcome'),
        outcomeNote: optString(j, 'outcome_note'),
        cantGoReason: optString(j, 'cant_go_reason'),
        distanceM: optDouble(j, 'distance_m'),
        estWalkMinutes: optDouble(j, 'est_walk_minutes'),
        attemptNo: reqInt(j, 'attempt_no'),
        createdAt: reqDate(j, 'created_at'),
        approvedAt: optDate(j, 'approved_at'),
        acceptedAt: optDate(j, 'accepted_at'),
        reachedAt: optDate(j, 'reached_at'),
        closedAt: optDate(j, 'closed_at'),
      );
}

class CandidateOut {
  const CandidateOut({
    required this.volunteerId,
    required this.name,
    required this.eligible,
    required this.distanceM,
    required this.walkMinutes,
    required this.reason,
  });

  final String volunteerId;
  final String name;
  final bool eligible;
  final double distanceM;
  final double walkMinutes;
  final String reason;

  factory CandidateOut.fromJson(Json j) => CandidateOut(
        volunteerId: reqString(j, 'volunteer_id'),
        name: reqString(j, 'name'),
        eligible: reqBool(j, 'eligible'),
        distanceM: reqDouble(j, 'distance_m'),
        walkMinutes: reqDouble(j, 'walk_minutes'),
        reason: reqString(j, 'reason'),
      );
}
