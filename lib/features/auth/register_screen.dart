import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api/api_error_text.dart';
import '../../core/api/api_exception.dart';
import '../../core/api/nova_api.dart';
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
import 'login_screen.dart';
import 'otp_widgets.dart';

/// Registration: first/last name, unique phone, school level, filière
/// (the level's own, D-098), cascading wilaya → commune pickers, password
/// rules — exactly the conception's required fields, validated by the
/// backend. While the Admin switch is on (D-093/D-096) the phone is
/// verified by a code before the account is created.
///
/// Two steps, as on the website: the account (names, phone, password),
/// then the school details, the phone code and the acceptance of the
/// terms and the privacy policy (D-122).
///
/// With [onboarding] the same form completes an imported Student's
/// academic identity (`PUT /onboarding`): no phone or password.
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key, this.onboarding = false, this.fromSignIn = false});

  final bool onboarding;

  /// Opened from sign-in: "Already have an account?" goes back to it;
  /// otherwise (the gateway, D-133) it opens sign-in in its place.
  final bool fromSignIn;

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

  /// 0: account, 1: school details (registration only).
  int _step = 0;

  /// D-122: the terms and the privacy policy are accepted before the
  /// account is created.
  bool _acceptedTerms = false;
  late final TapGestureRecognizer _termsTap = TapGestureRecognizer()..onTap = () => _openLegal('/terms');
  late final TapGestureRecognizer _privacyTap = TapGestureRecognizer()..onTap = () => _openLegal('/privacy');

  /// Fields of the account step; an error on any of them shows that step.
  static const Set<String> _accountFields = <String>{
    'first_name',
    'last_name',
    'phone',
    'password',
    'password_confirmation',
  };

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

  /// The website's legal pages, in the browser.
  Future<void> _openLegal(String path) async {
    final Uri site = Uri.parse(NovaApi.defaultBaseUrl);
    await launchUrl(site.replace(path: path, query: null), mode: LaunchMode.externalApplication);
  }

  @override
  void dispose() {
    _termsTap.dispose();
    _privacyTap.dispose();
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
          _step = 0;
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
  Map<String, String> _localErrors() => <String, String>{
        ..._accountErrors(),
        ..._schoolErrors(),
      };

  /// The account step: names, then (registration) phone and password.
  Map<String, String> _accountErrors() {
    final String required = context.tr('auth.fieldRequired');
    final Map<String, String> errors = <String, String>{
      if (_first.text.trim().isEmpty) 'first_name': required,
      if (_last.text.trim().isEmpty) 'last_name': required,
    };
    if (!widget.onboarding) {
      if (!_strictMobile.hasMatch(_phone.text.trim())) errors['phone'] = context.tr('auth.phoneStrict');
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

  /// The school step: level, filière, wilaya and commune.
  Map<String, String> _schoolErrors() {
    final String required = context.tr('auth.fieldRequired');
    return <String, String>{
      if (_level == null) 'level_id': required,
      if (_trackEnabled && _track == null) 'track_id': required,
      if (_wilaya == null) 'wilaya_id': required,
      if (_commune == null) 'commune_id': required,
    };
  }

  /// Step 1 → 2, checked here only: the account is created at the end.
  void _next() {
    final Map<String, String> errors = _accountErrors();
    setState(() {
      _phoneTaken = false;
      _fieldErrors = errors;
      _error = errors.isEmpty ? null : context.tr('auth.checkFields');
      if (errors.isEmpty) _step = 1;
    });
  }

  /// Shows the step holding a server field error.
  void _showStepOf(Map<String, String> errors) {
    if (!widget.onboarding && errors.keys.any(_accountFields.contains)) _step = 0;
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
        _showStepOf(local);
      });
      return;
    }
    if (!widget.onboarding && !_acceptedTerms) {
      setState(() => _error = context.tr('auth.termsRequired'));
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
        setState(() {
          _phoneTaken = true;
          _step = 0;
        });
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
        _showStepOf(error.fieldErrors);
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NovaColors.paperCard,
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          AuthHero(
            showBack: !widget.onboarding,
            top: widget.onboarding ? null : _steps(),
            title: context.tr(
              widget.onboarding ? 'auth.onboardingTitle' : 'auth.createAccount',
            ),
            subtitle: context.tr(
              widget.onboarding ? 'auth.onboardingSub' : 'auth.createSubtitle',
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 24, 18, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ...stagger(
                  _form(),
                  step: const Duration(milliseconds: 45),
                ),
                if (_error != null) AuthMessage(_error!),
                if (_phoneTaken) _phoneTakenNotice(),
                if (!widget.onboarding && _step == 0)
                  AuthSubmitButton(label: context.tr('auth.nextStep'), busy: false, onTap: _next)
                else
                  Row(
                    children: [
                      // `.authStepActions`: "Previous" takes .42 of the row.
                      if (!widget.onboarding) ...[
                        Expanded(
                          flex: 42,
                          child: AuthOutlineButton(
                            label: context.tr('auth.previous'),
                            icon: Icons.arrow_back_rounded,
                            onTap: _busy ? null : () => setState(() => _step = 0),
                          ),
                        ),
                        const SizedBox(width: 10),
                      ],
                      Expanded(
                        flex: 100,
                        child: AuthSubmitButton(
                          label: context.tr(widget.onboarding ? 'auth.saveDetails' : 'auth.createSpace'),
                          busy: _busy,
                          onTap: _submit,
                        ),
                      ),
                    ],
                  ),
                if (!widget.onboarding) ...[
                  const SizedBox(height: 12),
                  // The website's line under the form: "Already have an account? Sign in".
                  AuthModeSwitch(
                    signIn: false,
                    onSwitch: () => widget.fromSignIn
                        ? Navigator.of(context).maybePop()
                        : Navigator.of(context).pushReplacement(
                            MaterialPageRoute<void>(builder: (_) => const LoginScreen(showBack: true)),
                          ),
                  ),
                ],
                if (widget.onboarding) ...[
                  const SizedBox(height: 10),
                  Center(
                    child: AuthTextAction(
                      label: context.tr('settings.signOut'),
                      onTap: () => AppScope.of(context).session.logout(),
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

  /// `.authSteps`: "1 Account — 2 School details"; the active tile is blue,
  /// turned −6° in its `--hx-blue-soft` ring, the step done shows a check.
  Widget _steps() {
    Widget step(int index, String key) {
      final bool active = _step == index;
      final bool done = _step > index;
      final Color ink = done ? NovaColors.onlineGreen : (active ? NovaColors.textStrong : NovaColors.textMuted);
      final Widget tile = Container(
        width: 34,
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: done ? NovaColors.liveBg : (active ? NovaColors.accent : NovaColors.paperRaised),
          borderRadius: BorderRadius.circular(11),
          boxShadow: active ? [BoxShadow(spreadRadius: 5, color: NovaColors.accentMist)] : null,
        ),
        child: done
            ? Icon(Icons.check_rounded, size: 14, color: NovaColors.onlineGreen)
            : Text(
                '${index + 1}',
                style: TextStyle(
                  fontFamily: NovaTypography.display,
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                  height: 1,
                  color: active ? Colors.white : NovaColors.textMuted,
                ),
              ),
      );
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          active ? Transform.rotate(angle: -0.105, child: tile) : tile,
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              context.tr(key),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: NovaTypography.display,
                fontFamilyFallback: NovaTypography.fallback,
                fontWeight: FontWeight.w800,
                fontSize: 14,
                color: ink,
              ),
            ),
          ),
        ],
      );
    }

    return Row(
      children: [
        Expanded(
          child: Row(
            children: [
              Flexible(child: step(0, 'auth.stepAccount')),
              const SizedBox(width: 6),
              Container(width: 10, height: 3, decoration: BoxDecoration(color: NovaColors.lineStrong, borderRadius: BorderRadius.circular(3))),
            ],
          ),
        ),
        const SizedBox(width: 20),
        Expanded(child: Align(alignment: AlignmentDirectional.centerStart, child: step(1, 'auth.stepSchool'))),
      ],
    );
  }

  /// The outlined buttons of the phone code (`.authBack` in
  /// `.authStepActions`).
  Widget _codeButton({required String label, required VoidCallback? onTap}) => AuthOutlineButton(label: label, onTap: onTap);

  /// D-122: the checkbox, with the terms and the privacy policy opening
  /// the website's pages.
  Widget _termsAcceptance() {
    final TextStyle base = TextStyle(
      fontFamily: NovaTypography.body,
      fontFamilyFallback: NovaTypography.fallback,
      fontSize: 15,
      height: 1.55,
      color: NovaColors.textBody,
    );
    final TextStyle link = base.copyWith(
      fontFamily: NovaTypography.display,
      color: NovaColors.accent,
      fontWeight: FontWeight.w800,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 32,
            height: 32,
            child: Checkbox(
              value: _acceptedTerms,
              activeColor: NovaColors.accent,
              side: BorderSide(color: NovaColors.lineStrong, width: 1.5),
              onChanged: (bool? value) => setState(() {
                _acceptedTerms = value ?? false;
                if (_acceptedTerms && _error == context.tr('auth.termsRequired')) _error = null;
              }),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text.rich(
                TextSpan(
                  style: base,
                  children: [
                    TextSpan(text: '${context.tr('auth.termsAccept')} '),
                    TextSpan(text: context.tr('auth.termsLink'), style: link, recognizer: _termsTap),
                    TextSpan(text: ' ${context.tr('auth.termsAnd')} '),
                    TextSpan(text: context.tr('auth.privacyLink'), style: link, recognizer: _privacyTap),
                    const TextSpan(text: '.'),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The website's "sign in instead" error (`.authError.authLoadError`);
  /// its button goes back to the sign-in screen with the number typed here.
  Widget _phoneTakenNotice() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
        decoration: BoxDecoration(color: NovaColors.dangerBg, borderRadius: BorderRadius.circular(14)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.tr('auth.phoneTaken'),
              style: TextStyle(
                fontFamily: NovaTypography.body,
                fontFamilyFallback: NovaTypography.fallback,
                fontWeight: FontWeight.w600,
                fontSize: 15,
                height: 1.5,
                color: NovaColors.heartRed,
              ),
            ),
            const SizedBox(height: 10),
            PressableScale(
              onTap: () => Navigator.of(context).maybePop<String>(_phone.text.trim()),
              semanticLabel: 'Sign in with this number',
              child: Container(
                constraints: const BoxConstraints(minHeight: 44),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: NovaColors.heartRed),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      context.tr('auth.signInInstead'),
                      style: TextStyle(
                        fontFamily: NovaTypography.display,
                        fontFamilyFallback: NovaTypography.fallback,
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        color: NovaColors.heartRed,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// D-093/D-096 (`RegisterPhoneVerification`): the channel, "send the
  /// code", then the 6-digit code, for the number typed above; another
  /// number needs a new code.
  List<Widget> _phoneVerification() {
    final String phone = _phone.text.trim();
    final bool codeSent = _challengeId.isNotEmpty && _challengePhone == phone;
    if (_phoneVerified) return <Widget>[AuthNotice(context.tr('auth.phoneVerified'))];
    return <Widget>[
      AuthGroupLegend(context.tr('auth.verifyPhone')),
      AuthMessage(
        codeSent
            ? context.trf('auth.verifyCodeSent', <String, String>{
                'phone': '\u2066$phone\u2069',
                'channel': otpChannelName(context, _channel),
              })
            : context.trf('auth.verifyPhoneDesc', <String, String>{
                'phone': '\u2066${phone.isEmpty ? '05xxxxxxxx' : phone}\u2069',
              }),
        error: false,
      ),
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
      Padding(
        padding: const EdgeInsets.only(bottom: 18),
        child: Row(
          children: [
            Expanded(
              child: _codeButton(
                label: resendLabel(
                  context,
                  resendIn,
                  idleKey: codeSent ? 'otp.resend' : 'otp.sendCode',
                ),
                onTap: _codeBusy || resendIn > 0 ? null : _sendCode,
              ),
            ),
            if (codeSent) ...[
              const SizedBox(width: 10),
              Expanded(
                child: _codeButton(
                  label: context.tr('otp.verify'),
                  onTap: _codeBusy ? null : _verifyCode,
                ),
              ),
            ],
          ],
        ),
      ),
      if (_codeBusy)
        Padding(
          padding: const EdgeInsets.only(bottom: 18),
          child: Center(
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: NovaColors.accent),
            ),
          ),
        ),
    ];
  }

  List<Widget> _form() {
    if (widget.onboarding) {
      return <Widget>[
        AuthGroupLegend(context.tr('auth.groupPersonal')),
        ..._nameFields(),
        ..._schoolFields(),
      ];
    }
    if (_step == 0) {
      return <Widget>[
        AuthGroupLegend(context.tr('auth.groupPersonal')),
        ..._nameFields(),
        ..._phoneAndPassword(),
      ];
    }
    return <Widget>[
      ..._schoolFields(),
      if (_verificationRequired) ..._phoneVerification(),
      _termsAcceptance(),
    ];
  }

  List<Widget> _nameFields() {
    return [
      _Field(
        controller: _first,
        label: context.tr('auth.firstName'),
        hint: '',
        icon: Icons.person_outline_rounded,
        error: _fieldErrors['first_name'],
      ),
      _Field(
        controller: _last,
        label: context.tr('auth.lastName'),
        hint: '',
        icon: Icons.person_outline_rounded,
        error: _fieldErrors['last_name'],
      ),
    ];
  }

  /// Registration step 1 after the names: phone and password.
  List<Widget> _phoneAndPassword() {
    return [
        _Field(
          controller: _phone,
          label: context.tr('auth.phoneLabel'),
          // D-081: exactly as typed at sign-in, 05XXXXXXXX.
          hint: '05xxxxxxxx',
          keyboard: TextInputType.number,
          formatters: <TextInputFormatter>[
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(10),
          ],
          icon: Icons.phone_outlined,
          error: _fieldErrors['phone'],
        ),
        AuthGroupLegend(context.tr('auth.groupSecure')),
        ..._passwordFields(),
    ];
  }

  List<Widget> _schoolFields() {
    return [
      AuthGroupLegend(context.tr('auth.groupAcademic')),
      RefPickerField(
        label: context.tr('auth.level'),
        value: _level,
        options: _levels,
        icon: Icons.school_outlined,
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
        icon: Icons.school_outlined,
        enabled: _trackEnabled,
        emptyHint: _trackEnabled ? null : context.tr('auth.trackNotRequired'),
        error: _fieldErrors['track_id'],
        onChanged: (RefItem? value) => setState(() => _track = value),
      ),
      AuthGroupLegend(context.tr('auth.groupLocation')),
      RefPickerField(
        label: context.tr('settings.wilaya'),
        value: _wilaya,
        options: _wilayas,
        icon: Icons.location_on_outlined,
        error: _fieldErrors['wilaya_id'],
        onChanged: _pickWilaya,
      ),
      RefPickerField(
        label: context.tr('settings.commune'),
        value: _commune,
        options: _communes,
        icon: Icons.location_on_outlined,
        enabled: _wilaya != null,
        emptyHint: _wilaya == null ? context.tr('auth.pickWilaya') : null,
        error: _fieldErrors['commune_id'],
        onChanged: (RefItem? value) => setState(() => _commune = value),
      ),
    ];
  }

  List<Widget> _passwordFields() {
    final Widget eye = PasswordVisibilityToggle(
      obscure: _obscure,
      onToggle: () => setState(() => _obscure = !_obscure),
    );
    return [
        _Field(
          controller: _password,
          label: context.tr('auth.password'),
          hint: context.tr('auth.passwordHint'),
          icon: Icons.lock_outline_rounded,
          obscure: _obscure,
          error: _fieldErrors['password'],
          trailing: eye,
        ),
        _Field(
          controller: _confirm,
          label: context.tr('auth.confirmPassword'),
          hint: context.tr('auth.passwordHint'),
          icon: Icons.lock_outline_rounded,
          obscure: _obscure,
          error: _fieldErrors['password_confirmation'],
          trailing: eye,
        ),
        AuthMessage(context.tr('auth.oneSession'), error: false),
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
    return AuthFieldFrame(
      label: label,
      icon: icon,
      trailing: trailing,
      error: error,
      child: TextField(
        controller: controller,
        obscureText: obscure,
        keyboardType: keyboard,
        inputFormatters: formatters,
        autocorrect: false,
        style: authInputStyle,
        decoration: authInputDecoration(hint),
      ),
    );
  }
}

/// A labelled dropdown of reference rows (level, filière, wilaya, commune),
/// in the website's auth field (`.nvsTrigger` in `.authForm`).
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
    return AuthFieldFrame(
      label: label,
      icon: icon,
      error: error,
      enabled: enabled,
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: value?.id,
          isExpanded: true,
          dropdownColor: NovaColors.paperCard,
          borderRadius: BorderRadius.circular(16),
          hint: Text(emptyHint ?? context.tr('auth.select'), style: authHintStyle),
          icon: Icon(Icons.expand_more_rounded, size: 21, color: NovaColors.textMuted),
          items: options
              .map(
                (RefItem option) => DropdownMenuItem<int>(
                  value: option.id,
                  child: Text(option.name, overflow: TextOverflow.ellipsis, style: authInputStyle),
                ),
              )
              .toList(),
          onChanged: enabled
              ? (int? id) => onChanged(options.where((RefItem o) => o.id == id).firstOrNull)
              : null,
        ),
      ),
    );
  }
}
