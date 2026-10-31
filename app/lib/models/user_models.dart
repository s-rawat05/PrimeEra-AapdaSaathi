import '../core/json.dart';

/// Roles as defined by the backend (`schemas.Role`).
enum UserRole {
  resident,
  caregiver,
  neighbour,
  volunteer,
  admin,
  operator,
  unknown;

  static UserRole parse(String? s) =>
      UserRole.values.firstWhere((r) => r.name == s, orElse: () => UserRole.unknown);

  bool get isOps => this == UserRole.admin || this == UserRole.operator;
}

class UserOut {
  UserOut({
    required this.id,
    required this.fullName,
    required this.role,
    required this.roleRaw,
    required this.phoneMasked,
    required this.email,
    required this.language,
    required this.isDemo,
  });

  factory UserOut.fromJson(Json j) => UserOut(
        id: reqStr(j, 'id'),
        fullName: reqStr(j, 'full_name'),
        role: UserRole.parse(optStr(j, 'role')),
        roleRaw: optStr(j, 'role') ?? '',
        phoneMasked: optStr(j, 'phone_masked') ?? '',
        email: optStr(j, 'email'),
        language: optStr(j, 'language') ?? 'en',
        isDemo: reqBool(j, 'is_demo'),
      );

  final String id;
  final String fullName;
  final UserRole role;
  final String roleRaw;
  final String phoneMasked;
  final String? email;
  final String language;
  final bool isDemo;

  String get firstName => fullName.split(' ').first;
}

class ConsentOut {
  ConsentOut({
    required this.id,
    required this.consentType,
    required this.granted,
    required this.grantedBy,
    required this.guardianName,
    required this.grantedAt,
    required this.expiresAt,
    required this.withdrawnAt,
  });

  factory ConsentOut.fromJson(Json j) => ConsentOut(
        id: reqStr(j, 'id'),
        consentType: reqStr(j, 'consent_type'),
        granted: reqBool(j, 'granted'),
        grantedBy: optStr(j, 'granted_by') ?? 'self',
        guardianName: optStr(j, 'guardian_name'),
        grantedAt: optDate(j, 'granted_at'),
        expiresAt: optDate(j, 'expires_at'),
        withdrawnAt: optDate(j, 'withdrawn_at'),
      );

  final String id;
  final String consentType;
  final bool granted;
  final String grantedBy;
  final String? guardianName;
  final DateTime? grantedAt;
  final DateTime? expiresAt;
  final DateTime? withdrawnAt;

  bool get isActive =>
      granted && withdrawnAt == null && (expiresAt == null || expiresAt!.isAfter(DateTime.now().toUtc()));
}

