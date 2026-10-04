import 'package:flutter/material.dart';

import '../core/theme/nova_colors.dart';
import '../core/widgets/nova_scene_image.dart';
import 'json.dart';

/// Domain models for the Student app, built from `/api/v1` resources.
/// The painted [NovaScene] and glyph are presentation only: they stand
/// in while (or when there is no) cover, and are derived from ids so a
/// program keeps the same art everywhere.
NovaScene sceneFor(int id) =>
    NovaScene.values[id.abs() % NovaScene.values.length];

IconData subjectIcon(String code) {
  final String c = code.toLowerCase();
  if (c.contains('math')) return Icons.calculate_rounded;
  if (c.contains('phys')) return Icons.bolt_rounded;
  if (c.contains('science') || c.contains('bio')) return Icons.biotech_rounded;
  if (c.contains('philo')) return Icons.psychology_alt_rounded;
  if (c.contains('english') || c.contains('french') || c.contains('language') ||
      c.contains('arabic') || c.contains('german') || c.contains('spanish')) {
    return Icons.translate_rounded;
  }
  if (c.contains('history') || c.contains('geo')) return Icons.public_rounded;
  if (c.contains('islam')) return Icons.menu_book_rounded;
  return Icons.school_rounded;
}

/// Academic reference row (level, track, subject, wilaya, commune).
class RefItem {
  const RefItem({
    required this.id,
    required this.name,
    this.code = '',
    this.trackIds = const <int>[],
  });

  factory RefItem.fromJson(Json json) => RefItem(
        id: json.integer('id'),
        code: json.str('code'),
        name: localName(json),
        trackIds: json['track_ids'] is List
            ? (json['track_ids'] as List<dynamic>).whereType<int>().toList()
            : const <int>[],
      );

  final int id;
  final String code;
  final String name;

  /// A level's filières (`/levels` `track_ids`, D-098): none for 4AM, the
  /// troncs communs for 1AS, the BAC filières for 2AS and 3AS.
  final List<int> trackIds;

  bool get hasTracks => trackIds.isNotEmpty;

  /// The filières of this level, in the order of the flat `/tracks` list.
  List<RefItem> tracksFrom(List<RefItem> tracks) =>
      tracks.where((RefItem track) => trackIds.contains(track.id)).toList();
}

class Lesson {
  const Lesson({
    required this.title,
    required this.minutes,
    required this.watched,
    this.id = 0,
    this.description = '',
    this.durationSeconds = 0,
    this.resumeSeconds = 0,
    this.unlocked = true,
    this.hasQuiz = false,
    this.quizRequired = false,
    this.hasPdf = false,
    this.apiCompleted,
    this.quiz,
    this.pdf,
    this.allowDownload = false,
  });

  /// Public curriculum row (`lessons[]` of a course detail).
  factory Lesson.fromJson(Json json) {
    final int seconds = json.integer('duration_seconds');
    return Lesson(
      id: json.integer('id'),
      title: json.str('title'),
      description: json.str('description'),
      durationSeconds: seconds,
      minutes: (seconds / 60).ceil(),
      watched: 0,
      hasQuiz: json.flag('has_quiz'),
      hasPdf: json.flag('has_pdf'),
    );
  }

  final int id;
  final String title;
  final String description;
  final int minutes;
  final int durationSeconds;

  /// Max legitimate watch percentage (0-100). Progress never regresses.
  final int watched;
  final int resumeSeconds;

  /// All earlier lessons are complete (server-computed).
  final bool unlocked;
  final bool hasQuiz;
  final bool quizRequired;
  final bool hasPdf;

  /// Server verdict from `/courses/{id}/progress`; wins over the local
  /// rule when present.
  final bool? apiCompleted;
  final QuizData? quiz;
  final String? pdf;
  final bool allowDownload;

  bool get completed =>
      apiCompleted ??
      (watched >= 90 && (quiz == null || !quiz!.required || quiz!.passed));

