import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../data/account_store.dart';
import '../../data/catalog_store.dart';
import '../../data/chat_store.dart';
import '../../data/commerce_store.dart';
import '../../data/learning_store.dart';
import '../../data/live_store.dart';
import '../../data/json.dart';
import '../../data/models.dart';
import '../../data/session_store.dart';
import '../api/nova_api.dart';
import '../i18n/nova_strings.dart';
import '../push/firebase_push_platform.dart';
import '../push/push_platform.dart';
import '../push/push_service.dart';
import '../push/push_taps.dart';
import '../realtime/reverb_client.dart';
import '../theme/nova_colors.dart';
import 'account_intent.dart';

export '../../data/commerce_store.dart' show CartItem;

/// UI languages shipped with the app.
enum NovaLang { en, fr, ar }

extension NovaLangLabel on NovaLang {
  String get label => switch (this) {
        NovaLang.en => 'English',
        NovaLang.fr => 'Français',
        NovaLang.ar => 'العربية',
      };

  Locale get locale => switch (this) {
        NovaLang.en => const Locale('en'),
        NovaLang.fr => const Locale('fr'),
        NovaLang.ar => const Locale('ar'),
      };
}

/// App-wide state: preferences plus the `/api/v1` stores. Screens read
/// it through [AppScope] and rebuild when any store changes.
///
/// [AppState.live] talks to the production API (D-067); tests install
/// [AppState.seeded] with fixture data and no network.
class AppState extends ChangeNotifier {
  AppState._({
    required this.api,
    required this.session,
    required this.catalog,
    required this.learning,
    required this.commerce,
    required this.account,
    this.references,
    this.live,
    this.realtime,
    this.push,
    this._lang = defaultLang,
    // D-143 chat (chat agent).
    ChatStore? chat,
  }) : chat = chat ?? ChatStore(api) {
    for (final ChangeNotifier store in <ChangeNotifier>[
      session,
      catalog,
      learning,
      commerce,
      account,
    ]) {
      store.addListener(notifyListeners);
    }
    _wasSignedIn = session.signedIn;
    _lastSessionStatus = session.status;
    _lastRequiredStep = session.nextRequiredStep;
    session.addListener(_onSessionChanged);
    _wirePush();
  }

  factory AppState.live() {
    final NovaApi api = NovaApi();
    return AppState._(
      api: api,
      session: SessionStore(api),
      catalog: CatalogStore(api),
      learning: LearningStore(api),
      commerce: CommerceStore(api),
      account: AccountStore(api),
      references: ReferenceStore(api),
      live: LiveStore(api),
      realtime: ReverbClient(api),
      push: PushService(platform: FirebasePushPlatform.fromEnvironment(), api: api),
    );
  }

  /// Offline state for tests and previews: a signed-in session is not
  /// required, stores are pre-filled and never hit the network.
  factory AppState.seeded({
    required SessionStore session,
    required CatalogStore catalog,
    required LearningStore learning,
    required CommerceStore commerce,
    required AccountStore account,
    LiveStore? live,
    ReferenceStore? references,
    PushService? push,
    NovaLang lang = defaultLang,
    ChatStore? chat,
  }) =>
      AppState._(
        chat: chat,
        api: null,
        references: references,
        session: session,
        catalog: catalog,
        learning: learning,
        commerce: commerce,
        account: account,
        live: live,
        push: push,
        lang: lang,
      );

  static AppState? _instance;

  /// The running app's state; tests replace it with [AppState.seeded].
  static AppState get instance => _instance ??= AppState.live();
  static set instance(AppState state) => _instance = state;

  final NovaApi? api;
  final SessionStore session;
  final CatalogStore catalog;
  final LearningStore learning;
  final CommerceStore commerce;
  final AccountStore account;
  final ReferenceStore? references;

  /// Live endpoints; null in offline previews.
  final LiveStore? live;

  /// Reverb connection; null in offline previews.
  final ReverbClient? realtime;

  /// D-143 Firebase push; null in offline previews (off without its options).
  final PushService? push;

