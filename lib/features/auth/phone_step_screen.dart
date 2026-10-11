import 'package:flutter/material.dart';

import '../../core/api/api_error_text.dart';
import '../../core/api/api_exception.dart';
import '../../core/i18n/nova_strings.dart';
import '../../core/state/app_state.dart';
import '../../core/theme/nova_colors.dart';
import '../../core/utils/phone.dart';
import 'auth_hero.dart';
import 'otp_widgets.dart';

/// Required step for an account without a valid mobile (D-079): the
/// backend answers `PHONE_REQUIRED` everywhere until the Student enters
/// their own number (`PUT /auth/phone`). A number that already has an
/// account is theirs (sign in with it) or a relative's (enter their own).
class PhoneStepScreen extends StatefulWidget {
  const PhoneStepScreen({super.key});

  @override
  State<PhoneStepScreen> createState() => _PhoneStepScreenState();
}

class _PhoneStepScreenState extends State<PhoneStepScreen> {
  final TextEditingController _phone = TextEditingController();
  bool _busy = false;
  bool _taken = false;
  String? _fieldError;
  String? _error;

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    // Any spelling of an Algerian mobile, as on the website; the server
    // normalizes it and stays authoritative.
    if (normalizeAlgerianMobile(_phone.text) == null) {
      setState(() {
        _taken = false;
        _error = null;
        _fieldError = context.tr('auth.phoneInvalid');
      });
      return;
    }
    setState(() {
      _busy = true;
      _taken = false;
      _error = null;
      _fieldError = null;
    });
    try {
      // The gate moves on by itself once the session has a valid mobile.
      await AppScope.of(context).session.updatePhone(_phone.text.trim());
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        if (error.code == 'PHONE_ALREADY_REGISTERED') {
          _taken = true;
        } else if (error.fieldErrors.containsKey('phone')) {
          _fieldError = context.tr('auth.phoneInvalid');
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
    return Scaffold(
      backgroundColor: NovaColors.paperCard,
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          AuthHero(
            title: context.tr('phone.title'),
            subtitle: context.tr('phone.desc'),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 24, 18, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AuthTextField(
                  controller: _phone,
                  icon: Icons.phone_outlined,
                  label: context.tr('auth.phoneLabel'),
                  hint: '05 xx xx xx xx',
                  keyboard: TextInputType.phone,
                  action: TextInputAction.done,
                  error: _fieldError,
                  onChanged: (_) {
                    if (_taken) setState(() => _taken = false);
                  },
                  onSubmitted: (_) => _submit(),
                ),
                if (_taken || _error != null) AuthMessage(_taken ? context.tr('phone.taken') : _error!),
                AuthSubmitButton(label: context.tr('phone.save'), busy: _busy, onTap: _submit),
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