  /// Merges a `/courses/{id}/progress` row into this curriculum lesson.
  Lesson withProgress(Json row) => Lesson(
        id: id,
        title: title,
        description: description,
        durationSeconds: durationSeconds,
        minutes: minutes,
        watched: dinars(row['video_progress_percent']).clamp(0, 100),
        resumeSeconds: row.integer('resume_position_seconds'),
        unlocked: row.flag('unlocked', true),
        hasQuiz: row.flag('has_quiz', hasQuiz),
        quizRequired: row.flag('quiz_required'),
        hasPdf: row.flag('has_pdf', hasPdf),
        apiCompleted: row.flag('completed'),
        quiz: quiz,
        pdf: pdf,
        allowDownload: allowDownload,
      );
}

class QuizData {
  const QuizData({
    required this.questionCount,
    required this.required,
    required this.attemptsUsed,
    required this.bestScore,
    this.passingScore = 70,
    this.maxAttempts = 3,
    this.cooldownHours = 24,
  });

  final int questionCount;
  final bool required;
  final int passingScore;

  /// NULL would mean unlimited; the mock uses the default 3.
  final int maxAttempts;
  final int attemptsUsed;
  final int bestScore;
  final int cooldownHours;

  bool get passed => bestScore >= passingScore;
  bool get attemptsLeft => attemptsUsed < maxAttempts;
}

/// A quiz question: single choice, multiple choice or true/false.
class QuizQuestion {
  const QuizQuestion({
    required this.prompt,
    required this.options,
    required this.correctIndexes,
  });

  final String prompt;
  final List<String> options;
  final List<int> correctIndexes;

  bool get multiple => correctIndexes.length > 1;
}

/// A Course inside an Offer.
class PackItem {
  const PackItem({
    required this.courseTitle,
    this.allocated = 0,
    this.courseId = 0,
    this.courseSlug = '',
    this.teacher = '',
    this.subject = '',
  });

  factory PackItem.fromJson(Json json) => PackItem(
        courseId: json.integer('id'),
        courseSlug: json.str('slug'),
        courseTitle: json.str('title'),
        teacher: personName(json.obj('teacher')),
        subject: localName(json.obj('subject')),
      );

  final int courseId;
  final String courseSlug;
  final String courseTitle;
  final String teacher;
  final String subject;

  /// Internal allocation; never exposed by the public API (kept for the
  /// existing layout, 0 when unknown).
  final int allocated;
}

enum LiveStatus { live, scheduled, replay }

class LiveSession {
  const LiveSession({
    required this.title,
    required this.course,
    required this.teacher,
    required this.subject,
    required this.status,
    required this.attendees,
    required this.scene,
    this.id = 0,
    this.courseSlug = '',
    this.rawStatus = '',
    this.scheduledAt,
    this.scheduledLabel,
    this.image,
    this.commentsEnabled = true,
    this.commentMaxLength = 500,
  });

  factory LiveSession.fromJson(Json json) {
    final String raw = json.str('status');
    final bool replay = json.flag('replay_available');
    return LiveSession(
      id: json.integer('id'),
      title: json.str('title'),
      course: json.str('course_title'),
      courseSlug: json.str('course_slug'),
      teacher: json.str('teacher_name'),
      subject: '',
      rawStatus: raw,
      status: switch (raw) {
        'live' || 'starting' => LiveStatus.live,
        _ when replay => LiveStatus.replay,
        _ => LiveStatus.scheduled,
      },
      attendees: json.integer('attendees_count'),
      scene: sceneFor(json.integer('course_id')),
      scheduledAt: json.date('scheduled_at'),
      scheduledLabel: json.date('scheduled_at') == null
          ? null
          : '${shortDate(json.date('scheduled_at'))} · '
              '${_clock(json.date('scheduled_at')!)}',
      image: json.strOrNull('course_cover_url'),
      commentsEnabled: json.flag('comments_enabled', true),
      commentMaxLength: json.integer('comment_max_length', 500),
    );
  }

  final int id;
  final String title;
  final String course;
  final String courseSlug;
  final String teacher;
  final String subject;
  final LiveStatus status;

