import 'package:flutter/material.dart';

import '../../core/api/api_error_text.dart';
import '../../core/api/api_exception.dart';
import '../../core/i18n/nova_strings.dart';
import '../../core/state/app_state.dart';
import '../../core/theme/nova_colors.dart';
import '../../core/theme/nova_typography.dart';
import '../../core/utils/phone.dart';
import '../../core/widgets/pressable_scale.dart';
import 'auth_hero.dart';

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
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          AuthHero(
            title: context.tr('auth.newPasswordTitle'),
            subtitle: context.tr('auth.newPasswordSub'),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 26, 24, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (TextEditingController c, String key, String? fieldError)
                    in <(TextEditingController, String, String?)>[
                  (_password, 'auth.password', _fieldErrors['password']),
                  (_confirm, 'auth.confirmPassword', _fieldErrors['password_confirmation']),
                ])
                  Padding(
                    padding: const EdgeInsets.only(bottom: 15),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.tr(key),
                          style: NovaTypography.textTheme.labelMedium,
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          decoration: BoxDecoration(
                            color: NovaColors.paperCard,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: fieldError == null
                                  ? NovaColors.borderOnLight
                                  : NovaHue.rose.solid.withValues(alpha: 0.6),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.lock_outline_rounded,
                                size: 19,
                                color: NovaColors.textMuted,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: TextField(
                                  controller: c,
                                  obscureText: _obscure,
                                  autocorrect: false,
                                  style: NovaTypography.textTheme.bodyMedium,
                                  decoration: InputDecoration(
                                    hintText: context.tr('auth.passwordHint'),
                                    hintStyle: NovaTypography.muted(
                                      NovaTypography.textTheme.bodyMedium!,
                                    ),
                                    border: InputBorder.none,
                                    contentPadding:
                                        const EdgeInsets.symmetric(vertical: 15),
                                  ),
                                ),
                              ),
                              if (c == _password)
                                PressableScale(
                                  onTap: () =>
                                      setState(() => _obscure = !_obscure),
                                  semanticLabel: 'Show password',
                                  child: Icon(
                                    _obscure
                                        ? Icons.visibility_off_rounded
                                        : Icons.visibility_rounded,
                                    size: 20,
                                    color: NovaColors.textMuted,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        if (fieldError != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 6, left: 4),
                            child: Text(
                              fieldError,
                              style: NovaTypography.textTheme.labelSmall!.copyWith(
                                color: NovaHue.rose.onSurface,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
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
                PressableScale(
                  onTap: _busy ? null : _submit,
                  pressedScale: 0.97,
                  semanticLabel: 'Save password',
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
                            context.tr('auth.savePassword'),
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontWeight: FontWeight.w700,
                              fontSize: 15.5,
                              color: NovaColors.textOnDark,
                            ),
                          ),
                  ),
                ),
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
              ],
            ),
          ),
        ],
      ),
    );
  }
}
