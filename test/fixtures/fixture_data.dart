import 'package:flutter/material.dart';

import 'package:nova_mobile/data/models.dart';

import 'package:nova_mobile/core/theme/nova_colors.dart';
import 'package:nova_mobile/core/widgets/nova_scene_image.dart';

/// Mock catalog content shaped after the Nova domain (Offers shown as
/// "packs", Courses with Lessons/Quizzes/PDF resources, Teacher
/// profiles, Lives, Orders, Points ledger) so the screens can be wired
/// to the Laravel `/api/v1` endpoints without structural changes.
///
/// Business rules mirrored from the conception: 90% video completion,
/// sequential lesson locking, quiz 70% pass / 3 attempts / 24h
/// cooldown, Academic-Year access, Chargily + CCP + points checkout.
///
/// UNSPECIFIED: final copy, pricing and imagery come from the backend.
abstract final class HomeData {
  static const int notificationCount = 2;

  // Greeting (mock Student until auth is wired).
  static const String studentName = 'Ines';
  static const String greetingSubtitle = 'Welcome to NOVA';

  // Search and subject filters.
  static const String searchHint = 'Search';
  static const String allSubjects = 'All';
  static const List<String> subjects = [
    allSubjects,
    'Mathematics',
    'Physics',
    'Science',
    'English',
    'Philosophy',
  ];

  static const List<Pack> featuredPacks = [
    Pack(
      id: 201,
      slug: 'pack-1',
      name: 'Science Track — Complete Year',
      image: 'assets/images/packs/science_track.jpg',
      offerType: 'Annual',
      courseCount: 6,
      studentCount: 348,
      price: 18900,
      compareAtPrice: 24800,
      tags: ['Mathematics', 'Physics', 'Science'],
      scene: NovaScene.azure,
      icon: Icons.workspace_premium_rounded,
      headline: 'A brighter tomorrow',
      description:
          'Every Science-track course of the academic year in one offer, '
          'with planned lives and replays included.',
      items: [
        PackItem(courseTitle: 'Mathematics — Problem Solving Lab', allocated: 4200),
        PackItem(courseTitle: 'Physics — Mechanics Masterclass', allocated: 4200),
        PackItem(courseTitle: 'Science — Full Curriculum', allocated: 3800),
      ],
    ),
    Pack(
      id: 202,
      slug: 'pack-2',
      name: 'Maths + Physics Power Pack',
      image: 'assets/images/packs/power_pack.jpg',
      offerType: 'Semester',
      courseCount: 2,
      studentCount: 132,
      price: 7900,
      compareAtPrice: 10400,
      tags: ['Mathematics', 'Physics'],
      scene: NovaScene.azure,
      icon: Icons.functions_rounded,
      headline: 'Level up every day',
      description:
          'The problem-solving double act: both flagship courses with '
          'their quizzes, PDFs and lives.',
      items: [
        PackItem(courseTitle: 'Mathematics — Problem Solving Lab', allocated: 4500),
        PackItem(courseTitle: 'Physics — Mechanics Masterclass', allocated: 3400),
      ],
    ),
    Pack(
      id: 203,
      slug: 'pack-3',
      name: 'BAC Essentials',
      image: 'assets/images/packs/bac_essentials.jpg',
      offerType: 'Dawra',
      courseCount: 4,
      studentCount: 201,
      price: 12500,
      compareAtPrice: 15600,
      tags: ['Philosophy', 'English', 'Arabic'],
      scene: NovaScene.azure,
      icon: Icons.school_rounded,
      headline: 'Own your BAC year',
      description:
          'The focused BAC revision offer: essay method, exam English and '
          'the full philosophy blueprint.',
      items: [
        PackItem(courseTitle: 'Philosophy — Essay Blueprint', allocated: 3600),
        PackItem(courseTitle: 'English — Exam Boost', allocated: 2900),
        PackItem(courseTitle: 'Arabic — Method & Style', allocated: 3100),
      ],
    ),
  ];

