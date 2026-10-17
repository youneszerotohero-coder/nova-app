import 'package:clock/clock.dart';
import 'package:flutter/material.dart';

import '../../core/i18n/nova_strings.dart';
import '../../core/state/app_state.dart';
import '../../core/theme/nova_colors.dart';
import '../../data/chat_store.dart';
import '../../data/models.dart' show algeriaTime;

/// D-143 chat wording and formats: localized names, Algeria times, day
/// separators, sizes, durations and the hashed name colours.

/// The public room's title is the app's own ("NOVA announcements").
String chatRoomTitle(BuildContext context, ChatRoom room) =>
    room.isPublic ? context.tr('chat.publicTitle') : room.name;

/// The Admin writes as "NOVA Administration" (`sender.name` is null).
String chatNameOf(BuildContext context, ChatRole role, String? name) =>
    role == ChatRole.admin ? context.tr('chat.admin') : (name?.trim().isNotEmpty ?? false ? name!.trim() : context.tr('chat.member'));

String _two(int n) => n.toString().padLeft(2, '0');

/// "14:05", Algeria time.
String chatClock(DateTime? at) {
  if (at == null) return '';
  final DateTime local = algeriaTime(at);
  return '${_two(local.hour)}:${_two(local.minute)}';
}

const List<String> _monthsEn = <String>['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sept', 'Oct', 'Nov', 'Dec'];
const List<String> _monthsFr = <String>['janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin', 'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.'];

/// Month names as said in Algeria.
const List<String> _monthsAr = <String>['جانفي', 'فيفري', 'مارس', 'أفريل', 'ماي', 'جوان', 'جويلية', 'أوت', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'];

/// Whole Algeria days between [at] and now (0 = today).
int chatDaysAgo(DateTime at, [DateTime? now]) {
  final DateTime a = algeriaTime(now ?? clock.now());
  final DateTime b = algeriaTime(at);
  return DateTime.utc(a.year, a.month, a.day).difference(DateTime.utc(b.year, b.month, b.day)).inDays;
}

bool chatSameDay(DateTime a, DateTime b) {
  final DateTime x = algeriaTime(a);
  final DateTime y = algeriaTime(b);
  return x.year == y.year && x.month == y.month && x.day == y.day;
}

String chatDate(DateTime at, NovaLang lang) {
  final DateTime d = algeriaTime(at);
  return switch (lang) {
    NovaLang.en => '${d.day} ${_monthsEn[d.month - 1]} ${d.year}',
    NovaLang.fr => '${d.day} ${_monthsFr[d.month - 1]} ${d.year}',
    NovaLang.ar => '${d.day} ${_monthsAr[d.month - 1]} ${d.year}',
  };
}

/// The separator between days: "Today", "Yesterday", then the date.
String chatDayLabel(BuildContext context, DateTime at) {
  final int days = chatDaysAgo(at);
  if (days <= 0) return context.tr('notif.today');
  if (days == 1) return context.tr('notif.yesterday');
  return chatDate(at, AppScope.of(context).lang);
}

/// The list's time: the hour today, "Yesterday", then the date.
String chatListTime(BuildContext context, DateTime? at) {
  if (at == null) return '';
  final int days = chatDaysAgo(at);
  if (days <= 0) return chatClock(at);
  if (days == 1) return context.tr('notif.yesterday');
  final DateTime d = algeriaTime(at);
  return '${_two(d.day)}/${_two(d.month)}/${d.year % 100}';
}

/// "0:42", "4:59".
String chatDuration(Duration value) {
  final int seconds = value.inSeconds;
  return '${seconds ~/ 60}:${_two(seconds % 60)}';
}

/// "340 KB", "1.2 MB" ("Ko"/"Mo" in French).
String chatFileSize(int bytes, NovaLang lang) {
  final bool fr = lang == NovaLang.fr;
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).ceil()} ${fr ? 'Ko' : 'KB'}';
  }
  final String mb = (bytes / (1024 * 1024)).toStringAsFixed(1);
  return '${fr ? mb.replaceFirst('.', ',') : mb} ${fr ? 'Mo' : 'MB'}';
}

/// A stable colour per person for names in a group (the hue hashed from
/// the user id), readable on the card surface in both themes.
Color chatHueOf(int seed) {
  int hash = seed * 2654435761 & 0x7fffffff;
  hash ^= hash >> 13;
  final double hue = (hash % 360).toDouble();
  final bool dark = NovaColors.current.isDark;
  return HSLColor.fromAHSL(1, hue, dark ? 0.62 : 0.58, dark ? 0.70 : 0.40).toColor();
}

/// Arabic or Hebrew script decides the direction of a message, so a French
/// message reads left to right in the Arabic app (and the reverse).
TextDirection? chatTextDirection(String text) {
  for (final int rune in text.runes) {
    if ((rune >= 0x0590 && rune <= 0x08FF) || (rune >= 0xFB1D && rune <= 0xFEFC)) return TextDirection.rtl;
    if ((rune >= 0x41 && rune <= 0x5A) || (rune >= 0x61 && rune <= 0x7A) || (rune >= 0xC0 && rune <= 0x24F)) {
      return TextDirection.ltr;
    }
  }
  return null;
}

bool _rtlRune(int rune) => (rune >= 0x0590 && rune <= 0x08FF) || (rune >= 0xFB1D && rune <= 0xFEFC);

/// [text] as one bidi unit taking its own direction (a size, a date, a
/// name next to Arabic words).
String chatIsolate(String text) => '\u2068$text\u2069';

/// A file name in an Arabic sentence: a trailing Latin word ("2.pdf")
/// stays one left-to-right unit instead of reading "pdf.2".
String chatFileName(String name) {
  final int space = name.lastIndexOf(' ');
  if (space < 0 || !name.runes.any(_rtlRune)) return name;
  final String last = name.substring(space + 1);
  if (last.runes.any(_rtlRune)) return name;
  return '${name.substring(0, space + 1)}\u2066$last\u2069';
}

/// What the list shows for a room's last message (with its kind).
String chatPreview(BuildContext context, ChatLastMessage last) => switch (last.kind) {
      ChatMessageKind.voice => context.tr('chat.voiceMessage'),
      ChatMessageKind.pdf => last.preview.isNotEmpty ? chatFileName(last.preview) : context.tr('chat.pdf'),
      ChatMessageKind.text => last.preview,
    };
