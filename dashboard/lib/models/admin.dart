import 'auth.dart';
import 'json.dart';

class WardOut {
  const WardOut({
    required this.id,
    required this.code,
    required this.name,
    required this.district,
    required this.state,
    required this.lgdDistrictCode,
    required this.centroidLat,
    required this.centroidLng,
    required this.accessStatus,
    required this.accessNote,
    required this.isDemo,
    required this.boundaryGeojson,
  });

  final String id;
  final String code;
  final String name;
  final String district;
  final String state;
  final String? lgdDistrictCode;
  final double centroidLat;
  final double centroidLng;
  final String accessStatus;
  final String? accessNote;
  final bool isDemo;
  final Json? boundaryGeojson;

  factory WardOut.fromJson(Json j) => WardOut(
        id: reqString(j, 'id'),
        code: reqString(j, 'code'),
        name: reqString(j, 'name'),
        district: reqString(j, 'district'),
        state: reqString(j, 'state'),
        lgdDistrictCode: optString(j, 'lgd_district_code'),
        centroidLat: reqDouble(j, 'centroid_lat'),
        centroidLng: reqDouble(j, 'centroid_lng'),
        accessStatus: reqString(j, 'access_status'),
        accessNote: optString(j, 'access_note'),
        isDemo: reqBool(j, 'is_demo'),
        boundaryGeojson: optJson(j, 'boundary_geojson'),
      );
}

class GeoJsonUploadOut {
  const GeoJsonUploadOut({required this.created, required this.updated, required this.errors});

  final int created;
  final int updated;
  final List<String> errors;

  factory GeoJsonUploadOut.fromJson(Json j) =>
      GeoJsonUploadOut(created: reqInt(j, 'created'), updated: reqInt(j, 'updated'), errors: stringList(j, 'errors'));
}

