import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../widgets/nova_toast.dart';

/// The website's support address (`config/contact.ts`): the NOVA administration.
const String novaSupportEmail = 'noova.elearning@gmail.com';

/// Opens a mail to the NOVA administration, or shows the address when no mail app opens.
Future<void> contactNovaSupport(BuildContext context) async {
  bool opened = false;
  try {
    opened = await launchUrl(Uri.parse('mailto:$novaSupportEmail'), mode: LaunchMode.externalApplication);
  } catch (_) {
    opened = false;
  }
  if (!opened && context.mounted) novaToast(context, novaSupportEmail, icon: Icons.mail_outline_rounded);
}