  /// Backend lifecycle: scheduled|starting|live|ending|processing_replay|
  /// ended|cancelled|failed.
  final String rawStatus;
  final int attendees;
  final NovaScene scene;
  final DateTime? scheduledAt;
  final String? scheduledLabel;

  /// Session poster; the painted [scene] stands in when absent.
  final String? image;
  final bool commentsEnabled;
  final int commentMaxLength;

  bool get cancelled => rawStatus == 'cancelled' || rawStatus == 'failed';
  bool get ended =>
      rawStatus == 'ended' || rawStatus == 'processing_replay' || rawStatus == 'ending';
}

enum NotificationGroup { today, yesterday, thisWeek, earlier }

/// Africa/Algiers is UTC+1 all year (no DST): the returned DateTime's
/// wall-clock fields are Algeria time whatever the device time zone.
DateTime algeriaTime(DateTime instant) =>
    instant.toUtc().add(const Duration(hours: 1));

/// A Student notification (`GET /me/notifications`, or the
/// `NotificationCreated` broadcast). [title] and [body] are the stored
/// (English) text; screens render them in the active language from
/// [type] and [data] (`core/i18n/notification_text.dart`).
class AppNotification {
  const AppNotification({
    required this.icon,
    required this.title,
    required this.body,
    required this.time,
    required this.read,
    required this.group,
    required this.tint,
    required this.iconColor,
    this.id = '',
    this.type = '',
    this.liveId,
    this.createdAt,
    this.data = const <String, dynamic>{},
    this.scheduledAt,
  });

  factory AppNotification.fromJson(Json json) {
    final String type = json.str('type');
    final DateTime? created = json.date('created_at');
    final NovaHue hue = _notificationHue(type);
    return AppNotification(
      id: json.str('id'),
      type: type,
      liveId: json['live_id'] is int
          ? json['live_id'] as int
          : _liveIdFromUrl(json.strOrNull('url')),
      icon: _notificationIcon(type),
      title: json.str('title'),
      body: json.str('message'),
      data: json.obj('data') ?? const <String, dynamic>{},
      scheduledAt: json.date('scheduled_at'),
      createdAt: created,
      time: '',
      read: json['read_at'] != null,
      group: _groupFor(created, DateTime.now()),
      tint: hue.surfaceStrong,
      iconColor: hue.solid,
    );
  }

  final String id;
  final String type;
  final int? liveId;
  final IconData icon;
  final String title;
  final String body;

  /// Fixed label for rows without [createdAt] (previews).
  final String time;
  final bool read;
  final NotificationGroup group;
  final DateTime? createdAt;

  /// Structured params of a system notification (`live_title`,
  /// `order_number`, `points`…).
  final Json data;
  final DateTime? scheduledAt;
  final Color tint;
  final Color iconColor;

  /// Today / Yesterday / This week / Earlier, by Algeria calendar day
  /// relative to [now].
  NotificationGroup groupAt(DateTime now) =>
      createdAt == null ? group : _groupFor(createdAt, now);

  AppNotification markedRead() => AppNotification(
        id: id,
        type: type,
        liveId: liveId,
        icon: icon,
        title: title,
        body: body,
        data: data,
        scheduledAt: scheduledAt,
        createdAt: createdAt,
        time: time,
        read: true,
        group: group,
        tint: tint,
        iconColor: iconColor,
      );

  /// Live notifications without `live_id` still link to `/live/{id}`.
  static int? _liveIdFromUrl(String? url) {
    final RegExpMatch? match =
        url == null ? null : RegExp(r'^/live/(\d+)$').firstMatch(url);
    return match == null ? null : int.tryParse(match.group(1)!);
  }

  static IconData _notificationIcon(String type) => switch (type) {
        'live_scheduled' || 'live_started' || 'live_rescheduled' =>
          Icons.sensors_rounded,
        'live_reminder' => Icons.alarm_rounded,
        'live_cancelled' => Icons.event_busy_rounded,
        'live_replay_ready' => Icons.replay_rounded,
        'lesson_published' => Icons.play_lesson_rounded,
        'purchase_paid' || 'ccp_approved' => Icons.verified_rounded,
        'ccp_rejected' => Icons.receipt_long_rounded,
        'points_credited' || 'referral_reward_credited' => Icons.stars_rounded,
        'access_closed' => Icons.lock_clock_rounded,
        _ => Icons.campaign_rounded,
      };

