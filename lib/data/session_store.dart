import 'package:flutter/foundation.dart';

import '../core/api/api_exception.dart';
import '../core/api/nova_api.dart';
import 'json.dart';
import 'models.dart';
import 'otp.dart';

enum SessionStatus { booting, offline, signedOut, signedIn }

/// The Student's Laravel session (D-067): same endpoints and rules as
/// the web SPA, including one active session per Student.
class SessionStore extends ChangeNotifier {
  SessionStore(NovaApi api) : _api = api {
    api.onSessionLost = _onSessionLost;
  }

  /// A signed-in Student without a backend, for tests and previews; an
  /// [api] and the raw [user] let a test exercise session requests.
  SessionStore.seeded(StudentProfile profile, {this._api, this._user})
      : _profile = profile,
        _status = SessionStatus.signedIn;

  final NovaApi? _api;

  SessionStatus _status = SessionStatus.booting;
  Json? _user;
  StudentProfile? _profile;
  String? _endedReason;

  SessionStatus get status => _status;
  StudentProfile? get profile => _profile;
  bool get signedIn => _status == SessionStatus.signedIn;

  /// `password_change` | `phone` | `onboarding` | `school_year` | null —
  /// the backend blocks every other route until the step is done.
  String? get nextRequiredStep {
    final String? step = _user?.strOrNull('next_required_step');
    return step;
  }

  /// The Student's own first and last name as stored (never the
  /// `legacy_full_name` shown in their place when both are empty).
  (String, String) get storedName {
    final Json? student = _user?.obj('student');
    if (student == null) return (_profile?.firstName ?? '', _profile?.lastName ?? '');
    return (student.str('first_name').trim(), student.str('last_name').trim());
  }

  /// Why the last session ended on its own (`SESSION_REPLACED` when the
  /// Student signed in on another device), shown once on sign-in.
  String? get endedReason => _endedReason;

  void clearEndedReason() {
    _endedReason = null;
    notifyListeners();
  }

  /// Restores a stored session on launch.
  Future<void> boot() async {
    try {
      final NovaApi? api = _api;
      if (api == null) return;
      _setUser((await api.get('/auth/me')).obj('data'));
    } on ApiException catch (error) {
      if (error.isNetwork) {
        _status = SessionStatus.offline;
        notifyListeners();
      } else {
        await _signedOut();
      }
    }
  }

  Future<void> login({required String phone, required String password}) async {
    final Json body = await _api!.post('/auth/login', <String, String>{
      'phone': phone.trim(),
      'password': password,
    });
    final Json? user = body.obj('data');
    if (user?.str('role') != 'student') {
      // Admin accounts use the web console; the app is Student-only.
      await logout();
      throw const ApiException(
        status: 403,
        code: 'STUDENT_ONLY',
        message: 'This app is for Student accounts.',
      );
    }
    _endedReason = null;
    _setUser(user);
  }

  /// Registration does not sign in (backend rule); the caller signs in
  /// with the same phone and password afterwards. While the Admin switch
  /// is on, [fields] carry the `phone_verification_token` (D-093).
  Future<void> register(Map<String, Object?> fields) async {
    await _api!.post('/auth/register', fields);
  }

  /// D-093/D-096: whether registration needs the phone code step (the
  /// Admin switch, on by default).
  Future<bool> registrationPhoneVerificationRequired() async {
    final Json body = await _api!.get('/auth/registration-options');
    return body.obj('data')?.flag('phone_verification_required') ?? false;
  }

  /// D-093: sends a registration code to [phone] by [channel], written
  /// in [lang] (`ar` | `fr` | `en`).
  Future<OtpChallenge> sendRegistrationCode(String phone, OtpChannel channel, String lang) async =>
      _challenge(await _api!.post('/auth/register/otp', <String, String>{
        'phone': phone.trim(),
        'channel': channel.name,
        'lang': lang,
      }));

  /// The verification token sent with the registration.
  Future<String> verifyRegistrationCode(String challengeId, String code) async {
    final Json body = await _api!.post('/auth/register/otp/verify', <String, String>{
      'challenge_id': challengeId,
      'code': code.trim(),
    });
    return body.obj('data')?.str('verification_token') ?? '';
  }

  /// D-093 forgotten password, step 1: the answer is the same whether or
  /// not the number has an account.
  Future<OtpChallenge> requestPasswordReset(String phone, OtpChannel channel, String lang) async =>
      _challenge(await _api!.post('/auth/password/forgot', <String, String>{
        'phone': phone.trim(),
        'channel': channel.name,
        'lang': lang,
      }));

  /// Step 2: the code becomes a short-lived reset token.
  Future<String> verifyPasswordReset(String challengeId, String code) async {
    final Json body = await _api!.post('/auth/password/forgot/verify', <String, String>{
      'challenge_id': challengeId,
      'code': code.trim(),
    });
    return body.obj('data')?.str('reset_token') ?? '';
  }

  /// Step 3: the new password. Does not sign in; the backend signs out
  /// every session of the account.
  Future<void> resetPassword(String resetToken, String password, String confirmation) async {
    await _api!.post('/auth/password/forgot/reset', <String, String>{
      'reset_token': resetToken,
      'password': password,
      'password_confirmation': confirmation,
    });
  }

