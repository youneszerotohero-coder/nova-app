import '../../data/models.dart';
import '../state/app_state.dart';
import 'nova_strings.dart';

/// A notification's title and message in one language.
typedef NotificationText = ({String title, String message});

class _Spec {
  const _Spec(this.params, [this.legacy]);

  /// Message placeholder → key of the notification's `data` params.
  final Map<String, String> params;

  /// Reads the params back from the English text of rows stored before
  /// the params existed.
  final String? legacy;
}

/// Every system notification type the backend sends a Student, as the
/// web renders them (`lib/notification-format.ts`). Admin free text
/// (`admin_message`) and unknown types are shown exactly as stored.
const Map<String, _Spec> _specs = <String, _Spec>{
  'live_scheduled': _Spec(
    {'live': 'live_title', 'date': 'scheduled_at'},
    r'^(?<live>.+) is scheduled for .+ \(Algeria time\)\.$',
  ),
  'live_rescheduled': _Spec(
    {'live': 'live_title', 'date': 'scheduled_at'},
    r'^(?<live>.+) is now scheduled for .+ \(Algeria time\)\.$',
  ),
  'live_reminder': _Spec(
    {'live': 'live_title', 'date': 'scheduled_at'},
    r'^(?<live>.+) starts at .+\.$',
  ),
  'live_started': _Spec({'live': 'live_title'}, r'^(?<live>.+) is live now\.$'),
  'live_cancelled': _Spec({'live': 'live_title'}, r'^(?<live>.+) has been cancelled\.$'),
  'live_replay_ready': _Spec({'live': 'live_title'}, r'^(?<live>.+) is ready to watch\.$'),
  'lesson_published': _Spec({'lesson': 'lesson_title'}, r'^(?<lesson>.+) is now available\.$'),
  'access_closed': _Spec(
    {'year': 'academic_year_name'},
    r'^Your access for Academic Year (?<year>.+) is now closed\.$',
  ),
  'purchase_paid': _Spec(
    {'order': 'order_number'},
    r'^Your Order (?<order>\S+) is paid and your access is ready\.$',
  ),
  'points_credited': _Spec({'points': 'points'}),
  'referral_reward_credited': _Spec({'points': 'points'}),
  'ccp_approved': _Spec(
    {'order': 'order_number'},
    r'^Your CCP payment for Order (?<order>\S+) was approved\.$',
  ),
  'ccp_rejected': _Spec(
    {'order': 'order_number', 'reason': 'reason'},
    r'^Your CCP payment for Order (?<order>\S+) was rejected: ',
  ),
};

String _tr(String key, NovaLang lang) =>
    K[key]?[lang.name] ?? K[key]?['en'] ?? key;

/// [notification]'s title and message in [lang], rendered from its type
/// and structured params. A missing param keeps the localized title and
/// the stored message, like the web.
NotificationText notificationText(AppNotification notification, NovaLang lang) {
  final _Spec? spec = _specs[notification.type];
  if (spec == null) {
    return (title: notification.title, message: notification.body);
  }
  final String key = 'notif.${notification.type}';
  final String title = _tr('$key.title', lang);
  final String? legacySource = spec.legacy;
  final RegExpMatch? legacy =
      legacySource == null ? null : RegExp(legacySource).firstMatch(notification.body);
  String message = _tr('$key.message', lang);
  for (final MapEntry<String, String> param in spec.params.entries) {
    final Object? raw = notification.data[param.value] ??
        (param.value == 'scheduled_at' ? notification.scheduledAt : null) ??
        (legacy != null && legacy.groupNames.contains(param.key)
            ? legacy.namedGroup(param.key)
            : null);
    final String value = _param(raw, isDate: param.key == 'date', lang: lang);
    if (value.isEmpty) return (title: title, message: notification.body);
    message = message.replaceFirst('{${param.key}}', value);
  }
  return (title: title, message: message);
}

String _param(Object? raw, {required bool isDate, required NovaLang lang}) {
  if (isDate) {
    final DateTime? at = raw is DateTime
        ? raw
        : raw is String
            ? DateTime.tryParse(raw)
            : null;
    return at == null ? '' : formatAlgeriaDateTime(at, lang);
  }
  if (raw is String) return raw;
  if (raw is int) return '$raw';
  if (raw is double) {
    return raw == raw.truncateToDouble() ? '${raw.toInt()}' : '$raw';
  }
  return '';
}

const List<String> _monthsEn = <String>[
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sept', 'Oct', 'Nov', 'Dec',
];
const List<String> _monthsFr = <String>[
  'janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin', //
  'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.',
];

String _two(int n) => n.toString().padLeft(2, '0');

/// [instant] in Algeria time, formatted like the web's
/// `toLocaleString(…, {timeZone: 'Africa/Algiers', dateStyle: 'medium',
/// timeStyle: 'short'})` for `en-GB`, `fr-DZ` and `ar-DZ`:
/// `26 Sept 2026, 14:45` · `26 sept. 2026, 2:45 PM` · `26‏/09‏/2026، 2:45 م`.
String formatAlgeriaDateTime(DateTime instant, NovaLang lang) {
  final DateTime at = algeriaTime(instant);
  final String minute = _two(at.minute);
  final int hour12 = at.hour % 12 == 0 ? 12 : at.hour % 12;
  final bool pm = at.hour >= 12;
  return switch (lang) {
    NovaLang.en =>
      '${at.day} ${_monthsEn[at.month - 1]} ${at.year}, ${_two(at.hour)}:$minute',
    NovaLang.fr =>
      '${at.day} ${_monthsFr[at.month - 1]} ${at.year}, $hour12:$minute ${pm ? 'PM' : 'AM'}',
    NovaLang.ar => '${_two(at.day)}‏/${_two(at.month)}‏/${at.year}'
        '، $hour12:$minute ${pm ? 'م' : 'ص'}',
  };
}

/// What the list shows, like the web panel, for a notification without a
/// message: its Live date, or a generic line.
String emptyNotificationBody(AppNotification notification, NovaLang lang) {
  final DateTime? scheduled = notification.scheduledAt;
  if (scheduled != null) {
    return _tr('notif.scheduledAt', lang)
        .replaceAll('{date}', formatAlgeriaDateTime(scheduled, lang));
  }
  return _tr('notif.generic', lang);
}

/// When [notification] was created, in Algeria time; previews without a
/// timestamp keep their fixed label.
String notificationTime(AppNotification notification, NovaLang lang) {
  final DateTime? created = notification.createdAt;
  return created == null ? notification.time : formatAlgeriaDateTime(created, lang);
}
