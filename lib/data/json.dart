import '../core/state/app_state.dart';

typedef Json = Map<String, dynamic>;

/// Small, total readers for `/api/v1` payloads: a missing or null key
/// never throws, it falls back — the backend omits `whenLoaded` keys.
extension JsonRead on Json {
  Json? obj(String key) {
    final Object? v = this[key];
    return v is Map<String, dynamic> ? v : null;
  }

  List<Json> list(String key) {
    final Object? v = this[key];
    return v is List ? v.whereType<Map<String, dynamic>>().toList() : <Json>[];
  }

  String str(String key, [String fallback = '']) {
    final Object? v = this[key];
    return v == null ? fallback : '$v';
  }

  String? strOrNull(String key) {
    final Object? v = this[key];
    return v == null || (v is String && v.isEmpty) ? null : '$v';
  }

  int integer(String key, [int fallback = 0]) {
    final Object? v = this[key];
    if (v is int) return v;
    if (v is num) return v.round();
    if (v is String) return int.tryParse(v) ?? double.tryParse(v)?.round() ?? fallback;
    return fallback;
  }

  bool flag(String key, [bool fallback = false]) {
    final Object? v = this[key];
    return v is bool ? v : fallback;
  }

  DateTime? date(String key) {
    final Object? v = this[key];
    if (v is! String) return null;
    // Points/referral rows use raw "Y-m-d H:i:s" (UTC, no zone).
    final String iso = v.contains('T') ? v : '${v.replaceFirst(' ', 'T')}Z';
    return DateTime.tryParse(iso)?.toLocal();
  }
}

/// DZD amount from a `decimal:2` string ("2500.00") in whole dinars.
/// Display only — every total the Student pays is computed server-side.
int dinars(Object? value) {
  if (value is int) return value;
  if (value is num) return value.round();
  if (value is String) return double.tryParse(value)?.round() ?? 0;
  return 0;
}

/// Reference data carries `name_fr` / `name_ar` only; the English UI
/// shows the French name (the backend has no English labels).
String localName(Json? ref, [NovaLang? lang]) {
  if (ref == null) return '';
  final NovaLang active = lang ?? AppState.instance.lang;
  final String ar = ref.str('name_ar');
  final String fr = ref.str('name_fr');
  if (active == NovaLang.ar && ar.isNotEmpty) return ar;
  return fr.isNotEmpty ? fr : ar;
}

String personName(Json? person) {
  if (person == null) return '';
  return '${person.str('first_name')} ${person.str('last_name')}'.trim();
}
