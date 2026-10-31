import 'package:flutter/material.dart';

import '../../core/api/api_error_text.dart';
import '../../core/api/api_exception.dart';
import '../../core/i18n/nova_strings.dart';
import '../../core/state/app_state.dart';
import '../../core/theme/nova_colors.dart';
import '../../core/theme/nova_typography.dart';
import '../../core/utils/phone.dart';
import '../auth/otp_widgets.dart';

/// D-182: the Student changes their password with their current password
/// (no SMS code, D-093 sent one). This device stays signed in, every other
/// one is signed out.
class PasswordChangeForm extends StatefulWidget {
  const PasswordChangeForm({super.key, required this.phone});

  final String phone;

  @override
  State<PasswordChangeForm> createState() => _PasswordChangeFormState();
}

class _PasswordChangeFormState extends State<PasswordChangeForm> {
  final TextEditingController _current = TextEditingController();
  final TextEditingController _password = TextEditingController();
  final TextEditingController _confirm = TextEditingController();

  bool _obscure = true;
  bool _busy = false;
  String? _error;
  String? _status;
  Map<String, String> _fieldErrors = const <String, String>{};

  @override
  void dispose() {
    _current.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final String password = _password.text;
    final Map<String, String> local = <String, String>{
      if (_current.text.isEmpty) 'current_password': context.tr('security.currentRequired'),
      if (password.length < 8)
        'password': context.tr('pwd.short')
      else if (isSamePhone(password, widget.phone))
        'password': context.tr('pwd.samePhone')
      else if (_confirm.text != password)
        'password_confirmation': context.tr('pwd.mismatch'),
    };
    setState(() {
      _error = null;
      _status = null;
      _fieldErrors = local;
    });
    if (local.isNotEmpty) return;
    final AppState app = AppScope.of(context);
    setState(() => _busy = true);
    try {
      await app.session.changeOwnPassword(currentPassword: _current.text, password: password, confirmation: _confirm.text);
      if (!mounted) return;
      _current.clear();
      _password.clear();
      _confirm.clear();
      setState(() => _status = context.tr('security.changed'));
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        final Map<String, String> fields = error.code == ApiException.validationFailed
            ? <String, String>{
                ...error.fieldErrors,
                if (error.fieldErrors.containsKey('current_password'))
                  'current_password': context.tr('security.currentWrong'),
              }
            : const <String, String>{};
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
        // `.accountPasswordIntro`: the key and one line.
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(Icons.key_rounded, size: 16, color: NovaColors.accent),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                context.tr('security.changeCurrentDesc'),
                style: NovaTypography.textTheme.bodyMedium!.copyWith(color: NovaColors.textBody, fontSize: 14),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        AuthTextField(
          controller: _current,
          icon: Icons.lock_outline_rounded,
          label: context.tr('security.currentPassword'),
          hint: '••••••••',
          obscure: _obscure,
          autofill: AutofillHints.password,
          error: _fieldErrors['current_password'],
          trailing: PasswordVisibilityToggle(
            obscure: _obscure,
            onToggle: () => setState(() => _obscure = !_obscure),
          ),
        ),
        AuthTextField(
          controller: _password,
          icon: Icons.lock_outline_rounded,
          label: context.tr('forgot.newPassword'),
          hint: context.tr('auth.passwordHint'),
          obscure: _obscure,
          autofill: AutofillHints.newPassword,
          error: _fieldErrors['password'],
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
        if (_status != null) AuthMessage(_status!, error: false),
        AuthSubmitButton(busy: _busy, label: context.tr('security.save'), onTap: _save),
        const SizedBox(height: 10),
        Text(
          context.tr('settings.securityNote'),
          style: NovaTypography.textTheme.bodySmall!.copyWith(color: NovaColors.textMuted),
        ),
      ],
    );
  }
}