  static const List<Course> popularCourses = [
    Course(
      id: 101,
      slug: 'math-lab',
      teacherId: 1,
      teacherPhoto: 'assets/images/people/teacher_yacine.jpg',
      title: 'Mathematics — Problem Solving Lab',
      image: 'assets/images/courses/mathematics.jpg',
      teacher: 'Yacine Belkacem',
      price: 4800,
      compareAtPrice: 6200,
      subject: 'Mathematics',
      subjectId: 11,
      level: '3AS',
      scene: NovaScene.midnight,
      icon: Icons.calculate_rounded,
      description:
          'A problem-first laboratory: each lesson attacks a family of '
          'exam exercises, then locks it in with a short checkpoint quiz '
          'and a private method sheet.',
      plannedLives: 12,
      lessons: [
        Lesson(
          title: 'Reading an exam statement',
          minutes: 24,
          watched: 100,
          pdf: 'Method sheet — statements',
        ),
        Lesson(
          title: 'Sequences: convergence reflexes',
          minutes: 32,
          watched: 64,
          pdf: 'Recap — sequences',
          quiz: QuizData(
            questionCount: 5,
            required: true,
            attemptsUsed: 1,
            bestScore: 60,
          ),
        ),
        Lesson(
          title: 'Limits at the BAC — the 6 traps',
          minutes: 28,
          watched: 0,
          quiz: QuizData(
            questionCount: 4,
            required: true,
            attemptsUsed: 0,
            bestScore: 0,
          ),
        ),
        Lesson(title: 'Continuity workshop', minutes: 26, watched: 0),
        Lesson(
          title: 'Derivatives: the full toolkit',
          minutes: 38,
          watched: 0,
          pdf: 'Toolkit — derivatives',
        ),
      ],
    ),
    Course(
      id: 102,
      slug: 'physics-mechanics',
      teacherId: 2,
      teacherPhoto: 'assets/images/people/teacher_amel.jpg',
      title: 'Physics — Mechanics Masterclass',
      image: 'assets/images/courses/physics.jpg',
      teacher: 'Amel Khaldi',
      price: 4200,
      compareAtPrice: 5400,
      subject: 'Physics',
      subjectId: 12,
      level: '3AS',
      scene: NovaScene.sand,
      icon: Icons.rocket_launch_rounded,
      description:
          'From forces to flight: mechanics rebuilt around experiments, '
          'with checkpoint quizzes after every concept and protected '
          'formula sheets.',
      plannedLives: 8,
      owned: true,
      lessons: [
        Lesson(
          title: 'Reference frames & relativity of motion',
          minutes: 22,
          watched: 100,
        ),
        Lesson(
          title: "Newton's laws in exam conditions",
          minutes: 30,
          watched: 100,
          pdf: 'Recap — Newton',
        ),
        Lesson(
          title: 'Energy: the safest points',
          minutes: 27,
          watched: 55,
          quiz: QuizData(
            questionCount: 6,
            required: true,
            attemptsUsed: 2,
            bestScore: 83,
          ),
        ),
        Lesson(title: 'Momentum & collisions', minutes: 25, watched: 0),
      ],
    ),
    Course(
      id: 103,
      slug: 'philosophy-essay',
      teacherId: 3,
      teacherPhoto: 'assets/images/people/teacher_karim.jpg',
      title: 'Philosophy — Essay Blueprint',
      image: 'assets/images/courses/philosophy.jpg',
      teacher: 'Karim Tounsi',
      price: 3600,
      compareAtPrice: 4600,
      subject: 'Philosophy',
      subjectId: 13,
      level: '3AS',
      scene: NovaScene.dusk,
      icon: Icons.history_edu_rounded,
      description:
          'Method before memory: the essay blueprint that works for any '
          'BAC subject, with graded dissertation breakdowns.',
      plannedLives: 6,
      owned: true,
      lessons: [
        Lesson(
          title: 'The problem in 3 moves',
          minutes: 20,
          watched: 100,
          quiz: QuizData(
            questionCount: 4,
            required: false,
            attemptsUsed: 1,
            bestScore: 100,
          ),
        ),
        Lesson(
          title: 'Building the plan',
          minutes: 24,
          watched: 100,
          pdf: 'Blueprint — plans',
        ),
        Lesson(title: 'From plan to paragraphs', minutes: 26, watched: 100),
      ],
    ),
    Course(
      id: 104,
      slug: 'english-boost',
      teacherId: 4,
      teacherPhoto: 'assets/images/people/teacher_sarah.jpg',
      title: 'English — Exam Boost',
      image: 'assets/images/courses/english.jpg',
      teacher: 'Sarah Mansouri',
      price: 2900,
      compareAtPrice: 2900,
      subject: 'English',
      subjectId: 14,
      level: '3AS',
      scene: NovaScene.sage,
      icon: Icons.translate_rounded,
      description:
          'Everything the BAC English paper asks: reading strategies, '
          'writing frames and the tense system, drilled weekly.',
      plannedLives: 4,
      individualPurchaseEnabled: false,
      lessons: [
        Lesson(title: 'Reading: timing the paper', minutes: 18, watched: 0),
        Lesson(title: 'The tense system, once and for all', minutes: 22, watched: 0),
      ],
    ),
  ];

