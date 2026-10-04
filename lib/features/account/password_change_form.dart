import 'package:flutter/material.dart';

import '../../core/api/api_error_text.dart';
import '../../core/api/api_exception.dart';
import '../../core/i18n/nova_strings.dart';
import '../../core/state/app_state.dart';
import '../../core/theme/nova_colors.dart';
import '../../core/theme/nova_typography.dart';
import '../../core/utils/phone.dart';
import '../../data/otp.dart';
import '../auth/otp_widgets.dart';

/// D-093: the Student changes their password with a code sent to their
/// own number by SMS or WhatsApp, as they choose (D-096); no current
/// password. This device stays signed in, every other one is signed out.
class PasswordChangeForm extends StatefulWidget {
  const PasswordChangeForm({super.key, required this.phone});

  final String phone;

  @override
  State<PasswordChangeForm> createState() => _PasswordChangeFormState();
}

class _PasswordChangeFormState extends State<PasswordChangeForm>
    with ResendCountdown<PasswordChangeForm> {
  final TextEditingController _code = TextEditingController();
  final TextEditingController _password = TextEditingController();
  final TextEditingController _confirm = TextEditingController();

  OtpChannel _channel = OtpChannel.sms;
  String _challengeId = '';
  bool _obscure = true;
  bool _busy = false;
  String? _error;
  String? _status;
  Map<String, String> _fieldErrors = const <String, String>{};

  @override
  void dispose() {
    _code.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    final AppState app = AppScope.of(context);
    await _run(() async {
      final OtpChallenge challenge =
          await app.session.requestPasswordChangeCode(_channel, app.lang.name);
      if (!mounted) return;
      setState(() {
        _challengeId = challenge.id;
        _status = context.trf('security.codeSent', <String, String>{
          'phone': '\u2066${widget.phone}\u2069',
          'channel': otpChannelName(context, _channel),
        });
      });
      startResend(challenge.resendIn);
    });
  }

  Future<void> _save() async {
    final String password = _password.text;
    final Map<String, String> local = <String, String>{
      if (!isOtpCode(_code.text)) 'code': context.tr('otp.codeFormat'),
      if (password.length < 8)
        'password': context.tr('pwd.short')
      else if (isSamePhone(password, widget.phone))
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
      await app.session.changePasswordWithCode(
        challengeId: _challengeId,
        code: _code.text,
        password: password,
        confirmation: _confirm.text,
      );
      if (!mounted) return;
      _code.clear();
      _password.clear();
      _confirm.clear();
      setState(() {
        _challengeId = '';
        _status = context.tr('security.changed');
      });
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
      _status = null;
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
        _error = fields.isNotEmpty
            ? null
            : error.status >= 500
                ? context.tr('security.unavailable')
                : apiErrorText(context, error);
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          context.tr('security.changeDesc'),
          style: NovaTypography.muted(NovaTypography.textTheme.bodySmall!),
        ),
        const SizedBox(height: 14),
        if (_challengeId.isEmpty) ...[
          OtpChannelChoice(
            value: _channel,
            enabled: !_busy,
            onChanged: (OtpChannel channel) => setState(() => _channel = channel),
          ),
          if (_error != null) AuthMessage(_error!),
          if (_status != null) AuthMessage(_status!, error: false),
          AuthSubmitButton(
            busy: _busy,
            label: resendLabel(context, resendIn, idleKey: 'security.sendCode'),
            onTap: resendIn > 0 ? null : _sendCode,
          ),
        ] else ...[
          if (_status != null) AuthMessage(_status!, error: false),
          AuthTextField.code(
            controller: _code,
            label: context.tr('otp.codeLabel'),
            error: _fieldErrors['code'],
          ),
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
            onSubmitted: (_) => _save(),
          ),
          if (_error != null) AuthMessage(_error!),
          AuthSubmitButton(busy: _busy, label: context.tr('security.save'), onTap: _save),
          const SizedBox(height: 8),
          Center(
            child: AuthTextAction(
              label: resendLabel(context, resendIn),
              onTap: _busy || resendIn > 0 ? null : _sendCode,
            ),
          ),
        ],
        const SizedBox(height: 12),
        Text(
          context.tr('settings.securityNote'),
          style: NovaTypography.textTheme.labelSmall!.copyWith(color: NovaColors.textMuted),
        ),
      ],
    );
  }
}
