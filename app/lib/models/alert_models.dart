import '../core/json.dart';
import 'user_models.dart';

class ShelterOut {
  ShelterOut({
    required this.id,
    required this.wardId,
    required this.name,
    required this.address,
    required this.lat,
    required this.lng,
    required this.source,
    required this.isDemo,
    required this.distanceM,
    required this.estWalkMinutes,
  });

  factory ShelterOut.fromJson(Json j) => ShelterOut(
        id: reqStr(j, 'id'),
        wardId: optStr(j, 'ward_id') ?? '',
        name: reqStr(j, 'name'),
        address: optStr(j, 'address') ?? '',
        lat: reqDouble(j, 'lat'),
        lng: reqDouble(j, 'lng'),
        source: optStr(j, 'source') ?? '',
        isDemo: reqBool(j, 'is_demo'),
        distanceM: optDouble(j, 'distance_m'),
        estWalkMinutes: optDouble(j, 'est_walk_minutes'),
      );

  final String id;
  final String wardId;
  final String name;
  final String address;
  final double lat;
  final double lng;
  /// The official order/notification designating this relief post.
  final String source;
  final bool isDemo;
  final double? distanceM;
  final double? estWalkMinutes;
}

/// AapdaSaathi's framing of an official alert. Always shown with [label] — never as official text.
class Presentation {
  Presentation({
    required this.label,
    required this.title,
    required this.body,
    required this.style,
    required this.pictogram,
    required this.easyReadSteps,
  });

  factory Presentation.fromJson(Json j) => Presentation(
        label: optStr(j, 'label') ?? '',
        title: optStr(j, 'title') ?? '',
        body: optStr(j, 'body') ?? '',
        style: optStr(j, 'style') ?? 'standard',
        pictogram: optStr(j, 'pictogram') ?? 'warning',
        easyReadSteps: strList(j, 'easy_read_steps'),
      );

  final String label;
  final String title;
  final String body;
  final String style;
  final String pictogram;
  final List<String> easyReadSteps;
}

/// The CAP text exactly as issued by the authority.
class OfficialAlert {
  OfficialAlert({
    required this.sender,
    required this.event,
    required this.headline,
    required this.description,
    required this.instruction,
    required this.severity,
    required this.urgency,
    required this.certainty,
    required this.onset,
    required this.expires,
    required this.areaDesc,
    required this.officialUrl,
    required this.source,
    required this.sourceLabel,
    required this.onsetNote,
  });

  factory OfficialAlert.fromJson(Json j) => OfficialAlert(
        sender: optStr(j, 'sender'),
        event: optStr(j, 'event') ?? '',
        headline: optStr(j, 'headline'),
        description: optStr(j, 'description'),
        instruction: optStr(j, 'instruction'),
        severity: optStr(j, 'severity') ?? 'Unknown',
        urgency: optStr(j, 'urgency') ?? 'Unknown',
        certainty: optStr(j, 'certainty') ?? 'Unknown',
        onset: optDate(j, 'onset'),
        expires: optDate(j, 'expires'),
        areaDesc: optStr(j, 'area_desc'),
        officialUrl: optStr(j, 'official_url'),
        source: optStr(j, 'source') ?? '',
        sourceLabel: optStr(j, 'source_label') ?? '',
        onsetNote: optStr(j, 'onset_note'),
      );

  final String? sender;
  final String event;
  final String? headline;
  final String? description;
  final String? instruction;
  final String severity;
  final String urgency;
  final String certainty;
  final DateTime? onset;
  final DateTime? expires;
  final String? areaDesc;
  final String? officialUrl;
  final String source;
  final String sourceLabel;
  final String? onsetNote;
}

class AssistanceStatus {
  AssistanceStatus({
    required this.summary,
    required this.neighbourAsked,
    required this.volunteerStatus,
    required this.volunteerEtaMinutes,
  });

  factory AssistanceStatus.fromJson(Json j) => AssistanceStatus(
        summary: optStr(j, 'summary') ?? '',
        neighbourAsked: reqBool(j, 'neighbour_asked'),
        volunteerStatus: optStr(j, 'volunteer_status'),
        volunteerEtaMinutes: optDouble(j, 'volunteer_eta_minutes'),
      );

  final String summary;
  final bool neighbourAsked;
  final String? volunteerStatus;
  final double? volunteerEtaMinutes;
}

/// Delivery statuses.
abstract final class DeliveryStatus {
  static const pending = 'PENDING';
  static const noReply = 'NO_REPLY';
  static const safe = 'SAFE';
  static const help = 'HELP';
  static const unreachable = 'UNREACHABLE';
}

class AlertOut {
  AlertOut({
    required this.deliveryId,
    required this.incidentId,
    required this.incidentStatus,
    required this.isDemo,
    required this.status,
    required this.alertedAt,
    required this.repliedAt,
    required this.replyChannel,
    required this.accessibilityModes,
    required this.presentation,
    required this.official,
    required this.shelters,
    required this.assistance,
    required this.smsReplyHint,
    required this.raw,
  });