  static NovaHue _notificationHue(String type) => switch (type) {
        'live_scheduled' ||
        'live_started' ||
        'live_rescheduled' ||
        'live_reminder' =>
          NovaHue.sky,
        'live_replay_ready' => NovaHue.lilac,
        'lesson_published' => NovaHue.mint,
        'purchase_paid' || 'ccp_approved' => NovaHue.mint,
        'ccp_rejected' || 'live_cancelled' || 'access_closed' => NovaHue.rose,
        'points_credited' || 'referral_reward_credited' => NovaHue.butter,
        _ => NovaHue.peach,
      };

  static NotificationGroup _groupFor(DateTime? at, DateTime now) {
    if (at == null) return NotificationGroup.earlier;
    final DateTime a = algeriaTime(now);
    final DateTime b = algeriaTime(at);
    final int days = DateTime.utc(a.year, a.month, a.day)
        .difference(DateTime.utc(b.year, b.month, b.day))
        .inDays;
    if (days <= 0) return NotificationGroup.today;
    if (days == 1) return NotificationGroup.yesterday;
    if (days < 7) return NotificationGroup.thisWeek;
    return NotificationGroup.earlier;
  }
}

String _two(int n) => n.toString().padLeft(2, '0');
String _clock(DateTime at) => '${_two(at.hour)}:${_two(at.minute)}';

/// `dd/MM/yyyy` — the format the web account pages use.
String shortDate(DateTime? at) =>
    at == null ? '' : '${_two(at.day)}/${_two(at.month)}/${at.year}';

enum OrderStatus { paid, awaiting, pendingReview, rejected, cancelled, expired }

extension OrderStatusLabel on OrderStatus {
  String get label => switch (this) {
        OrderStatus.paid => 'Paid',
        OrderStatus.awaiting => 'Awaiting payment',
        OrderStatus.pendingReview => 'Pending review',
        OrderStatus.rejected => 'Receipt rejected',
        OrderStatus.cancelled => 'Cancelled',
        OrderStatus.expired => 'Expired',
      };
}

class Order {
  const Order({
    required this.number,
    required this.program,
    required this.kind,
    required this.date,
    required this.total,
    required this.status,
    required this.method,
    this.id = 0,
    this.canRetryPayment = false,
    this.quoteExpiresAt,
    this.latestPaymentStatus,
  });

  factory Order.fromJson(Json json) {
    final List<Json> items = json.list('items');
    final Json? first = items.isEmpty ? null : items.first;
    final Json? latest = json.obj('latest_payment');
    final String method = latest?.str('method') ?? '';
    final String paymentStatus = latest?.str('status') ?? '';
    return Order(
      id: json.integer('id'),
      number: json.str('order_number'),
      program: first?.str('title') ?? '',
      kind: first != null && first['offer_id'] != null ? 'Offer' : 'Course',
      date: shortDate(json.date('created_at')),
      total: dinars(json['final_amount']),
      method: switch (method) {
        'ccp' => 'CCP',
        'chargily' => 'Card',
        'points' => 'Points',
        _ => '—',
      },
      status: switch (json.str('status')) {
        'paid' => OrderStatus.paid,
        'cancelled' => OrderStatus.cancelled,
        'expired' => OrderStatus.expired,
        _ when paymentStatus == 'pending_review' => OrderStatus.pendingReview,
        _ when paymentStatus == 'rejected' => OrderStatus.rejected,
        _ => OrderStatus.awaiting,
      },
      canRetryPayment: json.flag('can_retry_payment'),
      quoteExpiresAt: json.date('quote_expires_at'),
      latestPaymentStatus: latest == null ? null : paymentStatus,
    );
  }

  final int id;
  final String number;
  final String program;
  final String kind;
  final String date;
  final int total;
  final OrderStatus status;
  final String method;
  final bool canRetryPayment;
  final DateTime? quoteExpiresAt;
  final String? latestPaymentStatus;

