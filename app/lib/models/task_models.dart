import '../core/json.dart';
import 'alert_models.dart';
import 'user_models.dart';

abstract final class TaskStatus {
  static const pendingApproval = 'PENDING_APPROVAL';
  static const assigned = 'ASSIGNED';
  static const accepted = 'ACCEPTED';
  static const reached = 'REACHED';
  static const completed = 'COMPLETED';
  static const cantGo = 'CANT_GO';
  static const cancelled = 'CANCELLED';
  static const rejected = 'REJECTED';

  static const closed = {reached, completed, cantGo, cancelled, rejected};
}

const kCantGoReasons = ['route_blocked', 'too_far', 'unsafe', 'unavailable'];
const kReachedOutcomes = ['resident_safe', 'evacuated', 'needs_rescue', 'not_found'];
const kReachedNeedsNote = {'needs_rescue', 'not_found'};
const kNeighbourOutcomes = ['SAFE', 'HELP', 'CANNOT_REACH'];

class TaskOut {
  TaskOut({
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

  factory TaskOut.fromJson(Json j) => TaskOut(
        id: reqStr(j, 'id'),
        incidentId: reqStr(j, 'incident_id'),
        incidentTitle: optStr(j, 'incident_title') ?? '',
        hazardType: optStr(j, 'hazard_type') ?? '',
        isDemo: reqBool(j, 'is_demo'),
        deliveryId: reqStr(j, 'delivery_id'),
        residentId: reqStr(j, 'resident_id'),
        residentFirstName: optStr(j, 'resident_first_name') ?? '',
        residentNeeds: strList(j, 'resident_needs'),
        kind: optStr(j, 'kind') ?? '',
        status: reqStr(j, 'status'),
        assigneeUserId: optStr(j, 'assignee_user_id'),
        assigneeName: optStr(j, 'assignee_name'),
        volunteerId: optStr(j, 'volunteer_id'),
        reason: optStr(j, 'reason') ?? '',
        outcome: optStr(j, 'outcome'),
        outcomeNote: optStr(j, 'outcome_note'),
        cantGoReason: optStr(j, 'cant_go_reason'),
        distanceM: optDouble(j, 'distance_m'),
        estWalkMinutes: optDouble(j, 'est_walk_minutes'),
        attemptNo: optInt(j, 'attempt_no', fallback: 1),
        createdAt: optDate(j, 'created_at'),
        approvedAt: optDate(j, 'approved_at'),
        acceptedAt: optDate(j, 'accepted_at'),
        reachedAt: optDate(j, 'reached_at'),
        closedAt: optDate(j, 'closed_at'),
      );

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
  final DateTime? createdAt;
  final DateTime? approvedAt;
  final DateTime? acceptedAt;
  final DateTime? reachedAt;
  final DateTime? closedAt;

  bool get isOpen => !TaskStatus.closed.contains(status);
  bool get isAssigned => status == TaskStatus.assigned;
  bool get isAccepted => status == TaskStatus.accepted;
}

class TaskDetailOut extends TaskOut {
  TaskDetailOut._(
    TaskOut b, {
    required this.residentFullName,
    required this.residentPhone,
    required this.exactLocation,
    required this.locationNote,
    required this.officialInstruction,
    required this.shelters,
    required this.walkEstimateNote,
  }) : super(
          id: b.id,
          incidentId: b.incidentId,
          incidentTitle: b.incidentTitle,
          hazardType: b.hazardType,
          isDemo: b.isDemo,
          deliveryId: b.deliveryId,
          residentId: b.residentId,
          residentFirstName: b.residentFirstName,
          residentNeeds: b.residentNeeds,
          kind: b.kind,
          status: b.status,
          assigneeUserId: b.assigneeUserId,
          assigneeName: b.assigneeName,
          volunteerId: b.volunteerId,
          reason: b.reason,
          outcome: b.outcome,
          outcomeNote: b.outcomeNote,
          cantGoReason: b.cantGoReason,
          distanceM: b.distanceM,
          estWalkMinutes: b.estWalkMinutes,
          attemptNo: b.attemptNo,
          createdAt: b.createdAt,
          approvedAt: b.approvedAt,
          acceptedAt: b.acceptedAt,
          reachedAt: b.reachedAt,
          closedAt: b.closedAt,
        );

  factory TaskDetailOut.fromJson(Json j) {
    final loc = optObj(j, 'exact_location');
    return TaskDetailOut._(
      TaskOut.fromJson(j),
      residentFullName: optStr(j, 'resident_full_name'),
      residentPhone: optStr(j, 'resident_phone'),
      exactLocation: loc == null ? null : ExactLocationOut.fromJson(loc),
      locationNote: optStr(j, 'location_note') ?? '',
      officialInstruction: optStr(j, 'official_instruction'),
      shelters: objList(j, 'shelters', ShelterOut.fromJson),
      walkEstimateNote: optStr(j, 'walk_estimate_note') ?? '',
    );
  }

  final String? residentFullName;
  final String? residentPhone;
  final ExactLocationOut? exactLocation;
  final String locationNote;
  final String? officialInstruction;
  final List<ShelterOut> shelters;
  final String walkEstimateNote;
}
