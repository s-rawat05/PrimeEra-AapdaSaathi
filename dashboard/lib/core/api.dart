import 'dart:typed_data';

import '../models/models.dart';

/// Typed client for the AapdaSaathi v1 API. Widgets depend only on this
/// interface so tests can inject a fake implementation.
abstract class AapdaApi {
  /// Bearer token attached to every request (null = signed out).
  String? get token;
  set token(String? value);

  /// Called when any request returns 401 (expired/revoked session).
  void Function()? onUnauthorized;

  // --------------------------------------------------------------- auth
  Future<TokenOut> login(String identifier, String password);
  Future<List<DemoPersona>> demoPersonas();
  Future<TokenOut> demoLogin(String userId);
  Future<MeOut> me();
  Future<String> realtimeTicket();
  Uri realtimeUri(String ticket);

  // --------------------------------------------------------------- incidents
  Future<PageOf<Incident>> listIncidents({String? status, bool? demo, int limit = 50, int offset = 0});
  Future<Incident> getIncident(String id);
  Future<Incident> createIncident({
    required String title,
    required String hazardType,
    required List<String> wardIds,
    required String severity,
    required String urgency,
    int? onsetInMinutes,
    String? headline,
    String? instruction,
    required bool isDemo,
  });
  Future<Incident> patchIncident(
    String id, {
    String? title,
    String? severity,
    int? onsetInMinutes,
    bool? requiresDispatchApproval,
    required String reason,
  });
  Future<Incident> closeIncident(String id, String note);
  Future<List<PriorityItem>> priority(String incidentId);
  Future<IncidentMap> incidentMap(String incidentId);
  Future<List<TimelineEvent>> incidentTimeline(String incidentId, {int limit = 200});
  Future<List<TaskOut>> incidentTasks(String incidentId);
  Future<IncidentReport> report(String incidentId);
  Future<String> reportCsv(String incidentId);

  // --------------------------------------------------------------- deliveries (case actions)
  Future<List<TimelineEvent>> deliveryTimeline(String deliveryId);
  Future<PriorityItem> resend(String deliveryId);
  Future<PriorityItem> overrideStatus(String deliveryId, {required String status, required String reason});
  Future<TaskOut?> dispatchNow(String deliveryId);
  Future<List<CandidateOut>> candidates(String deliveryId);
  Future<ExactLocationOut?> exactLocation(String deliveryId);

  // --------------------------------------------------------------- tasks
  Future<TaskOut> approveTask(String taskId);
  Future<TaskOut> rejectTask(String taskId, String reason);
  Future<TaskOut?> reassignTask(String taskId, {String? toVolunteerId, required String reason});

  // --------------------------------------------------------------- SACHET feed
  Future<FeedStatus> feedStatus();
  Future<List<FeedPollResult>> feedPoll();
  Future<PageOf<CapMessage>> feedMessages({bool includeFixtures = false, int limit = 50, int offset = 0});
  Future<String> feedMessageXml(String messageId);
  Future<Incident> replayMessage(String messageId, {required int onsetInMinutes, List<String>? wardIds});

  // --------------------------------------------------------------- demo
  Future<DemoStatus> demoStatus();
  Future<Incident> simulate(String fixture, {required int onsetInMinutes, List<String>? wardIds});
  Future<DemoResetOut> demoReset();
  Future<Map<String, dynamic>> demoSeed();
  Future<SmsResult> smsInbound(String fromPhone, String body);
  Future<List<OutboxItem>> smsOutbox({String? phone, int limit = 100});

  // --------------------------------------------------------------- audit
  Future<PageOf<AuditOut>> audit({String? entityType, String? entityId, String? action, int limit = 50, int offset = 0});

  // --------------------------------------------------------------- admin
  Future<List<WardOut>> wards({bool withGeometry = false});
  Future<GeoJsonUploadOut> uploadWardsGeojson(Uint8List bytes, String filename, {bool isDemo = false});
  Future<WardOut> setWardAccess(String wardId, String accessStatus, String? note);

  Future<List<ShelterOut>> shelters();
  Future<ShelterOut> createShelter({
    required String wardId,
    required String name,
    required String address,
    required double lat,
    required double lng,
    required String source,
  });
  Future<void> deleteShelter(String shelterId);

  Future<PageOf<ResidentOut>> residents({String? q, String? wardId, String? status, String? need, int limit = 50, int offset = 0});
  Future<ResidentOut> registerResident(Map<String, dynamic> body);
  Future<ResidentOut> reverifyResident(String residentId);
  Future<ResidentOut> withdrawResident(String residentId, String reason);
  Future<void> eraseResident(String residentId, String reason);

  Future<List<VolunteerOut>> volunteers();
  Future<VolunteerOut> createVolunteer(Map<String, dynamic> body);
  Future<VolunteerOut> setVolunteerAvailability(String volunteerId, bool isAvailable);
  Future<VolunteerOut> setVolunteerVerified(String volunteerId, bool verified);

  Future<List<NeighbourLinkOut>> neighbourLinks();
  Future<NeighbourLinkOut> createNeighbourLink({
    required String residentId,
    required String neighbourUserId,
    required int priority,
    double? distanceM,
  });
  Future<NeighbourLinkOut> setNeighbourLinkPriority(String linkId, int priority);
  Future<void> deleteNeighbourLink(String linkId);

  Future<List<PreAssignedOut>> preAssigned();
  Future<PreAssignedOut> createPreAssigned({required String residentId, required String volunteerId, required int priority});
  Future<void> deletePreAssigned(String id);

  Future<List<TemplateOut>> templates();
  Future<TemplateOut> upsertTemplate(Map<String, dynamic> body);

  Future<PageOf<UserAdminOut>> users({String? role, String? q, int limit = 50, int offset = 0});
  Future<UserAdminOut> createUser(Map<String, dynamic> body);
  Future<UserAdminOut> patchUser(String userId, {String? role, bool? isActive});
}