  /// Tapped system notifications, opened once the signed-in space shows.
  final PushTapRouter pushTaps = PushTapRouter();

  /// D-143 group chats of the signed-in user (any role). Not forwarded to
  /// this state's listeners: the chat screens listen to it directly.
  final ChatStore chat;
  final List<VoidCallback> _channels = <VoidCallback>[];

  /// The UI language on first launch.
  static const NovaLang defaultLang = NovaLang.ar;

  bool _darkMode = false;
  NovaLang _lang;
  bool _liveReminderSet = false;
  bool _wasSignedIn = false;
  SessionStatus _lastSessionStatus = SessionStatus.booting;
  String? _lastRequiredStep;

  bool get darkMode => _darkMode;

  /// D-134: "continue without an account" on the first screen; the app is
  /// browsed read-only until the visitor signs in (not remembered).
  bool _guest = false;
  bool get guest => _guest && !session.signedIn;

  void browseAsGuest(bool value) {
    if (_guest == value) return;
    _guest = value;
    notifyListeners();
  }

  /// What a visitor asked for before signing in; the Student space carries
  /// it out once signed in (D-127, D-134).
  AccountIntent? pendingIntent;

  /// A pushed page asking the Student space to show one of its tabs (e.g.
  /// an owned Offer's "My lessons"): the shell closes the pages above it.
  final ValueNotifier<int?> shellTabRequest = ValueNotifier<int?>(null);

  void openShellTab(int tab) => shellTabRequest.value = tab;

  NovaLang get lang => _lang;

  /// Starts the app: the saved language, the stored session, then the
  /// catalogue — never for a Teacher, whom every Student endpoint refuses
  /// (D-143). Firebase starts alongside when this build has push.
  Future<void> boot() async {
    await _restoreLang();
    _startPush();
    await session.boot();
    if (!session.isTeacher) await catalog.load();
  }

  /// A language the Student chose survives relaunches; until they choose,
  /// the app starts in [defaultLang].
  static const String _langKey = 'nova.lang';

  Future<void> _restoreLang() async {
    if (api == null) return;
    try {
      final String? saved = await const FlutterSecureStorage().read(key: _langKey);
      for (final NovaLang lang in NovaLang.values) {
        if (lang.name == saved && lang != _lang) {
          _lang = lang;
          notifyListeners();
        }
      }
    } catch (_) {
      // Unreadable storage: the default language.
    }
  }

  /// Catalogue Courses with the Student's ownership applied.
  List<Course> get courses => <Course>[
        for (final Course course in catalog.courses)
          learning.owns(course.id) ? course.copyWith(owned: true) : course,
      ];

  /// The signed-in Student with dashboard figures (points, lessons,
  /// 7-day activity) applied.
  StudentProfile? get profile => learning.dashboard.isEmpty
      ? session.profile
      : session.profile?.withDashboard(learning.dashboard);

  // Cart shortcuts kept for the existing screens.
  List<CartItem> get items => commerce.items;
  int get itemCount => commerce.itemCount;
  bool contains(String key) => commerce.contains(key);
  int get unreadCount => account.unreadCount;

  void setDarkMode(bool value) {
    NovaColors.current = value ? NovaPalette.dark : NovaPalette.light;
    _darkMode = value;
    notifyListeners();
  }

  void setLang(NovaLang lang) {
    if (lang == _lang) return;
    _lang = lang;
    notifyListeners();
    if (api != null) {
      const FlutterSecureStorage().write(key: _langKey, value: lang.name).catchError((Object _) {});
    }
    _nameChannels();
    // D-143: a Teacher has neither catalogue nor Lessons.
    if (session.isTeacher) return;
    // Reference names (subjects, levels…) are resolved per language.
    catalog.load();
    if (session.signedIn) learning.load();
  }

  void setLiveReminder() => _liveReminderSet = true;
  bool get liveReminderSet => _liveReminderSet;