class ResidentOut {
  ResidentOut({
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

  factory ResidentOut.fromJson(Json j) => ResidentOut(
        id: reqStr(j, 'id'),
        userId: optStr(j, 'user_id'),
        fullName: reqStr(j, 'full_name'),
        phoneMasked: optStr(j, 'phone_masked') ?? '',
        wardId: reqStr(j, 'ward_id'),
        wardName: optStr(j, 'ward_name') ?? '',
        language: optStr(j, 'language') ?? 'en',
        needs: strList(j, 'needs'),
        livesAlone: reqBool(j, 'lives_alone'),
        hasSmartphone: reqBool(j, 'has_smartphone', fallback: true),
        registrationStatus: optStr(j, 'registration_status') ?? '',
        registeredVia: optStr(j, 'registered_via') ?? '',
        reverifyDueAt: optDate(j, 'reverify_due_at'),
        isDemo: reqBool(j, 'is_demo'),
        consents: objList(j, 'consents', ConsentOut.fromJson),
        hasExactLocation: reqBool(j, 'has_exact_location'),
      );

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

  ConsentOut? consent(String type) {
    for (final c in consents) {
      if (c.consentType == type && c.isActive) return c;
    }
    return null;
  }

  bool get isActive => registrationStatus == 'active';
}

class VolunteerOut {
  VolunteerOut({
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

  factory VolunteerOut.fromJson(Json j) => VolunteerOut(
        id: reqStr(j, 'id'),
        userId: reqStr(j, 'user_id'),
        fullName: reqStr(j, 'full_name'),
        phoneMasked: optStr(j, 'phone_masked') ?? '',
        wardId: optStr(j, 'ward_id'),
        wardName: optStr(j, 'ward_name'),
        isAvailable: reqBool(j, 'is_available'),
        baseLat: optDouble(j, 'base_lat') ?? 0,
        baseLng: optDouble(j, 'base_lng') ?? 0,
        maxRadiusM: optDouble(j, 'max_radius_m') ?? 0,
        skills: strList(j, 'skills'),
        verified: reqBool(j, 'verified'),
        isDemo: reqBool(j, 'is_demo'),
        activeTaskId: optStr(j, 'active_task_id'),
      );

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
}

class MeOut {
  MeOut({
    required this.user,
    required this.resident,
    required this.volunteer,
    required this.demoMode,
    required this.notifyRealResidents,
    required this.raw,
  });

  factory MeOut.fromJson(Json j) {
    final res = optObj(j, 'resident');
    final vol = optObj(j, 'volunteer');
    return MeOut(
      user: UserOut.fromJson(optObj(j, 'user') ?? (throw const FormatException('Missing "user"'))),
      resident: res == null ? null : ResidentOut.fromJson(res),
      volunteer: vol == null ? null : VolunteerOut.fromJson(vol),
      demoMode: reqBool(j, 'demo_mode'),
      notifyRealResidents: reqBool(j, 'notify_real_residents'),
      raw: j,
    );
  }

  final UserOut user;
  final ResidentOut? resident;
  final VolunteerOut? volunteer;
  final bool demoMode;
  final bool notifyRealResidents;

  /// Original JSON, kept so the profile can be cached for offline restarts.
  final Json raw;
}

class TokenOut {
  TokenOut({required this.accessToken, required this.expiresIn, required this.user, required this.isNewUser});

  factory TokenOut.fromJson(Json j) => TokenOut(
        accessToken: reqStr(j, 'access_token'),
        expiresIn: optInt(j, 'expires_in'),
        user: UserOut.fromJson(optObj(j, 'user') ?? (throw const FormatException('Missing "user"'))),
        isNewUser: reqBool(j, 'is_new_user'),
      );

  final String accessToken;
  final int expiresIn;
  final UserOut user;
  final bool isNewUser;
}

class OtpRequestOut {
  OtpRequestOut({required this.sent, required this.expiresIn, required this.channel, required this.note});

  factory OtpRequestOut.fromJson(Json j) => OtpRequestOut(
        sent: reqBool(j, 'sent'),
        expiresIn: optInt(j, 'expires_in'),
        channel: optStr(j, 'channel') ?? '',
        note: optStr(j, 'note') ?? '',
      );

  final bool sent;
  final int expiresIn;
  final String channel;
  final String note;
}

class DemoPersona {
  DemoPersona({required this.userId, required this.fullName, required this.role, required this.description});

  factory DemoPersona.fromJson(Json j) => DemoPersona(
        userId: reqStr(j, 'user_id'),
        fullName: reqStr(j, 'full_name'),
        role: UserRole.parse(optStr(j, 'role')),
        description: optStr(j, 'description') ?? '',
      );

  final String userId;
  final String fullName;
  final UserRole role;
  final String description;
}

class WardOut {
  WardOut({
    required this.id,
    required this.code,
    required this.name,
    required this.district,
    required this.state,
    required this.centroidLat,
    required this.centroidLng,
    required this.accessStatus,
    required this.isDemo,
  });

  factory WardOut.fromJson(Json j) => WardOut(
        id: reqStr(j, 'id'),
        code: optStr(j, 'code') ?? '',
        name: reqStr(j, 'name'),
        district: optStr(j, 'district') ?? '',
        state: optStr(j, 'state') ?? '',
        centroidLat: optDouble(j, 'centroid_lat') ?? 0,
        centroidLng: optDouble(j, 'centroid_lng') ?? 0,
        accessStatus: optStr(j, 'access_status') ?? 'open',
        isDemo: reqBool(j, 'is_demo'),
      );

  final String id;
  final String code;
  final String name;
  final String district;
  final String state;
  final double centroidLat;
  final double centroidLng;
  final String accessStatus;
  final bool isDemo;
}

class ExactLocationOut {
  ExactLocationOut({
    required this.lat,
    required this.lng,
    required this.addressText,
    required this.landmark,
    required this.source,
  });

  factory ExactLocationOut.fromJson(Json j) => ExactLocationOut(
        lat: reqDouble(j, 'lat'),
        lng: reqDouble(j, 'lng'),
        addressText: optStr(j, 'address_text'),
        landmark: optStr(j, 'landmark'),
        source: optStr(j, 'source') ?? '',
      );

  final double lat;
  final double lng;
  final String? addressText;
  final String? landmark;
  final String source;
}

/// Accessibility needs the registry collects (needs, not diagnoses).
const kNeeds = <String>[
  'hearing',
  'vision',
  'mobility',
  'bedridden',
  'cognitive',
  'elderly_alone',
  'speech',
  'feature_phone',
];

class TrustedContactIn {
  TrustedContactIn({
    required this.fullName,
    required this.phone,
    this.relationship = 'family',
    this.canViewLocation = false,
  });

  final String fullName;
  final String phone;
  final String relationship;
  final bool canViewLocation;

  Json toJson() => {
        'full_name': fullName,
        'phone': phone,
        'relationship': relationship,
        'can_view_location': canViewLocation,
      };
}

class RegistrationIn {
  RegistrationIn({
    required this.fullName,
    required this.wardId,
    required this.language,
    required this.needs,
    required this.livesAlone,
    required this.hasSmartphone,
    required this.consentRegistry,
    required this.consentLocation,
    required this.consentCaregiverShare,
    required this.grantedBy,
    this.guardianName,
    this.lat,
    this.lng,
    this.addressText,
    this.landmark,
    this.trustedContacts = const [],
  });

  final String fullName;
  final String wardId;
  final String language;
  final List<String> needs;
  final bool livesAlone;
  final bool hasSmartphone;
  final bool consentRegistry;
  final bool consentLocation;
  final bool consentCaregiverShare;
  final String grantedBy;
  final String? guardianName;
  final double? lat;
  final double? lng;
  final String? addressText;
  final String? landmark;
  final List<TrustedContactIn> trustedContacts;

  Json toJson() => {
        'full_name': fullName,
        'ward_id': wardId,
        'language': language,
        'needs': needs,
        'lives_alone': livesAlone,
        'has_smartphone': hasSmartphone,
        'consent_registry': consentRegistry,
        'consent_location': consentLocation,
        'consent_caregiver_share': consentCaregiverShare,
        'granted_by': grantedBy,
        if (guardianName != null && guardianName!.isNotEmpty) 'guardian_name': guardianName,
        if (lat != null) 'lat': lat,
        if (lng != null) 'lng': lng,
        if (addressText != null && addressText!.isNotEmpty) 'address_text': addressText,
        if (landmark != null && landmark!.isNotEmpty) 'landmark': landmark,
        'trusted_contacts': trustedContacts.map((c) => c.toJson()).toList(),
      };
}
