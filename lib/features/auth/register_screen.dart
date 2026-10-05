import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/api/api_error_text.dart';
import '../../core/api/api_exception.dart';
import '../../core/i18n/nova_strings.dart';
import '../../core/state/app_state.dart';
import '../../core/theme/nova_colors.dart';
import '../../core/theme/nova_typography.dart';
import '../../core/utils/phone.dart';
import '../../core/widgets/motion.dart';
import '../../core/widgets/pressable_scale.dart';
import '../../data/account_store.dart';
import '../../data/models.dart';
import '../../data/otp.dart';
import 'auth_hero.dart';
import 'otp_widgets.dart';

/// Registration: first/last name, unique phone, school level, filière
/// (the level's own, D-098), cascading wilaya → commune pickers, password
/// rules — exactly the conception's required fields, validated by the
/// backend. While the Admin switch is on (D-093/D-096) the phone is
/// verified by a code before the account is created.
///
/// With [onboarding] the same form completes an imported Student's
/// academic identity (`PUT /onboarding`): no phone or password.
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key, this.onboarding = false});

  final bool onboarding;

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen>
    with ResendCountdown<RegisterScreen> {
  final TextEditingController _first = TextEditingController();
  final TextEditingController _last = TextEditingController();
  final TextEditingController _phone = TextEditingController();
  final TextEditingController _password = TextEditingController();
  final TextEditingController _confirm = TextEditingController();
  final TextEditingController _code = TextEditingController();

  List<RefItem> _levels = const <RefItem>[];
  List<RefItem> _tracks = const <RefItem>[];
  List<RefItem> _wilayas = const <RefItem>[];
  List<RefItem> _communes = const <RefItem>[];

  RefItem? _level;
  RefItem? _track;
  RefItem? _wilaya;
  RefItem? _commune;
  bool _obscure = true;
  bool _busy = false;
  String? _error;
  Map<String, String> _fieldErrors = const <String, String>{};

  /// 409 `PHONE_ALREADY_REGISTERED` (D-079): the number already has an
  /// account, created by the school or registered earlier — sign in.
  bool _phoneTaken = false;

  /// D-093/D-096 registration phone verification (`/auth/registration-options`).
  bool _verificationRequired = false;
  OtpChannel _channel = OtpChannel.sms;
  String _challengeId = '';
  String _challengePhone = '';
  bool _codeBusy = false;
  String? _codeError;

  /// The number the token was issued for; another number needs a new code.
  String _verifiedPhone = '';
  String _verificationToken = '';

  bool get _phoneVerified =>
      _verificationToken.isNotEmpty && _verifiedPhone == _phone.text.trim();

  /// Backend rule (D-098): a level with filières requires one of its own,
  /// a level without filière takes none.
  bool get _trackEnabled => _level?.hasTracks ?? false;

  List<RefItem> get _levelTracks => _level?.tracksFrom(_tracks) ?? const <RefItem>[];

  ReferenceStore? get _references => AppScope.of(context).references;

  @override
  void initState() {
    super.initState();
    // The verification block follows the number being typed.
    _phone.addListener(_onPhoneChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadReferences();
      if (!widget.onboarding) _loadRegistrationOptions();
    });
  }

  String _lastPhone = '';

  void _onPhoneChanged() {
    final String phone = _phone.text.trim();
    if (phone == _lastPhone) return;
    _lastPhone = phone;
    if (_verificationRequired) setState(() => _codeError = null);
  }

  Future<void> _loadRegistrationOptions() async {
    try {
      final bool required =
          await AppScope.of(context).session.registrationPhoneVerificationRequired();
      if (mounted) setState(() => _verificationRequired = required);
    } on ApiException {
      // Unknown: the registration answer says when a code is needed.
    }
  }

  @override
  void dispose() {
    _phone.removeListener(_onPhoneChanged);
    for (final TextEditingController c in <TextEditingController>[
      _first,
      _last,
      _phone,
      _password,
      _confirm,
      _code,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadReferences() async {
    final StudentProfile? profile = AppScope.of(context).session.profile;
    if (widget.onboarding && profile != null) {
      _first.text = profile.firstName;
      _last.text = profile.lastName;
    }
    final ReferenceStore? references = _references;
    if (references == null) return;
    try {
      final List<List<RefItem>> lists = await Future.wait(<Future<List<RefItem>>>[
        references.levels(),
        references.tracks(),
        references.wilayas(),
      ]);
      if (!mounted) return;
      setState(() {
        _levels = lists[0];
        _tracks = lists[1];
        _wilayas = lists[2];
      });
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = apiErrorText(context, error));
    }
  }

  Future<void> _pickWilaya(RefItem? wilaya) async {
    setState(() {
      _wilaya = wilaya;
      _commune = null;
      _communes = const <RefItem>[];
    });
    final ReferenceStore? references = _references;
    if (wilaya == null || references == null) return;
    try {
      final List<RefItem> communes = await references.communes(wilaya.id);
      if (mounted && _wilaya?.id == wilaya.id) {
        setState(() => _communes = communes);
      }
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = apiErrorText(context, error));
    }
  }

  Map<String, Object?> get _academicFields => <String, Object?>{
        'first_name': _first.text.trim(),
        'last_name': _last.text.trim(),
        'level_id': _level?.id,
        'track_id': _trackEnabled ? _track?.id : null,
        'wilaya_id': _wilaya?.id,
        'commune_id': _commune?.id,
      };

  static final RegExp _strictMobile = RegExp(r'^0[567][0-9]{8}$');

  /// Sends (or resends) the registration code to the number typed.
  Future<void> _sendCode() async {
    final String phone = _phone.text.trim();
    if (!_strictMobile.hasMatch(phone)) {
      setState(() => _fieldErrors = <String, String>{'phone': context.tr('auth.phoneStrict')});
      return;
    }
    final AppState app = AppScope.of(context);
    setState(() {
      _codeBusy = true;
      _codeError = null;
      _phoneTaken = false;
      _fieldErrors = const <String, String>{};
    });
    try {
      final OtpChallenge challenge =
          await app.session.sendRegistrationCode(phone, _channel, app.lang.name);
      if (!mounted) return;
      _code.clear();
      setState(() {
        _challengeId = challenge.id;
        _challengePhone = phone;
      });
      startResend(challenge.resendIn);
    } on ApiException catch (error) {
      if (!mounted) return;
      final int? retryAfter = otpRetryAfter(error);
      if (retryAfter != null) startResend(retryAfter);
      setState(() {
        if (error.code == 'PHONE_ALREADY_REGISTERED') {
          _phoneTaken = true;
        } else if (error.code == 'PHONE_VERIFICATION_DISABLED') {
          // The Admin switched it off meanwhile: no code is needed.
          _verificationRequired = false;
        } else {
          _codeError = apiErrorText(context, error);
        }
      });
    } finally {
      if (mounted) setState(() => _codeBusy = false);
    }
  }

  Future<void> _verifyCode() async {
    if (!isOtpCode(_code.text)) {
      setState(() => _codeError = context.tr('otp.codeFormat'));
      return;
    }
    final String phone = _challengePhone;
    setState(() {
      _codeBusy = true;
      _codeError = null;
    });
    try {
      final String token =
          await AppScope.of(context).session.verifyRegistrationCode(_challengeId, _code.text);
      if (!mounted) return;
      setState(() {
        _verifiedPhone = phone;
        _verificationToken = token;
        _challengeId = '';
        _error = null;
      });
    } on ApiException catch (error) {
      if (mounted) setState(() => _codeError = apiErrorText(context, error));
    } finally {
      if (mounted) setState(() => _codeBusy = false);
    }
  }

  /// Missing fields and the password rules (D-078), in the app language
  /// before asking the server, which stays authoritative and answers in
  /// English.
  Map<String, String> _localErrors() {
    final String required = context.tr('auth.fieldRequired');
    final Map<String, String> errors = <String, String>{
      if (_first.text.trim().isEmpty) 'first_name': required,
      if (_last.text.trim().isEmpty) 'last_name': required,
      if (_level == null) 'level_id': required,
      if (_trackEnabled && _track == null) 'track_id': required,
      if (_wilaya == null) 'wilaya_id': required,
      if (_commune == null) 'commune_id': required,
    };
    if (!widget.onboarding) {
      final String password = _password.text;
      if (password.length < 8) {
        errors['password'] = context.tr('pwd.short');
      } else if (isSamePhone(password, _phone.text)) {
        errors['password'] = context.tr('pwd.samePhone');
      } else if (_confirm.text != password) {
        errors['password_confirmation'] = context.tr('pwd.mismatch');
      }
    }
    return errors;
  }

  Future<void> _submit() async {
    final AppState app = AppScope.of(context);
    // D-081: registration takes the number exactly as it will be typed at
    // sign-in, 05/06/07 then 8 digits, as the website checks it first.
    if (!widget.onboarding && !_strictMobile.hasMatch(_phone.text.trim())) {
      final String message = context.tr('auth.phoneStrict');
      setState(() {
        _phoneTaken = false;
        _error = message;
        _fieldErrors = <String, String>{'phone': message};
      });
      return;
    }
    final Map<String, String> local = _localErrors();
    if (local.isNotEmpty) {
      setState(() {
        _phoneTaken = false;
        _error = context.tr('auth.checkFields');
        _fieldErrors = local;
      });
      return;
    }
    if (!widget.onboarding && _verificationRequired && !_phoneVerified) {
      setState(() {
        _phoneTaken = false;
        _error = context.tr('auth.phoneVerificationNeeded');
      });
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _phoneTaken = false;
      _fieldErrors = const <String, String>{};
    });
    try {
      if (widget.onboarding) {
        await app.session.completeOnboarding(_academicFields);
      } else {
        await app.session.register(<String, Object?>{
          ..._academicFields,
          'phone': _phone.text.trim(),
          'password': _password.text,
          'password_confirmation': _confirm.text,
          if (_verificationRequired && _phoneVerified)
            'phone_verification_token': _verificationToken,
        });
        // Registration does not open a session; sign in right away so
        // the new Student lands in their space.
        await app.session.login(phone: _phone.text, password: _password.text);
      }
    } on ApiException catch (error) {
      if (!mounted) return;
      if (error.code == 'PHONE_ALREADY_REGISTERED') {
        setState(() => _phoneTaken = true);
        return;
      }
      if (error.code == 'PHONE_VERIFICATION_REQUIRED' ||
          error.code == 'PHONE_VERIFICATION_INVALID') {
        // The switch was turned on meanwhile, or the token expired: show
        // the code step again.
        setState(() {
          _verificationRequired = true;
          _verificationToken = '';
          _verifiedPhone = '';
          _fieldErrors = const <String, String>{};
          _error = apiErrorText(context, error);
        });
        return;
      }
      setState(() {
        _fieldErrors = error.fieldErrors;
        _error = apiErrorText(context, error);
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          AuthHero(
            showBack: !widget.onboarding,
            title: context.tr(
              widget.onboarding ? 'auth.onboardingTitle' : 'auth.createAccount',
            ),
            subtitle: context.tr(
              widget.onboarding ? 'auth.onboardingSub' : 'auth.createSubtitle',
            ),
            bottom: widget.onboarding
                ? null
                : AuthModeSwitch(
                    signIn: false,
                    onSwitch: () => Navigator.of(context).maybePop(),
                  ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 26, 24, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ...stagger(_form(), step: const Duration(milliseconds: 45)),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: Text(
                      _error!,
                      style: NovaTypography.textTheme.bodySmall!.copyWith(
                        color: NovaHue.rose.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                if (_phoneTaken) _phoneTakenNotice(),
                const SizedBox(height: 10),
                PressableScale(
                  onTap: _busy ? null : _submit,
                  pressedScale: 0.97,
                  semanticLabel: widget.onboarding
                      ? 'Save my details'
                      : 'Create account',
                  child: Container(
                    height: 58,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: NovaColors.ink950,
                      borderRadius: BorderRadius.circular(100),
                    ),
                    child: _busy
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.6,
                              color: NovaColors.textOnDark,
                            ),
                          )
                        : Text(
                            context.tr(
                              widget.onboarding
                                  ? 'auth.saveDetails'
                                  : 'auth.createSpace',
                            ),
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontWeight: FontWeight.w700,
                              fontSize: 15.5,
                              color: NovaColors.textOnDark,
                            ),
                          ),
                  ),
                ),
                if (widget.onboarding) ...[
                  const SizedBox(height: 14),
                  Center(
                    child: PressableScale(
                      onTap: () => AppScope.of(context).session.logout(),
                      semanticLabel: 'Sign out',
                      child: Text(
                        context.tr('settings.signOut'),
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          color: NovaColors.textMuted,
                        ),
                      ),
                    ),
                  ),
                ] else ...[
                  const SizedBox(height: 14),
                  Center(
                    child: Text(
                      context.tr('auth.termsNote'),
                      style: NovaTypography.muted(
                        NovaTypography.textTheme.labelSmall!,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The website's "sign in instead" notice; the action goes back to the
  /// sign-in screen with the number typed here.
  Widget _phoneTakenNotice() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.tr('auth.phoneTaken'),
            style: NovaTypography.textTheme.bodySmall!.copyWith(
              color: NovaHue.rose.onSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          PressableScale(
            onTap: () => Navigator.of(context).maybePop<String>(_phone.text.trim()),
            semanticLabel: 'Sign in with this number',
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 9),
              decoration: BoxDecoration(
                color: NovaColors.accent,
                borderRadius: BorderRadius.circular(100),
              ),
              child: Text(
                context.tr('auth.signInInstead'),
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontWeight: FontWeight.w700,
                  fontSize: 12.5,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// D-093/D-096: the channel, "send the code", then the 6-digit code,
  /// for the number typed above; another number needs a new code.
  Widget _phoneVerification() {
    final String phone = _phone.text.trim();
    final bool codeSent = _challengeId.isNotEmpty && _challengePhone == phone;
    final Widget body;
    if (_phoneVerified) {
      body = Row(
        children: [
          const Icon(Icons.verified_rounded, size: 19, color: NovaColors.accentDeep),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              context.tr('auth.phoneVerified'),
              style: NovaTypography.textTheme.bodySmall!.copyWith(
                color: NovaColors.accentDeep,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      );
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(context.tr('auth.verifyPhone'), style: NovaTypography.textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(
            codeSent
                ? context.trf('auth.verifyCodeSent', <String, String>{
                    'phone': '\u2066$phone\u2069',
                    'channel': otpChannelName(context, _channel),
                  })
                : context.trf('auth.verifyPhoneDesc', <String, String>{
                    'phone': '\u2066${phone.isEmpty ? '05xxxxxxxx' : phone}\u2069',
                  }),
            style: NovaTypography.muted(NovaTypography.textTheme.bodySmall!),
          ),
          const SizedBox(height: 12),
          if (codeSent)
            AuthTextField.code(
              controller: _code,
              label: context.tr('otp.codeLabel'),
              onSubmitted: (_) => _verifyCode(),
            )
          else
            OtpChannelChoice(
              value: _channel,
              enabled: !_codeBusy,
              onChanged: (OtpChannel channel) => setState(() => _channel = channel),
            ),
          if (_codeError != null) AuthMessage(_codeError!),
          Wrap(
            spacing: 18,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (codeSent)
                AuthTextAction(
                  label: context.tr('otp.verify'),
                  onTap: _codeBusy ? null : _verifyCode,
                ),
              AuthTextAction(
                label: resendLabel(
                  context,
                  resendIn,
                  idleKey: codeSent ? 'otp.resend' : 'otp.sendCode',
                ),
                onTap: _codeBusy || resendIn > 0 ? null : _sendCode,
              ),
              if (_codeBusy)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: NovaColors.accentDeep),
                ),
            ],
          ),
        ],
      );
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: NovaColors.accentMist,
        borderRadius: BorderRadius.circular(16),
      ),
      child: body,
    );
  }

  List<Widget> _form() {
    return [
      _Field(
        controller: _first,
        label: context.tr('auth.firstName'),
        hint: 'Ines',
        error: _fieldErrors['first_name'],
      ),
      _Field(
        controller: _last,
        label: context.tr('auth.lastName'),
        hint: 'Benali',
        error: _fieldErrors['last_name'],
      ),
      if (!widget.onboarding)
        _Field(
          controller: _phone,
          label: context.tr('settings.phone'),
          // D-081: exactly as typed at sign-in, 05XXXXXXXX.
          hint: '05xxxxxxxx',
          keyboard: TextInputType.number,
          formatters: <TextInputFormatter>[
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(10),
          ],
          icon: Icons.phone_rounded,
          error: _fieldErrors['phone'],
        ),
      if (!widget.onboarding && _verificationRequired) _phoneVerification(),
      RefPickerField(
        label: context.tr('auth.level'),
        value: _level,
        options: _levels,
        icon: Icons.school_rounded,
        error: _fieldErrors['level_id'],
        onChanged: (RefItem? value) => setState(() {
          _level = value;
          // Keep the filière only when it belongs to the new level.
          if (!_levelTracks.any((RefItem t) => t.id == _track?.id)) _track = null;
        }),
      ),
      RefPickerField(
        label: context.tr('settings.track'),
        value: _track,
        options: _levelTracks,
        icon: Icons.account_tree_rounded,
        enabled: _trackEnabled,
        emptyHint: _trackEnabled ? null : context.tr('auth.trackNotRequired'),
        error: _fieldErrors['track_id'],
        onChanged: (RefItem? value) => setState(() => _track = value),
      ),
      RefPickerField(
        label: context.tr('settings.wilaya'),
        value: _wilaya,
        options: _wilayas,
        icon: Icons.location_city_rounded,
        error: _fieldErrors['wilaya_id'],
        onChanged: _pickWilaya,
      ),
      RefPickerField(
        label: context.tr('settings.commune'),
        value: _commune,
        options: _communes,
        icon: Icons.home_work_rounded,
        enabled: _wilaya != null,
        emptyHint: _wilaya == null ? context.tr('auth.pickWilaya') : null,
        error: _fieldErrors['commune_id'],
        onChanged: (RefItem? value) => setState(() => _commune = value),
      ),
      if (!widget.onboarding) ...[
        _Field(
          controller: _password,
          label: context.tr('auth.password'),
          hint: context.tr('auth.passwordHint'),
          icon: Icons.lock_outline_rounded,
          obscure: _obscure,
          error: _fieldErrors['password'],
          trailing: PressableScale(
            onTap: () => setState(() => _obscure = !_obscure),
            semanticLabel: 'Show password',
            child: Icon(
              _obscure ? Icons.visibility_off_rounded : Icons.visibility_rounded,
              size: 20,
              color: NovaColors.textMuted,
            ),
          ),
        ),
        _Field(
          controller: _confirm,
          label: context.tr('auth.confirmPassword'),
          hint: '••••••••',
          icon: Icons.lock_outline_rounded,
          obscure: _obscure,
          error: _fieldErrors['password_confirmation'],
        ),
        Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            color: NovaColors.accentMist,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.verified_user_rounded,
                size: 18,
                color: NovaColors.accentDeep,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  context.tr('auth.oneSession'),
                  style: NovaTypography.textTheme.bodySmall!.copyWith(
                    color: NovaColors.accentDeep,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    ];
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.label,
    required this.hint,
    this.keyboard,
    this.icon,
    this.obscure = false,
    this.trailing,
    this.error,
    this.formatters,
  });

  final TextEditingController controller;

  /// Input limits, e.g. digits only for the phone.
  final List<TextInputFormatter>? formatters;
  final String label;
  final String hint;
  final TextInputType? keyboard;
  final IconData? icon;
  final bool obscure;
  final Widget? trailing;
  final String? error;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: NovaTypography.textTheme.labelMedium),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: NovaColors.paperCard,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: error == null
                    ? NovaColors.borderOnLight
                    : NovaHue.rose.solid.withValues(alpha: 0.6),
              ),
            ),
            child: Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 19, color: NovaColors.textMuted),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: TextField(
                    controller: controller,
                    obscureText: obscure,
                    keyboardType: keyboard,
                    inputFormatters: formatters,
                    autocorrect: false,
                    style: NovaTypography.textTheme.bodyMedium,
                    decoration: InputDecoration(
                      hintText: hint,
                      hintStyle: NovaTypography.muted(
                        NovaTypography.textTheme.bodyMedium!,
                      ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 15),
                    ),
                  ),
                ),
                ?trailing,
              ],
            ),
          ),
          if (error != null) _FieldError(error!),
        ],
      ),
    );
  }
}

