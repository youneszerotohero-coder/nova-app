import 'package:flutter/material.dart';

import '../../core/api/api_error_text.dart';
import '../../core/api/api_exception.dart';
import '../../core/i18n/nova_strings.dart';
import '../../core/state/app_state.dart';
import '../../core/theme/nova_colors.dart';
import '../../core/theme/nova_typography.dart';
import '../../core/widgets/page_scaffold.dart';
import '../../core/widgets/pressable_scale.dart';
import '../auth/otp_widgets.dart';

/// D-118: the Student deletes their own account after typing their
/// password. The server erases the identity and learning data and closes
/// the account; the root gate then returns to sign-in.
class DeleteAccountScreen extends StatefulWidget {
  const DeleteAccountScreen({super.key});

  @override
  State<DeleteAccountScreen> createState() => _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends State<DeleteAccountScreen> {
  final TextEditingController _password = TextEditingController();
  bool _obscure = true;
  bool _busy = false;
  String? _error;
  String? _passwordError;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _delete() async {
    if (_password.text.isEmpty) {
      setState(() => _passwordError = context.tr('deleteAccount.passwordRequired'));
      return;
    }
    final AppState app = AppScope.of(context);
    setState(() {
      _busy = true;
      _error = null;
      _passwordError = null;
    });
    try {
      await app.session.deleteAccount(_password.text);
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        if (error.code == ApiException.validationFailed && error.fieldErrors.containsKey('password')) {
          _passwordError = context.tr('deleteAccount.wrongPassword');
        } else {
          _error = apiErrorText(context, error);
        }
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final TextStyle body = NovaTypography.textTheme.bodyMedium!.copyWith(color: NovaColors.textStrong);
    return PageScaffold(
      title: context.tr('deleteAccount.title'),
      kicker: context.tr('settings.title'),
      watermark: Icons.person_remove_outlined,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
        children: [
          NovaSectionCard(
            icon: Icons.warning_amber_rounded,
            hue: NovaHue.rose,
            title: context.tr('deleteAccount.whatHappens'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final String key in const <String>[
                  'deleteAccount.erased',
                  'deleteAccount.access',
                  'deleteAccount.payments',
                  'deleteAccount.final',
                ])
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 7),
                          child: Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                              color: NovaColors.heartRed,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(child: Text(context.tr(key), style: body)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          NovaCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AuthTextField(
                  controller: _password,
                  icon: Icons.lock_outline_rounded,
                  label: context.tr('deleteAccount.passwordLabel'),
                  hint: '••••••••',
                  obscure: _obscure,
                  autofill: AutofillHints.password,
                  error: _passwordError,
                  enabled: !_busy,
                  trailing: PasswordVisibilityToggle(
                    obscure: _obscure,
                    onToggle: () => setState(() => _obscure = !_obscure),
                  ),
                  onSubmitted: (_) => _delete(),
                ),
                if (_error != null) AuthMessage(_error!),
                PressableScale(
                  onTap: _busy ? null : _delete,
                  semanticLabel: context.tr('deleteAccount.confirm'),
                  child: Container(
                    height: 54,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: NovaColors.heartRed,
                      borderRadius: BorderRadius.circular(100),
                    ),
                    child: _busy
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                          )
                        : Text(
                            context.tr('deleteAccount.confirm'),
                            style: const TextStyle(
                              fontFamily: 'Inter',
                              fontWeight: FontWeight.w700,
                              fontSize: 14.5,
                              color: Colors.white,
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
