import 'package:flutter/material.dart';

import '../../core/api/api_error_text.dart';
import '../../core/api/api_exception.dart';
import '../../core/i18n/nova_strings.dart';
import '../../core/state/app_state.dart';
import '../../core/utils/phone.dart';
import '../../data/otp.dart';
import 'auth_hero.dart';
import 'otp_widgets.dart';

enum _Step { phone, code, password }

/// D-093 forgotten password, as on the website: phone and channel (SMS
/// or WhatsApp, D-096) → 6-digit code → new password. The server answers
/// the same whether the number has an account or not, so the screen never
/// says whether it does. Pops with the number once the password is
/// changed, so sign-in can prefill it.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key, this.initialPhone = ''});

  final String initialPhone;

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen>
    with ResendCountdown<ForgotPasswordScreen> {
  late final TextEditingController _phone = TextEditingController(text: widget.initialPhone);
  final TextEditingController _code = TextEditingController();
  final TextEditingController _password = TextEditingController();
  final TextEditingController _confirm = TextEditingController();

  _Step _step = _Step.phone;
  OtpChannel _channel = OtpChannel.sms;
  String _sentTo = '';
  String _challengeId = '';
  String _resetToken = '';
  bool _obscure = true;
  bool _busy = false;
  String? _error;
  Map<String, String> _fieldErrors = const <String, String>{};

  @override
  void dispose() {
    _phone.dispose();
    _code.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _requestCode() async {
    final String? phone = normalizeAlgerianMobile(_phone.text);
    if (phone == null) {
      setState(() {
        _error = null;
        _fieldErrors = <String, String>{'phone': context.tr('auth.phoneInvalid')};
      });
      return;
    }
    final AppState app = AppScope.of(context);
    await _run(() async {
      final OtpChallenge challenge =
          await app.session.requestPasswordReset(phone, _channel, app.lang.name);
      if (!mounted) return;
      _code.clear();
      setState(() {
        _sentTo = phone;
        _challengeId = challenge.id;
        _step = _Step.code;
      });
      startResend(challenge.resendIn);
    });
  }

  Future<void> _verifyCode() async {
    if (!isOtpCode(_code.text)) {
      setState(() => _fieldErrors = <String, String>{'code': context.tr('otp.codeFormat')});
      return;
    }
    final AppState app = AppScope.of(context);
    await _run(() async {
      final String token = await app.session.verifyPasswordReset(_challengeId, _code.text);
      if (!mounted) return;
      setState(() {
        _resetToken = token;
        _step = _Step.password;
      });
    });
  }

  Future<void> _savePassword() async {
    final String password = _password.text;
    final Map<String, String> local = <String, String>{
      if (password.length < 8)
        'password': context.tr('pwd.short')
      else if (isSamePhone(password, _sentTo))
        'password': context.tr('pwd.samePhone')
      else if (_confirm.text != password)
        'password_confirmation': context.tr('pwd.mismatch'),
    };
    if (local.isNotEmpty) {
      setState(() {
        _error = null;
        _fieldErrors = local;
      });
      return;
    }
    final AppState app = AppScope.of(context);
    await _run(() async {
      await app.session.resetPassword(_resetToken, password, _confirm.text);
      // Every session was signed out: sign in again, the number typed.
      if (mounted) Navigator.of(context).pop<String>(_sentTo);
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
      _fieldErrors = const <String, String>{};
    });
    try {
      await action();
    } on ApiException catch (error) {
      if (!mounted) return;
      final int? retryAfter = otpRetryAfter(error);
      if (retryAfter != null) startResend(retryAfter);
      setState(() {
        final Map<String, String> fields =
            error.code == ApiException.validationFailed ? error.fieldErrors : const <String, String>{};
        // A field error is shown next to its field only.
        _fieldErrors = fields;
        _error = fields.isEmpty ? apiErrorText(context, error) : null;
        // The reset step expired: start again from the number.
        if (error.code == 'RESET_TOKEN_INVALID') _step = _Step.phone;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _changeNumber() => setState(() {
        _step = _Step.phone;
        _error = null;
        _fieldErrors = const <String, String>{};
      });

  @override
  Widget build(BuildContext context) {
    final String title = switch (_step) {
      _Step.phone => context.tr('forgot.title'),
      _Step.code => context.tr('forgot.codeTitle'),
      _Step.password => context.tr('forgot.passwordTitle'),
    };
    final String subtitle = switch (_step) {
      _Step.phone => context.tr('forgot.subtitle'),
      _Step.code => context.trf('forgot.codeSent', <String, String>{
          // Kept left-to-right inside Arabic text.
          'phone': '\u2066$_sentTo\u2069',
          'channel': otpChannelName(context, _channel),
        }),
      _Step.password => context.tr('forgot.passwordSubtitle'),
    };
    return Scaffold(
      body: AutofillGroup(
        child: ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            AuthHero(showBack: true, title: title, subtitle: subtitle),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 26, 24, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ..._fields(),
                  if (_error != null) AuthMessage(_error!),
                  const SizedBox(height: 4),
                  AuthSubmitButton(
                    busy: _busy,
                    label: switch (_step) {
                      _Step.phone => context.tr('otp.sendCode'),
                      _Step.code => context.tr('otp.verify'),
                      _Step.password => context.tr('forgot.savePassword'),
                    },
                    onTap: switch (_step) {
                      _Step.phone => _requestCode,
                      _Step.code => _verifyCode,
                      _Step.password => _savePassword,
                    },
                  ),
                  const SizedBox(height: 12),
                  if (_step == _Step.code)
                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      spacing: 12,
                      children: [
                        AuthTextAction(
                          label: resendLabel(context, resendIn),
                          onTap: _busy || resendIn > 0 ? null : _requestCode,
                        ),
                        AuthTextAction(
                          label: context.tr('forgot.changeNumber'),
                          onTap: _busy ? null : _changeNumber,
                        ),
                      ],
                    )
                  else
                    Center(
                      child: AuthTextAction(
                        label: context.tr('forgot.backToLogin'),
                        onTap: () => Navigator.of(context).maybePop(),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _fields() => switch (_step) {
        _Step.phone => <Widget>[
            AuthTextField(
              controller: _phone,
              icon: Icons.phone_rounded,
              label: context.tr('auth.phoneLabel'),
              hint: '05 xx xx xx xx',
              keyboard: TextInputType.phone,
              autofill: AutofillHints.telephoneNumber,
              error: _fieldErrors['phone'],
            ),
            OtpChannelChoice(
              value: _channel,
              enabled: !_busy,
              onChanged: (OtpChannel channel) => setState(() => _channel = channel),
            ),
          ],
        _Step.code => <Widget>[
            AuthTextField.code(
              controller: _code,
              label: context.tr('otp.codeLabel'),
              error: _fieldErrors['code'],
              onSubmitted: (_) => _verifyCode(),
            ),
          ],
        _Step.password => <Widget>[
            AuthTextField(
              controller: _password,
              icon: Icons.lock_outline_rounded,
              label: context.tr('forgot.newPassword'),
              hint: context.tr('auth.passwordHint'),
              obscure: _obscure,
              autofill: AutofillHints.newPassword,
              error: _fieldErrors['password'],
              trailing: PasswordVisibilityToggle(
                obscure: _obscure,
                onToggle: () => setState(() => _obscure = !_obscure),
              ),
            ),
            AuthTextField(
              controller: _confirm,
              icon: Icons.lock_outline_rounded,
              label: context.tr('auth.confirmPassword'),
              hint: '••••••••',
              obscure: _obscure,
              autofill: AutofillHints.newPassword,
              error: _fieldErrors['password_confirmation'],
              onSubmitted: (_) => _savePassword(),
            ),
          ],
      };
}