  /// Loads everything that needs the session once, and wipes it on
  /// sign-out so nothing of one Student survives into the next.
  void _onSessionChanged() {
    _syncPush();
    final bool signedIn = session.signedIn;
    final SessionStatus previous = _lastSessionStatus;
    _lastSessionStatus = session.status;
    final String? previousStep = _lastRequiredStep;
    _lastRequiredStep = signedIn ? session.nextRequiredStep : null;
    if (signedIn == _wasSignedIn) {
      // A required step (password, phone, onboarding) just finished: the
      // Student's data could not load behind it, and onboarding sets the
      // level the catalogue follows.
      if (signedIn && previousStep != null && session.nextRequiredStep == null) {
        if (!session.isTeacher) catalog.load();
        refreshAccount();
        chat.loadRooms();
      }
      return;
    }
    _wasSignedIn = signedIn;
    if (signedIn && session.isTeacher) {
      // D-143: a Teacher loads no Student store, only their notifications.
      account.refreshNotifications();
      _listenRealtime();
      _watchSession();
    } else if (signedIn) {
      // D-083: a signed-in Student sees the catalogue of their level and
      // filière. The boot load already carried the stored session cookie.
      if (previous != SessionStatus.booting) catalog.load();
      learning.load();
      commerce.load();
      account.load();
      _listenRealtime();
      _watchSession();
      _startChat();
    } else {
      // Signed out: the first screen again, not the visitor's browsing.
      _guest = false;
      pushTaps.clear();
      _stopSessionWatch();
      _stopChat();
      for (final VoidCallback stop in _channels) {
        stop();
      }
      _channels.clear();
      realtime?.disconnect();
      learning.clear();
      commerce.clear();
      account.clear();
      // Signed out: the whole public catalogue again.
      catalog.load();
    }
  }

  /// Account-wide channels (web `lib/realtime.ts`): a sign-in on another
  /// device ends this session at once; new notifications are announced
  /// and refresh the bell without polling.
  void _listenRealtime() {
    final ReverbClient? client = realtime;
    final StudentProfile? me = session.profile;
    if (client == null || !client.configured || me == null) return;
    client.connect();
    _channels.add(client.subscribe('private-user.${me.id}', (String event, Json data) {
      if (event == 'SessionReplaced') {
        session.replacedElsewhere(data.str('session_fingerprint'));
      }
      // D-143: a Teacher has no Student channel; their notifications come here.
      if (event == 'NotificationCreated' && session.isTeacher) onNotificationCreated(data);
    }));
    if (!session.isTeacher) {
      _channels.add(client.subscribe('private-student.${me.studentId}', (String event, Json data) {
        if (event == 'NotificationCreated') onNotificationCreated(data);
      }));
    }
  }

  /// A `NotificationCreated` broadcast: listed and announced at once
  /// (chime and banner, once per id), then the list, the bell and the
  /// points refresh from the server.
  void onNotificationCreated(Json payload) {
    account.receive(payload);
    _reloadNotifications();
  }

  /// The bell and the list again (with the points for a Student; a
  /// Teacher has notifications only, D-143).
  void _reloadNotifications() {
    if (session.isTeacher) {
      account.refreshNotifications();
    } else {
      account.load();
    }
  }

  /// Reverb delivers `SessionReplaced` at once, so `GET /auth/session` is
  /// only its fallback (web `auth.tsx`, D-071): every 2 min while realtime
  /// is up, every 7 s while it is down, once on reconnection and on
  /// return to the foreground, never while the app is in the background.
  static const Duration sessionPollTick = Duration(seconds: 7);
  static const Duration sessionFallbackInterval = Duration(minutes: 2);

  Timer? _sessionTimer;
  AppLifecycleListener? _lifecycle;
  DateTime _lastSessionCheck = DateTime.now();
  bool _realtimeUp = false;

  void _watchSession() {
    if (api == null) return;
    _stopSessionWatch();
    _lastSessionCheck = DateTime.now();
    _sessionTimer = Timer.periodic(sessionPollTick, (_) => _sessionTick());
    _lifecycle = AppLifecycleListener(onResume: _checkSession);
    realtime?.connected.addListener(_onRealtimeConnection);
  }