  /// Still payable: awaiting payment (no receipt under review) within
  /// the 30-minute quote window the backend enforces.
  bool get payable =>
      status == OrderStatus.awaiting &&
      (quoteExpiresAt == null || quoteExpiresAt!.isAfter(DateTime.now()));
}

class PointsEntry {
  const PointsEntry({
    required this.label,
    required this.date,
    required this.delta,
    required this.balance,
    this.type = '',
    this.hasReason = false,
  });

  factory PointsEntry.fromJson(Json json) {
    final String reason = json.str('reason');
    return PointsEntry(
      label: reason.isNotEmpty ? reason : _pointsLabel(json.str('type')),
      date: shortDate(json.date('created_at')),
      delta: json.integer('points_delta'),
      balance: json.integer('balance_after'),
      type: json.str('type'),
      hasReason: reason.isNotEmpty,
    );
  }

  final String label;

  /// Ledger type (`referral_reward`, `purchase_spend`...), for the
  /// label in the app language; [hasReason] when the school wrote one.
  final String type;
  final bool hasReason;
  final String date;
  final int delta;
  final int balance;

  static String _pointsLabel(String type) => switch (type) {
        'referral_reward' => 'Referral reward',
        'purchase_spend' => 'Spent on a purchase',
        'points_reservation' => 'Reserved for checkout',
        'reservation_release' => 'Reservation released',
        'admin_adjustment' => 'Adjustment by the school',
        _ => 'Points',
      };
}

class StudentProfile {
  const StudentProfile({
    required this.firstName,
    required this.lastName,
    required this.phone,
    required this.level,
    required this.track,
    required this.wilaya,
    required this.commune,
    required this.referralCode,
    required this.points,
    required this.streakDays,
    required this.handle,
    required this.bio,
    required this.lessonsCompleted,
    required this.hoursWatched,
    required this.rank,
    required this.weeklyLessons,
    this.weeklyDates = const <DateTime>[],
    this.id = 0,
    this.studentId = 0,
    this.photo,
  });

  /// From `UserResource` (`/auth/me`, `/auth/login`); activity figures
  /// are filled in from `/me/dashboard` by [withDashboard].
  factory StudentProfile.fromUser(Json user) {
    final Json student = user.obj('student') ?? <String, dynamic>{};
    String first = student.str('first_name');
    String last = student.str('last_name');
    if (first.isEmpty && last.isEmpty) {
      first = student.str('legacy_full_name');
    }
    return StudentProfile(
      id: user.integer('id'),
      studentId: student.integer('id'),
      firstName: first,
      lastName: last,
      phone: user.str('phone'),
      level: localName(student.obj('level')),
      track: localName(student.obj('track')),
      wilaya: localName(student.obj('wilaya')),
      commune: localName(student.obj('commune')),
      referralCode: student.str('referral_code'),
      points: 0,
      streakDays: 0,
      handle: '',
      bio: '',
      lessonsCompleted: 0,
      hoursWatched: 0,
      rank: 0,
      weeklyLessons: const <int>[],
    );
  }

  /// User id (`user.{id}` channel) and Student id (`student.{id}`).
  final int id;
  final int studentId;
  final String firstName;
  final String lastName;
  final String phone;
  final String level;
  final String track;
  final String wilaya;
  final String commune;
  final String referralCode;
  final int points;

  /// Not provided by the backend (UNSPECIFIED); 0 hides the figure.
  final int streakDays;
  final String handle;
  final String bio;

  /// Lessons completed since the start of the academic year.
  final int lessonsCompleted;

  /// Not provided by the backend (UNSPECIFIED); 0 hides the figure.
  final int hoursWatched;
  final int rank;

  /// Lessons completed per day over the last 7 days, oldest first.
  final List<int> weeklyLessons;

  /// The day of each [weeklyLessons] entry (dashboard `date`).
  final List<DateTime> weeklyDates;

  /// Profile picture; the backend has none for Students, so a monogram.
  final String? photo;