  static const List<Teacher> teachers = [
    Teacher(
      id: 1,
      name: 'Yacine Belkacem',
      photo: 'assets/images/people/teacher_yacine.jpg',
      subject: 'Mathematics',
      scene: NovaScene.sunrise,
      bio:
          'Ten years of BAC mathematics in Algiers. Obsessed with exam '
          'reflexes: read less, solve more, check everything.',
      subjects: ['Mathematics'],
    ),
    Teacher(
      id: 2,
      name: 'Amel Khaldi',
      photo: 'assets/images/people/teacher_amel.jpg',
      subject: 'Physics',
      scene: NovaScene.amber,
      bio:
          'Physics teacher and former lab engineer. Turns every mechanics '
          'chapter into an experiment you can picture under exam stress.',
      subjects: ['Physics', 'Science'],
    ),
    Teacher(
      id: 3,
      name: 'Karim Tounsi',
      photo: 'assets/images/people/teacher_karim.jpg',
      subject: 'Philosophy',
      scene: NovaScene.dusk,
      bio:
          'Philosophy corrector for national exams. Teaches the essay as '
          'a craft: a sharp problem, an honest plan, clean sentences.',
      subjects: ['Philosophy'],
    ),
    Teacher(
      id: 4,
      name: 'Sarah Mansouri',
      photo: 'assets/images/people/teacher_sarah.jpg',
      subject: 'English',
      scene: NovaScene.blush,
      bio:
          'English teacher focused on BAC papers. Weekly drills, clear '
          'frames and vocabulary that actually scores.',
      subjects: ['English'],
    ),
    Teacher(
      id: 5,
      name: 'Nadia Haddad',
      photo: 'assets/images/people/teacher_nadia.jpg',
      subject: 'Science',
      scene: NovaScene.sage,
      bio:
          'Science teacher for the full 3AS curriculum — SVT and physics '
          'chapters rehearsed with past-exam calendars.',
      subjects: ['Science'],
    ),
  ];

  /// Lives across the platform (one live at a time platform-wide).
  static const List<LiveSession> lives = [
    LiveSession(
      id: 301,
      title: 'Limits at the BAC — the 6 traps',
      course: 'Mathematics — Problem Solving Lab',
      image: 'assets/images/courses/mathematics.jpg',
      teacher: 'Yacine Belkacem',
      subject: 'Mathematics',
      status: LiveStatus.live,
      attendees: 486,
      scene: NovaScene.midnight,
    ),
    LiveSession(
      id: 302,
      title: 'Energy questions: the safest points',
      course: 'Physics — Mechanics Masterclass',
      image: 'assets/images/courses/physics.jpg',
      teacher: 'Amel Khaldi',
      subject: 'Physics',
      status: LiveStatus.scheduled,
      scheduledLabel: 'Tonight · 18:00',
      attendees: 0,
      scene: NovaScene.sand,
    ),
    LiveSession(
      id: 303,
      title: 'The problem in 3 moves — live rehearsal',
      course: 'Philosophy — Essay Blueprint',
      image: 'assets/images/courses/philosophy.jpg',
      teacher: 'Karim Tounsi',
      subject: 'Philosophy',
      status: LiveStatus.replay,
      attendees: 612,
      scene: NovaScene.dusk,
    ),
    LiveSession(
      id: 304,
      title: 'Reading: timing the paper',
      course: 'English — Exam Boost',
      image: 'assets/images/courses/english.jpg',
      teacher: 'Sarah Mansouri',
      subject: 'English',
      status: LiveStatus.scheduled,
      scheduledLabel: 'Tomorrow · 17:30',
      attendees: 0,
      scene: NovaScene.sage,
    ),
  ];

