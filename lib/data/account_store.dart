import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/api/api_exception.dart';
import '../core/api/nova_api.dart';
import 'json.dart';
import 'models.dart';

/// Points wallet, referral and in-app notifications. Push (FCM/APNs)
/// is out of scope (D-067): notifications are fetched page by page
/// (20 per page, newest first) and new ones arrive over Reverb.
class AccountStore extends ChangeNotifier {
  AccountStore(this._api);

  AccountStore.seeded({
    List<AppNotification> notifications = const <AppNotification>[],
    this._ledger = const <PointsEntry>[],
    this._balance = 0,
  })  : _api = null,
        _notifications = notifications,
        _unread = notifications.where((AppNotification n) => !n.read).length;

  final NovaApi? _api;

  List<AppNotification> _notifications = const <AppNotification>[];
  int _unread = 0;
  int _page = 1;
  int _lastPage = 1;
  bool _loadingMore = false;

  /// Bumped when the history restarts at page 1, so a page still in
  /// flight is not appended to the new list.
  int _generation = 0;
  final StreamController<AppNotification> _arrivals =
      StreamController<AppNotification>.broadcast();
  List<PointsEntry> _ledger = const <PointsEntry>[];
  int _balance = 0;
  int _earned = 0;
  Json _referral = <String, dynamic>{};

  List<AppNotification> get notifications => _notifications;

  /// The server's `unread_count` (the bell badge).
  int get unreadCount => _unread;
  bool get hasMoreNotifications => _page < _lastPage;
  bool get loadingMoreNotifications => _loadingMore;

  /// Unread notifications delivered in realtime, once per id: the app
  /// chimes and shows a banner for each.
  Stream<AppNotification> get arrivals => _arrivals.stream;
  List<PointsEntry> get ledger => _ledger;
  int get pointsBalance => _balance;
  int get pointsEarned => _earned;
  Json get referral => _referral;

  Future<void> load() async {
    final NovaApi? api = _api;
    if (api == null) return;
    try {
      final List<Json> bodies = await Future.wait(<Future<Json>>[
        _notificationPage(api, 1),
        api.get('/me/points'),
        api.get('/me/referral'),
      ]);
      _mergeFirstPage(bodies[0]);
      final Json points = bodies[1].obj('data') ?? <String, dynamic>{};
      _balance = points.integer('balance');
      _earned = points.integer('earned');
      _ledger = points.list('transactions').map(PointsEntry.fromJson).toList();
      _referral = bodies[2].obj('data') ?? <String, dynamic>{};
      notifyListeners();
    } on ApiException {
      // Keep the last known state.
    }
  }

  /// The history from page 1 again (screen opened, pull-to-refresh):
  /// older pages load again while scrolling.
  Future<void> refreshNotifications() async {
    final NovaApi? api = _api;
    if (api == null) return;
    final int generation = ++_generation;
    try {
      final Json body = await _notificationPage(api, 1);
      if (generation != _generation) return;
      _notifications = _parse(body);
      _page = 1;
      _lastPage = _lastPageOf(body, 1);
      _unread = body.integer('unread_count');
      notifyListeners();
    } on ApiException {
      // Keep the last known state.
    }
  }

  /// Appends the next page, skipping rows already listed (a new
  /// notification shifts every page by one).
  Future<void> loadMoreNotifications() async {
    final NovaApi? api = _api;
    if (api == null || _loadingMore || _page >= _lastPage) return;
    final int generation = _generation;
    final int next = _page + 1;
    _loadingMore = true;
    notifyListeners();
    try {
      final Json body = await _notificationPage(api, next);
      if (generation != _generation) return;
      final Set<String> listed = <String>{
        for (final AppNotification n in _notifications) n.id,
      };
      _notifications = <AppNotification>[
        ..._notifications,
        ..._parse(body).where((AppNotification n) => !listed.contains(n.id)),
      ];
      _page = next;
      _lastPage = _lastPageOf(body, next);
      _unread = body.integer('unread_count', _unread);
    } on ApiException {
      // Keep what is listed; the next scroll or "Show more" retries.
    } finally {
      _loadingMore = false;
      notifyListeners();
    }
  }

  /// A notification delivered in realtime (`NotificationCreated`, the
  /// stored payload plus id, read_at, created_at): listed on top at once
  /// and announced once per id.
  void receive(Json payload) {
    final AppNotification notification = AppNotification.fromJson(payload);
    if (notification.id.isEmpty ||
        _notifications.any((AppNotification n) => n.id == notification.id)) {
      return;
    }
    _notifications = <AppNotification>[notification, ..._notifications];
    if (!notification.read) {
      _unread++;
      _arrivals.add(notification);
    }
    notifyListeners();
  }

  Future<Json> _notificationPage(NovaApi api, int page) =>
      api.get('/me/notifications', query: <String, Object?>{'page': page});

  List<AppNotification> _parse(Json body) =>
      body.list('data').map(AppNotification.fromJson).toList();

  int _lastPageOf(Json body, int fallback) =>
      body.obj('meta')?.integer('last_page', fallback) ?? fallback;

  /// A fresh first page over what is listed: new rows on top, older
  /// pages kept so the history does not jump while it is read.
  void _mergeFirstPage(Json body) {
    final List<AppNotification> fresh = _parse(body);
    final Set<String> ids = <String>{for (final AppNotification n in fresh) n.id};
    _notifications = <AppNotification>[
      ...fresh,
      ..._notifications.where((AppNotification n) => !ids.contains(n.id)),
    ];
    _lastPage = _lastPageOf(body, _page);
    _unread = body.integer('unread_count');
  }

  Future<void> markRead(AppNotification notification) async {
    // The banner and the list may hold the same row: count it once.
    if (notification.read ||
        (notification.id.isNotEmpty &&
            _notifications.any((AppNotification n) => n.id == notification.id && n.read))) {
      return;
    }
    _notifications = <AppNotification>[
      for (final AppNotification n in _notifications)
        n.id == notification.id ? n.markedRead() : n,
    ];
    _unread = (_unread - 1).clamp(0, 1 << 30);
    notifyListeners();
    await _api?.patch('/me/notifications/${notification.id}/read');
  }

  Future<void> markAllRead() async {
    _notifications = <AppNotification>[
      for (final AppNotification n in _notifications) n.markedRead(),
    ];
    _unread = 0;
    notifyListeners();
    await _api?.patch('/me/notifications/read-all');
  }

  Future<void> applyReferral(String code) async {
    final Json body = await _api!.post('/referral/apply', <String, String>{
      'referral_code': code.trim(),
    });
    _referral = body.obj('data') ?? _referral;
    notifyListeners();
  }

  void clear() {
    _notifications = const <AppNotification>[];
    _unread = 0;
    _page = 1;
    _lastPage = 1;
    _generation++;
    _ledger = const <PointsEntry>[];
    _balance = 0;
    _earned = 0;
    _referral = <String, dynamic>{};
    notifyListeners();
  }

  @override
  void dispose() {
    _arrivals.close();
    super.dispose();
  }
}

/// Academic reference data for registration and onboarding.
class ReferenceStore {
  ReferenceStore(this._api);

  final NovaApi _api;

  Future<List<RefItem>> _list(String path) async =>
      (await _api.get(path)).list('data').map(RefItem.fromJson).toList();

  Future<List<RefItem>> levels() => _list('/levels');
  Future<List<RefItem>> tracks() => _list('/tracks');
  Future<List<RefItem>> wilayas() => _list('/wilayas');
  Future<List<RefItem>> communes(int wilayaId) =>
      _list('/wilayas/$wilayaId/communes');
}
