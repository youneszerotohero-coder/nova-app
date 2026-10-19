import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api/api_error_text.dart';
import '../../core/api/api_exception.dart';
import '../../core/state/app_state.dart';
import '../../core/widgets/nova_toast.dart';
import '../../data/models.dart';
import '../account/orders_screen.dart';
import '../auth/auth_routes.dart';
import '../auth/forgot_password_screen.dart';
import '../catalog/offers_catalog_screen.dart';
import '../catalog/units_catalog_screen.dart';
import '../detail/course_detail_screen.dart';
import '../learning/open_course.dart';
import '../messages/chat_list_screen.dart';
import '../shell/shell_screen.dart';

/// D-150: the assistant's links are website paths
/// (`AssistantTools::LINKS`, product cards); each opens the app's own
/// screen for it. A path the app has no screen for opens on the website.
Future<void> openAssistantHref(BuildContext context, String href) async {
  final AppState app = AppScope.of(context);
  final NavigatorState navigator = Navigator.of(context);
  void push(Widget page) => navigator.push(MaterialPageRoute<void>(builder: (_) => page));
  void tab(int index) {
    // Back to the space under the assistant, on that tab.
    navigator.popUntil((Route<dynamic> route) => route.isFirst);
    app.openShellTab(index);
  }

  final Uri uri = Uri.parse(href);
  final List<String> parts = uri.pathSegments;
  final String first = parts.isEmpty ? '' : parts.first;
  final String? slug = parts.length > 1 ? parts[1] : null;
  try {
    switch ((first, slug)) {
      case ('courses', final String slug):
        push(CourseDetailScreen(course: await app.catalog.course(slug)));
      case ('bundles', final String slug):
        push(CourseDetailScreen.pack(pack: await app.catalog.offer(slug)));
      case ('learn', final String slug):
        final Course course =
            app.learning.owned.where((Course c) => c.slug == slug).firstOrNull ?? await app.catalog.course(slug, owned: true);
        if (context.mounted) await openOwnedCourse(context, course);
      case ('courses', null):
        push(const UnitsCatalogScreen());
      case ('bundles', null):
        push(const OffersCatalogScreen());
      case ('cart', _):
        tab(ShellScreen.cart);
      case ('login', _):
        if (context.mounted) await openSignIn(context);
      case ('register', _):
        if (context.mounted) await openRegistration(context);
      case ('forgot-password', _):
        push(const ForgotPasswordScreen());
      case ('account', 'enrollments'):
        tab(ShellScreen.units);
      case ('account', 'lives'):
        tab(ShellScreen.lives);
      case ('account', 'settings'):
        tab(ShellScreen.account);
      case ('account', 'orders'):
        push(const OrdersScreen());
      case ('account', 'messages'):
        push(const ChatListScreen());
      default:
        await launchUrl(Uri.parse('https://nova-elearning.com$href'), mode: LaunchMode.externalApplication);
    }
  } on ApiException catch (error) {
    if (context.mounted) novaToast(context, apiErrorText(context, error), icon: Icons.error_outline_rounded);
  }
}
