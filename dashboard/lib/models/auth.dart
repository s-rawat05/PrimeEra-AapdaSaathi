import 'admin.dart';
import 'json.dart';

const opsRoles = {'admin', 'operator'};

class UserOut {
  const UserOut({
    required this.id,
    required this.fullName,
    required this.role,
    required this.phoneMasked,
    required this.email,
    required this.language,
    required this.isDemo,
  });

  final String id;
  final String fullName;
  final String role;
  final String phoneMasked;
  final String? email;
  final String language;
  final bool isDemo;

  bool get isAdmin => role == 'admin';
  bool get isOperator => role == 'operator';
  bool get isOps => opsRoles.contains(role);

  factory UserOut.fromJson(Json j) => UserOut(
        id: reqString(j, 'id'),
        fullName: reqString(j, 'full_name'),
        role: reqString(j, 'role'),
        phoneMasked: reqString(j, 'phone_masked'),
        email: optString(j, 'email'),
        language: reqString(j, 'language'),
        isDemo: reqBool(j, 'is_demo'),
      );
}

class TokenOut {
  const TokenOut({required this.accessToken, required this.expiresIn, required this.user, required this.isNewUser});

  final String accessToken;
  final int expiresIn;
  final UserOut user;
  final bool isNewUser;

  factory TokenOut.fromJson(Json j) => TokenOut(
        accessToken: reqString(j, 'access_token'),
        expiresIn: reqInt(j, 'expires_in'),
        user: UserOut.fromJson(asJson(j['user'])),
        isNewUser: boolOr(j, 'is_new_user', false),
      );
}

class DemoPersona {
  const DemoPersona({required this.userId, required this.fullName, required this.role, required this.description});

  final String userId;
  final String fullName;
  final String role;
  final String description;

  bool get isOps => opsRoles.contains(role);

  factory DemoPersona.fromJson(Json j) => DemoPersona(
        userId: reqString(j, 'user_id'),
        fullName: reqString(j, 'full_name'),
        role: reqString(j, 'role'),
        description: optString(j, 'description') ?? '',
      );
}

class MeOut {
  const MeOut({
    required this.user,
    required this.resident,
    required this.volunteer,
    required this.demoMode,
    required this.notifyRealResidents,
  });

  final UserOut user;
  final ResidentOut? resident;
  final VolunteerOut? volunteer;
  final bool demoMode;
  final bool notifyRealResidents;

  factory MeOut.fromJson(Json j) => MeOut(
        user: UserOut.fromJson(asJson(j['user'])),
        resident: j['resident'] == null ? null : ResidentOut.fromJson(asJson(j['resident'])),
        volunteer: j['volunteer'] == null ? null : VolunteerOut.fromJson(asJson(j['volunteer'])),
        demoMode: reqBool(j, 'demo_mode'),
        notifyRealResidents: reqBool(j, 'notify_real_residents'),
      );
}
