import '../core/api_client.dart';
import '../models/models.dart';

/// Caregiver, neighbour and volunteer data. These actions are NOT queued offline: a responder must
/// know immediately whether the control room received their answer.
class ResponderRepository {
  ResponderRepository(this._api);

  final AapdaApi _api;

  Future<List<CaregiverResidentOut>> caregiverResidents() => _api.caregiverResidents();

  Future<RespondOut> caregiverRespond(String deliveryId, String status, {String? note}) =>
      _api.caregiverRespond(deliveryId, status, note: note);

  Future<List<TaskOut>> neighbourChecks({bool includeClosed = true}) =>
      _api.neighbourChecks(includeClosed: includeClosed);

  Future<TaskOut> neighbourRespond(String taskId, String outcome, {String? note}) =>
      _api.neighbourRespond(taskId, outcome, note: note);

  Future<VolunteerOut> volunteerMe() => _api.volunteerMe();

  Future<VolunteerOut> setAvailability(bool v) => _api.setAvailability(v);

  Future<List<TaskOut>> volunteerTasks({bool includeClosed = true}) =>
      _api.volunteerTasks(includeClosed: includeClosed);

  Future<TaskDetailOut> taskDetail(String id) => _api.taskDetail(id);

  Future<TaskOut> accept(String id) => _api.acceptTask(id);

  Future<TaskOut> cantGo(String id, String reason, {String? note}) => _api.cantGo(id, reason, note: note);

  Future<TaskOut> reached(String id, String outcome, {String? note}) => _api.reached(id, outcome, note: note);
}