  factory AlertOut.fromJson(Json j) => AlertOut(
        deliveryId: reqStr(j, 'delivery_id'),
        incidentId: reqStr(j, 'incident_id'),
        incidentStatus: optStr(j, 'incident_status') ?? '',
        isDemo: reqBool(j, 'is_demo'),
        status: reqStr(j, 'status'),
        alertedAt: optDate(j, 'alerted_at'),
        repliedAt: optDate(j, 'replied_at'),
        replyChannel: optStr(j, 'reply_channel'),
        accessibilityModes: strList(j, 'accessibility_modes'),
        presentation: Presentation.fromJson(optObj(j, 'presentation') ?? const {}),
        official: OfficialAlert.fromJson(optObj(j, 'official') ?? const {}),
        shelters: objList(j, 'shelters', ShelterOut.fromJson),
        assistance: AssistanceStatus.fromJson(optObj(j, 'assistance') ?? const {}),
        smsReplyHint: optStr(j, 'sms_reply_hint') ?? '',
        raw: j,
      );

  final String deliveryId;
  final String incidentId;
  final String incidentStatus;
  final bool isDemo;
  final String status;
  final DateTime? alertedAt;
  final DateTime? repliedAt;
  final String? replyChannel;
  final List<String> accessibilityModes;
  final Presentation presentation;
  final OfficialAlert official;
  final List<ShelterOut> shelters;
  final AssistanceStatus assistance;
  final String smsReplyHint;

  /// Original JSON, used for the offline cache.
  final Json raw;

  bool get awaitingReply => status == DeliveryStatus.noReply || status == DeliveryStatus.pending;
  bool get isSafe => status == DeliveryStatus.safe;
  bool get isHelp => status == DeliveryStatus.help;
  bool get isActiveIncident => incidentStatus == 'active';
  ShelterOut? get nearestShelter => shelters.isEmpty ? null : shelters.first;
}

class RespondOut {
  RespondOut({required this.deliveryId, required this.status, required this.changed, required this.serverTime});

  factory RespondOut.fromJson(Json j) => RespondOut(
        deliveryId: reqStr(j, 'delivery_id'),
        status: reqStr(j, 'status'),
        changed: reqBool(j, 'changed'),
        serverTime: optDate(j, 'server_time'),
      );

  final String deliveryId;
  final String status;
  final bool changed;
  final DateTime? serverTime;
}

class PageOut<T> {
  PageOut({required this.items, required this.total, required this.limit, required this.offset});

  factory PageOut.fromJson(Json j, T Function(Json) f) => PageOut(
        items: objList(j, 'items', f),
        total: optInt(j, 'total'),
        limit: optInt(j, 'limit'),
        offset: optInt(j, 'offset'),
      );

  final List<T> items;
  final int total;
  final int limit;
  final int offset;
}

/// A row of the operator priority list, as shown to a linked caregiver.
class PriorityItem {
  PriorityItem({
    required this.deliveryId,
    required this.residentId,
    required this.residentName,
    required this.status,
    required this.alertedAt,
    required this.repliedAt,
    required this.replyChannel,
    required this.resolvedBy,
    required this.escalationStep,
    required this.needsRescue,
  });

  factory PriorityItem.fromJson(Json j) => PriorityItem(
        deliveryId: reqStr(j, 'delivery_id'),
        residentId: reqStr(j, 'resident_id'),
        residentName: optStr(j, 'resident_name') ?? '',
        status: reqStr(j, 'status'),
        alertedAt: optDate(j, 'alerted_at'),
        repliedAt: optDate(j, 'replied_at'),
        replyChannel: optStr(j, 'reply_channel'),
        resolvedBy: optStr(j, 'resolved_by'),
        escalationStep: optStr(j, 'escalation_step') ?? '',
        needsRescue: reqBool(j, 'needs_rescue'),
      );

  final String deliveryId;
  final String residentId;
  final String residentName;
  final String status;
  final DateTime? alertedAt;
  final DateTime? repliedAt;
  final String? replyChannel;
  final String? resolvedBy;
  final String escalationStep;
  final bool needsRescue;
}

class CaregiverResidentOut {
  CaregiverResidentOut({required this.resident, required this.activeAlerts, required this.exactLocation});

  factory CaregiverResidentOut.fromJson(Json j) {
    final loc = optObj(j, 'exact_location');
    return CaregiverResidentOut(
      resident: ResidentOut.fromJson(optObj(j, 'resident') ?? (throw const FormatException('Missing "resident"'))),
      activeAlerts: objList(j, 'active_alerts', PriorityItem.fromJson),
      exactLocation: loc == null ? null : ExactLocationOut.fromJson(loc),
    );
  }

  final ResidentOut resident;
  final List<PriorityItem> activeAlerts;
  final ExactLocationOut? exactLocation;
}
