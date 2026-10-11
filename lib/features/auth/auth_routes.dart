import 'package:flutter/material.dart';

import 'login_screen.dart';
import 'register_screen.dart';

/// Sign-in, from the gateway (D-133) or after a registration found the number
/// already taken.
Future<void> openSignIn(BuildContext context, {String? phone}) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => LoginScreen(showBack: true, initialPhone: phone)),
  );
}

/// Account creation; a number that already has an account comes back to
/// sign-in with that number.
Future<void> openRegistration(BuildContext context) async {
  final String? phone = await Navigator.of(context).push<String>(
    MaterialPageRoute<String>(builder: (_) => const RegisterScreen()),
  );
  if (phone != null && context.mounted) await openSignIn(context, phone: phone);
}