  /// D-093: a signed-in Student asks for a code on their own number
  /// before changing their password.
  Future<OtpChallenge> requestPasswordChangeCode(OtpChannel channel, String lang) async =>
      _challenge(await _api!.post('/auth/password/otp', <String, String>{
        'channel': channel.name,
        'lang': lang,
      }));

  /// Changes the password with the code. This device stays signed in
  /// with a renewed session; the other devices are signed out.
  Future<void> changePasswordWithCode({
    required String challengeId,
    required String code,
    required String password,
    required String confirmation,
  }) async {
    _setUser(
      (await _api!.put('/auth/password', <String, String>{
        'challenge_id': challengeId,
        'code': code.trim(),
        'password': password,
        'password_confirmation': confirmation,
      }))
          .obj('data'),
    );
  }

  static OtpChallenge _challenge(Json body) =>
      OtpChallenge.fromJson(body.obj('data') ?? <String, dynamic>{});

  /// D-079: an account without a valid mobile enters the Student's own
  /// number once; the answer is the updated user (next step moves on).
  Future<void> updatePhone(String phone) async {
    _setUser(
      (await _api!.put('/auth/phone', <String, String>{'phone': phone}))
          .obj('data'),
    );
  }

  Future<void> completeOnboarding(Map<String, Object?> fields) async {
    _setUser((await _api!.put('/onboarding', fields)).obj('data'));
  }

  /// The Student's current level and filière ids, null when unset.
  (int?, int?) get schoolReferences {
    final Json? student = _user?.obj('student');
    int? reference(String key) {
      final Object? id = student?.obj(key)?['id'];
      return id is int ? id : null;
    }

    return (reference('level'), reference('track'));
  }

  /// D-098: at the start of a new school year the Student keeps or
  /// changes their level and filière (`next_required_step: school_year`).
  Future<void> confirmSchoolYear({required int levelId, int? trackId}) async {
    _setUser(
      (await _api!.put('/auth/school-year', <String, Object?>{
        'level_id': levelId,
        'track_id': trackId,
      }))
          .obj('data'),
    );
  }

  /// D-073: entering a Live needs a first and last name
  /// (`PROFILE_NAME_REQUIRED`). Saved through the onboarding endpoint with
  /// the Student's current references; `legacy_full_name` is never sent.
  Future<void> saveLiveName({required String firstName, required String lastName}) async {
    final Json student = _user?.obj('student') ?? <String, dynamic>{};
    int? reference(String key) {
      final Object? id = student.obj(key)?['id'];
      return id is int ? id : null;
    }

    await completeOnboarding(<String, Object?>{
      'first_name': firstName,
      'last_name': lastName,
      'level_id': reference('level'),
      'track_id': reference('track'),
      'wilaya_id': reference('wilaya'),
      'commune_id': reference('commune'),
    });
  }

  /// `GET /auth/session`, the fallback for a missed `SessionReplaced`
  /// broadcast (D-071): another fingerprint means this session was
  /// replaced. Transient failures wait for the next check; a 401 already
  /// signs out through [NovaApi.onSessionLost].
  Future<void> checkSession() async {
    final NovaApi? api = _api;
    final String? mine = fingerprint;
    if (api == null || mine == null || _status != SessionStatus.signedIn) return;
    try {
      final Json body = await api.get('/auth/session');
      final String? current = body.obj('data')?.strOrNull('session_fingerprint');
      if (current != null && current != mine) replacedElsewhere(current);
    } on ApiException {
      // Next tick.
    }
  }

  Future<void> changePassword(String password, String confirmation) async {
    _setUser(
      (await _api!.post('/auth/change-password', <String, String>{
        'password': password,
        'password_confirmation': confirmation,
      }))
          .obj('data'),
    );
  }

  Future<void> logout() async {
    try {
      await _api?.post('/auth/logout');
    } on ApiException {
      // Signing out locally must work even offline or when expired.
    }
    await _signedOut();
  }

  /// This session's fingerprint (`/auth/me`), to tell a replacement
  /// broadcast by another device from our own sign-in.
  String? get fingerprint => _user?.strOrNull('session_fingerprint');

  /// `SessionReplaced` on `private-user.{id}`: another device signed in.
  void replacedElsewhere(String fingerprint) {
    if (_status != SessionStatus.signedIn || fingerprint == this.fingerprint) return;
    _endedReason = ApiException.sessionReplaced;
    _signedOut();
  }

  /// Refreshes profile figures (points, lessons) after activity.
  void updateProfile(StudentProfile profile) {
    _profile = profile;
    notifyListeners();
  }

  void _setUser(Json? user) {
    if (user == null) return;
    _user = user;
    _profile = StudentProfile.fromUser(user);
    _status = SessionStatus.signedIn;
    notifyListeners();
  }

  Future<void> _signedOut() async {
    _user = null;
    _profile = null;
    _status = SessionStatus.signedOut;
    await _api?.clearSession();
    notifyListeners();
  }

  void _onSessionLost(ApiException error) {
    if (_status != SessionStatus.signedIn) return;
    _endedReason = error.code;
    _signedOut();
  }
}