  void _stopSessionWatch() {
    _sessionTimer?.cancel();
    _sessionTimer = null;
    _lifecycle?.dispose();
    _lifecycle = null;
    realtime?.connected.removeListener(_onRealtimeConnection);
    _realtimeUp = false;
  }

  void _sessionTick() {
    final AppLifecycleState? state = WidgetsBinding.instance.lifecycleState;
    if (state != null && state != AppLifecycleState.resumed) return;
    final bool up = realtime?.connected.value ?? false;
    if (up && DateTime.now().difference(_lastSessionCheck) < sessionFallbackInterval) return;
    _checkSession();
  }

  /// A reconnection may have missed a `SessionReplaced`: check at once.
  void _onRealtimeConnection() {
    final bool up = realtime?.connected.value ?? false;
    if (up && !_realtimeUp) _checkSession();
    _realtimeUp = up;
  }

  void _checkSession() {
    _lastSessionCheck = DateTime.now();
    session.checkSession();
  }

  // ── D-143 group chats (chat agent) ─────────────────────────────────────
  // Rooms load after sign-in for every role, each room's channel (and the
  // staff channel of moderated rooms) is followed, and everything is
  // dropped on sign-out. A purchase can add rooms: [refreshAccount].
  AppLifecycleListener? _chatLifecycle;

  void _startChat() {
    chat.start(me: session.profile?.id ?? 0, realtime: realtime);
    _chatLifecycle?.dispose();
    if (api != null) _chatLifecycle = AppLifecycleListener(onResume: chat.onResumed);
  }

  void _stopChat() {
    _chatLifecycle?.dispose();
    _chatLifecycle = null;
    chat.clear();
  }
  // ── end D-143 group chats ──────────────────────────────────────────────

  /// Reloads the Student's data after a purchase or enrolment.
  Future<void> refreshAccount() async {
    if (session.isTeacher) return account.refreshNotifications();
    await Future.wait(<Future<void>>[
      learning.load(),
      commerce.load(),
      account.load(),
      chat.loadRooms(),
    ]);
  }
}

// ── D-143 push: system notifications (platform agent) ──────────────────────
extension on AppState {
  void _wirePush() {
    final PushService? service = push;
    if (service == null) return;
    // The token leaves the account while the session still works.
    session.beforeLogout = service.unregister;
    service.foreground.listen(_onPushForeground);
    service.opened.listen(pushTaps.open);
  }

  void _startPush() {
    push?.start();
    _nameChannels();
  }

  void _nameChannels() {
    String tr(String key) => K[key]?[lang.name] ?? K[key]?['en'] ?? key;
    push?.nameChannels(messages: tr('push.channelMessages'), general: tr('push.channelGeneral'));
  }

  /// The token is registered once the account is past its required steps
  /// (the backend refuses everything else before), deleted when it ends.
  void _syncPush() {
    final PushService? service = push;
    if (service == null) return;
    if (session.signedIn && session.nextRequiredStep == null) {
      service.signedIn();
    } else if (!session.signedIn && session.status != SessionStatus.booting) {
      service.signedOut();
    }
  }

  /// A message while the app is open: chat messages have their own sound
  /// and banner (chat feature); anything else chimes and shows the
  /// notification banner like a realtime one (once per id), then the list
  /// reloads.
  void _onPushForeground(PushPayload payload) {
    if (payload.isChat || !session.signedIn) return;
    final String? id = payload.notificationId;
    // Without its database id the row cannot be marked read: the list only.
    if (id == null) return _reloadNotifications();
    account.receive(<String, dynamic>{
      'id': id,
      'type': payload.type,
      'title': payload.title ?? '',
      'message': payload.body ?? '',
      'read_at': null,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    });
    _reloadNotifications();
  }
}
// ── end D-143 push ─────────────────────────────────────────────────────────

/// InheritedNotifier bridge so any widget can read/rebuild on state.
class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child})
      : super(notifier: state);

  static AppState of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;
}