  static const List<AppNotification> notifications = [
    AppNotification(
      icon: Icons.podcasts_rounded,
      title: 'Live started',
      body: '"Limits at the BAC — the 6 traps" is live now. Join before '
          'the room fills up.',
      time: 'Just now',
      read: false,
      group: NotificationGroup.today,
      tint: Color(0xFFDCEBFE),
      iconColor: Color(0xFF2B87F7),
    ),
    AppNotification(
      icon: Icons.movie_rounded,
      title: 'Replay available',
      body: 'The replay of "The problem in 3 moves — live rehearsal" is '
          'ready to watch.',
      time: '2 h ago',
      read: false,
      group: NotificationGroup.today,
      tint: Color(0xFFEFE7FE),
      iconColor: Color(0xFF8B5CF6),
    ),
    AppNotification(
      icon: Icons.play_lesson_rounded,
      title: 'New lesson published',
      body: '"Limits at the BAC — the 6 traps" was added to Mathematics '
          '— Problem Solving Lab.',
      time: 'Yesterday',
      read: true,
      group: NotificationGroup.yesterday,
      tint: Color(0xFFDFF3E7),
      iconColor: Color(0xFF1FA97A),
    ),
    AppNotification(
      icon: Icons.receipt_long_rounded,
      title: 'CCP payment approved',
      body: 'Your receipt for BAC Essentials was approved. Access is '
          'active for the academic year.',
      time: '2 days ago',
      read: true,
      group: NotificationGroup.thisWeek,
      tint: Color(0xFFFDEFD9),
      iconColor: Color(0xFFF18A50),
    ),
    AppNotification(
      icon: Icons.stars_rounded,
      title: 'Referral points earned',
      body: 'Amine created his account with your code and made his first '
          'purchase. +600 points credited.',
      time: '3 days ago',
      read: true,
      group: NotificationGroup.thisWeek,
      tint: Color(0xFFFBE2E3),
      iconColor: Color(0xFFE5484D),
    ),
  ];

  static const List<Order> orders = [
    Order(
      number: 'ORD-2412-0048',
      program: 'Physics — Mechanics Masterclass',
      kind: 'Individual Course',
      date: '12 Sep 2026',
      total: 4200,
      status: OrderStatus.paid,
      method: 'Card · CIB',
    ),
    Order(
      number: 'ORD-2412-0041',
      program: 'BAC Essentials',
      kind: 'Offer',
      date: '08 Sep 2026',
      total: 12500,
      status: OrderStatus.pendingReview,
      method: 'CCP transfer',
    ),
    Order(
      number: 'ORD-2409-0312',
      program: 'Philosophy — Essay Blueprint',
      kind: 'Individual Course',
      date: '21 Aug 2026',
      total: 3600,
      status: OrderStatus.awaiting,
      method: 'Card · EDAHABIA',
    ),
    Order(
      number: 'ORD-2409-0287',
      program: 'English — Exam Boost',
      kind: 'Individual Course',
      date: '02 Aug 2026',
      total: 2900,
      status: OrderStatus.paid,
      method: 'Points',
    ),
  ];