class _FieldError extends StatelessWidget {
  const _FieldError(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6, left: 4),
      child: Text(
        text,
        style: NovaTypography.textTheme.labelSmall!.copyWith(
          color: NovaHue.rose.onSurface,
        ),
      ),
    );
  }
}

/// A labelled dropdown of reference rows (level, filière, wilaya, commune).
class RefPickerField extends StatelessWidget {
  const RefPickerField({
    super.key,
    required this.label,
    required this.value,
    required this.options,
    required this.icon,
    required this.onChanged,
    this.enabled = true,
    this.emptyHint,
    this.error,
  });

  final String label;
  final RefItem? value;
  final List<RefItem> options;
  final IconData icon;
  final ValueChanged<RefItem?> onChanged;
  final bool enabled;
  final String? emptyHint;
  final String? error;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: NovaTypography.textTheme.labelMedium),
          const SizedBox(height: 8),
          AnimatedOpacity(
            duration: const Duration(milliseconds: 200),
            opacity: enabled ? 1 : 0.55,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: NovaColors.paperCard,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: error == null
                      ? NovaColors.borderOnLight
                      : NovaHue.rose.solid.withValues(alpha: 0.6),
                ),
              ),
              child: Row(
                children: [
                  Icon(icon, size: 19, color: NovaColors.textMuted),
                  const SizedBox(width: 10),
                  Expanded(
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<int>(
                        value: value?.id,
                        isExpanded: true,
                        borderRadius: BorderRadius.circular(16),
                        hint: Text(
                          emptyHint ?? context.tr('auth.select'),
                          style: NovaTypography.muted(
                            NovaTypography.textTheme.bodyMedium!,
                          ),
                        ),
                        icon: Icon(
                          Icons.expand_more_rounded,
                          size: 21,
                          color: NovaColors.textMuted,
                        ),
                        items: options
                            .map(
                              (RefItem option) => DropdownMenuItem<int>(
                                value: option.id,
                                child: Text(
                                  option.name,
                                  overflow: TextOverflow.ellipsis,
                                  style: NovaTypography.textTheme.bodyMedium,
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: enabled
                            ? (int? id) => onChanged(
                                  options
                                      .where((RefItem o) => o.id == id)
                                      .firstOrNull,
                                )
                            : null,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (error != null) _FieldError(error!),
        ],
      ),
    );
  }
}
