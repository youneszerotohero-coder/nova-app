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
    final String? fieldError = _fieldError;
    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          AuthHero(
            title: context.tr('phone.title'),
            subtitle: context.tr('phone.desc'),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 26, 24, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  context.tr('auth.phoneLabel'),
                  style: NovaTypography.textTheme.labelMedium,
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: NovaColors.paperCard,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: fieldError == null && !_taken
                          ? NovaColors.borderOnLight
                          : NovaHue.rose.solid.withValues(alpha: 0.6),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.phone_rounded,
                        size: 19,
                        color: NovaColors.textMuted,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: _phone,
                          keyboardType: TextInputType.phone,
                          textInputAction: TextInputAction.done,
                          autocorrect: false,
                          onChanged: (_) {
                            if (_taken) setState(() => _taken = false);
                          },
                          onSubmitted: (_) => _submit(),
                          style: NovaTypography.textTheme.bodyMedium,
                          decoration: InputDecoration(
                            hintText: '05 xx xx xx xx',
                            hintStyle: NovaTypography.muted(
                              NovaTypography.textTheme.bodyMedium!,
                            ),
                            border: InputBorder.none,
                            contentPadding:
                                const EdgeInsets.symmetric(vertical: 15),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (fieldError != null)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(top: 6, start: 4),
                    child: Text(
                      fieldError,
                      style: NovaTypography.textTheme.labelSmall!.copyWith(
                        color: NovaHue.rose.onSurface,
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                if (_taken || _error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: Text(
                      _taken ? context.tr('phone.taken') : _error!,
                      style: NovaTypography.textTheme.bodySmall!.copyWith(
                        color: NovaHue.rose.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                PressableScale(
                  onTap: _busy ? null : _submit,
                  pressedScale: 0.97,
                  semanticLabel: context.tr('phone.save'),
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
                            context.tr('phone.save'),
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
                    child: Padding(
                      padding: const EdgeInsets.all(8),
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
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