  /// Newest first; each balance is the running total after the entry,
  /// so the list reconciles down to [student]'s points.
  static const List<PointsEntry> pointsLedger = [
    PointsEntry(
      label: 'Referral reward — Amine B.',
      date: '14 Sep',
      delta: 600,
      balance: 750,
    ),
    PointsEntry(
      label: 'Redeemed on order ORD-2409-0287',
      date: '02 Aug',
      delta: -300,
      balance: 150,
    ),
    PointsEntry(
      label: 'Purchase — English — Exam Boost',
      date: '12 Jul',
      delta: 290,
      balance: 450,
    ),
    PointsEntry(
      label: 'Welcome bonus',
      date: '03 Jul',
      delta: 160,
      balance: 160,
    ),
  ];

  static const StudentProfile student = StudentProfile(
    firstName: 'Ines',
    lastName: 'Benali',
    phone: '0550 12 34 56',
    level: '3AS',
    track: 'Sciences',
    wilaya: 'Alger',
    commune: 'Hydra',
    referralCode: 'INES-4F82',
    points: 750,
    streakDays: 6,
    handle: 'ines.benali',
    bio: '3AS Sciences · chasing a 17 in maths. Lives every Tuesday.',
    lessonsCompleted: 78,
    hoursWatched: 43,
    rank: 12,
    weeklyLessons: [4, 2, 7, 3, 6, 1, 5],
    photo: 'assets/images/people/student_ines.jpg',
  );

  /// Weekday initials for the activity chart, Monday first.
  static const List<String> weekdayLabels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  /// Lessons completed per week of the current month.
  static const List<int> monthlyLessons = [12, 16, 14, 28];
  static const List<String> monthLabels = ['W1', 'W2', 'W3', 'W4'];

  /// Classmates behind the avatar stacks on course and live cards.
  /// UNSPECIFIED: real cohorts come from /api/v1.
  static const List<String> classmates = [
    'Nadir Cherif',
    'Lina Haddad',
    'Sofiane Merabet',
    'Rania Ouali',
    'Adel Ziani',
  ];

  /// Portraits for the first classmates in the stacks, by name.
  static const Map<String, String> classmatePhotos = {
    'Nadir Cherif': 'assets/images/people/classmate_1.jpg',
    'Lina Haddad': 'assets/images/people/classmate_2.jpg',
    'Sofiane Merabet': 'assets/images/people/classmate_3.jpg',
  };

  /// Portrait for a teacher by display name, when one exists.
  static String? teacherPhoto(String name) {
    for (final Teacher teacher in teachers) {
      if (teacher.name == name) return teacher.photo;
    }
    return null;
  }

  /// Earned and in-progress badges on the profile.
  static const List<Achievement> achievements = [
    Achievement(
      title: 'Week streak',
      caption: '6 days in a row',
      icon: Icons.local_fire_department_rounded,
      hue: NovaHue.peach,
    ),
    Achievement(
      title: 'Quiz ace',
      caption: '8 passed first try',
      icon: Icons.workspace_premium_rounded,
      hue: NovaHue.butter,
    ),
    Achievement(
      title: 'Live regular',
      caption: '11 sessions attended',
      icon: Icons.podcasts_rounded,
      hue: NovaHue.rose,
    ),
    Achievement(
      title: 'Top 15',
      caption: 'Rank 12 this month',
      icon: Icons.emoji_events_rounded,
      hue: NovaHue.mint,
      locked: true,
    ),
  ];

  // Registration reference data (Admin-managed academic identity).
  static const List<String> levels = ['1AM', '2AM', '3AM', '4AM', '1AS', '2AS', '3AS'];
  static const List<String> tracks = ['Sciences', 'Mathematics', 'Letters', 'Languages'];
  static const Map<String, List<String>> wilayas = {
    'Alger': ['Hydra', 'El Biar', 'Bab Ezzouar', 'Kouba'],
    'Oran': ['Oran', 'Bir El Djir', 'Es Sénia'],
    'Blida': ['Blida', 'Boufarik', 'Ouled Yaïch'],
    'Constantine': ['Constantine', 'El Khroub', 'Hamma Bouziane'],
    'Sétif': ['Sétif', 'El Eulma', 'Aïn Oulmène'],
  };
}