class ShelterOut {
  const ShelterOut({
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

  final String id;
  final String wardId;
  final String name;
  final String address;
  final double lat;
  final double lng;
  final String source;
  final bool isDemo;
  final double? distanceM;
  final double? estWalkMinutes;

  factory ShelterOut.fromJson(Json j) => ShelterOut(
        id: reqString(j, 'id'),
        wardId: reqString(j, 'ward_id'),
        name: reqString(j, 'name'),
        address: reqString(j, 'address'),
        lat: reqDouble(j, 'lat'),
        lng: reqDouble(j, 'lng'),
        source: reqString(j, 'source'),
        isDemo: reqBool(j, 'is_demo'),
        distanceM: optDouble(j, 'distance_m'),
        estWalkMinutes: optDouble(j, 'est_walk_minutes'),
      );
}

class ConsentOut {
  const ConsentOut({
    required this.id,
    required this.consentType,
    required this.granted,
    required this.grantedBy,
    required this.guardianName,
    required this.grantedAt,
    required this.expiresAt,
    required this.withdrawnAt,
  });

  final String id;
  final String consentType;
  final bool granted;
  final String grantedBy;
  final String? guardianName;
  final DateTime grantedAt;
  final DateTime expiresAt;
  final DateTime? withdrawnAt;

  bool isExpired(DateTime now) => expiresAt.isBefore(now);
  bool get isWithdrawn => withdrawnAt != null;

  factory ConsentOut.fromJson(Json j) => ConsentOut(
        id: reqString(j, 'id'),
        consentType: reqString(j, 'consent_type'),
        granted: reqBool(j, 'granted'),
        grantedBy: reqString(j, 'granted_by'),
        guardianName: optString(j, 'guardian_name'),
        grantedAt: reqDate(j, 'granted_at'),
        expiresAt: reqDate(j, 'expires_at'),
        withdrawnAt: optDate(j, 'withdrawn_at'),
      );
}

class ResidentOut {
  const ResidentOut({
    required this.id,
    required this.userId,
    required this.fullName,
    required this.phoneMasked,
    required this.wardId,
    required this.wardName,
    required this.language,
    required this.needs,
    required this.livesAlone,
    required this.hasSmartphone,
    required this.registrationStatus,
    required this.registeredVia,
    required this.reverifyDueAt,
    required this.isDemo,
    required this.consents,
    required this.hasExactLocation,
  });

  final String id;
  final String? userId;
  final String fullName;
  final String phoneMasked;
  final String wardId;
  final String wardName;
  final String language;
  final List<String> needs;
  final bool livesAlone;
  final bool hasSmartphone;
  final String registrationStatus;
  final String registeredVia;
  final DateTime? reverifyDueAt;
  final bool isDemo;
  final List<ConsentOut> consents;
  final bool hasExactLocation;

  factory ResidentOut.fromJson(Json j) => ResidentOut(
        id: reqString(j, 'id'),
        userId: optString(j, 'user_id'),
        fullName: reqString(j, 'full_name'),
        phoneMasked: reqString(j, 'phone_masked'),
        wardId: reqString(j, 'ward_id'),
        wardName: reqString(j, 'ward_name'),
        language: reqString(j, 'language'),
        needs: stringList(j, 'needs'),
        livesAlone: reqBool(j, 'lives_alone'),
        hasSmartphone: reqBool(j, 'has_smartphone'),
        registrationStatus: reqString(j, 'registration_status'),
        registeredVia: reqString(j, 'registered_via'),
        reverifyDueAt: optDate(j, 'reverify_due_at'),
        isDemo: reqBool(j, 'is_demo'),
        consents: asJsonList(j['consents']).map(ConsentOut.fromJson).toList(),
        hasExactLocation: boolOr(j, 'has_exact_location', false),
      );
}

class VolunteerOut {
  const VolunteerOut({
    required this.id,
    required this.userId,
    required this.fullName,
    required this.phoneMasked,
    required this.wardId,
    required this.wardName,
    required this.isAvailable,
    required this.baseLat,
    required this.baseLng,
    required this.maxRadiusM,
    required this.skills,
    required this.verified,
    required this.isDemo,
    required this.activeTaskId,
  });

  final String id;
  final String userId;
  final String fullName;
  final String phoneMasked;
  final String? wardId;
  final String? wardName;
  final bool isAvailable;
  final double baseLat;
  final double baseLng;
  final double maxRadiusM;
  final List<String> skills;
  final bool verified;
  final bool isDemo;
  final String? activeTaskId;

  factory VolunteerOut.fromJson(Json j) => VolunteerOut(
        id: reqString(j, 'id'),
        userId: reqString(j, 'user_id'),
        fullName: reqString(j, 'full_name'),
        phoneMasked: reqString(j, 'phone_masked'),
        wardId: optString(j, 'ward_id'),
        wardName: optString(j, 'ward_name'),
        isAvailable: reqBool(j, 'is_available'),
        baseLat: reqDouble(j, 'base_lat'),
        baseLng: reqDouble(j, 'base_lng'),
        maxRadiusM: reqDouble(j, 'max_radius_m'),
        skills: stringList(j, 'skills'),
        verified: reqBool(j, 'verified'),
        isDemo: reqBool(j, 'is_demo'),
        activeTaskId: optString(j, 'active_task_id'),
      );
}

class NeighbourLinkOut {
  const NeighbourLinkOut({
    required this.id,
    required this.residentId,
    required this.residentName,
    required this.neighbourUserId,
    required this.neighbourName,
    required this.priority,
    required this.distanceM,
  });

  final String id;
  final String residentId;
  final String residentName;
  final String neighbourUserId;
  final String neighbourName;
  final int priority;
  final double? distanceM;

  factory NeighbourLinkOut.fromJson(Json j) => NeighbourLinkOut(
        id: reqString(j, 'id'),
        residentId: reqString(j, 'resident_id'),
        residentName: reqString(j, 'resident_name'),
        neighbourUserId: reqString(j, 'neighbour_user_id'),
        neighbourName: reqString(j, 'neighbour_name'),
        priority: reqInt(j, 'priority'),
        distanceM: optDouble(j, 'distance_m'),
      );
}

class PreAssignedOut {
  const PreAssignedOut({
    required this.id,
    required this.residentId,
    required this.residentName,
    required this.volunteerId,
    required this.volunteerName,
    required this.priority,
  });

  final String id;
  final String residentId;
  final String residentName;
  final String volunteerId;
  final String volunteerName;
  final int priority;

  factory PreAssignedOut.fromJson(Json j) => PreAssignedOut(
        id: reqString(j, 'id'),
        residentId: reqString(j, 'resident_id'),
        residentName: reqString(j, 'resident_name'),
        volunteerId: reqString(j, 'volunteer_id'),
        volunteerName: reqString(j, 'volunteer_name'),
        priority: reqInt(j, 'priority'),
      );
}

class TemplateOut {
  const TemplateOut({
    required this.id,
    required this.hazardType,
    required this.language,
    required this.style,
    required this.title,
    required this.body,
    required this.pictogram,
    required this.audioAssetUrl,
    required this.isActive,
  });

  final String id;
  final String hazardType;
  final String language;
  final String style;
  final String title;
  final String body;
  final String? pictogram;
  final String? audioAssetUrl;
  final bool isActive;

  factory TemplateOut.fromJson(Json j) => TemplateOut(
        id: reqString(j, 'id'),
        hazardType: reqString(j, 'hazard_type'),
        language: reqString(j, 'language'),
        style: reqString(j, 'style'),
        title: reqString(j, 'title'),
        body: reqString(j, 'body'),
        pictogram: optString(j, 'pictogram'),
        audioAssetUrl: optString(j, 'audio_asset_url'),
        isActive: reqBool(j, 'is_active'),
      );
}

class UserAdminOut {
  const UserAdminOut({required this.user, required this.isActive, required this.createdAt});

  final UserOut user;
  final bool isActive;
  final DateTime createdAt;

  factory UserAdminOut.fromJson(Json j) => UserAdminOut(
        user: UserOut.fromJson(j),
        isActive: reqBool(j, 'is_active'),
        createdAt: reqDate(j, 'created_at'),
      );
}

class ExactLocationOut {
  const ExactLocationOut({
    required this.lat,
    required this.lng,
    required this.addressText,
    required this.landmark,
    required this.source,
  });

  final double lat;
  final double lng;
  final String? addressText;
  final String? landmark;
  final String source;

  factory ExactLocationOut.fromJson(Json j) => ExactLocationOut(
        lat: reqDouble(j, 'lat'),
        lng: reqDouble(j, 'lng'),
        addressText: optString(j, 'address_text'),
        landmark: optString(j, 'landmark'),
        source: reqString(j, 'source'),
      );
}

class AuditOut {
  const AuditOut({
    required this.id,
    required this.actorUserId,
    required this.actorName,
    required this.actorRole,
    required this.action,
    required this.entityType,
    required this.entityId,
    required this.reason,
    required this.before,
    required this.after,
    required this.createdAt,
  });

  final String id;
  final String? actorUserId;
  final String? actorName;
  final String? actorRole;
  final String action;
  final String entityType;
  final String? entityId;
  final String? reason;
  final Json? before;
  final Json? after;
  final DateTime createdAt;

  factory AuditOut.fromJson(Json j) => AuditOut(
        id: reqString(j, 'id'),
        actorUserId: optString(j, 'actor_user_id'),
        actorName: optString(j, 'actor_name'),
        actorRole: optString(j, 'actor_role'),
        action: reqString(j, 'action'),
        entityType: reqString(j, 'entity_type'),
        entityId: optString(j, 'entity_id'),
        reason: optString(j, 'reason'),
        before: optJson(j, 'before'),
        after: optJson(j, 'after'),
        createdAt: reqDate(j, 'created_at'),
      );
}