  String get fullName => '$firstName $lastName'.trim();

  StudentProfile withDashboard(Json dashboard) {
    final Json summary = dashboard.obj('summary') ?? <String, dynamic>{};
    return StudentProfile(
      id: id,
      studentId: studentId,
      firstName: firstName,
      lastName: lastName,
      phone: phone,
      level: level,
      track: track,
      wilaya: wilaya,
      commune: commune,
      referralCode: referralCode,
      points: summary.integer('points_balance'),
      streakDays: streakDays,
      handle: handle,
      bio: bio,
      lessonsCompleted: summary.integer('lessons_completed'),
      hoursWatched: hoursWatched,
      rank: rank,
      weeklyLessons: <int>[
        for (final Json day in dashboard.list('activity_last_7_days'))
          day.integer('lessons'),
      ],
      weeklyDates: <DateTime>[
        for (final Json day in dashboard.list('activity_last_7_days'))
          if (DateTime.tryParse(day.str('date')) != null)
            DateTime.parse(day.str('date')),
      ],
      photo: photo,
    );
  }

}

/// An Offer (the UI calls it a pack).
class Pack {
  const Pack({
    required this.name,
    required this.offerType,
    required this.courseCount,
    required this.studentCount,
    required this.price,
    required this.compareAtPrice,
    required this.tags,
    required this.scene,
    required this.icon,
    required this.headline,
    required this.description,
    required this.items,
    this.id = 0,
    this.slug = '',
    this.teachers = const <String>[],
    this.type = '',
    this.lessonsCount = 0,
    this.plannedLives = 0,
    this.image,
    this.matchesStudentProfile,
  });

  factory Pack.fromJson(Json json) {
    final int id = json.integer('id');
    final String type = json.str('type');
    final int price = dinars(json['price']);
    final int reference = dinars(json['courses_reference_total']);
    final List<PackItem> items =
        json.list('courses').map(PackItem.fromJson).toList();
    final String description = json.str('description');
    return Pack(
      id: id,
      slug: json.str('slug'),
      name: json.str('title'),
      offerType: offerTypeLabel(type),
      type: type,
      courseCount: json.integer('courses_count', items.length),
      studentCount: 0,
      price: price,
      // The reference total is the sum of the individually sold paid
      // courses; only a real saving is shown as a strike-through.
      compareAtPrice: reference > price ? reference : price,
      tags: <String>[offerTypeLabel(type)],
      scene: sceneFor(id + 3),
      icon: Icons.auto_awesome_rounded,
      headline: json.str('title'),
      description: description,
      items: items,
      teachers: json.list('teachers').map(personName).toList(),
      lessonsCount: json.integer('lessons_count'),
      plannedLives: json.integer('planned_live_count'),
      image: json.strOrNull('cover_url') ?? json.strOrNull('cover_original_url'),
      matchesStudentProfile: _profileMatch(json),
    );
  }

  final int id;
  final String slug;
  final String name;
  final String offerType;

  /// Backend offer type code (`dawra`, `trimestre`...).
  final String type;
  final int courseCount;

  /// Not exposed by the public API; 0 hides it.
  final int studentCount;
  final int price;
  final int compareAtPrice;
  final List<String> tags;
  final NovaScene scene;
  final IconData icon;
  final String headline;
  final String description;
  final List<PackItem> items;
  final List<String> teachers;
  final int lessonsCount;
  final int plannedLives;

  /// Offer poster; the painted [scene] stands in when absent.
  final String? image;

  /// Public detail only (D-083): false when a Course of the Offer is outside
  /// the signed-in Student's level or filière; null when not said.
  final bool? matchesStudentProfile;

  int get discountPercent => compareAtPrice > price
      ? (((compareAtPrice - price) / compareAtPrice) * 100).round()
      : 0;
}

String offerTypeLabel(String type) => switch (type) {
      'dawra' => 'Dawra',
      'trimestre' => 'Trimester',
      'semester' => 'Semester',
      'annual' => 'Annual',
      'multi_teacher' => 'Multi-teacher',
      'custom' => 'Custom',
      _ => 'Offer',
    };

