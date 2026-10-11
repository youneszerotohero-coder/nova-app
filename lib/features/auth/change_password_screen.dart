import 'package:flutter/material.dart';

import '../../core/api/api_error_text.dart';
import '../../core/api/api_exception.dart';
import '../../core/i18n/nova_strings.dart';
import '../../core/state/app_state.dart';
import '../../core/theme/nova_colors.dart';
import '../../core/utils/phone.dart';
import 'auth_hero.dart';
import 'otp_widgets.dart';

/// Required first step for a school-imported Student: the backend
/// blocks every route with `PASSWORD_CHANGE_REQUIRED` until a new
/// password is set (`POST /auth/change-password`).
class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final TextEditingController _password = TextEditingController();
  final TextEditingController _confirm = TextEditingController();
  bool _obscure = true;
  bool _busy = false;
  String? _error;

  /// `password` / `password_confirmation`: the local rules below, or the
  /// server's own field errors (it stays authoritative).
  Map<String, String> _fieldErrors = const <String, String>{};

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  /// The website's rules (D-078), explained before asking the server:
  /// 8 characters, not the phone number in any spelling, confirmed.
  Map<String, String> _localErrors() {
    final String password = _password.text;
    final String phone = AppScope.of(context).session.profile?.phone ?? '';
    final Map<String, String> errors = <String, String>{};
    if (password.length < 8) {
      errors['password'] = context.tr('pwd.short');
    } else if (phone.isNotEmpty && isSamePhone(password, phone)) {
      errors['password'] = context.tr('pwd.samePhone');
    }
    if (!errors.containsKey('password') && _confirm.text != password) {
      errors['password_confirmation'] = context.tr('pwd.mismatch');
    }
    return errors;
  }

  Future<void> _submit() async {
    final Map<String, String> local = _localErrors();
    if (local.isNotEmpty) {
      setState(() {
        _fieldErrors = local;
        _error = null;
      });
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _fieldErrors = const <String, String>{};
    });
    try {
      await AppScope.of(context)
          .session
          .changePassword(_password.text, _confirm.text);
    } on ApiException catch (error) {
      if (!mounted) return;
      final Map<String, String> fields = error.fieldErrors;
      setState(() {
        _fieldErrors = fields;
        _error = fields.containsKey('password') ||
                fields.containsKey('password_confirmation')
            ? null
            : apiErrorText(context, error);
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
            title: context.tr('auth.newPasswordTitle'),
            subtitle: context.tr('auth.newPasswordSub'),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 24, 18, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AuthTextField(
                  controller: _password,
                  icon: Icons.lock_outline_rounded,
                  label: context.tr('auth.password'),
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
                  hint: context.tr('auth.passwordHint'),
                  obscure: _obscure,
                  autofill: AutofillHints.newPassword,
                  error: _fieldErrors['password_confirmation'],
                  onSubmitted: (_) => _submit(),
                ),
                if (_error != null) AuthMessage(_error!),
                AuthSubmitButton(label: context.tr('auth.savePassword'), busy: _busy, onTap: _submit),
                const SizedBox(height: 10),
                Center(
                  child: AuthTextAction(
                    label: context.tr('settings.signOut'),
                    onTap: () => AppScope.of(context).session.logout(),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
