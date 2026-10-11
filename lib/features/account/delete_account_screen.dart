import 'package:flutter/material.dart';

import '../../core/api/api_error_text.dart';
import '../../core/api/api_exception.dart';
import '../../core/i18n/nova_strings.dart';
import '../../core/state/app_state.dart';
import '../../core/theme/nova_colors.dart';
import '../../core/widgets/hero_style.dart';
import '../../core/widgets/nova_page_header.dart';
import '../auth/otp_widgets.dart';
import 'dashboard_card.dart';

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
    final TextStyle body = heroText(15, color: NovaColors.textStrong);
    return Scaffold(
      backgroundColor: NovaColors.paper,
      body: ListView(
        padding: EdgeInsets.only(bottom: 40 + MediaQuery.paddingOf(context).bottom),
        children: [
          NovaPageHeader(
            title: context.tr('deleteAccount.title'),
            kicker: HeroTitle.plain(context.tr('settings.title')),
            showBack: true,
          ),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DashboardCard(
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
                                padding: const EdgeInsets.only(top: 9),
                                child: Container(
                                  width: 6,
                                  height: 6,
                                  decoration: BoxDecoration(color: NovaColors.heartRed, shape: BoxShape.circle),
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
                const SizedBox(height: 18),
                DashboardCard(
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
                      // `.hxBtn--danger`.
                      NovaButton(
                        label: context.tr('deleteAccount.confirm'),
                        variant: NovaButtonVariant.danger,
                        expand: true,
                        loading: _busy,
                        onTap: _delete,
                      ),
                    ],
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