class Course {
  const Course({
    required this.title,
    required this.teacher,
    required this.price,
    required this.compareAtPrice,
    required this.subject,
    required this.level,
    required this.scene,
    required this.icon,
    required this.description,
    required this.plannedLives,
    required this.lessons,
    this.id = 0,
    this.slug = '',
    this.teacherId = 0,
    this.teacherPhoto,
    this.subjectId = 0,
    this._lessonsCount = 0,
    this.apiProgress,
    this.apiCompletedLessons,
    this.owned = false,
    this.individualPurchaseEnabled = true,
    this.isFree = false,
    this.image,
    this.matchesStudentProfile,
    this.offerPriceFrom,
    this.packs = const <CoursePack>[],
  });

  /// `PublicCourseResource` (list or detail, with `lessons[]` on detail).
  factory Course.fromJson(Json json, {bool owned = false}) {
    final int id = json.integer('id');
    final Json? subject = json.obj('subject');
    final List<Lesson> lessons =
        json.list('lessons').map(Lesson.fromJson).toList();
    final int price = dinars(json['reference_price']);
    final Json? teacher = json.obj('teacher');
    return Course(
      id: id,
      slug: json.str('slug'),
      title: json.str('title'),
      teacher: personName(teacher),
      teacherId: teacher?.integer('id') ?? 0,
      teacherPhoto: teacher?.strOrNull('photo_url'),
      price: price,
      compareAtPrice: price,
      subject: localName(subject),
      subjectId: subject?.integer('id') ?? 0,
      level: localName(json.obj('level')),
      scene: sceneFor(id),
      icon: subjectIcon(subject?.str('code') ?? ''),
      description: json.str('description'),
      plannedLives: json.integer('planned_live_count'),
      lessons: lessons,
      lessonsCount: json.integer('lessons_count', lessons.length),
      owned: owned,
      individualPurchaseEnabled: json.flag('individual_purchase_enabled', true),
      isFree: json.flag('is_free'),
      image: json.strOrNull('cover_url') ?? json.strOrNull('cover_original_url'),
      matchesStudentProfile: _profileMatch(json),
      offerPriceFrom: json['offer_price_from'] == null ? null : dinars(json['offer_price_from']),
      packs: json.list('offers').map(CoursePack.fromJson).toList(),
    );
  }

  final int id;
  final String slug;
  final String title;
  final String teacher;
  final int teacherId;
  final String? teacherPhoto;
  final int price;
  final int compareAtPrice;
  final String subject;
  final int subjectId;
  final String level;
  final NovaScene scene;
  final IconData icon;
  final String description;
  final int plannedLives;
  final List<Lesson> lessons;

  /// `lessons_count` from the API; the curriculum length when unknown.
  int get lessonsCount => _lessonsCount > 0 ? _lessonsCount : lessons.length;
  final int _lessonsCount;

  /// Server progress (`progress_percent`) when known.
  final int? apiProgress;

  /// Server count of completed lessons (dashboard), used before the
  /// curriculum itself is loaded.
  final int? apiCompletedLessons;

  /// Active access grant for the signed-in Student.
  final bool owned;

  /// When false the course is only reachable through an Offer.
  final bool individualPurchaseEnabled;

  /// Open to every Student at no cost and never sold (D-054). Mirrors
  /// `courses.is_free`; [price] keeps its catalogue meaning.
  final bool isFree;

  /// Course poster; the painted [scene] stands in when absent.
  final String? image;

  /// Public detail only (D-083): false when the signed-in Student's level
  /// or filière is not this Course's; null when not said.
  final bool? matchesStudentProfile;

  /// D-091, sold through Packs only: the cheapest Pack price, null while
  /// no Pack is on sale (or when the Unit is sold on its own).
  final int? offerPriceFrom;

  /// D-091, public detail of a Unit sold through Packs only: the Packs
  /// the Student can buy, cheapest first.
  final List<CoursePack> packs;

