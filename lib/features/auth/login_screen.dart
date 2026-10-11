import 'package:flutter/material.dart';

import '../../core/api/api_error_text.dart';
import '../../core/api/api_exception.dart';
import '../../core/state/app_state.dart';
import '../../core/theme/nova_colors.dart';
import '../../data/session_store.dart';
import '../../core/i18n/nova_strings.dart';
import '../../core/widgets/motion.dart';
import 'auth_hero.dart';
import 'forgot_password_screen.dart';
import 'otp_widgets.dart';
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
    final SessionStore session = AppScope.of(context).session;
    // The website centres the sign-in form on the phone's height
    // (`.authPageLogin .authPanel`); a short screen scrolls instead.
    return Scaffold(
      backgroundColor: NovaColors.paperCard,
      body: CustomScrollView(
        slivers: [
          SliverFillRemaining(
            hasScrollBody: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AuthHeader(showBack: widget.showBack),
                const Spacer(),
                AuthHero(
                  header: false,
                  title: context.tr('auth.welcomeBack'),
                  subtitle: context.tr('auth.signInSubtitle'),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 24, 18, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (session.endedReason == ApiException.sessionReplaced) AuthMessage(context.tr('err.sessionReplaced')),
                      if (session.endedReason == SessionStore.accountDeleted) AuthNotice(context.tr('deleteAccount.done')),
                      if (_passwordReset) AuthNotice(context.tr('auth.passwordResetDone')),
                      ...stagger(_fields()),
                      // `.manualResetNote`: the link under the password.
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: AuthTextAction(label: context.tr('auth.forgot'), onTap: _openForgotPassword),
                      ),
                      const SizedBox(height: 14),
                      if (_error != null) AuthMessage(_error!),
                      AuthSubmitButton(label: context.tr('auth.signIn'), busy: _busy, onTap: _submit),
                      const SizedBox(height: 12),
                      // The website's line under the form: "New to Nova? Create an account".
                      AuthModeSwitch(signIn: true, onSwitch: _openRegister),
                    ],
                  ),
                ),
                const Spacer(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _fields() {
    return [
      AuthTextField(
        controller: _phone,
        icon: Icons.phone_outlined,
        label: context.tr('auth.phoneLabel'),
        hint: '05 xx xx xx xx',
        keyboard: TextInputType.phone,
        action: TextInputAction.next,
      ),
      AuthTextField(
        controller: _password,
        icon: Icons.lock_outline_rounded,
        label: context.tr('auth.password'),
        hint: context.tr('auth.passwordHint'),
        obscure: _obscure,
        action: TextInputAction.done,
        onSubmitted: (_) => _submit(),
        trailing: PasswordVisibilityToggle(
          obscure: _obscure,
          onToggle: () => setState(() => _obscure = !_obscure),
        ),
      ),
    ];
  }
}
