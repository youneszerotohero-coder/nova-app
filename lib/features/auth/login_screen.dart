import 'package:flutter/material.dart';

import '../../core/api/api_error_text.dart';
import '../../core/api/api_exception.dart';
import '../../core/state/app_state.dart';
import '../../core/theme/nova_colors.dart';
import '../../data/session_store.dart';
import '../../core/i18n/nova_strings.dart';
import '../../core/theme/nova_typography.dart';
import '../../core/widgets/hero_style.dart';
import '../../core/widgets/motion.dart';
import '../../core/widgets/pressable_scale.dart';
import 'auth_hero.dart';
import 'forgot_password_screen.dart';
import 'register_screen.dart';

/// Split auth screen: brand panel + phone/password sign-in, with the
/// forgotten-password flow by code (D-093).
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.showBack = false, this.initialPhone});

  /// Opened over the app by a visitor (D-127): a back button returns to browsing.
  final bool showBack;

  /// A number registration found already taken: sign in with it.
  final String? initialPhone;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _phone = TextEditingController();
  final TextEditingController _password = TextEditingController();
  bool _obscure = true;
  bool _busy = false;
  String? _error;

  /// Back from a forgotten-password reset: "sign in with the new password".
  bool _passwordReset = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialPhone != null) _phone.text = widget.initialPhone!;
  }

  @override
  void dispose() {
    _phone.dispose();
    _password.dispose();
    super.dispose();
  }

  /// Signs in against `/auth/login`; the root gate swaps to the app
  /// once the session is live, so nothing is pushed from here.
  Future<void> _submit() async {
    if (_phone.text.trim().isEmpty || _password.text.isEmpty) {
      setState(() => _error = context.tr('auth.fillBoth'));
      return;
    }
    final SessionStore session = AppScope.of(context).session;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await session.login(phone: _phone.text, password: _password.text);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = apiErrorText(context, error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// D-093: the forgotten-password flow comes back with the number once
  /// the password is changed; sign-in opens with it typed.
  Future<void> _openForgotPassword() async {
    final String? phone = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        builder: (_) => ForgotPasswordScreen(initialPhone: _phone.text.trim()),
      ),
    );
    if (phone == null || !mounted) return;
    setState(() {
      _phone.text = phone;
      _password.clear();
      _error = null;
      _passwordReset = true;
    });
  }

  /// Registration comes back with the phone when that number already
  /// has an account (409 `PHONE_ALREADY_REGISTERED`): sign in with it.
  Future<void> _openRegister() async {
    final String? phone = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(builder: (_) => const RegisterScreen(fromSignIn: true)),
    );
    if (phone == null || !mounted) return;
    setState(() {
      _phone.text = phone;
      _password.clear();
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          AuthHero(
            showBack: widget.showBack,
            title: context.tr('auth.welcomeBack'),
            subtitle: context.tr('auth.signInSubtitle'),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 26, 24, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (AppScope.of(context).session.endedReason ==
                    ApiException.sessionReplaced)
                  _Banner(text: context.tr('err.sessionReplaced')),
                if (AppScope.of(context).session.endedReason == SessionStore.accountDeleted)
                  _Banner(text: context.tr('deleteAccount.done'), icon: Icons.check_circle_rounded),
                if (_passwordReset)
                  _Banner(text: context.tr('auth.passwordResetDone'), icon: Icons.check_circle_rounded),
                ...stagger(_fields()),
                if (_error != null) _Banner(text: _error!, error: true),
                const SizedBox(height: 8),
                NovaButton(
                  label: context.tr('auth.signIn'),
                  chipIcon: Icons.arrow_forward_rounded,
                  expand: true,
                  loading: _busy,
                  onTap: _submit,
                ),
                const SizedBox(height: 16),
                Center(
                  child: PressableScale(
                    onTap: _openForgotPassword,
                    semanticLabel: 'Forgot password',
                    child: Text(
                      context.tr('auth.forgot'),
                      style: NovaTypography.textTheme.labelLarge!.copyWith(color: NovaColors.accent),
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                // The website's line under the form: "New to Nova? Create an account".
                AuthModeSwitch(signIn: true, onSwitch: _openRegister),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _fields() {
    return [
      _AuthField(
        controller: _phone,
        icon: Icons.phone_rounded,
        label: context.tr('auth.phoneLabel'),
        hint: '05 xx xx xx xx',
        keyboard: TextInputType.phone,
        action: TextInputAction.next,
      ),
      _AuthField(
        controller: _password,
        icon: Icons.lock_outline_rounded,
        label: context.tr('auth.password'),
        hint: '••••••••',
        obscure: _obscure,
        action: TextInputAction.done,
        onSubmitted: (_) => _submit(),
        trailing: PressableScale(
          onTap: () => setState(() => _obscure = !_obscure),
          semanticLabel: 'Show password',
          child: Icon(
            _obscure ? Icons.visibility_off_rounded : Icons.visibility_rounded,
            size: 20,
            color: NovaColors.textMuted,
          ),
        ),
      ),
    ];
  }
}

/// Shared styled auth input.
class _AuthField extends StatelessWidget {
  const _AuthField({
    required this.controller,
    required this.icon,
    required this.label,
    required this.hint,
    this.obscure = false,
    this.keyboard,
    this.trailing,
    this.action,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final TextInputAction? action;
  final ValueChanged<String>? onSubmitted;
  final IconData icon;
  final String label;
  final String hint;
  final bool obscure;
  final TextInputType? keyboard;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: NovaTypography.textTheme.labelLarge),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: NovaColors.paperCard,
              borderRadius: BorderRadius.circular(17),
              border: Border.all(
color: NovaColors.textStrong.withValues(alpha: 0.14), width: 1.5),
            ),
            child: Row(
              children: [
                Icon(icon, size: 20, color: NovaColors.textMuted),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: controller,
                    obscureText: obscure,
                    textInputAction: action,
                    onSubmitted: onSubmitted,
                    autocorrect: false,
                    keyboardType: keyboard,
                    style: NovaTypography.textTheme.bodyMedium,
                    decoration: InputDecoration(
                      hintText: hint,
                      hintStyle: NovaTypography.muted(
                        NovaTypography.textTheme.bodyMedium!,
                      ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ),
                ?trailing,
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Inline notice under the header: a replaced session or a sign-in
/// error, in the app's own words.
class _Banner extends StatelessWidget {
  const _Banner({required this.text, this.error = false, this.icon});

  final String text;
  final bool error;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final NovaHue hue = error ? NovaHue.rose : NovaHue.butter;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: hue.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: hue.solid.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(
            icon ?? (error ? Icons.error_outline_rounded : Icons.devices_other_rounded),
            size: 18,
            color: hue.onSurface,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: NovaTypography.textTheme.bodySmall!.copyWith(
                color: hue.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