  /// A paid Unit never sold on its own (D-091): Buy and Add act on one
  /// of its Packs.
  bool get packOnly => !isFree && !individualPurchaseEnabled;

  /// The price the catalogue shows and filters on: the cheapest Pack for
  /// a Unit sold through Packs only (null while none is on sale, D-091).
  int? get cataloguePrice => packOnly ? offerPriceFrom : price;

  int get discountPercent => compareAtPrice > price
      ? (((compareAtPrice - price) / compareAtPrice) * 100).round()
      : 0;

  int get completedLessons => lessons.isEmpty && apiCompletedLessons != null
      ? apiCompletedLessons!
      : lessons.where((l) => l.completed).length;

  /// Duration-weighted progress, per the conception formula; the
  /// server's figure wins when it is known.
  int get progressPercent {
    if (apiProgress != null) return apiProgress!;
    final int totalMinutes = lessons.fold(0, (int s, Lesson l) => s + l.minutes);
    if (totalMinutes == 0) return 0;
    final int earned = lessons.fold(
      0,
      (int s, Lesson l) => s + (l.watched * l.minutes) ~/ 100,
    );
    return (earned * 100) ~/ totalMinutes;
  }

  Course copyWith({
    bool? owned,
    List<Lesson>? lessons,
    int? apiProgress,
  }) =>
      Course(
        id: id,
        slug: slug,
        title: title,
        teacher: teacher,
        teacherId: teacherId,
        teacherPhoto: teacherPhoto,
        price: price,
        compareAtPrice: compareAtPrice,
        subject: subject,
        subjectId: subjectId,
        level: level,
        scene: scene,
        icon: icon,
        description: description,
        plannedLives: plannedLives,
        lessons: lessons ?? this.lessons,
        lessonsCount: _lessonsCount,
        apiProgress: apiProgress ?? this.apiProgress,
        apiCompletedLessons: apiCompletedLessons,
        owned: owned ?? this.owned,
        individualPurchaseEnabled: individualPurchaseEnabled,
        isFree: isFree,
        image: image,
        matchesStudentProfile: matchesStudentProfile,
        offerPriceFrom: offerPriceFrom,
        packs: packs,
      );
}

/// A Pack containing a Unit sold through Packs only (`offers[]` of the
/// public Course detail, D-091).
class CoursePack {
  const CoursePack({
    required this.id,
    required this.slug,
    required this.title,
    required this.type,
    required this.price,
  });

  factory CoursePack.fromJson(Json json) => CoursePack(
        id: json.integer('id'),
        slug: json.str('slug'),
        title: json.str('title'),
        type: json.str('type'),
        price: dinars(json['price']),
      );

  final int id;
  final String slug;
  final String title;
  final String type;
  final int price;
}

class Teacher {
  const Teacher({
    required this.name,
    required this.subject,
    required this.scene,
    required this.bio,
    required this.subjects,
    this.id = 0,
    this.photo,
  });

  factory Teacher.fromJson(Json json) {
    final List<String> subjects =
        json.list('subjects').map((Json s) => localName(s)).toList();
    final int id = json.integer('id');
    return Teacher(
      id: id,
      name: personName(json),
      subject: subjects.isEmpty ? '' : subjects.first,
      subjects: subjects,
      scene: sceneFor(id + 1),
      bio: json.str('bio'),
      photo: json.strOrNull('photo_url'),
    );
  }

  final int id;
  final String name;
  final String subject;
  final NovaScene scene;
  final String bio;
  final List<String> subjects;

  /// Portrait URL; a monogram stands in when absent.
  final String? photo;
}

/// A profile badge: earned milestones plus the next one to chase.
class Achievement {
  const Achievement({
    required this.title,
    required this.caption,
    required this.icon,
    required this.hue,
    this.locked = false,
  });

  final String title;
  final String caption;
  final IconData icon;
  final NovaHue hue;

  /// Still to earn — rendered dimmed behind a lock.
  final bool locked;
}

/// `matches_student_profile` of a public detail (D-083), when present.
bool? _profileMatch(Json json) {
  final Object? value = json['matches_student_profile'];
  return value is bool ? value : null;
}
