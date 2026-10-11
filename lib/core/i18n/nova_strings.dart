import 'package:flutter/material.dart';

import '../state/app_state.dart';

/// All user-facing UI chrome in the three shipped languages.
/// Domain content (course titles, teacher names, lesson bodies…) comes
/// from the backend, so it stays as-is.
///
/// Usage: `context.tr(K.explore)` — templates replace `{n}`-style
/// tokens via [context.trf].
const Map<String, Map<String, String>> K = {
  // Tabs & menu.
  'tab.home': {'en': 'Home', 'fr': 'Accueil', 'ar': 'الدار'},
  'tab.explore': {'en': 'Explore', 'fr': 'Explorer', 'ar': 'استكشاف'},
  'tab.myCourses': {'en': 'My lessons', 'fr': 'Cours', 'ar': 'دروسي'},
  'tab.cart': {'en': 'Cart', 'fr': 'Panier', 'ar': 'السلة'},
  'tab.profile': {'en': 'Account', 'fr': 'Compte', 'ar': 'حسابي'},

  'menu.close': {'en': 'Close', 'fr': 'Fermer', 'ar': 'إغلاق'},
  'menu.darkMode': {'en': 'Dark mode', 'fr': 'Mode sombre', 'ar': 'الوضع الداكن'},
  'menu.language': {'en': 'Language', 'fr': 'Langue', 'ar': 'اللغة'},

  // Home.
  'home.hello': {'en': 'Hello', 'fr': 'Bonjour', 'ar': 'مرحباً'},
  'home.searchHint': {'en': 'Search', 'fr': 'Rechercher', 'ar': 'بحث'},
  'home.welcome': {'en': 'Welcome to NOVA', 'fr': 'Bienvenue sur NOVA', 'ar': 'مرحباً بك في NOVA'},
  'home.learnToday': {'en': 'LEARN TODAY', 'fr': 'APPRENDS AUJOURD’HUI', 'ar': 'تعلّم اليوم'},

  // Backend codes shown to Students, in the website's wording.
  'offer.type_dawra': {'en': 'Dawra', 'fr': 'Dawra', 'ar': 'دورة'},
  'offer.type_trimestre': {'en': 'Trimester', 'fr': 'Trimestre', 'ar': 'فصلي'},
  'offer.type_annual': {'en': 'Annual', 'fr': 'Annuel', 'ar': 'سنوي'},
  'offer.type_semester': {'en': 'Semester', 'fr': 'Semestre', 'ar': 'سداسي'},
  'offer.type_multi_teacher': {'en': 'Multi-teacher', 'fr': 'Multi-enseignants', 'ar': 'متعدد الأساتذة'},
  'offer.type_custom': {'en': 'Custom', 'fr': 'Sur mesure', 'ar': 'مخصص'},
  'points.type_referral_reward': {'en': 'Friend invite reward', 'fr': 'Récompense de parrainage', 'ar': 'مكافأة دعوة صديق'},
  'points.type_points_reservation': {'en': 'Held for your Order', 'fr': 'Réservés pour votre commande', 'ar': 'محجوزة لطلبك'},
  'points.type_reservation_release': {'en': 'Returned to you', 'fr': 'Rendus sur votre solde', 'ar': 'أُعيدت إلى رصيدك'},
  'points.type_purchase_spend': {'en': 'Used on a purchase', 'fr': 'Utilisés pour un achat', 'ar': 'استُعملت في عملية شراء'},
  'points.type_admin_adjustment': {'en': 'Adjusted by NOVA', 'fr': 'Ajustés par NOVA', 'ar': 'تعديل من نوفا'},
  'points.type_reversal': {'en': 'Correction', 'fr': 'Correction', 'ar': 'تصحيح'},
  'kind.offer': {'en': 'Offer', 'fr': 'Offre', 'ar': 'عرض'},
  'kind.course': {'en': 'Course', 'fr': 'Cours', 'ar': 'دورة'},
  'kind.individualCourse': {'en': 'Individual course', 'fr': 'Cours individuel', 'ar': 'دورة فردية'},
  'method.card': {'en': 'Card', 'fr': 'Carte', 'ar': 'بطاقة'},
  'method.points': {'en': 'Points', 'fr': 'Points', 'ar': 'نقاط'},
  'wallet.balanceShort': {'en': 'bal. {n}', 'fr': 'solde {n}', 'ar': 'الرصيد {n}'},
  'common.prof': {'en': 'Prof. {name}', 'fr': 'Prof. {name}', 'ar': 'الأستاذ {name}'},
  'auth.passwordHint': {'en': '8+ characters', 'fr': '8 caractères minimum', 'ar': '8 أحرف على الأقل'},
  'auth.fieldRequired': {'en': 'This field is required.', 'fr': 'Ce champ est obligatoire.', 'ar': 'هذا الحقل مطلوب.'},
  'auth.checkFields': {
    'en': 'Check the highlighted fields.',
    'fr': 'Vérifie les champs signalés.',
    'ar': 'تحقق من الحقول المشار إليها.',
  },
  'menu.studentApp': {'en': 'Student app', 'fr': 'Application élève', 'ar': 'تطبيق الطالب'},
  'home.popular': {'en': 'Popular courses', 'fr': 'Cours populaires', 'ar': 'الدورات الأكثر رواجاً'},
  'home.ourTeachers': {'en': 'Our teachers', 'fr': 'Nos professeurs', 'ar': 'أساتذتنا'},
  'common.seeAll': {'en': 'See all', 'fr': 'Tout voir', 'ar': 'عرض الكل'},
  'common.back': {'en': 'Back', 'fr': 'Retour', 'ar': 'ارجع'},
  'common.open': {'en': 'Open', 'fr': 'Ouvrir', 'ar': 'فتح'},
  'common.owned': {'en': 'Owned', 'fr': 'Acquis', 'ar': 'مُقتنى'},
  'common.notifications': {'en': 'Notifications', 'fr': 'Notifications', 'ar': 'الإشعارات'},
  'common.filters': {'en': 'Filters', 'fr': 'Filtres', 'ar': 'التصفية'},

  // Filter sheet (Explore).
  'filter.title': {'en': 'Filters', 'fr': 'Filtres', 'ar': 'التصفية'},
  'filter.reset': {'en': 'Reset', 'fr': 'Réinitialiser', 'ar': 'إعادة تعيين'},
  'filter.resetAll': {'en': 'Reset filters', 'fr': 'Réinitialiser les filtres', 'ar': 'إعادة تعيين الفلاتر'},
  'filter.teachers': {'en': 'Teachers', 'fr': 'Professeurs', 'ar': 'الأساتذة'},
  'filter.subjects': {'en': 'Subjects', 'fr': 'Matières', 'ar': 'المواد'},
  'filter.any': {'en': 'Any', 'fr': 'Tous', 'ar': 'الكل'},
  'filter.selected': {'en': '{n} selected', 'fr': '{n} choisi(s)', 'ar': '{n} محدد'},
  'filter.clear': {'en': 'Clear {label}', 'fr': 'Effacer {label}', 'ar': 'مسح {label}'},
  'filter.maxPrice': {'en': 'Max price', 'fr': 'Prix maximum', 'ar': 'الحد الأقصى للسعر'},
  'filter.anyPrice': {'en': 'Any price', 'fr': 'Tous les prix', 'ar': 'أي سعر'},
  'filter.upTo': {'en': 'Up to {price}', 'fr': 'Jusqu’à {price}', 'ar': 'حتى {price}'},
  'filter.onlyFree': {'en': 'Only free', 'fr': 'Gratuits uniquement', 'ar': 'المجانية فقط'},
  'filter.noFree': {
    'en': 'No free courses right now',
    'fr': 'Aucun cours gratuit pour le moment',
    'ar': 'لا توجد دورات مجانية حالياً',
  },
  'filter.oneFree': {'en': '1 course open to everyone', 'fr': '1 cours ouvert à tous', 'ar': 'دورة واحدة مفتوحة للجميع'},
  'filter.manyFree': {
    'en': '{n} courses open to everyone',
    'fr': '{n} cours ouverts à tous',
    'ar': '{n} دورات مفتوحة للجميع',
  },
  'filter.apply': {'en': 'Apply filters', 'fr': 'Appliquer les filtres', 'ar': 'تطبيق الفلاتر'},
  'filter.showResults': {'en': 'Show results', 'fr': 'Afficher les résultats', 'ar': 'عرض النتائج'},
  'filter.noResults': {'en': 'No results match', 'fr': 'Aucun résultat', 'ar': 'لا توجد نتائج مطابقة'},
  'filter.showOne': {'en': 'Show 1 result', 'fr': 'Afficher 1 résultat', 'ar': 'عرض نتيجة واحدة'},
  'filter.showMany': {'en': 'Show {n} results', 'fr': 'Afficher {n} résultats', 'ar': 'عرض {n} نتيجة'},

  // Explore.
  'explore.title': {'en': 'Explore', 'fr': 'Explorer', 'ar': 'استكشاف'},
  'explore.searchHint': {
    'en': 'Search courses, offers or teachers',
    'fr': 'Rechercher cours, offres ou professeurs',
    'ar': 'ابحث عن دورات أو عروض أو أساتذة',
  },
  'seg.courses': {'en': 'Courses', 'fr': 'Cours', 'ar': 'دورات'},
  'seg.packs': {'en': 'Offers', 'fr': 'Offres', 'ar': 'عروض'},
  'seg.teachers': {'en': 'Teachers', 'fr': 'Professeurs', 'ar': 'الأساتذة'},
  'explore.kicker': {
    'en': '{c} courses · {p} offers',
    'fr': '{c} cours · {p} offres',
    'ar': '{c} دورات · {p} عروض',
  },
  'orders.kicker': {'en': '{n} orders', 'fr': '{n} commandes', 'ar': '{n} طلبات'},
  'explore.found': {
    'en': '{n} found',
    'fr': '{n} trouvés',
    'ar': '{n} نتيجة',
  },
  'explore.noMatchTitle': {'en': 'No perfect match yet', 'fr': 'Aucun résultat parfait', 'ar': 'لا توجد نتائج مطابقة'},
  'explore.noMatchMsg': {
    'en': 'Try another subject or reset the filters.',
    'fr': 'Essaie une autre matière ou réinitialise les filtres.',
    'ar': 'جرّب مادة أخرى أو أعد ضبط عوامل التصفية.',
  },
  'explore.noPackTitle': {'en': 'No offer matches', 'fr': 'Aucune offre trouvée', 'ar': 'لا توجد عروض مطابقة'},
  'explore.noPackMsg': {'en': 'Try another search term.', 'fr': 'Essaie un autre mot-clé.', 'ar': 'جرّب كلمة بحث أخرى.'},
  'explore.noSuggestion': {
    'en': 'No course or offer matches this search.',
    'fr': 'Aucun cours ni offre ne correspond.',
    'ar': 'لا توجد دورة أو عرض مطابق لهذا البحث.',
  },
  'explore.noTeacherTitle': {'en': 'No teacher matches', 'fr': 'Aucun professeur trouvé', 'ar': 'لا يوجد أستاذ مطابق'},
  'explore.noTeacherMsg': {'en': 'Try another name or subject.', 'fr': 'Essaie un autre nom ou une matière.', 'ar': 'جرّب اسماً أو مادة أخرى.'},
  'explore.yearAccess': {
    'en': 'Complete academic-year access',
    'fr': 'Accès à toute l’année scolaire',
    'ar': 'وصول كامل للسنة الدراسية',
  },
  'explore.assignedSubjects': {
    'en': '{n} assigned subjects',
    'fr': '{n} matière(s) enseignée(s)',
    'ar': '{n} مواد مُدرَّسة',
  },

  'teacher.title': {'en': 'Teacher', 'fr': 'Professeur', 'ar': 'الأستاذ'},
  'teacher.coursesBy': {
    'en': 'Courses by {name}',
    'fr': 'Cours de {name}',
    'ar': 'دورات {name}',
  },
  'teacher.packsBy': {
    'en': 'Offers with {name}',
    'fr': 'Offres avec {name}',
    'ar': 'عروض {name}',
  },
  'stat.lives': {'en': 'Lives', 'fr': 'Lives', 'ar': 'بث مباشر'},

  // Detail.
  'detail.course': {'en': 'Course', 'fr': 'Cours', 'ar': 'دورة'},
  'detail.offer': {'en': 'Offer', 'fr': 'Offre', 'ar': 'عرض'},
  'detail.insideCourse': {
    'en': 'Inside the course',
    'fr': 'Dans le cours',
    'ar': 'محتوى الدورة',
  },
  'detail.included': {
    'en': 'Everything included in your offer',
    'fr': 'Tout ce que comprend ton offre',
    'ar': 'كل ما يتضمنه عرضك',
  },
  'detail.lessonsStat': {'en': '{n} lessons', 'fr': '{n} leçons', 'ar': '{n} دروس'},
  'detail.coursesStat': {'en': '{n} courses', 'fr': '{n} cours', 'ar': '{n} دورات'},
  'detail.livesStat': {'en': '{n} planned lives', 'fr': '{n} lives programmés', 'ar': '{n} بثاً مباشراً مخططاً'},
  'detail.save': {'en': 'Save {n}%', 'fr': 'Économise {n}%', 'ar': 'وفّر {n}%'},
  'detail.studentsStat': {'en': '{n} students', 'fr': '{n} élèves', 'ar': '{n} تلاميذ'},
  'detail.curriculum': {'en': 'Curriculum', 'fr': 'Programme', 'ar': 'المنهج'},
  'detail.lessonVideo': {'en': '{n} min video', 'fr': 'Vidéo de {n} min', 'ar': 'فيديو {n} دقيقة'},
  'learn.rowMinutes': {'en': '{n} min', 'fr': '{n} min', 'ar': '{n} دقيقة'},
  'learn.rowQuiz': {'en': 'quiz', 'fr': 'quiz', 'ar': 'اختبار'},
  'detail.pdfSheet': {'en': '· PDF sheet', 'fr': '· fiche PDF', 'ar': '· ملزمة PDF'},
  'detail.quizCheckpoint': {'en': '· quiz checkpoint', 'fr': '· quiz de validation', 'ar': '· اختبار قصير'},
  'detail.quizRequired': {
    'en': 'Required quiz · {n}% to pass',
    'fr': 'Quiz obligatoire · {n}% pour réussir',
    'ar': 'اختبار إلزامي · النجاح بـ {n}%',
  },
  'detail.quizOptional': {'en': 'Optional quiz', 'fr': 'Quiz facultatif', 'ar': 'اختبار اختياري'},
  'detail.purchasedCredited': {
    'en': 'Purchased — credited',
    'fr': 'Déjà acquis — crédité',
    'ar': 'مُقتنى — محتسب',
  },
  'detail.allocated': {'en': 'Allocated {x}', 'fr': 'Part fixée à {x}', 'ar': 'الحصة {x}'},
  'detail.overlapNote': {
    'en': 'You never repay an active course — courses you already own are '
        'credited from the offer price.',
    'fr': 'Tu ne repayes jamais un cours actif — les cours déjà acquis '
        'sont crédités sur le prix de l’offre.',
    'ar': 'لن تدفع أبداً مقابل دورة تملكها — الدورات المُقتناة تُخصم من '
        'سعر العرض.',
  },
  'detail.checklist1': {
    'en': 'Ordered lessons with quiz checkpoints',
    'fr': 'Leçons ordonnées avec quiz de validation',
    'ar': 'دروس مرتبة مع اختبارات قصيرة',
  },
  'detail.checklist2': {
    'en': 'Protected PDFs with your private watermark',
    'fr': 'PDF protégés avec ton filigrane personnel',
    'ar': 'ملفات PDF محمية بعلامتك المائية الخاصة',
  },
  'detail.checklist3': {
    'en': 'Access for the active academic year',
    'fr': 'Accès pour l’année scolaire en cours',
    'ar': 'وصول للسنة الدراسية الحالية',
  },
  'detail.secureNote': {
    'en': 'Secure checkout · verified access only',
    'fr': 'Paiement sécurisé · accès vérifié uniquement',
    'ar': 'دفع آمن · وصول موثّق فقط',
  },
  'detail.addToCart': {'en': 'Add to cart', 'fr': 'Ajouter au panier', 'ar': 'أضف إلى السلة'},
  'detail.added': {'en': 'Added', 'fr': 'Ajouté', 'ar': 'تمت الإضافة'},
  'detail.buyNow': {'en': 'Buy now', 'fr': 'Acheter', 'ar': 'اشترِ الآن'},
  'detail.ownedTitle': {'en': 'Owned', 'fr': 'Acquis', 'ar': 'مُقتنى'},
  'detail.ownedSub': {
    'en': 'Verified access · academic year',
    'fr': 'Accès vérifié · année scolaire',
    'ar': 'وصول موثّق · السنة الدراسية',
  },
  // D-091: a Unit sold through Offers only (the website's wording, D-109).
  'detail.packsFrom': {'en': 'In Offers from', 'fr': 'En offre dès', 'ar': 'ضمن العروض ابتداءً من'},
  'detail.packsOnly': {'en': 'In Offers only', 'fr': 'En offre uniquement', 'ar': 'ضمن العروض فقط'},
  'detail.addPack': {'en': 'Add the Pack', 'fr': 'Ajouter le pack', 'ar': 'أضف الباقة'},
  'detail.soldInPack': {'en': 'Sold within the Pack {title}', 'fr': 'Vendu dans le pack {title}', 'ar': 'يُباع ضمن الباقة {title}'},
  'detail.soldInPacks': {'en': 'Sold within {count} Packs', 'fr': 'Vendu dans {count} packs', 'ar': 'يُباع ضمن {count} باقات'},
  'detail.choosePackTitle': {'en': 'Choose a Pack', 'fr': 'Choisis un pack', 'ar': 'اختر باقة'},
  'detail.choosePackHint': {
    'en': 'This course is sold within Packs. Choose the one you want.',
    'fr': 'Ce cours est vendu dans des packs. Choisis celui qui te convient.',
    'ar': 'تُباع هذه الدورة ضمن باقات. اختر الباقة التي تناسبك.',
  },
  'detail.offersOnly': {
    'en': 'Available through offers only',
    'fr': 'Disponible via les offres uniquement',
    'ar': 'متاح عبر العروض فقط',
  },
  'detail.addedToast': {
    'en': 'Course added to your cart',
    'fr': 'Cours ajouté à ton panier',
    'ar': 'تمت إضافة الدورة إلى سلتك',
  },
  'detail.packAddedToast': {
    'en': 'Offer added to your cart',
    'fr': 'Offre ajoutée à ton panier',
    'ar': 'تمت إضافة العرض إلى سلتك',
  },

  // Cart & checkout.
  'cart.title': {'en': 'Cart', 'fr': 'Panier', 'ar': 'السلة'},
  'cart.emptyTitle': {'en': 'Your cart is ready for a goal', 'fr': 'Ton panier attend un objectif', 'ar': 'سلتك جاهزة لهدفك'},
  'cart.emptyMsg': {
    'en': 'Courses and offers you add land here, ready to check out one '
        'program at a time.',
    'fr': 'Les cours et offres ajoutés arrivent ici, à régler un '
        'programme à la fois.',
    'ar': 'الدورات والعروض التي تضيفها تظهر هنا، لتدفع برنامجاً واحداً في كل مرة.',
  },
  'cart.oneAtATime': {
    'en': 'Checkout is completed one program at a time — select the one '
        'you want to pay first.',
    'fr': 'Le paiement se fait un programme à la fois — sélectionne '
        'celui à régler en premier.',
    'ar': 'تتم عملية الدفع لبرنامج واحد في كل مرة — اختر الذي تريد دفعه أولاً.',
  },
  'cart.checkout': {'en': 'Pass to checkout', 'fr': 'Passer au paiement', 'ar': 'المتابعة للدفع'},
  'cart.total': {'en': 'Total', 'fr': 'Total', 'ar': 'المجموع'},
  'cart.remove': {'en': 'Remove', 'fr': 'Retirer', 'ar': 'إزالة'},
  'cart.removed': {'en': 'Removed from cart', 'fr': 'Retiré du panier', 'ar': 'أُزيل من السلة'},
  'cart.yearAccess': {
    'en': 'Access for the active academic year',
    'fr': 'Accès pour l’année scolaire en cours',
    'ar': 'وصول طوال السنة الدراسية الجارية',
  },
  'cart.browse': {'en': 'Browse courses', 'fr': 'Parcourir les cours', 'ar': 'تصفّح الدورات'},
  'cart.tip': {
    'en': 'Need another subject? Offers credit courses you already own.',
    'fr': 'Besoin d’une autre matière ? Les offres créditent les cours '
        'déjà acquis.',
    'ar': 'تحتاج مادة أخرى؟ العروض تحتسب الدورات التي تملكها.',
  },
  'checkout.title': {'en': 'Checkout', 'fr': 'Paiement', 'ar': 'الدفع'},
  'checkout.orderSummary': {'en': 'Order summary', 'fr': 'Récapitulatif', 'ar': 'ملخص الطلب'},
  'checkout.subtotal': {'en': 'Subtotal', 'fr': 'Sous-total', 'ar': 'المجموع الفرعي'},
  'checkout.ownedCredit': {
    'en': 'Already owned courses',
    'fr': 'Cours déjà acquis',
    'ar': 'دورات مُقتناة مسبقاً',
  },
  'checkout.promoDiscount': {'en': 'Promo discount', 'fr': 'Remise promo', 'ar': 'خصم ترويجي'},
  'checkout.pointsApplied': {
    'en': 'Points ({n} automatically applied)',
    'fr': 'Points ({n} appliqués automatiquement)',
    'ar': 'نقاط المكافآت ({n} مطبقة تلقائياً)',
  },
  'checkout.totalDue': {'en': 'Total due', 'fr': 'Total à payer', 'ar': 'المجموع المستحق'},
  'checkout.vatNote': {
    'en': 'VAT included · recalculated server-side at order creation',
    'fr': 'TVA incluse · recalculée côté serveur à la création',
    'ar': 'الرسوم متضمنة · يُعاد الحساب في الخادم عند إنشاء الطلب',
  },
  'checkout.covered': {
    'en': 'Covered entirely by your owned courses, discounts and points.',
    'fr': 'Entièrement couvert par tes cours acquis, remises et points.',
    'ar': 'مغطى بالكامل بدوراتك المُقتناة والخصومات والنقاط.',
  },
  'checkout.haveCode': {'en': 'Have a discount code?', 'fr': 'Un code de réduction ?', 'ar': 'لديك رمز خصم؟'},
  'checkout.codeLabel': {'en': 'Discount code', 'fr': 'Code de réduction', 'ar': 'رمز الخصم'},
  'checkout.apply': {'en': 'Apply', 'fr': 'Appliquer', 'ar': 'تطبيق'},
  'checkout.removeCode': {'en': 'Remove', 'fr': 'Retirer', 'ar': 'حذف'},
  'checkout.codeHint': {'en': 'Enter your code', 'fr': 'Saisis ton code', 'ar': 'أدخل الرمز'},
  'checkout.codeHelp': {
    'en': 'Referral or promo — we recognize it automatically.',
    'fr': 'Parrainage ou promo — reconnu automatiquement.',
    'ar': 'إحالة أو رمز ترويجي — نتعرف عليه تلقائياً.',
  },
  'checkout.promoApplied': {
    'en': 'Promo code {code} applied.',
    'fr': 'Code promo {code} appliqué.',
    'ar': 'تم تطبيق الرمز الترويجي {code}.',
  },
  'checkout.referralApplied': {
    'en': 'Referral discount applied to this order.',
    'fr': 'Réduction de parrainage appliquée à cette commande.',
    'ar': 'تم تطبيق خصم الإحالة على هذا الطلب بنجاح.',
  },
  'checkout.referralAuto': {
    'en': 'Your linked referral discount was applied automatically.',
    'fr': 'Ta remise de parrainage liée a été appliquée automatiquement.',
    'ar': 'تم تطبيق خصم الإحالة المرتبط بحسابك تلقائياً.',
  },
  'checkout.method': {'en': 'Payment method', 'fr': 'Moyen de paiement', 'ar': 'طريقة الدفع'},
  'checkout.card': {'en': 'Pay by card', 'fr': 'Payer par carte', 'ar': 'الدفع بالبطاقة'},
  'checkout.cardSub': {
    'en': 'CIB or EDAHABIA — Chargily secure checkout',
    'fr': 'CIB ou EDAHABIA — paiement sécurisé Chargily',
    'ar': 'CIB أو الذهبية — دفع آمن عبر Chargily',
  },
  'checkout.ccp': {'en': 'CCP transfer', 'fr': 'Virement CCP', 'ar': 'تحويل CCP'},
  'checkout.ccpSub': {
    'en': 'Upload your receipt — access after review',
    'fr': 'Téléverse ton reçu — accès après vérification',
    'ar': 'ارفع وصل الدفع — الوصول بعد المراجعة',
  },
  'checkout.uploadReceipt': {
    'en': 'Upload receipt (PDF, PNG or JPEG)',
    'fr': 'Téléverser le reçu (PDF, PNG ou JPEG)',
    'ar': 'ارفع الوصل (PDF أو PNG أو JPEG)',
  },
  'checkout.receipt': {'en': 'Private receipt', 'fr': 'Reçu confidentiel', 'ar': 'إرفاق وصل الدفع'},
  'checkout.receiptTypes': {'en': 'PDF, PNG or JPEG', 'fr': 'PDF, PNG ou JPEG', 'ar': 'PDF أو PNG أو JPEG'},
  'checkout.receiptUpload': {'en': 'Upload', 'fr': 'Téléverser', 'ar': 'رفع الملف'},
  'checkout.receiptChange': {'en': 'Change', 'fr': 'Modifier', 'ar': 'تغيير'},
  'checkout.continue': {'en': 'Continue securely', 'fr': 'Continuer en sécurité', 'ar': 'أكمل بأمان'},
  'checkout.sendOrder': {'en': 'Send order + receipt', 'fr': 'Envoyer commande + reçu', 'ar': 'أرسل الطلب + الوصل'},
  'checkout.confirmOrder': {'en': 'Confirm order', 'fr': 'Confirmer la commande', 'ar': 'أكّد الطلب'},
  'checkout.creating': {'en': 'Creating secure order…', 'fr': 'Création de la commande sécurisée…', 'ar': 'جارٍ إنشاء الطلب الآمن…'},
  'checkout.creatingSub': {
    'en': 'The server recalculates every discount before charging.',
    'fr': 'Le serveur recalcule chaque remise avant le paiement.',
    'ar': 'يعيد الخادم حساب كل خصم قبل الدفع.',
  },
  'checkout.orderPaid': {'en': 'Order paid', 'fr': 'Commande payée', 'ar': 'تم دفع الطلب'},
  'checkout.orderSent': {'en': 'Order sent', 'fr': 'Commande envoyée', 'ar': 'تم إرسال الطلب'},
  'checkout.paidMsg': {
    'en': 'Payment verified. Access is active for the academic year. '
        'Order {n}.',
    'fr': 'Paiement vérifié. Accès actif pour l’année scolaire. '
        'Commande {n}.',
    'ar': 'تم التحقق من الدفع. الوصول مفعّل للسنة الدراسية. الطلب {n}.',
  },
  'checkout.queuedMsg': {
    'en': 'Your receipt is under review. Access stays locked until an '
        'admin approves it — you will be notified.',
    'fr': 'Ton reçu est en cours de vérification. L’accès reste bloqué '
        'jusqu’à validation par un admin — tu seras notifié.',
    'ar': 'وصلك قيد المراجعة. يبقى الوصول مقفلاً حتى موافقة المشرف — '
        'ستصلك إشعار.',
  },
  'checkout.keepExploring': {'en': 'Keep exploring', 'fr': 'Continuer à explorer', 'ar': 'مواصلة الاستكشاف'},
  'checkout.viewOrders': {'en': 'View orders', 'fr': 'Voir mes commandes', 'ar': 'عرض الطلبات'},

  // Orders.
  'orders.title': {'en': 'Orders', 'fr': 'Commandes', 'ar': 'الطلبات'},
  'orders.paid': {'en': 'Paid', 'fr': 'Payée', 'ar': 'مدفوع'},
  'orders.awaiting': {'en': 'Awaiting payment', 'fr': 'En attente de paiement', 'ar': 'في انتظار الدفع'},
  'orders.pendingReview': {'en': 'Pending review', 'fr': 'En vérification', 'ar': 'قيد المراجعة'},
  'orders.retry': {'en': 'Retry', 'fr': 'Réessayer', 'ar': 'إعادة المحاولة'},

  // My learning & lives.
  'learning.title': {'en': 'My learning', 'fr': 'Mon apprentissage', 'ar': 'تعلّمي'},
  'learning.noCourses': {'en': 'No purchased courses yet', 'fr': 'Aucun cours acheté', 'ar': 'لا دورات مشتراة بعد'},
  'learning.noCoursesMsg': {
    'en': 'Browse the catalog and your courses will show up here.',
    'fr': 'Parcours le catalogue et tes cours apparaîtront ici.',
    'ar': 'تصفح الكتالوج وستظهر دوراتك هنا.',
  },
  'learning.verified': {'en': 'Verified access', 'fr': 'Accès vérifié', 'ar': 'وصول موثّق'},
  'learning.completedYear': {
    'en': 'Completed · academic year',
    'fr': 'Terminé · année scolaire',
    'ar': 'مكتمل · السنة الدراسية',
  },
  'learning.lessonsOf': {
    'en': '{a}/{b} lessons · Prof. {teacher}',
    'fr': '{a}/{b} leçons · Prof. {teacher}',
    'ar': '{a}/{b} دروس · أ. {teacher}',
  },
  'learning.lives': {'en': 'Lives', 'fr': 'Lives', 'ar': 'البث المباشر'},
  'learning.all': {'en': 'All', 'fr': 'Tous', 'ar': 'الكل'},
  'learning.liveNow': {'en': 'Live now', 'fr': 'En direct', 'ar': 'مباشر الآن'},
  'learning.upcoming': {'en': 'Upcoming', 'fr': 'À venir', 'ar': 'قادمة'},
  'learning.replays': {'en': 'Replays', 'fr': 'Replays', 'ar': 'إعادة العرض'},
  'learning.nothingFiltered': {
    'en': 'Nothing in this filter',
    'fr': 'Rien dans ce filtre',
    'ar': 'لا شيء في هذا التصنيف',
  },
  'learning.nothingFilteredMsg': {
    'en': 'Scheduled lives, live rooms and replays all appear here.',
    'fr': 'Lives programmés, salles et replays apparaissent ici.',
    'ar': 'البثوث المجدولة والغرف وإعادات العرض تظهر هنا.',
  },
  'learning.reminderSet': {
    'en': 'Reminder set — we will notify you when it starts.',
    'fr': 'Rappel activé — tu seras notifié au démarrage.',
    'ar': 'تم ضبط التذكير — سنخبرك عند البدء.',
  },

  // Learn.
  'learn.lessons': {'en': 'Lessons', 'fr': 'Leçons', 'ar': 'الدروس'},
  'learn.headerProgress': {
    'en': '{a}/{b} lessons · {n}% complete',
    'fr': '{a}/{b} leçons · {n}% terminé',
    'ar': '{a}/{b} دروس · {n}% مكتمل',
  },
  'learn.quizzes': {'en': 'Quizzes', 'fr': 'Quiz', 'ar': 'الاختبارات'},
  'learn.resources': {'en': 'PDF', 'fr': 'PDF', 'ar': 'PDF'},
  'learn.progressTab': {'en': 'Progress', 'fr': 'Progression', 'ar': 'التقدم'},
  'learn.watched': {'en': '{n}% watched · 90% to complete', 'fr': '{n}% vus · 90% pour terminer', 'ar': 'شوهد {n}% · 90% للإكمال'},
  'learn.lessonOf': {'en': 'Lesson {i} of {n}', 'fr': 'Leçon {i} sur {n}', 'ar': 'الدرس {i} من {n}'},
  'learn.includesPdf': {'en': ' · includes a private PDF', 'fr': ' · inclut un PDF privé', 'ar': ' · يتضمن PDF خاصاً'},
  'learn.quizRequiredToUnlock': {
    'en': ' · quiz required to complete it',
    'fr': ' · quiz requis pour la valider',
    'ar': ' · اختبار إلزامي لإتمامه',
  },
  'learn.resumePill': {'en': 'Resumes where you left off', 'fr': 'Reprends où tu t’es arrêté', 'ar': 'يكمل من حيث توقفت'},
  'learn.locked': {'en': 'Not available yet', 'fr': 'Pas encore disponible', 'ar': 'غير متاح بعد'},
  'learn.pdf': {'en': 'PDF', 'fr': 'PDF', 'ar': 'PDF'},
  'learn.quiz': {'en': 'quiz', 'fr': 'quiz', 'ar': 'اختبار'},
  'learn.play': {'en': 'Play', 'fr': 'Lire', 'ar': 'تشغيل'},
  'learn.pause': {'en': 'Pause', 'fr': 'Pause', 'ar': 'إيقاف مؤقت'},
  'learn.checkpoint': {'en': 'Checkpoint', 'fr': 'Checkpoint', 'ar': 'اختبار'},
  'learn.passed': {'en': 'Passed', 'fr': 'Réussi', 'ar': 'ناجح'},
  'learn.questions': {'en': '{n} questions', 'fr': '{n} questions', 'ar': '{n} أسئلة'},
  'learn.toPass': {'en': '{n}% to pass', 'fr': '{n}% pour réussir', 'ar': 'النجاح بـ {n}%'},
  'learn.attempts': {'en': '{n} attempts', 'fr': '{n} tentatives', 'ar': '{n} محاولات'},
  'learn.bestLeft': {'en': 'Best {a}% · {b} left', 'fr': 'Meilleur {a}% · {b} restantes', 'ar': 'الأفضل {a}% · بقي {b}'},
  'learn.noCheckpoint': {'en': 'No checkpoint in this course', 'fr': 'Aucun checkpoint dans ce cours', 'ar': 'لا يوجد اختبار في هذه الدورة'},
  'learn.noCheckpointMsg': {'en': 'Lessons with a quiz appear here.', 'fr': 'Les leçons avec quiz apparaissent ici.', 'ar': 'الدروس التي بها اختبار تظهر هنا.'},
  'learn.checkpointTitle': {'en': 'Nova checkpoint · lesson quiz', 'fr': 'Checkpoint Nova · quiz de leçon', 'ar': 'اختبار نوفا · اختبار الدرس'},
  'learn.questionOf': {'en': 'Question {i} of {n}', 'fr': 'Question {i} sur {n}', 'ar': 'السؤال {i} من {n}'},
  'learn.several': {'en': 'Several answers are correct', 'fr': 'Plusieurs réponses sont correctes', 'ar': 'عدة إجابات صحيحة'},
  'learn.pickOne': {'en': 'Pick one answer', 'fr': 'Choisis une réponse', 'ar': 'اختر إجابة واحدة'},
  'learn.confirm': {'en': 'Confirm', 'fr': 'Confirmer', 'ar': 'تأكيد'},
  'learn.nextQuestion': {'en': 'Next question', 'fr': 'Question suivante', 'ar': 'السؤال التالي'},
  'learn.seeResult': {'en': 'See result', 'fr': 'Voir le résultat', 'ar': 'عرض النتيجة'},
  'learn.correctSoFar': {'en': 'Correct so far — keep it up.', 'fr': 'Correct pour l’instant — continue.', 'ar': 'صحيح حتى الآن — واصل.'},
  'learn.notQuite': {
    'en': 'Not quite — best of {n} attempts counts.',
    'fr': 'Presque — la meilleure de {n} tentatives compte.',
    'ar': 'ليس تماماً — تُحتسب أفضل {n} محاولات.',
  },
  'learn.noResources': {'en': 'No resources yet', 'fr': 'Aucune ressource', 'ar': 'لا موارد بعد'},
  'learn.noResourcesMsg': {
    'en': 'Private PDF sheets attached to lessons appear here.',
    'fr': 'Les fiches PDF privées des leçons apparaissent ici.',
    'ar': 'ملزمات PDF الخاصة بالدروس تظهر هنا.',
  },
  'learn.privatePdf': {'en': 'Private · short-lived signed access', 'fr': 'Privé · accès signé à durée limitée', 'ar': 'خاص · وصول موقّع محدود المدة'},
  'learn.courseProgress': {'en': 'course', 'fr': 'du cours', 'ar': 'من الدورة'},
  'learn.progressNote': {
    'en': 'Weighted by video duration — rewinding never lowers your '
        'saved progress.',
    'fr': 'Pondéré par la durée des vidéos — rembobiner ne réduit '
        'jamais ta progression.',
    'ar': 'مرجّح حسب مدة الفيديو — إعادة التشغيل لا تخفض تقدمك.',
  },
  'learn.lessonsDone': {'en': 'lessons done', 'fr': 'leçons terminées', 'ar': 'دروس مكتملة'},
  'learn.watchMinutes': {'en': 'watch minutes', 'fr': 'minutes vues', 'ar': 'دقائق مشاهدة'},
  'learn.complete': {'en': 'Complete', 'fr': 'Terminé', 'ar': 'مكتمل'},
  'learn.inProgress': {'en': 'In progress', 'fr': 'En cours', 'ar': 'قيد التقدم'},
  'learn.notStarted': {'en': 'Not started', 'fr': 'Non commencé', 'ar': 'لم يبدأ'},

  // Live room.
  'live.class': {'en': 'LIVE CLASS', 'fr': 'COURS EN DIRECT', 'ar': 'حصة مباشرة'},
  'live.replayBadge': {'en': 'REPLAY', 'fr': 'REPLAY', 'ar': 'إعادة'},
  'live.connected': {'en': 'Connected · {s}', 'fr': 'Connecté · {s}', 'ar': 'متصل · {s}'},
  'live.questionHint': {
    'en': 'Your question is visible only to the teaching team',
    'fr': 'Ta question n’est visible que de l’équipe pédagogique',
    'ar': 'سؤالك يظهر فقط لفريق التدريس',
  },
  'live.messageSent': {
    'en': 'Message sent — visible only to the teaching team.',
    'fr': 'Message envoyé — visible uniquement de l’équipe pédagogique.',
    'ar': 'تم إرسال الرسالة — تظهر فقط لفريق التدريس.',
  },
  'live.raiseHand': {'en': 'Raise hand to speak', 'fr': 'Lève la main pour parler', 'ar': 'ارفع يدك للتحدث'},
  'live.handInQueue': {'en': 'Your hand is in the queue', 'fr': 'Ta main est dans la file', 'ar': 'يدك في قائمة الانتظار'},

  // Notifications.
  'notif.subtitle': {
    'en': 'Stay updated with your learning activity',
    'fr': 'Reste au courant de ton activité d’apprentissage',
    'ar': 'ابقَ على اطلاع بنشاطك التعليمي',
  },
  'notif.markAll': {
    'en': 'Mark all as read',
    'fr': 'Tout marquer comme lu',
    'ar': 'تعليم الكل كمقروء',
  },
  'notif.today': {'en': 'Today', 'fr': 'Aujourd’hui', 'ar': 'اليوم'},
  'notif.yesterday': {'en': 'Yesterday', 'fr': 'Hier', 'ar': 'أمس'},
  'notif.thisWeek': {'en': 'This week', 'fr': 'Cette semaine', 'ar': 'هذا الأسبوع'},
  'notif.allCaughtUp': {
    'en': 'You’re all caught up!',
    'fr': 'Tu es à jour !',
    'ar': 'لقد شاهدت كل الإشعارات!',
  },
  'notif.showMore': {'en': 'Show more', 'fr': 'Voir plus', 'ar': 'عرض المزيد'},
  'notif.loading': {'en': 'Loading…', 'fr': 'Chargement…', 'ar': 'جارٍ التحميل…'},
  'notif.scheduledAt': {'en': 'Scheduled for {date}', 'fr': 'Prévu le {date}', 'ar': 'مبرمج في {date}'},
  'notif.generic': {'en': 'New update from NOVA', 'fr': 'Nouvelle info de NOVA', 'ar': 'تحديث جديد من نوفا'},
  // System notifications, rendered from their `data` params (web
  // `lib/notification-format.ts`); `{date}` is Algeria time.
  'notif.live_scheduled.title': {'en': 'New Live scheduled', 'fr': 'Nouveau live programmé', 'ar': 'حصة مباشرة جديدة مبرمجة'},
  'notif.live_scheduled.message': {
    'en': '{live} is scheduled for {date} (Algeria time).',
    'fr': '{live} est programmé le {date} (heure d’Algérie).',
    'ar': '{live} مبرمجة يوم {date} (بتوقيت الجزائر).',
  },
  'notif.live_rescheduled.title': {'en': 'Live rescheduled', 'fr': 'Live reprogrammé', 'ar': 'تغيير موعد الحصة المباشرة'},
  'notif.live_rescheduled.message': {
    'en': '{live} is now scheduled for {date} (Algeria time).',
    'fr': '{live} est désormais programmé le {date} (heure d’Algérie).',
    'ar': '{live} أصبحت مبرمجة يوم {date} (بتوقيت الجزائر).',
  },
  'notif.live_reminder.title': {'en': 'Live starts soon', 'fr': 'Le live commence bientôt', 'ar': 'الحصة المباشرة ستبدأ قريبًا'},
  'notif.live_reminder.message': {
    'en': '{live} starts at {date} (Algeria time).',
    'fr': '{live} commence le {date} (heure d’Algérie).',
    'ar': 'تبدأ {live} يوم {date} (بتوقيت الجزائر).',
  },
  'notif.live_started.title': {'en': 'Live started', 'fr': 'Le live a commencé', 'ar': 'بدأت الحصة المباشرة'},
  'notif.live_started.message': {
    'en': '{live} is live now.',
    'fr': '{live} est en direct maintenant.',
    'ar': '{live} مباشرة الآن.',
  },
  'notif.live_cancelled.title': {'en': 'Live cancelled', 'fr': 'Live annulé', 'ar': 'أُلغيت الحصة المباشرة'},
  'notif.live_cancelled.message': {
    'en': '{live} has been cancelled.',
    'fr': '{live} a été annulé.',
    'ar': 'تم إلغاء {live}.',
  },
  'notif.live_replay_ready.title': {'en': 'New lesson in your Unit', 'fr': 'Nouvelle leçon dans ton unité', 'ar': 'درس جديد في الوحدة'},
  'notif.live_replay_ready.message': {
    'en': '{live} is ready to watch.',
    'fr': '{live} est maintenant une leçon de ton unité.',
    'ar': 'لايف «{live}» راهو درس في الوحدة تاعك.',
  },
  'notif.lesson_published.title': {'en': 'New Lesson published', 'fr': 'Nouvelle leçon publiée', 'ar': 'درس جديد منشور'},
  'notif.lesson_published.message': {
    'en': '{lesson} is now available.',
    'fr': '{lesson} est maintenant disponible.',
    'ar': '{lesson} متاح الآن.',
  },
  'notif.access_closed.title': {'en': 'Academic access closed', 'fr': 'Accès académique clôturé', 'ar': 'انتهى الوصول الأكاديمي'},
  'notif.access_closed.message': {
    'en': 'Your access for Academic Year {year} is now closed.',
    'fr': 'Votre accès pour l’année scolaire {year} est désormais clôturé.',
    'ar': 'انتهى وصولك للسنة الدراسية {year}.',
  },
  'notif.purchase_paid.title': {'en': 'Purchase paid', 'fr': 'Achat payé', 'ar': 'تم دفع الطلب'},
  'notif.purchase_paid.message': {
    'en': 'Your Order {order} is paid and your access is ready.',
    'fr': 'Votre commande {order} est payée et votre accès est prêt.',
    'ar': 'تم دفع طلبك {order} ووصولك جاهز.',
  },
  'notif.points_credited.title': {'en': 'Points credited', 'fr': 'Points crédités', 'ar': 'تمت إضافة نقاط'},
  'notif.points_credited.message': {
    'en': '{points} points were credited to your Nova balance.',
    'fr': '{points} points ont été crédités sur votre solde Nova.',
    'ar': 'تمت إضافة {points} نقطة إلى رصيدك في نوفا.',
  },
  'notif.referral_reward_credited.title': {
    'en': 'Referral reward credited',
    'fr': 'Récompense de parrainage créditée',
    'ar': 'تمت إضافة مكافأة الإحالة',
  },
  'notif.referral_reward_credited.message': {
    'en': '{points} points were credited to your Nova balance.',
    'fr': '{points} points ont été crédités sur votre solde Nova.',
    'ar': 'تمت إضافة {points} نقطة إلى رصيدك في نوفا.',
  },
  'notif.ccp_approved.title': {'en': 'CCP receipt approved', 'fr': 'Reçu CCP approuvé', 'ar': 'تم قبول وصل CCP'},
  'notif.ccp_approved.message': {
    'en': 'Your CCP payment for Order {order} was approved.',
    'fr': 'Votre paiement CCP pour la commande {order} a été approuvé.',
    'ar': 'تم قبول دفعك عبر CCP للطلب {order}.',
  },
  'notif.ccp_rejected.title': {'en': 'CCP receipt rejected', 'fr': 'Reçu CCP refusé', 'ar': 'تم رفض وصل CCP'},
  'notif.ccp_rejected.message': {
    'en': 'Your CCP payment for Order {order} was rejected: {reason}',
    'fr': 'Votre paiement CCP pour la commande {order} a été refusé : {reason}',
    'ar': 'تم رفض دفعك عبر CCP للطلب {order}: {reason}',
  },

  // Profile.
  'profile.title': {'en': 'My space', 'fr': 'Mon espace', 'ar': 'مساحتي'},
  'profile.orders': {'en': 'Orders & payments', 'fr': 'Commandes & paiements', 'ar': 'الطلبات والمدفوعات'},
  'profile.ordersSub': {'en': 'Billing history and statuses', 'fr': 'Historique et statuts', 'ar': 'سجل الفواتير والحالات'},
  'profile.wallet': {'en': 'Wallet & rewards', 'fr': 'Cagnotte & récompenses', 'ar': 'المحفظة والمكافآت'},
  'profile.walletSub': {
    'en': '{n} points · referral code',
    'fr': '{n} points · code de parrainage',
    'ar': '{n} نقطة · رمز الإحالة',
  },
  'profile.notificationsSub': {'en': '{n} unread', 'fr': '{n} non lues', 'ar': '{n} غير مقروءة'},
  'profile.cartSub': {'en': '{n} program(s) waiting', 'fr': '{n} programme(s) en attente', 'ar': '{n} برنامج في الانتظار'},
  'profile.cartSubOne': {'en': '1 program waiting', 'fr': '1 programme en attente', 'ar': 'برنامج واحد في الانتظار'},
  'profile.myLearning': {'en': 'My learning', 'fr': 'Mon apprentissage', 'ar': 'تعلّمي'},
  'profile.myLearningSub': {'en': 'Units, lessons and lives', 'fr': 'Unités, leçons et lives', 'ar': 'الدروس واللايفات'},
  'profile.settings': {'en': 'Settings', 'fr': 'Paramètres', 'ar': 'الإعدادات'},
  'profile.settingsSub': {
    'en': 'School-managed identity · sign out',
    'fr': 'Identité gérée par l’école · déconnexion',
    'ar': 'هوية يديرها المدرسة · تسجيل الخروج',
  },
  'profile.streak': {'en': 'streak', 'fr': 'jours de suite', 'ar': 'أيام متتالية'},
  'profile.coursesOwned': {'en': 'courses owned', 'fr': 'cours acquis', 'ar': 'دورات مُقتناة'},
  'profile.editProfile': {'en': 'Edit profile', 'fr': 'Modifier le profil', 'ar': 'تعديل الملف'},
  'profile.verified': {'en': 'Verified student', 'fr': 'Élève vérifié', 'ar': 'طالب موثّق'},
  'profile.achievements': {'en': 'Achievements', 'fr': 'Récompenses', 'ar': 'الإنجازات'},
  'profile.locked': {'en': 'Locked', 'fr': 'À débloquer', 'ar': 'مقفل'},
  'profile.thisWeek': {'en': 'This week', 'fr': 'Cette semaine', 'ar': 'هذا الأسبوع'},
  'profile.weekSummary': {
    'en': '{n} lessons completed · keep the streak alive',
    'fr': '{n} leçons terminées · garde la série',
    'ar': '{n} درساً مكتملاً · حافظ على السلسلة',
  },
  'profile.shortcuts': {'en': 'Shortcuts', 'fr': 'Raccourcis', 'ar': 'اختصارات'},
  'profile.editManaged': {
    'en': 'Your academic identity is managed by the school.',
    'fr': 'Ton identité scolaire est gérée par l’école.',
    'ar': 'هويتك الدراسية تديرها المدرسة.',
  },
  'stat.courses': {'en': 'Courses', 'fr': 'Cours', 'ar': 'دورات'},
  'stat.lessons': {'en': 'Lessons', 'fr': 'Leçons', 'ar': 'دروس'},
  'stat.hours': {'en': 'Hours', 'fr': 'Heures', 'ar': 'ساعات'},
  'stat.rank': {'en': 'Rank', 'fr': 'Rang', 'ar': 'الترتيب'},
  'stat.streak': {'en': 'Day streak', 'fr': 'Jours de suite', 'ar': 'أيام متتالية'},
  'home.progressTitle': {'en': 'Progress performance', 'fr': 'Ta progression', 'ar': 'أداء التقدّم'},
  'home.progressSub': {
    'en': '{n} lessons completed',
    'fr': '{n} leçons terminées',
    'ar': '{n} درساً مكتملاً',
  },
  'home.weekly': {'en': 'Weekly', 'fr': 'Semaine', 'ar': 'أسبوعي'},
  'home.monthly': {'en': 'Month', 'fr': 'Mois', 'ar': 'شهري'},
  'home.progressPill': {'en': 'Progress: {n}%', 'fr': 'Progression : {n}%', 'ar': 'التقدّم: {n}%'},
  'home.continueTitle': {'en': 'Jump back in', 'fr': 'Reprendre', 'ar': 'تابع من حيث توقفت'},
  'learning.videosCount': {'en': '{n} Videos', 'fr': '{n} vidéos', 'ar': '{n} فيديوهات'},
  'learning.lessonsCount': {'en': '{n} Lessons', 'fr': '{n} leçons', 'ar': '{n} درساً'},
  'learning.livesCount': {'en': '{n} Lives', 'fr': '{n} lives', 'ar': '{n} بث مباشر'},
  'learning.resume': {'en': 'Resume', 'fr': 'Reprendre', 'ar': 'استئناف'},

  // Wallet.
  'wallet.title': {'en': 'Wallet & rewards', 'fr': 'Cagnotte & récompenses', 'ar': 'المحفظة والمكافآت'},
  'wallet.subtitle': {
    'en': 'Points earned from purchases and referrals.',
    'fr': 'Points gagnés sur tes achats et parrainages.',
    'ar': 'نقاط مكتسبة من مشترياتك وإحالاتك.',
  },
  'orders.subtitle': {
    'en': 'Every purchase, its method and where it stands.',
    'fr': 'Chaque achat, son moyen de paiement et son statut.',
    'ar': 'كل عملية شراء وطريقة دفعها وحالتها.',
  },
  'settings.subtitle': {
    'en': 'Appearance, school-managed identity and sign out.',
    'fr': 'Apparence, identité gérée par l’école et déconnexion.',
    'ar': 'المظهر والهوية التي تديرها المدرسة وتسجيل الخروج.',
  },
  'wallet.available': {'en': 'available points', 'fr': 'points disponibles', 'ar': 'نقطة متاحة'},
  'wallet.note': {
    'en': 'Points apply automatically at checkout and are never '
        'redeemable for cash.',
    'fr': 'Les points s’appliquent automatiquement au paiement et ne '
        'sont jamais convertibles en argent.',
    'ar': 'تُطبق النقاط تلقائياً عند الدفع ولا تُستبدل بالنقود أبداً.',
  },
  'wallet.ledger': {'en': 'Points ledger', 'fr': 'Historique des points', 'ar': 'سجل النقاط'},
  'wallet.ledgerNote': {
    'en': 'Immutable history — every credit and debit stays.',
    'fr': 'Historique immuable — chaque crédit et débit reste.',
    'ar': 'سجل غير قابل للتغيير — كل إضافة وخصم يبقى.',
  },
  'wallet.refer': {'en': 'Refer a friend', 'fr': 'Parraine un ami', 'ar': 'أحِل صديقاً'},
  'wallet.referDesc': {
    'en': 'They get a discount on their first purchase; you earn points '
        'once they pay.',
    'fr': 'Il obtient une remise sur son premier achat ; tu gagnes des '
        'points dès qu’il paie.',
    'ar': 'يحصل على خصم على أول عملية شراء؛ وتكسب نقاطاً بمجرد أن يدفع.',
  },
  'wallet.copy': {'en': 'Copy', 'fr': 'Copier', 'ar': 'نسخ'},
  'wallet.copied': {
    'en': 'Referral code copied — share it with a friend.',
    'fr': 'Code copié — partage-le à un ami.',
    'ar': 'تم نسخ رمز الإحالة — شاركه مع صديق.',
  },
  'wallet.referMeta': {
    'en': '1 referred student · rewards credited after their first '
        'eligible purchase',
    'fr': '1 élève parrainé · récompense créditée après son premier '
        'achat éligible',
    'ar': 'تلميذ واحد مُحال · تُضاف المكافأة بعد أول عملية شراء مؤهلة',
  },
  'wallet.earn': {'en': 'Earn points — browse courses', 'fr': 'Gagner des points — voir les cours', 'ar': 'اكسب نقاط — تصفح الدورات'},

  // Settings.
  'settings.title': {'en': 'Settings', 'fr': 'Paramètres', 'ar': 'الإعدادات'},
  'settings.appearance': {'en': 'Appearance', 'fr': 'Apparence', 'ar': 'المظهر'},
  'settings.darkMode': {'en': 'Dark mode', 'fr': 'Mode sombre', 'ar': 'الوضع الداكن'},
  'settings.darkModeSub': {
    'en': 'Deep navy surfaces across the whole app.',
    'fr': 'Surfaces navy profondes dans toute l’app.',
    'ar': 'أسطح كحلية داكنة في كل التطبيق.',
  },
  'settings.language': {'en': 'Language', 'fr': 'Langue', 'ar': 'اللغة'},
  'settings.schoolManaged': {
    'en': 'School-managed identity',
    'fr': 'Identité gérée par l’école',
    'ar': 'هوية يديرها المدرسة',
  },
  'settings.fullName': {'en': 'Full name', 'fr': 'Nom complet', 'ar': 'الاسم الكامل'},
  'settings.phone': {'en': 'Phone', 'fr': 'Téléphone', 'ar': 'الهاتف'},
  'settings.level': {'en': 'Level', 'fr': 'Niveau', 'ar': 'المستوى'},
  'settings.track': {'en': 'Track', 'fr': 'Filière', 'ar': 'الشعبة'},
  'settings.wilaya': {'en': 'Wilaya', 'fr': 'Wilaya', 'ar': 'الولاية'},
  'settings.commune': {'en': 'Commune', 'fr': 'Commune', 'ar': 'البلدية'},
  'settings.referralCode': {'en': 'Referral code', 'fr': 'Code de parrainage', 'ar': 'رمز الإحالة'},
  'settings.managedNote': {
    'en': 'Any identity change goes through the Nova administration: '
        'contact the school and an admin will update it.',
    'fr': 'Toute modification d’identité passe par l’administration '
        'Nova : contacte l’école et un admin la mettra à jour.',
    'ar': 'أي تغيير في الهوية يمر عبر إدارة نوفا: اتصل بالمدرسة وسيقوم '
        'المشرف بتحديثها.',
  },
  'settings.inAppAlerts': {'en': 'In-app alerts', 'fr': 'Alertes in-app', 'ar': 'تنبيهات التطبيق'},
  'settings.alertsSub': {
    'en': 'Lives, replays, lessons and payment updates.',
    'fr': 'Lives, replays, leçons et paiements.',
    'ar': 'البثوث وإعادات العرض والدروس والمدفوعات.',
  },
  'settings.security': {'en': 'Security', 'fr': 'Sécurité', 'ar': 'الأمان'},
  'settings.securityNote': {
    'en': 'One active session at a time — a new login invalidates the '
        'old one.',
    'fr': 'Une seule session active — une nouvelle connexion invalide '
        'l’ancienne.',
    'ar': 'جلسة نشطة واحدة — تسجيل دخول جديد يلغي القديم.',
  },
  'settings.signOut': {'en': 'Sign out', 'fr': 'Se déconnecter', 'ar': 'تسجيل الخروج'},

  // Account deletion (D-118).
  'deleteAccount.title': {'en': 'Delete my account', 'fr': 'Supprimer mon compte', 'ar': 'حذف حسابي'},
  'deleteAccount.whatHappens': {
    'en': 'What deleting your account does',
    'fr': 'Ce que fait la suppression du compte',
    'ar': 'ماذا يحدث عند حذف حسابك',
  },
  'deleteAccount.erased': {
    'en': 'Your name, phone number, school details and password are erased.',
    'fr': 'Ton nom, ton numéro, tes informations scolaires et ton mot de passe sont effacés.',
    'ar': 'يُمحى اسمك ورقم هاتفك ومعلوماتك المدرسية وكلمة المرور.',
  },
  'deleteAccount.access': {
    'en': 'You lose access to every course you own, with your progress, quizzes and notifications.',
    'fr': 'Tu perds l’accès à tous tes cours, avec ta progression, tes quiz et tes notifications.',
    'ar': 'تفقد الوصول إلى كل دوراتك مع تقدّمك واختباراتك وإشعاراتك.',
  },
  'deleteAccount.payments': {
    'en': 'Past payments are kept for accounting, without your name or number. Nothing is refunded.',
    'fr': 'Les paiements passés restent en comptabilité, sans ton nom ni ton numéro. Rien n’est remboursé.',
    'ar': 'تبقى المدفوعات السابقة في المحاسبة دون اسمك أو رقمك. لا يُسترجع أي مبلغ.',
  },
  'deleteAccount.final': {
    'en': 'This cannot be undone. You can sign up again later with the same number, as a new account.',
    'fr': 'C’est définitif. Tu pourras te réinscrire plus tard avec le même numéro, comme nouveau compte.',
    'ar': 'لا يمكن التراجع عن ذلك. يمكنك التسجيل لاحقًا بنفس الرقم كحساب جديد.',
  },
  'deleteAccount.passwordLabel': {
    'en': 'Type your password to confirm',
    'fr': 'Saisis ton mot de passe pour confirmer',
    'ar': 'اكتب كلمة المرور للتأكيد',
  },
  'deleteAccount.passwordRequired': {
    'en': 'Type your password.',
    'fr': 'Saisis ton mot de passe.',
    'ar': 'اكتب كلمة المرور.',
  },
  'deleteAccount.wrongPassword': {
    'en': 'Wrong password.',
    'fr': 'Mot de passe incorrect.',
    'ar': 'كلمة المرور غير صحيحة.',
  },
  'deleteAccount.confirm': {
    'en': 'Delete my account permanently',
    'fr': 'Supprimer mon compte définitivement',
    'ar': 'حذف حسابي نهائيًا',
  },
  'deleteAccount.done': {
    'en': 'Your account has been deleted.',
    'fr': 'Ton compte a été supprimé.',
    'ar': 'تم حذف حسابك.',
  },

  // Auth.
  'auth.welcomeBack': {'en': 'Welcome *back*', 'fr': 'Bon *retour*', 'ar': 'مرحبا *بيك* من جديد'},
  'auth.signInSubtitle': {'en': 'Sign in to pick up where you left off.', 'fr': 'Connectez-vous pour reprendre là où vous en étiez.', 'ar': 'ادخل باش تكمّل من وين حبست.'},
  'auth.identifier': {'en': 'Identifier', 'fr': 'Identifiant', 'ar': 'المعرّف'},
  'auth.password': {'en': 'Password', 'fr': 'Mot de passe', 'ar': 'كلمة المرور'},
  'auth.forgot': {'en': 'Forgot your password?', 'fr': 'Mot de passe oublié ?', 'ar': 'نسيت كلمة السر؟'},
  'auth.signIn': {'en': 'Sign in', 'fr': 'Se connecter', 'ar': 'ادخل'},
  'auth.newHere': {'en': 'New to Nova?', 'fr': 'Nouveau sur Nova ?', 'ar': 'جديد في نوفا؟'},
  'auth.register': {'en': 'Register', 'fr': 'S’inscrire', 'ar': 'تسجيل'},
  'auth.tabRegister': {'en': 'Create an account', 'fr': 'Créer un compte', 'ar': 'دير حساب'},
  'auth.createNewAccount': {
    'en': 'Create a new account',
    'fr': 'Créer un nouveau compte',
    'ar': 'إنشاء حساب جديد',
  },
  'auth.or': {'en': 'or', 'fr': 'ou', 'ar': 'أو'},
  'auth.createAccount': {'en': 'Create your *account*', 'fr': 'Créez votre *compte*', 'ar': 'دير *حسابك*'},
  'auth.createSubtitle': {'en': 'Let’s start with your name, number and password.', 'fr': 'On commence par le nom, le numéro et le mot de passe.', 'ar': 'نبداو بالاسم، الرقم وكلمة السر.'},
  'auth.firstName': {'en': 'First name', 'fr': 'Prénom', 'ar': 'الاسم'},
  'auth.lastName': {'en': 'Last name', 'fr': 'Nom', 'ar': 'اللقب'},
  'auth.level': {'en': 'School level', 'fr': 'Niveau scolaire', 'ar': 'المستوى الدراسي'},
  'auth.select': {'en': 'Select', 'fr': 'Sélectionner', 'ar': 'اختر'},
  'auth.trackNotRequired': {
    'en': 'Not required for this level',
    'fr': 'Non requis pour ce niveau',
    'ar': 'غير مطلوب لهذا المستوى',
  },
  'auth.pickWilaya': {'en': 'Pick a wilaya first', 'fr': 'Choisis d’abord une wilaya', 'ar': 'اختر ولاية أولاً'},
  'auth.createSpace': {'en': 'Create my space', 'fr': 'Créer mon espace', 'ar': 'أنشئ مساحتي'},
  // Two-step registration and the terms checkbox (D-122), website wording.
  'auth.stepAccount': {'en': 'Account', 'fr': 'Compte', 'ar': 'الحساب'},
  'auth.stepSchool': {'en': 'School details', 'fr': 'Parcours scolaire', 'ar': 'المعلومات الدراسية'},
  'auth.nextStep': {'en': 'Next step', 'fr': 'Étape suivante', 'ar': 'الخطوة التالية'},
  'auth.previous': {'en': 'Previous', 'fr': 'Précédent', 'ar': 'السابق'},
  'auth.termsAccept': {'en': 'I have read and accept the', 'fr': 'J’ai lu et j’accepte les', 'ar': 'قرأت وأوافق على'},
  'auth.termsLink': {'en': 'Terms of use', 'fr': 'Conditions d’utilisation', 'ar': 'شروط الاستخدام'},
  'auth.termsAnd': {'en': 'and the', 'fr': 'et la', 'ar': 'و'},
  'auth.privacyLink': {'en': 'Privacy Policy', 'fr': 'Politique de confidentialité', 'ar': 'سياسة الخصوصية'},
  'auth.termsRequired': {
    'en': 'Accept the terms of use and the privacy policy to create your account.',
    'fr': 'Acceptez les conditions d’utilisation et la politique de confidentialité pour créer votre compte.',
    'ar': 'وافق على شروط الاستخدام وسياسة الخصوصية لإنشاء حسابك.',
  },
  'auth.oneSession': {
    'en': 'One active session at a time — a new login invalidates the '
        'previous one.',
    'fr': 'Une seule session active — une nouvelle connexion invalide '
        'la précédente.',
    'ar': 'جلسة نشطة واحدة — تسجيل الدخول الجديد يلغي السابق.',
  },
  'auth.spaceReady': {'en': 'Your space is ready.', 'fr': 'Ton espace est prêt.', 'ar': 'مساحتك جاهزة.'},
  'auth.spaceReadySub': {
    'en': 'Sign in with your phone number to start learning.',
    'fr': 'Connecte-toi avec ton numéro pour commencer à apprendre.',
    'ar': 'سجّل الدخول برقم هاتفك لبدء التعلّم.',
  },
  'auth.goSignIn': {'en': 'Go to sign in', 'fr': 'Aller à la connexion', 'ar': 'اذهب لتسجيل الدخول'},
  // D-093/D-096 codes by SMS or WhatsApp (the website's `otp.*`,
  // `forgot.*`, `dash.password_*` and `errors.code.*` wording).
  'otp.codeLabel': {'en': 'Verification code', 'fr': 'Code de vérification', 'ar': 'رمز التحقق'},
  'otp.codeFormat': {
    'en': 'Enter the 6-digit code you received.',
    'fr': 'Saisis le code à 6 chiffres reçu.',
    'ar': 'أدخل الرمز المكوّن من 6 أرقام الذي وصلك.',
  },
  'otp.sendCode': {'en': 'Send the code', 'fr': 'Envoyer le code', 'ar': 'إرسال الرمز'},
  'otp.resend': {'en': 'Send a new code', 'fr': 'Envoyer un nouveau code', 'ar': 'إرسال رمز جديد'},
  'otp.resendIn': {'en': 'New code in {seconds} s', 'fr': 'Nouveau code dans {seconds} s', 'ar': 'رمز جديد بعد {seconds} ث'},
  'otp.verify': {'en': 'Verify', 'fr': 'Vérifier', 'ar': 'تحقّق'},
  'otp.remainingAttempts': {'en': '{count} attempt(s) left.', 'fr': 'Encore {count} essai(s).', 'ar': 'بقيت {count} محاولة.'},
  'otp.channelLabel': {'en': 'Receive the code by', 'fr': 'Recevoir le code par', 'ar': 'استلام الرمز عبر'},
  'otp.channelSms': {'en': 'SMS', 'fr': 'SMS', 'ar': 'SMS'},
  'otp.channelWhatsapp': {'en': 'WhatsApp', 'fr': 'WhatsApp', 'ar': 'واتساب'},
  'otp.invalid': {'en': 'This code is incorrect.', 'fr': 'Ce code est incorrect.', 'ar': 'هذا الرمز غير صحيح.'},
  'otp.expired': {
    'en': 'This code has expired or was replaced by a newer one. Request a new code.',
    'fr': 'Ce code a expiré ou a été remplacé par un nouveau code. Demande un nouveau code.',
    'ar': 'انتهت صلاحية هذا الرمز أو تم استبداله برمز أحدث. اطلب رمزاً جديداً.',
  },
  'otp.attemptsExceeded': {
    'en': 'Too many wrong codes. Request a new code.',
    'fr': 'Trop de codes erronés. Demande un nouveau code.',
    'ar': 'محاولات خاطئة كثيرة. اطلب رمزاً جديداً.',
  },
  'otp.resendTooSoon': {
    'en': 'Wait a moment before requesting a new code.',
    'fr': 'Patiente un instant avant de demander un nouveau code.',
    'ar': 'انتظر قليلاً قبل طلب رمز جديد.',
  },
  'otp.tooManyRequests': {
    'en': 'Too many code requests. Please retry later.',
    'fr': 'Trop de demandes de code. Réessaie plus tard.',
    'ar': 'طلبات رموز كثيرة. أعد المحاولة لاحقاً.',
  },
  'otp.serviceUnavailable': {
    'en': 'Codes cannot be sent right now. Please retry later.',
    'fr': 'Les codes ne peuvent pas être envoyés pour le moment. Réessaie plus tard.',
    'ar': 'لا يمكن إرسال الرموز حالياً. أعد المحاولة لاحقاً.',
  },
  'otp.resetTokenInvalid': {
    'en': 'This step has expired. Start again and request a new code.',
    'fr': 'Cette étape a expiré. Recommence et demande un nouveau code.',
    'ar': 'انتهت صلاحية هذه الخطوة. ابدأ من جديد واطلب رمزاً جديداً.',
  },
  'otp.phoneVerificationRequired': {
    'en': 'Verify your phone number with the code first.',
    'fr': 'Vérifie d’abord ton numéro avec le code reçu.',
    'ar': 'تحقّق أولاً من رقم هاتفك بالرمز الذي وصلك.',
  },
  'otp.phoneVerificationInvalid': {
    'en': 'The phone verification has expired or does not match this number. Request a new code.',
    'fr': 'La vérification du numéro a expiré ou ne correspond pas à ce numéro. Demande un nouveau code.',
    'ar': 'انتهت صلاحية التحقق من الرقم أو لا يطابق هذا الرقم. اطلب رمزاً جديداً.',
  },
  'forgot.title': {'en': 'Forgot your password?', 'fr': 'Mot de passe oublié ?', 'ar': 'نسيت كلمة المرور؟'},
  'forgot.subtitle': {
    'en': 'Enter the phone number of your Student account. We send you a code by SMS or WhatsApp.',
    'fr': 'Saisis le numéro de téléphone de ton compte élève. Nous t’envoyons un code par SMS ou WhatsApp.',
    'ar': 'أدخل رقم هاتف حسابك كتلميذ. سنرسل لك رمزاً عبر SMS أو واتساب.',
  },
  'forgot.codeTitle': {'en': 'Enter the code', 'fr': 'Saisis le code', 'ar': 'أدخل الرمز'},
  'forgot.codeSent': {
    'en': 'If this number belongs to a NOVA Student account, a 6-digit code was sent to {phone} '
        'by {channel}. It is valid for 5 minutes.',
    'fr': 'Si ce numéro correspond à un compte élève NOVA, un code à 6 chiffres a été envoyé par '
        '{channel} au {phone}. Il est valable 5 minutes.',
    'ar': 'إذا كان هذا الرقم مرتبطاً بحساب تلميذ في NOVA، فقد أُرسل رمز من 6 أرقام عبر {channel} '
        'إلى {phone}. صالح لمدة 5 دقائق.',
  },
  'forgot.passwordTitle': {'en': 'Choose a new password', 'fr': 'Choisis un nouveau mot de passe', 'ar': 'اختر كلمة مرور جديدة'},
  'forgot.passwordSubtitle': {
    'en': 'Your new password must have at least 8 characters. Every device will be signed out.',
    'fr': 'Ton nouveau mot de passe doit contenir au moins 8 caractères. Tous tes appareils seront déconnectés.',
    'ar': 'يجب أن تحتوي كلمة المرور الجديدة على 8 أحرف على الأقل. سيتم تسجيل الخروج من جميع الأجهزة.',
  },
  'forgot.newPassword': {'en': 'New password', 'fr': 'Nouveau mot de passe', 'ar': 'كلمة المرور الجديدة'},
  'forgot.savePassword': {'en': 'Save the new password', 'fr': 'Enregistrer le mot de passe', 'ar': 'حفظ كلمة المرور الجديدة'},
  'forgot.changeNumber': {'en': 'Change the number', 'fr': 'Changer de numéro', 'ar': 'تغيير الرقم'},
  'forgot.backToLogin': {'en': 'Back to sign in', 'fr': 'Retour à la connexion', 'ar': 'العودة إلى تسجيل الدخول'},
  'auth.passwordResetDone': {
    'en': 'Your password was changed. Sign in with your new password.',
    'fr': 'Ton mot de passe a été modifié. Connecte-toi avec ton nouveau mot de passe.',
    'ar': 'تم تغيير كلمة المرور. سجّل الدخول بكلمة المرور الجديدة.',
  },
  'auth.phoneVerificationNeeded': {
    'en': 'Verify your phone number with the code before creating your account.',
    'fr': 'Vérifie ton numéro avec le code reçu avant de créer ton compte.',
    'ar': 'تحقّق من رقم هاتفك بالرمز قبل إنشاء حسابك.',
  },
  'auth.verifyPhone': {'en': 'Verify your phone number', 'fr': 'Vérifie ton numéro de téléphone', 'ar': 'تحقّق من رقم هاتفك'},
  'auth.verifyPhoneDesc': {
    'en': 'We send a 6-digit code to {phone} by SMS or WhatsApp.',
    'fr': 'Nous envoyons un code à 6 chiffres au {phone} par SMS ou WhatsApp.',
    'ar': 'نرسل رمزاً من 6 أرقام إلى {phone} عبر SMS أو واتساب.',
  },
  'auth.verifyCodeSent': {
    'en': 'A code was sent by {channel} to {phone}. It is valid for 5 minutes.',
    'fr': 'Un code a été envoyé par {channel} au {phone}. Il est valable 5 minutes.',
    'ar': 'تم إرسال رمز عبر {channel} إلى {phone}. صالح لمدة 5 دقائق.',
  },
  'auth.phoneVerified': {'en': 'Phone number verified.', 'fr': 'Numéro de téléphone vérifié.', 'ar': 'تم التحقق من رقم الهاتف.'},
  'security.changeDesc': {
    'en': 'To change your password, we send a code to your phone number by SMS or WhatsApp.',
    'fr': 'Pour changer ton mot de passe, nous envoyons un code à ton numéro par SMS ou WhatsApp.',
    'ar': 'لتغيير كلمة المرور، نرسل رمزاً إلى رقم هاتفك عبر SMS أو واتساب.',
  },
  'security.sendCode': {'en': 'Send me a code', 'fr': 'M’envoyer un code', 'ar': 'أرسل لي رمزاً'},
  'security.codeSent': {
    'en': 'A 6-digit code was sent by {channel} to {phone}. It is valid for 5 minutes.',
    'fr': 'Un code à 6 chiffres a été envoyé par {channel} au {phone}. Il est valable 5 minutes.',
    'ar': 'تم إرسال رمز من 6 أرقام عبر {channel} إلى {phone}. صالح لمدة 5 دقائق.',
  },
  'security.save': {'en': 'Change the password', 'fr': 'Changer le mot de passe', 'ar': 'تغيير كلمة المرور'},
  'security.changed': {
    'en': 'Your password was changed. Your other devices were signed out.',
    'fr': 'Ton mot de passe a été modifié. Tes autres appareils ont été déconnectés.',
    'ar': 'تم تغيير كلمة المرور. تم تسجيل الخروج من أجهزتك الأخرى.',
  },
  'security.unavailable': {
    'en': 'The password could not be changed. Please retry.',
    'fr': 'Le mot de passe n’a pas pu être modifié. Réessaie.',
    'ar': 'تعذّر تغيير كلمة المرور. أعد المحاولة.',
  },

  // D-098: the school-year confirmation (website `onboarding.school_year_*`).
  'schoolYear.title': {'en': 'Confirm your year and track', 'fr': 'Confirme ton année et ta filière', 'ar': 'أكّد سنتك وشعبتك'},
  'schoolYear.subtitle': {
    'en': 'A new school year has started. Keep or change your school level and track before continuing.',
    'fr': 'Une nouvelle année scolaire a commencé. Garde ou modifie ton niveau et ta filière avant de continuer.',
    'ar': 'بدأت سنة دراسية جديدة. احتفظ بمستواك وشعبتك أو غيّرهما قبل المتابعة.',
  },
  'schoolYear.confirm': {'en': 'Confirm', 'fr': 'Confirmer', 'ar': 'تأكيد'},

  // API wiring (D-067): shared words, auth steps, empty states, errors.
  'common.all': {'en': 'All', 'fr': 'Tout', 'ar': 'الكل'},
  'common.free': {'en': 'Free', 'fr': 'Gratuit', 'ar': 'مجاني'},
  'common.retry': {'en': 'Try again', 'fr': 'Réessayer', 'ar': 'أعد المحاولة'},
  'day.mon': {'en': 'Mon', 'fr': 'Lun', 'ar': 'إث'},
  'day.tue': {'en': 'Tue', 'fr': 'Mar', 'ar': 'ثل'},
  'day.wed': {'en': 'Wed', 'fr': 'Mer', 'ar': 'أر'},
  'day.thu': {'en': 'Thu', 'fr': 'Jeu', 'ar': 'خم'},
  'day.fri': {'en': 'Fri', 'fr': 'Ven', 'ar': 'جم'},
  'day.sat': {'en': 'Sat', 'fr': 'Sam', 'ar': 'سب'},
  'day.sun': {'en': 'Sun', 'fr': 'Dim', 'ar': 'أح'},
  'menu.points': {'en': '{n} points', 'fr': '{n} points', 'ar': '{n} نقطة'},
  'menu.lessonsDone': {
    'en': '{n} lessons completed',
    'fr': '{n} leçons terminées',
    'ar': '{n} دروس مكتملة',
  },
  'auth.fillBoth': {
    'en': 'Enter your phone number and password.',
    'fr': 'Saisis ton numéro et ton mot de passe.',
    'ar': 'أدخل رقم هاتفك وكلمة المرور.',
  },
  'auth.confirmPassword': {'en': 'Confirm password', 'fr': 'Confirme le mot de passe', 'ar': 'تأكيد كلمة المرور'},
  'auth.onboardingTitle': {'en': 'Complete your profile', 'fr': 'Complète ton profil', 'ar': 'أكمل ملفك'},
  'auth.onboardingSub': {
    'en': 'Your school created your account. Confirm your details to start learning.',
    'fr': 'Ton école a créé ton compte. Confirme tes informations pour commencer.',
    'ar': 'أنشأت مدرستك حسابك. أكّد معلوماتك لتبدأ التعلّم.',
  },
  'auth.saveDetails': {'en': 'Save my details', 'fr': 'Enregistrer', 'ar': 'حفظ معلوماتي'},
  'auth.newPasswordTitle': {'en': 'Choose your password', 'fr': 'Choisis ton mot de passe', 'ar': 'اختر كلمة مرورك'},
  'auth.newPasswordSub': {
    'en': 'For your security, replace the password your school gave you.',
    'fr': 'Pour ta sécurité, remplace le mot de passe donné par ton école.',
    'ar': 'لأمانك، استبدل كلمة المرور التي منحتها لك مدرستك.',
  },
  'auth.savePassword': {'en': 'Save password', 'fr': 'Enregistrer', 'ar': 'حفظ كلمة المرور'},

  // One account per Student (D-078, D-079): the website's wording.
  'auth.phoneInvalid': {
    'en': 'Enter a valid mobile number: 05, 06 or 07 followed by 8 digits.',
    'fr': 'Saisis un numéro de mobile valide : 05, 06 ou 07 suivi de 8 chiffres.',
    'ar': 'أدخل رقم هاتف محمول صحيحاً: 05 أو 06 أو 07 متبوعاً بـ 8 أرقام.',
  },
  'auth.phoneTaken': {
    'en': 'An account already exists with this phone number. If it is yours, sign in with '
        'this number instead of creating a new account (if you never chose a password for '
        'it, your password is your phone number). If it belongs to a family member, '
        'register with your own mobile number. Forgot your password? Use “Forgot your '
        'password?” on the sign-in screen to receive a code by SMS or WhatsApp.',
    'fr': 'Un compte existe déjà avec ce numéro de téléphone. S’il est à toi, connecte-toi '
        'avec ce numéro au lieu de créer un nouveau compte (si tu n’as jamais choisi de mot '
        'de passe, c’est ton numéro de téléphone). S’il appartient à un membre de ta '
        'famille, inscris-toi avec ton propre numéro. Mot de passe oublié ? Utilise « Mot '
        'de passe oublié ? » sur l’écran de connexion pour recevoir un code par SMS ou WhatsApp.',
    'ar': 'يوجد حساب مسجل بهذا الرقم. إذا كان حسابك، فسجّل الدخول بهذا الرقم بدلاً من إنشاء '
        'حساب جديد (إذا لم تختر كلمة مرور من قبل، فهي رقم هاتفك). وإذا كان لأحد أفراد '
        'عائلتك، فسجّل برقمك أنت. نسيت كلمة المرور؟ استعمل «نسيت كلمة المرور؟» في شاشة '
        'تسجيل الدخول لتلقي رمز عبر SMS أو واتساب.',
  },
  // D-081: registration takes the number exactly as it is typed at sign-in.
  'auth.phoneStrict': {
    'en': 'The number must have exactly 10 digits and start with 05, 06 or 07: digits '
        'only, no spaces or letters.',
    'fr': 'Le numéro doit contenir exactement 10 chiffres et commencer par 05, 06 ou 07 : '
        'uniquement des chiffres, sans espace ni lettre.',
    'ar': 'يجب أن يتكون الرقم من 10 أرقام بالضبط ويبدأ بـ 05 أو 06 أو 07: أرقام فقط، بدون '
        'مسافات أو حروف.',
  },
  'auth.phoneLabel': {'en': 'Phone number', 'fr': 'Numéro de téléphone', 'ar': 'رقم الهاتف'},
  // D-079: the one-time phone step (website `onboarding.phone_*`).
  'phone.title': {
    'en': 'Enter your phone number',
    'fr': 'Saisis ton numéro de téléphone',
    'ar': 'أدخل رقم هاتفك',
  },
  'phone.desc': {
    'en': 'Your account was created without a valid mobile number. Each Student signs in '
        'with their own number. If a family member already has a NOVA account with their '
        'number, enter yours.',
    'fr': 'Ton compte a été créé sans numéro de mobile valide. Chaque élève se connecte avec '
        'son propre numéro. Si un membre de ta famille a déjà un compte NOVA avec son '
        'numéro, saisis le tien.',
    'ar': 'تم إنشاء حسابك دون رقم هاتف محمول صحيح. يسجّل كل طالب الدخول برقمه الخاص. إذا كان '
        'لأحد أفراد عائلتك حساب على NOVA برقمه، فأدخل رقمك أنت.',
  },
  'phone.taken': {
    'en': 'This number already has a NOVA account. If it is yours (created by the school), '
        'sign out and sign in with this number. If it belongs to a family member, enter '
        'your own number.',
    'fr': 'Ce numéro a déjà un compte NOVA. S’il est à toi (créé par l’établissement), '
        'déconnecte-toi et connecte-toi avec ce numéro. S’il appartient à un membre de ta '
        'famille, saisis ton propre numéro.',
    'ar': 'هذا الرقم مرتبط بحساب على NOVA. إذا كان حسابك (أنشأته المؤسسة)، فسجّل الخروج ثم '
        'سجّل الدخول بهذا الرقم. وإذا كان لأحد أفراد عائلتك، فأدخل رقمك أنت.',
  },
  'phone.save': {'en': 'Save my number', 'fr': 'Enregistrer mon numéro', 'ar': 'حفظ رقمي'},
  // D-083: products outside the Student's level and filière.
  'detail.outOfTrackTitle': {
    'en': 'Not available for your level or track',
    'fr': 'Non disponible pour ton niveau ou ta filière',
    'ar': 'غير متاح لمستواك أو شعبتك',
  },
  'detail.outOfTrackCourse': {
    'en': 'This Course is not part of your level and track ({profile}). It cannot be bought '
        'or enrolled in from your account. If your level or track is wrong, contact the school.',
    'fr': 'Ce cours ne fait pas partie de ton niveau et de ta filière ({profile}). Il ne peut '
        'être ni acheté ni suivi depuis ton compte. Si ton niveau ou ta filière est incorrect, '
        'contacte l’établissement.',
    'ar': 'هذه الدورة ليست ضمن مستواك وشعبتك ({profile}). لا يمكن شراؤها أو التسجيل فيها من '
        'حسابك. إذا كان مستواك أو شعبتك غير صحيح، تواصل مع إدارة المنصة.',
  },
  'detail.outOfTrackOffer': {
    'en': 'This Offer includes Courses outside your level and track ({profile}). It cannot be '
        'bought from your account. If your level or track is wrong, contact the school.',
    'fr': 'Cette offre contient des cours hors de ton niveau et de ta filière ({profile}). Elle '
        'ne peut pas être achetée depuis ton compte. Si ton niveau ou ta filière est '
        'incorrect, contacte l’établissement.',
    'ar': 'يتضمن هذا العرض دورات خارج مستواك وشعبتك ({profile}). لا يمكن شراؤه من حسابك. إذا '
        'كان مستواك أو شعبتك غير صحيح، تواصل مع إدارة المنصة.',
  },
  'err.outOfTrack': {
    'en': 'This is not available for your level or track. If your level or track is wrong, '
        'contact the school.',
    'fr': 'Ce contenu n’est pas disponible pour ton niveau ou ta filière. Si ton niveau ou ta '
        'filière est incorrect, contacte l’établissement.',
    'ar': 'هذا غير متاح لمستواك أو شعبتك. إذا كان مستواك أو شعبتك غير صحيح، تواصل مع إدارة المنصة.',
  },
  'err.profileLocked': {
    'en': 'Your level, track, Wilaya and Commune are managed by the school. Contact the '
        'school to change them.',
    'fr': 'Ton niveau, ta filière, ta wilaya et ta commune sont gérés par l’établissement. '
        'Contacte l’établissement pour les modifier.',
    'ar': 'مستواك وشعبتك وولايتك وبلديتك تديرها إدارة المنصة. تواصل مع الإدارة لتعديلها.',
  },
  'err.phoneRequired': {
    'en': 'Enter your own mobile phone number before continuing.',
    'fr': 'Saisis ton propre numéro de mobile avant de continuer.',
    'ar': 'أدخل رقم هاتفك المحمول الخاص قبل المتابعة.',
  },
  'auth.signInInstead': {
    'en': 'Sign in with this number',
    'fr': 'Se connecter avec ce numéro',
    'ar': 'تسجيل الدخول بهذا الرقم',
  },
  'auth.duplicateClosed': {
    'en': 'This account was closed because you already have a NOVA account with your '
        'offers. Sign in to that account with your phone number ({phone}). If you never '
        'chose a password for it, your password is your phone number. Forgot your '
        'password? Use “Forgot your password?” to receive a code by SMS or WhatsApp.',
    'fr': 'Ce compte a été fermé car tu as déjà un compte NOVA avec tes offres. '
        'Connecte-toi à ce compte avec ton numéro de téléphone ({phone}). Si tu n’as '
        'jamais choisi de mot de passe pour ce compte, c’est ton numéro de téléphone. Mot '
        'de passe oublié ? Utilise « Mot de passe oublié ? » pour recevoir un code par SMS ou WhatsApp.',
    'ar': 'تم إغلاق هذا الحساب لأن لديك حساباً آخر على NOVA يحتوي على عروضك. سجّل الدخول '
        'إلى ذلك الحساب برقم هاتفك ({phone}). إذا لم تختر كلمة مرور لذلك الحساب من قبل، '
        'فكلمة المرور هي رقم هاتفك. نسيت كلمة المرور؟ استعمل «نسيت كلمة المرور؟» لتلقي رمز عبر SMS أو واتساب.',
  },
  'err.ownedOtherAccount': {
    'en': 'Another NOVA account with your phone number already has this. Sign in to that '
        'account with your phone number instead of paying again, or contact the school.',
    'fr': 'Un autre compte NOVA avec ton numéro de téléphone possède déjà cet accès. '
        'Connecte-toi à ce compte avec ton numéro au lieu de payer à nouveau, ou contacte '
        'l’établissement.',
    'ar': 'يوجد حساب آخر على NOVA برقم هاتفك يملك هذا بالفعل. سجّل الدخول إلى ذلك الحساب '
        'برقم هاتفك بدلاً من الدفع مرة أخرى، أو تواصل مع إدارة المنصة.',
  },
  'pwd.short': {
    'en': 'Use at least 8 characters.',
    'fr': 'Utilise au moins 8 caractères.',
    'ar': 'استخدم 8 أحرف على الأقل.',
  },
  'pwd.mismatch': {
    'en': 'The two passwords do not match.',
    'fr': 'Les deux mots de passe ne correspondent pas.',
    'ar': 'كلمتا المرور غير متطابقتين.',
  },
  'pwd.samePhone': {
    'en': 'Choose a password different from your phone number.',
    'fr': 'Choisis un mot de passe différent de ton numéro de téléphone.',
    'ar': 'اختر كلمة مرور مختلفة عن رقم هاتفك.',
  },
  'checkout.securePayment': {'en': 'Secure payment', 'fr': 'Paiement sécurisé', 'ar': 'دفع آمن'},
  'checkout.offer': {'en': 'Offer', 'fr': 'Offre', 'ar': 'عرض'},
  'checkout.course': {'en': 'Individual Course', 'fr': 'Cours individuel', 'ar': 'دورة فردية'},
  'checkout.accessYear': {
    'en': 'Access for the {y} academic year',
    'fr': 'Accès pour l’année scolaire {y}',
    'ar': 'وصول للسنة الدراسية {y}',
  },
  'checkout.accessActiveYear': {
    'en': 'Access for the active academic year',
    'fr': 'Accès pour l’année scolaire en cours',
    'ar': 'وصول للسنة الدراسية الحالية',
  },
  'checkout.referralDiscount': {'en': 'Referral discount', 'fr': 'Remise parrainage', 'ar': 'خصم الإحالة'},
  'checkout.receiptTooBig': {
    'en': 'The receipt must be a JPG, PNG or PDF under 10 MB.',
    'fr': 'Le reçu doit être un JPG, PNG ou PDF de moins de 10 Mo.',
    'ar': 'يجب أن يكون الوصل JPG أو PNG أو PDF أقل من 10 ميغابايت.',
  },
  'checkout.cardOpened': {
    'en': 'Finish paying in your browser',
    'fr': 'Termine le paiement dans ton navigateur',
    'ar': 'أكمل الدفع في متصفحك',
  },
  'checkout.cardMsg': {
    'en': 'Your access opens as soon as the card payment is confirmed. Follow it in Orders.',
    'fr': 'Ton accès s’ouvre dès la confirmation du paiement. Suis-le dans Commandes.',
    'ar': 'يُفتح وصولك فور تأكيد الدفع بالبطاقة. تابعه في الطلبات.',
  },
  'detail.joinFree': {'en': 'Join for free', 'fr': 'Rejoindre gratuitement', 'ar': 'انضم مجاناً'},
  'detail.joined': {'en': 'You joined this course.', 'fr': 'Tu as rejoint ce cours.', 'ar': 'انضممت إلى هذا المساق.'},
  'notif.earlier': {'en': 'Earlier', 'fr': 'Plus tôt', 'ar': 'سابقاً'},
  'notif.emptyTitle': {'en': 'No notifications yet', 'fr': 'Aucune notification', 'ar': 'لا إشعارات بعد'},
  'notif.emptyMsg': {
    'en': 'Lives, new lessons and payment updates will show up here.',
    'fr': 'Les lives, nouvelles leçons et paiements apparaîtront ici.',
    'ar': 'ستظهر هنا الحصص المباشرة والدروس الجديدة وتحديثات الدفع.',
  },
  'orders.emptyTitle': {'en': 'No orders yet', 'fr': 'Aucune commande', 'ar': 'لا طلبات بعد'},
  'orders.emptyMsg': {
    'en': 'Programs you buy will appear here with their payment status.',
    'fr': 'Les programmes achetés apparaîtront ici avec leur statut.',
    'ar': 'ستظهر هنا البرامج التي تشتريها مع حالة الدفع.',
  },
  'orders.rejected': {'en': 'Receipt rejected', 'fr': 'Reçu refusé', 'ar': 'الوصل مرفوض'},
  'orders.cancelled': {'en': 'Cancelled', 'fr': 'Annulée', 'ar': 'ملغى'},
  'orders.expired': {'en': 'Expired', 'fr': 'Expirée', 'ar': 'منتهي'},
  'wallet.empty': {
    'en': 'No points activity yet.',
    'fr': 'Aucun mouvement de points pour l’instant.',
    'ar': 'لا حركة للنقاط بعد.',
  },
  'err.generic': {
    'en': 'Something went wrong. Please try again.',
    'fr': 'Un problème est survenu. Réessaie.',
    'ar': 'حدث خطأ. حاول مرة أخرى.',
  },
  'err.network': {
    'en': 'No connection to NOVA. Check your internet and try again.',
    'fr': 'Pas de connexion à NOVA. Vérifie ton internet et réessaie.',
    'ar': 'لا اتصال بنوفا. تحقّق من الإنترنت وحاول مجدداً.',
  },
  'err.server': {
    'en': 'NOVA is temporarily unavailable. Please try again shortly.',
    'fr': 'NOVA est momentanément indisponible. Réessaie bientôt.',
    'ar': 'نوفا غير متاح مؤقتاً. حاول بعد قليل.',
  },
  'err.credentials': {
    'en': 'Phone number or password is incorrect.',
    'fr': 'Numéro ou mot de passe incorrect.',
    'ar': 'رقم الهاتف أو كلمة المرور غير صحيحة.',
  },
  'err.sessionReplaced': {
    'en': 'You were signed out because your account signed in on another device.',
    'fr': 'Tu as été déconnecté car ton compte s’est connecté sur un autre appareil.',
    'ar': 'تم تسجيل خروجك لأن حسابك سجّل الدخول من جهاز آخر.',
  },
  'err.studentOnly': {
    'en': 'This app is for Student accounts. Use the web console for administration.',
    'fr': 'Cette application est réservée aux élèves. Utilise la console web pour l’administration.',
    'ar': 'هذا التطبيق مخصّص لحسابات الطلاب. استخدم لوحة الويب للإدارة.',
  },
  'err.forbidden': {
    'en': 'This account cannot access NOVA right now. Contact the school.',
    'fr': 'Ce compte ne peut pas accéder à NOVA pour le moment. Contacte l’école.',
    'ar': 'لا يمكن لهذا الحساب الوصول إلى نوفا حالياً. تواصل مع المدرسة.',
  },
  'err.tooMany': {
    'en': 'Too many attempts. Wait a minute and try again.',
    'fr': 'Trop de tentatives. Attends une minute et réessaie.',
    'ar': 'محاولات كثيرة. انتظر دقيقة وحاول مجدداً.',
  },
  'err.courseFree': {
    'en': 'This course is free — join it from its page.',
    'fr': 'Ce cours est gratuit — rejoins-le depuis sa page.',
    'ar': 'هذا المساق مجاني — انضم إليه من صفحته.',
  },
  'err.notSold': {
    'en': 'This course is only available inside an offer.',
    'fr': 'Ce cours n’est disponible que dans une offre.',
    'ar': 'هذا المساق متاح فقط ضمن عرض.',
  },
  'err.owned': {
    'en': 'You already have access to this program.',
    'fr': 'Tu as déjà accès à ce programme.',
    'ar': 'لديك وصول إلى هذا البرنامج بالفعل.',
  },
  'err.unavailable': {
    'en': 'This offer is no longer available.',
    'fr': 'Cette offre n’est plus disponible.',
    'ar': 'هذا العرض لم يعد متاحاً.',
  },
  'err.codeInvalid': {
    'en': 'This code is not valid for this order.',
    'fr': 'Ce code n’est pas valable pour cette commande.',
    'ar': 'هذا الرمز غير صالح لهذا الطلب.',
  },
  'err.referralDiscount': {
    'en': 'The referral discount does not apply to this order.',
    'fr': 'La remise parrainage ne s’applique pas à cette commande.',
    'ar': 'خصم الإحالة لا ينطبق على هذا الطلب.',
  },
  'err.points': {
    'en': 'Points cannot be used for this order.',
    'fr': 'Les points ne peuvent pas être utilisés pour cette commande.',
    'ar': 'لا يمكن استخدام النقاط لهذا الطلب.',
  },
  'err.noYear': {
    'en': 'Enrolment is closed until the next academic year opens.',
    'fr': 'Les inscriptions sont fermées jusqu’à la prochaine année scolaire.',
    'ar': 'التسجيل مغلق حتى افتتاح السنة الدراسية القادمة.',
  },
  'err.referralAttached': {
    'en': 'A referral code is already attached to your account.',
    'fr': 'Un code de parrainage est déjà lié à ton compte.',
    'ar': 'رمز إحالة مرتبط بحسابك بالفعل.',
  },
  'err.referralInvalid': {
    'en': 'This referral code is not valid.',
    'fr': 'Ce code de parrainage n’est pas valable.',
    'ar': 'رمز الإحالة هذا غير صالح.',
  },
  'err.referralSelf': {
    'en': 'You cannot use your own referral code.',
    'fr': 'Tu ne peux pas utiliser ton propre code.',
    'ar': 'لا يمكنك استخدام رمز إحالتك.',
  },
  'err.referralClosed': {
    'en': 'Referral codes can no longer be added to this account.',
    'fr': 'Un code de parrainage ne peut plus être ajouté à ce compte.',
    'ar': 'لم يعد بالإمكان إضافة رمز إحالة لهذا الحساب.',
  },

  // Protected player (D-067 Phase 2) — same states as the web player.
  'player.checkPlay': {'en': 'Check & play', 'fr': 'Vérifier et lire', 'ar': 'تحقّق وشغّل'},
  'player.protected': {'en': 'Protected lesson', 'fr': 'Leçon protégée', 'ar': 'درس محمي'},
  'player.phaseAccess': {'en': 'Confirming your access…', 'fr': 'Vérification de ton accès…', 'ar': 'جارٍ التحقق من وصولك…'},
  'player.phaseDevice': {'en': 'Checking device protection…', 'fr': 'Vérification de la protection de l’appareil…', 'ar': 'جارٍ التحقق من حماية الجهاز…'},
  'player.phaseMedia': {'en': 'Loading protected media…', 'fr': 'Chargement du média protégé…', 'ar': 'جارٍ تحميل الوسائط المحمية…'},
  'player.settings': {'en': 'Settings', 'fr': 'Réglages', 'ar': 'الإعدادات'},
  'player.fullscreen': {'en': 'Full screen', 'fr': 'Plein écran', 'ar': 'ملء الشاشة'},
  'player.speed': {'en': 'Speed', 'fr': 'Vitesse', 'ar': 'السرعة'},
  'player.normal': {'en': 'Normal', 'fr': 'Normale', 'ar': 'عادية'},
  'player.quality': {'en': 'Quality', 'fr': 'Qualité', 'ar': 'الجودة'},
  'player.auto': {'en': 'Auto', 'fr': 'Auto', 'ar': 'تلقائي'},
  'player.err.processing': {
    'en': 'This lesson is still being prepared. Try again in a few minutes.',
    'fr': 'Cette leçon est encore en préparation. Réessaie dans quelques minutes.',
    'ar': 'هذا الدرس قيد التحضير. حاول بعد بضع دقائق.',
  },
  'player.err.access': {
    'en': 'You don’t have access to this lesson.',
    'fr': 'Tu n’as pas accès à cette leçon.',
    'ar': 'ليس لديك وصول إلى هذا الدرس.',
  },
  'player.err.session_expired': {
    'en': 'Your playback session ended. Tap retry to continue.',
    'fr': 'Ta session de lecture a expiré. Touche Réessayer pour continuer.',
    'ar': 'انتهت جلسة التشغيل. اضغط إعادة المحاولة للمتابعة.',
  },
  'player.err.license': {
    'en': 'The protection licence could not be obtained.',
    'fr': 'La licence de protection n’a pas pu être obtenue.',
    'ar': 'تعذّر الحصول على ترخيص الحماية.',
  },
  'player.err.drm_init': {
    'en': 'This device’s protection could not start.',
    'fr': 'La protection de cet appareil n’a pas pu démarrer.',
    'ar': 'تعذّر تشغيل حماية هذا الجهاز.',
  },
  'player.err.capability': {
    'en': 'This device cannot play protected lessons.',
    'fr': 'Cet appareil ne peut pas lire les leçons protégées.',
    'ar': 'لا يستطيع هذا الجهاز تشغيل الدروس المحمية.',
  },
  'player.err.security': {
    'en': 'This device doesn’t have the hardware protection NOVA lessons require. Use another phone or a computer.',
    'fr': 'Cet appareil n’a pas la protection matérielle requise. Utilise un autre téléphone ou un ordinateur.',
    'ar': 'لا يملك هذا الجهاز الحماية المادية المطلوبة. استخدم هاتفاً آخر أو حاسوباً.',
  },
  'player.err.output': {
    'en': 'Playback is blocked on this display. Disconnect external screens and try again.',
    'fr': 'La lecture est bloquée sur cet écran. Débranche les écrans externes et réessaie.',
    'ar': 'التشغيل محظور على هذه الشاشة. افصل الشاشات الخارجية وحاول مجدداً.',
  },
  'player.err.decode': {
    'en': 'The video could not be decoded.',
    'fr': 'La vidéo n’a pas pu être décodée.',
    'ar': 'تعذّر فك ترميز الفيديو.',
  },
  'player.err.timeout': {
    'en': 'The connection is too slow. Check your internet and retry.',
    'fr': 'La connexion est trop lente. Vérifie ton internet et réessaie.',
    'ar': 'الاتصال بطيء جداً. تحقّق من الإنترنت وأعد المحاولة.',
  },
  'player.err.delivery': {
    'en': 'The lesson could not be loaded. Retry in a moment.',
    'fr': 'La leçon n’a pas pu être chargée. Réessaie dans un instant.',
    'ar': 'تعذّر تحميل الدرس. أعد المحاولة بعد لحظة.',
  },
  'player.err.rate': {
    'en': 'Too many attempts. Wait a minute and retry.',
    'fr': 'Trop de tentatives. Attends une minute et réessaie.',
    'ar': 'محاولات كثيرة. انتظر دقيقة وأعد المحاولة.',
  },
  // D-070 clear copy (web `player.clear.*`): its messages never speak of
  // protected media.
  'player.clearBadge': {
    'en': 'Personal copy · identity watermark',
    'fr': 'Copie personnelle · filigrane nominatif',
    'ar': 'نسخة شخصية · علامة مائية باسمك',
  },
  'player.clearLoading': {'en': 'Loading the video…', 'fr': 'Chargement de la vidéo…', 'ar': 'جارٍ تحميل الفيديو…'},
  'player.clearChecking': {'en': 'Preparing the video…', 'fr': 'Préparation de la vidéo…', 'ar': 'جارٍ تجهيز الفيديو…'},
  'player.play': {'en': 'Play', 'fr': 'Lire', 'ar': 'تشغيل'},
  'player.err.clear_unavailable': {
    'en': 'This video is being prepared for your phone. It will start automatically in a moment.',
    'fr': 'Cette vidéo est en cours de préparation pour ton téléphone. Elle démarrera automatiquement dans un instant.',
    'ar': 'يجري تحضير هذا الفيديو لهاتفك. سيبدأ تلقائيًا بعد لحظات.',
  },
  'player.clearErr.processing': {
    'en': 'This video is still being prepared. Please try again shortly.',
    'fr': 'Cette vidéo est encore en cours de préparation. Réessaie dans quelques instants.',
    'ar': 'هذا الفيديو ما زال قيد التجهيز. يرجى المحاولة بعد قليل.',
  },
  'player.clearErr.timeout': {
    'en': 'The video took too long to respond. Check your connection and retry.',
    'fr': 'La vidéo a mis trop de temps à répondre. Vérifie ta connexion et réessaie.',
    'ar': 'استغرق الفيديو وقتًا طويلًا للاستجابة. تحقق من اتصالك وأعد المحاولة.',
  },
  'player.clearErr.session_expired': {
    'en': 'Your playback session has expired. Please retry.',
    'fr': 'Ta session de lecture a expiré. Réessaie.',
    'ar': 'انتهت صلاحية جلسة التشغيل. يرجى إعادة المحاولة.',
  },
  'player.clearErr.decode': {
    'en': 'This device could not play the video.',
    'fr': 'Cet appareil n’a pas pu lire la vidéo.',
    'ar': 'تعذر على هذا الجهاز تشغيل الفيديو.',
  },
  'player.clearErr.delivery': {
    'en': 'The video is temporarily unavailable. Please retry.',
    'fr': 'La vidéo est temporairement indisponible. Réessaie.',
    'ar': 'الفيديو غير متاح مؤقتًا. يرجى إعادة المحاولة.',
  },
  'player.err.ios_blocked': {
    'en': 'Protected lessons can’t play on iPhone yet. Use an Android phone or a computer.',
    'fr': 'Les leçons protégées ne sont pas encore lisibles sur iPhone. Utilise un téléphone Android ou un ordinateur.',
    'ar': 'لا يمكن تشغيل الدروس المحمية على آيفون بعد. استخدم هاتف أندرويد أو حاسوباً.',
  },
  'learn.lockedRow': {'en': 'Not available yet', 'fr': 'Pas encore disponible', 'ar': 'غير متاح بعد'},
  'learn.noLessons': {'en': 'No lessons yet', 'fr': 'Aucune leçon', 'ar': 'لا دروس بعد'},
  'learn.noLessonsMsg': {
    'en': 'Lessons appear here as soon as the teacher publishes them.',
    'fr': 'Les leçons apparaissent dès que le professeur les publie.',
    'ar': 'تظهر الدروس هنا فور نشرها من الأستاذ.',
  },
  'learn.watchedPill': {'en': '{n}% watched', 'fr': '{n} % vus', 'ar': 'شوهد {n}%'},
  'learn.passQuizToUnlock': {
    'en': 'Pass the quiz to complete the lesson',
    'fr': 'Réussis le quiz pour valider la leçon',
    'ar': 'انجح في الاختبار لإتمام الدرس',
  },
  'learn.quizRequired': {
    'en': 'Required to complete the lesson',
    'fr': 'Obligatoire pour valider la leçon',
    'ar': 'إلزامي لإتمام الدرس',
  },
  'learn.quizLockedMsg': {
    'en': 'Watch at least 90% of the lesson before opening its quiz.',
    'fr': 'Regarde au moins 90 % de la leçon avant d’ouvrir son quiz.',
    'ar': 'شاهد 90% على الأقل من الدرس قبل فتح اختباره.',
  },
  'learn.noAttemptsLeft': {'en': 'No attempts left for this quiz.', 'fr': 'Plus aucune tentative pour ce quiz.', 'ar': 'لم تبقَ محاولات لهذا الاختبار.'},
  'learn.retryAt': {'en': 'You can retry this quiz from {t}.', 'fr': 'Tu pourras réessayer à partir du {t}.', 'ar': 'يمكنك إعادة المحاولة ابتداءً من {t}.'},
  'learn.submitQuiz': {'en': 'Submit', 'fr': 'Valider', 'ar': 'إرسال'},
  'learn.quizPassedTitle': {'en': 'Quiz passed', 'fr': 'Quiz réussi', 'ar': 'نجحت في الاختبار'},
  'learn.quizFailedTitle': {'en': 'Not passed this time', 'fr': 'Pas réussi cette fois', 'ar': 'لم تنجح هذه المرة'},
  'learn.quizPassedMsg': {
    'en': 'You scored {n}%. The lesson is complete.',
    'fr': 'Tu as obtenu {n} %. La leçon est validée.',
    'ar': 'حصلت على {n}%. تم إتمام الدرس.',
  },
  'learn.quizPassedWatchMsg': {
    'en': 'You scored {n}%. Finish the video to complete the lesson.',
    'fr': 'Tu as obtenu {n} %. Termine la vidéo pour valider la leçon.',
    'ar': 'حصلت على {n}%. أكمل مشاهدة الفيديو لإتمام الدرس.',
  },
  'learn.quizScoreLine': {'en': 'Score {n}% · {p}% to pass', 'fr': 'Score {n} % · {p} % pour réussir', 'ar': 'النتيجة {n}% · النجاح بـ {p}%'},
  'learn.bestScore': {'en': 'Best score', 'fr': 'Meilleur score', 'ar': 'أفضل نتيجة'},
  'learn.attemptsLeft': {'en': 'Attempts left', 'fr': 'Tentatives restantes', 'ar': 'المحاولات المتبقية'},
  'learn.retryFrom': {'en': 'Retry from', 'fr': 'Nouvel essai dès', 'ar': 'إعادة المحاولة من'},
  'learn.unlimited': {'en': 'Unlimited', 'fr': 'Illimitées', 'ar': 'غير محدودة'},
  'learn.nextUnlocked': {'en': 'The lesson is complete.', 'fr': 'La leçon est validée.', 'ar': 'تم إتمام الدرس.'},
  'learn.finishVideoToComplete': {
    'en': 'Finish the video to complete the lesson.',
    'fr': 'Termine la vidéo pour valider la leçon.',
    'ar': 'أكمل مشاهدة الفيديو لإتمام الدرس.',
  },
  'learn.reviewAndRetry': {
    'en': 'Review the lesson, then try again.',
    'fr': 'Revois la leçon, puis réessaie.',
    'ar': 'راجع الدرس ثم أعد المحاولة.',
  },
  'learn.done': {'en': 'Done', 'fr': 'Terminer', 'ar': 'تم'},
  'learn.keepGoing': {'en': 'Keep going', 'fr': 'Continuer', 'ar': 'تابع'},
  'learn.pdfUnavailable': {'en': 'PDF unavailable', 'fr': 'PDF indisponible', 'ar': 'الملف غير متاح'},

  // Live room (D-067 Phase 3) — same states as the web live room.
  'live.connecting': {'en': 'Joining the live class…', 'fr': 'Connexion au live…', 'ar': 'جارٍ الانضمام إلى البث…'},
  'live.starting': {
    'en': 'The broadcast is starting. Playback begins automatically.',
    'fr': 'Le direct démarre. La lecture commencera automatiquement.',
    'ar': 'يبدأ البث الآن. سيبدأ التشغيل تلقائياً.',
  },
  'live.startingShort': {'en': 'Starting…', 'fr': 'Démarrage…', 'ar': 'جارٍ البدء…'},
  'live.reconnecting': {'en': 'Reconnecting…', 'fr': 'Reconnexion…', 'ar': 'إعادة الاتصال…'},
  'live.interruptedShort': {'en': 'Interrupted', 'fr': 'Interrompu', 'ar': 'متوقف'},
  'live.interrupted': {
    'en': 'The broadcast is interrupted. It resumes automatically as soon as it is back.',
    'fr': 'Le direct est interrompu. Il reprendra automatiquement dès son retour.',
    'ar': 'البث متوقف. سيُستأنف تلقائياً فور عودته.',
  },
  'live.waiting': {
    'en': 'This live class hasn’t started yet.',
    'fr': 'Ce live n’a pas encore commencé.',
    'ar': 'لم يبدأ هذا البث بعد.',
  },
  'live.waitingAt': {
    'en': 'This live class starts {t}. Stay here: playback begins automatically.',
    'fr': 'Ce live commence le {t}. Reste ici : la lecture démarrera automatiquement.',
    'ar': 'يبدأ هذا البث في {t}. ابقَ هنا: سيبدأ التشغيل تلقائياً.',
  },
  'live.ended': {'en': 'This live class has ended.', 'fr': 'Ce live est terminé.', 'ar': 'انتهى هذا البث.'},
  'live.replaySoon': {'en': 'This live class has ended. Its video will soon be a lesson of your Unit.', 'fr': 'Ce live est terminé. Sa vidéo sera bientôt une leçon de ton unité.', 'ar': 'كمل اللايف. الفيديو تاعو يولّي درس في الوحدة تاعك عن قريب.'},
  'live.cancelled': {'en': 'This live class was cancelled.', 'fr': 'Ce live a été annulé.', 'ar': 'أُلغي هذا البث.'},
  'live.failed': {
    'en': 'This live class could not take place.',
    'fr': 'Ce live n’a pas pu avoir lieu.',
    'ar': 'تعذّر إجراء هذا البث.',
  },
  'live.sound': {'en': 'Sound', 'fr': 'Son', 'ar': 'الصوت'},
  'live.questionsClosed': {
    'en': 'Questions are closed for this live class',
    'fr': 'Les questions sont fermées pour ce live',
    'ar': 'الأسئلة مغلقة لهذا البث',
  },
  'live.connectingMic': {'en': 'Connecting your microphone…', 'fr': 'Connexion du micro…', 'ar': 'جارٍ توصيل الميكروفون…'},
  'live.speakingLower': {'en': 'You’re speaking · lower hand', 'fr': 'Tu as la parole · baisser la main', 'ar': 'أنت تتحدث · أنزل يدك'},
  'live.reconnectingPlayer': {
    'en': 'Reconnecting to the live broadcast…',
    'fr': 'Reconnexion au direct…',
    'ar': 'جارٍ إعادة الاتصال بالبث المباشر…',
  },
  // Speaking (D-073).
  'live.youAreSpeaking': {'en': 'You are speaking', 'fr': 'Tu parles', 'ar': 'أنت تتحدث'},
  'live.studentSpeaking': {'en': '{name} is speaking', 'fr': '{name} parle', 'ar': '{name} يتحدث'},
  'live.aStudentSpeaking': {'en': 'A student is speaking', 'fr': 'Un élève parle', 'ar': 'طالب يتحدث'},
  'live.tapToHear': {
    'en': 'Tap to hear the live conversation',
    'fr': 'Appuie pour entendre la conversation en direct',
    'ar': 'اضغط لسماع المحادثة المباشرة',
  },
  'live.videoPaused': {
    'en': 'Video paused, audio continues',
    'fr': 'Vidéo en pause, le son continue',
    'ar': 'الفيديو متوقف مؤقتًا، الصوت مستمر',
  },
  'live.videoPausedBody': {
    'en': 'Your connection cannot carry the professor’s video right now. You can still hear and speak; the video resumes automatically.',
    'fr': 'Ta connexion ne peut pas recevoir la vidéo du professeur pour le moment. Tu peux toujours écouter et parler ; la vidéo reprendra automatiquement.',
    'ar': 'اتصالك لا يستطيع استقبال فيديو الأستاذ حاليًا. يمكنك الاستماع والتحدث، وسيستأنف الفيديو تلقائيًا.',
  },
  // Name required to enter a Live (D-073).
  'live.nameTitle': {
    'en': 'Add your name to join the Live',
    'fr': 'Ajoute ton nom pour rejoindre le Live',
    'ar': 'أضف اسمك للانضمام إلى البث المباشر',
  },
  'live.nameBody': {
    'en': 'The teaching team sees your first and last name on your questions and when you raise your hand.',
    'fr': 'L’équipe pédagogique voit ton prénom et ton nom sur tes questions et quand tu lèves la main.',
    'ar': 'يرى الفريق التعليمي اسمك ولقبك على أسئلتك وعندما ترفع يدك.',
  },
  'live.nameSubmit': {'en': 'Continue to the Live', 'fr': 'Continuer vers le Live', 'ar': 'المتابعة إلى البث المباشر'},
  'live.nameError': {
    'en': 'Your name could not be saved. Please retry.',
    'fr': 'Ton nom n’a pas pu être enregistré. Réessaie.',
    'ar': 'تعذر حفظ اسمك. يرجى إعادة المحاولة.',
  },
  'live.firstName': {'en': 'First name', 'fr': 'Prénom', 'ar': 'الاسم'},
  'live.lastName': {'en': 'Last name', 'fr': 'Nom', 'ar': 'اللقب'},
  'live.firstNameRequired': {'en': 'Enter your first name.', 'fr': 'Saisis ton prénom.', 'ar': 'أدخل اسمك.'},
  'live.lastNameRequired': {'en': 'Enter your last name.', 'fr': 'Saisis ton nom.', 'ar': 'أدخل لقبك.'},
  'err.liveBusy': {
    'en': 'The live class is busy for a moment. Try again.',
    'fr': 'Le live est occupé pour un instant. Réessaie.',
    'ar': 'البث مشغول للحظة. حاول مجدداً.',
  },
  'live.speakerDropped': {
    'en': 'Your microphone connection was lost. You’re back on the broadcast.',
    'fr': 'La connexion du micro a été perdue. Tu es revenu au direct.',
    'ar': 'انقطع اتصال الميكروفون. عدت إلى البث.',
  },
  'live.micUnavailable': {
    'en': 'The microphone isn’t available. Check the permission and that no other app uses it.',
    'fr': 'Le micro n’est pas disponible. Vérifie l’autorisation et qu’aucune autre app ne l’utilise.',
    'ar': 'الميكروفون غير متاح. تحقّق من الإذن وأن لا تطبيق آخر يستخدمه.',
  },

  // Store updates.
  'update.availableTitle': {'en': 'Update available', 'fr': 'Mise à jour disponible', 'ar': 'تحديث متوفر'},
  'update.availableBody': {
    'en': 'NOVA {v} is available. Update now to get the latest improvements.',
    'fr': 'NOVA {v} est disponible. Mets à jour pour profiter des dernières améliorations.',
    'ar': 'الإصدار {v} من نوفا متوفر. حدّث الآن للاستفادة من آخر التحسينات.',
  },
  'update.now': {'en': 'Update', 'fr': 'Mettre à jour', 'ar': 'تحديث'},
  'update.later': {'en': 'Later', 'fr': 'Plus tard', 'ar': 'لاحقاً'},
  'update.readyTitle': {'en': 'Update ready', 'fr': 'Mise à jour prête', 'ar': 'التحديث جاهز'},
  'update.readyBody': {
    'en': 'The new version is downloaded. Restart NOVA to finish installing it.',
    'fr': 'La nouvelle version est téléchargée. Redémarre NOVA pour terminer l’installation.',
    'ar': 'تم تنزيل الإصدار الجديد. أعد تشغيل نوفا لإكمال التثبيت.',
  },
  'update.restart': {'en': 'Restart', 'fr': 'Redémarrer', 'ar': 'إعادة التشغيل'},

  // Screen-capture protection (D-067).
  'capture.blocked': {
    'en': 'Screen recording or mirroring is on. NOVA stays hidden and '
        'playback is stopped until it ends.',
    'fr': 'L’enregistrement ou la recopie d’écran est actif. NOVA reste '
        'masquée et la lecture est arrêtée jusqu’à la fin.',
    'ar': 'تسجيل الشاشة أو عرضها مفعّل. يبقى نوفا مخفياً ويتوقف التشغيل '
        'حتى ينتهي.',
  },
  'capture.screenshot': {
    'en': 'Screenshots of NOVA content are not allowed.',
    'fr': 'Les captures d’écran du contenu NOVA ne sont pas autorisées.',
    'ar': 'لا يُسمح بلقطات الشاشة لمحتوى نوفا.',
  },

  // D-132 / D-133: the app follows the website (shell, gateway, home, units, one-page Lessons, Lives); same wording as website-front/src/lib/i18n.tsx.
  'tab.lives': {'en': 'Live', 'fr': 'Direct', 'ar': 'لايف'},
  'topbar.settings': {'en': 'Settings', 'fr': 'Paramètres', 'ar': 'الإعدادات'},
  'topbar.notifications': {'en': 'Notifications', 'fr': 'Notifications', 'ar': 'الإشعارات'},
  'splash.tagline': {'en': 'The BAC? We’ll get it together.', 'fr': 'Le BAC ? On l’obtient ensemble.', 'ar': 'الباك؟ نجيبوه مع بعض.'},
  'gateway.eyebrow': {'en': 'Welcome to Nova', 'fr': 'Bienvenue sur Nova', 'ar': 'مرحبا بيك في نوفا'},
  'gateway.title': {'en': 'Quick question before we *start*!', 'fr': 'Petite question avant de *commencer* !', 'ar': 'سؤال *صغير* قبل ما نبداو!'},
  'gateway.subtitle': {'en': 'Pick the one that matches you.', 'fr': 'Choisissez ce qui vous ressemble.', 'ar': 'اختار واش يشبهلك.'},
  'gateway.loginTag': {'en': 'I already have an account', 'fr': 'J’ai déjà un compte', 'ar': 'عندي حساب من قبل'},
  'gateway.loginText': {'en': 'Our Instagram or Telegram page already contacted you and told you that you are registered.', 'fr': 'Notre page Instagram ou Telegram vous a déjà contacté et vous a dit que vous êtes inscrit.', 'ar': 'صفحتنا في إنستغرام ولا تيليغرام تواصلت معاك وقالتلك راك مسجّل.'},
  'gateway.loginCta': {'en': 'Sign in', 'fr': 'Me connecter', 'ar': 'ادخل لحسابي'},
  'gateway.registerTag': {'en': 'I’m new here', 'fr': 'Je suis nouveau', 'ar': 'أنا جديد هنا'},
  'gateway.registerText': {'en': 'You have never contacted our Instagram or Telegram pages and this is your first visit to the platform.', 'fr': 'Vous n’avez jamais contacté nos pages Instagram ou Telegram et c’est votre première visite.', 'ar': 'عمرك ما تواصلت مع صفحاتنا في إنستغرام ولا تيليغرام، وهادي أول مرة تجي للمنصة.'},
  'gateway.registerCta': {'en': 'Create my account', 'fr': 'Créer mon compte', 'ar': 'دير حساب جديد'},
  'gateway.hint': {'en': 'Already registered? Don’t create a second account — just sign in.', 'fr': 'Déjà inscrit ? Pas de deuxième compte : connectez-vous.', 'ar': 'مسجّل من قبل؟ ما تديرش حساب ثاني، ادخل برك.'},
  'home.greeting': {'en': 'Welcome *back*, {name}.', 'fr': 'Bonjour {name} ! On *continue* ?', 'ar': 'أهلا {name}! *يلّا* نكمّلو'},
  'home.greetingGeneric': {'en': 'Welcome *back*.', 'fr': 'Bonjour ! On *continue* ?', 'ar': 'أهلا! *يلّا* نكمّلو'},
  'home.lead': {'en': 'Open your Units or discover the ones made for your level.', 'fr': 'Reprenez vos unités ou découvrez celles de votre niveau.', 'ar': 'كمّل الدروس تاعك ولا اكتشف الجداد تاع المستوى تاعك.'},
  'home.continue': {'en': 'Continue learning', 'fr': 'Reprendre', 'ar': 'كمّل القراية'},
  'home.seeOffers': {'en': 'See the Offers', 'fr': 'Voir les offres', 'ar': 'شوف العروض'},
  'home.liveNow': {'en': 'Your live class is on now', 'fr': 'Votre live a commencé !', 'ar': 'الحصة اللايف تاعك بدات!'},
  'home.waitingRoom': {'en': 'The waiting room is open', 'fr': 'La salle d’attente est ouverte !', 'ar': 'قاعة الانتظار تحلّت!'},
  'home.unitsTitle': {'en': 'Units', 'fr': 'Unités', 'ar': 'الدروس'},
  'home.unitsTextOwned': {'en': 'Your Units first, then more for your level.', 'fr': 'Vos unités d’abord, puis d’autres pour votre niveau.', 'ar': 'الدروس تاعك هوما الأولين، ومن بعد دروس أخرى للمستوى تاعك.'},
  'home.unitsText': {'en': 'Chosen for your level. Open one to see its lessons.', 'fr': 'Choisies pour votre niveau. Ouvrez-en une pour voir ses leçons.', 'ar': 'مختارين على قد المستوى تاعك. حل واحد باش تشوف واش فيه.'},
  'home.allUnits': {'en': 'All Units', 'fr': 'Toutes les unités', 'ar': 'كل الدروس'},
  'home.offersTitle': {'en': 'Offers', 'fr': 'Offres', 'ar': 'العروض'},
  'home.offersTextOwned': {'en': 'Your Offers first, then the ones for your level.', 'fr': 'Vos offres d’abord, puis celles de votre niveau.', 'ar': 'العروض تاعك هوما الأولين، ومن بعد عروض المستوى تاعك.'},
  'home.offersText': {'en': 'Several Units in a single purchase, for your level.', 'fr': 'Plusieurs unités en un seul achat, pour votre niveau.', 'ar': 'بزاف دروس في شرية وحدة، للمستوى تاعك.'},
  'home.allOffers': {'en': 'All Offers', 'fr': 'Toutes les offres', 'ar': 'كل العروض'},
  'home.openUnit': {'en': 'Open Unit', 'fr': 'Ouvrir', 'ar': 'حل الدرس'},
  'home.seeMore': {'en': 'See more', 'fr': 'Voir plus', 'ar': 'شوف أكثر'},
  'home.buyNow': {'en': 'Buy now', 'fr': 'Acheter', 'ar': 'شراء الآن'},
  'home.purchased': {'en': 'Purchased', 'fr': 'Acheté', 'ar': 'تم الشراء'},
  'home.unlocked': {'en': 'Unlocked', 'fr': 'Débloquée', 'ar': 'محلول'},
  'home.emptyTitle': {'en': 'New Units are *on their way*', 'fr': 'De nouvelles unités *arrivent*', 'ar': 'دروس جداد *في الطريق*'},
  'home.emptyText': {'en': 'Units and Offers for your level will appear here as soon as they are published.', 'fr': 'Les unités et offres de votre niveau arriveront ici dès qu’elles seront publiées.', 'ar': 'الدروس والعروض تاع المستوى تاعك يبانو هنا كيما ينشروهم.'},
  'units.eyebrow': {'en': 'My learning', 'fr': 'Mes cours', 'ar': 'القراية تاعي'},
  'units.title': {'en': 'My *units*', 'fr': 'Mes *unités*', 'ar': '*دروسي*'},
  'units.lead': {'en': 'All the Units you can open right now.', 'fr': 'Toutes les unités que vous pouvez ouvrir maintenant.', 'ar': 'كل الدروس اللي تقدر تحلّهم دروك.'},
  'units.howTo1': {'en': 'Open a Unit', 'fr': 'Ouvre une unité', 'ar': 'حل وحدة'},
  'units.howTo2': {'en': 'Pick a lesson in the list', 'fr': 'Choisis une leçon dans la liste', 'ar': 'اختار درس من الليستة'},
  'units.howTo3': {'en': 'Video, PDF and quiz: everything is on the lesson page', 'fr': 'Vidéo, PDF et quiz : tout est sur la page de la leçon', 'ar': 'الفيديو، الـPDF والكويز: كلش في صفحة الدرس'},
  'units.lessonsDone': {'en': '{done} of {total} done', 'fr': '{done} sur {total} terminées', 'ar': 'كمّلت {done} من {total}'},
  'units.nextLesson': {'en': 'Next lesson:', 'fr': 'Prochaine leçon :', 'ar': 'الدرس الجاي:'},
  'units.continue': {'en': 'Continue', 'fr': 'Continuer', 'ar': 'كمّل'},
  'units.start': {'en': 'Start', 'fr': 'Commencer', 'ar': 'ابدا'},
  'units.allLessons': {'en': 'All the lessons', 'fr': 'Toutes les leçons', 'ar': 'كل الدروس'},
  'units.completed': {'en': 'Completed', 'fr': 'Terminée', 'ar': 'كمّل'},
  'units.empty': {'en': 'No Unit yet', 'fr': 'Aucune unité pour l’instant', 'ar': 'ما عندك حتى درس'},
  'units.emptyText': {'en': 'Once a payment is confirmed, your Units appear here. Free Units too.', 'fr': 'Dès qu’un paiement est confirmé, vos unités apparaissent ici. Les gratuites aussi.', 'ar': 'كي يتأكد الخلاص، الدروس تاعك يبانو هنا. حتى الدروس بلاش.'},
  'units.browse': {'en': 'Browse Units', 'fr': 'Voir les unités', 'ar': 'شوف الدروس'},
  'unit.lead': {'en': 'Every lesson has its video, its PDF and its quiz on the same page.', 'fr': 'Chaque leçon a sa vidéo, son PDF et son quiz sur la même page.', 'ar': 'كل درس عندو الفيديو، الـPDF والكويز تاعو في نفس الصفحة.'},
  'unit.resume': {'en': 'Continue: {title}', 'fr': 'Continuer : {title}', 'ar': 'كمّل: {title}'},
  'unit.startFirst': {'en': 'Start with lesson 1', 'fr': 'Commencer par la leçon 1', 'ar': 'ابدا بالدرس 1'},
  'unit.howTo1': {'en': 'Pick a lesson in the list', 'fr': 'Choisis une leçon dans la liste', 'ar': 'اختار درس من الليستة'},
  'unit.howTo2': {'en': 'Watch its video', 'fr': 'Regarde sa vidéo', 'ar': 'تفرّج الفيديو تاعو'},
  'unit.howTo3': {'en': 'Read its PDF and take its quiz, on the same page', 'fr': 'Lis son PDF et fais son quiz, sur la même page', 'ar': 'اقرا الـPDF وجاوب على الكويز، في نفس الصفحة'},
  'unit.lessons': {'en': 'Unit Lessons', 'fr': 'Les leçons', 'ar': 'دروس الوحدة'},
  'unit.fromLive': {'en': 'Live', 'fr': 'Live', 'ar': 'لايف'},
  'unit.continueHere': {'en': 'Continue here', 'fr': 'Continue ici', 'ar': 'كمّل من هنا'},
  'unit.startHere': {'en': 'Start here', 'fr': 'Commence ici', 'ar': 'ابدا من هنا'},
  'unit.noLessons': {'en': 'No Lessons yet', 'fr': 'Pas encore de leçons', 'ar': 'مازال ما كاين حتى درس'},
  'unit.noLessonsText': {'en': 'The Lessons of this Unit will appear here as soon as they are published.', 'fr': 'Les leçons de cette unité apparaîtront ici dès leur publication.', 'ar': 'دروس هاد الوحدة يبانو هنا كيما ينشروهم.'},
  'unit.minutes': {'en': '{n} min', 'fr': '{n} min', 'ar': '{n} دقيقة'},
  'lesson.allLessons': {'en': 'All the lessons', 'fr': 'Toutes les leçons', 'ar': 'كل الدروس'},
  'lesson.fromLive': {'en': 'Recorded during the live class', 'fr': 'Enregistrée pendant le live', 'ar': 'تسجّل في اللايف'},
  'lesson.stepVideo': {'en': 'Video', 'fr': 'Vidéo', 'ar': 'الفيديو'},
  'lesson.stepPdf': {'en': 'PDF', 'fr': 'PDF', 'ar': 'PDF'},
  'lesson.stepQuiz': {'en': 'Quiz', 'fr': 'Quiz', 'ar': 'الكويز'},
  'lesson.stepDone': {'en': 'Done', 'fr': 'Fait', 'ar': 'كمّلت'},
  'lesson.stepNone': {'en': 'Not yet', 'fr': 'Pas encore', 'ar': 'مازال'},
  'lesson.stepTodo': {'en': 'To do', 'fr': 'À faire', 'ar': 'باقي'},
  'lesson.blockVideo': {'en': 'Watch the video', 'fr': 'Regarde la vidéo', 'ar': 'تفرّج الفيديو'},
  'lesson.videoDone': {'en': 'Video watched. Well done!', 'fr': 'Vidéo regardée. Bravo !', 'ar': 'تفرّجت الفيديو. يعطيك الصحة!'},
  'lesson.videoProgress': {'en': 'You watched {n}%. The video counts as watched at 90%.', 'fr': 'Tu as regardé {n} %. La vidéo compte comme vue à 90 %.', 'ar': 'تفرّجت {n}%. الفيديو يتحسب كي توصل 90%.'},
  'lesson.videoHint': {'en': 'Press play. The video counts as watched at 90%.', 'fr': 'Appuie sur lecture. La vidéo compte comme vue à 90 %.', 'ar': 'اضغط على التشغيل. الفيديو يتحسب كي توصل 90%.'},
  'lesson.blockPdf': {'en': 'Read the PDF', 'fr': 'Lis le PDF', 'ar': 'اقرا الـPDF'},
  'lesson.pdfTitle': {'en': 'The lesson summary', 'fr': 'Le résumé de la leçon', 'ar': 'ملخص الدرس'},
  'lesson.pdfOpened': {'en': 'Opened. You can open it again at any time.', 'fr': 'Ouvert. Tu peux le rouvrir quand tu veux.', 'ar': 'حلّيتو. تقدر تعاود تحلّو وقتما حبيت.'},
  'lesson.pdfText': {'en': 'It opens right here, only for you.', 'fr': 'Il s’ouvre ici, rien que pour toi.', 'ar': 'يتحل هنا، غير ليك.'},
  'lesson.openPdf': {'en': 'Open the PDF', 'fr': 'Ouvrir le PDF', 'ar': 'حل الـPDF'},
  'lesson.noPdf': {'en': 'No PDF for this lesson for now.', 'fr': 'Pas de PDF pour cette leçon pour l’instant.', 'ar': 'ما كاينش PDF لهاد الدرس حاليا.'},
  'lesson.blockQuiz': {'en': 'Take the quiz', 'fr': 'Fais le quiz', 'ar': 'جاوب على الكويز'},
  'lesson.noQuiz': {'en': 'No quiz for this lesson for now.', 'fr': 'Pas de quiz pour cette leçon pour l’instant.', 'ar': 'ما كاينش كويز لهاد الدرس حاليا.'},
  'lesson.quizPassed': {'en': 'Quiz passed, bravo!', 'fr': 'Quiz réussi, bravo !', 'ar': 'نجحت في الكويز، برافو!'},
  'lesson.quizTitle': {'en': 'A few questions to check what you learned', 'fr': 'Quelques questions pour vérifier ce que tu as appris', 'ar': 'شوية أسئلة باش تشوف واش فهمت'},
  'lesson.quizLoading': {'en': 'Loading your quiz…', 'fr': 'Chargement de ton quiz…', 'ar': 'راهو يتحمّل الكويز…'},
  'lesson.quizRetryAt': {'en': 'You can try again on {date}.', 'fr': 'Tu pourras réessayer le {date}.', 'ar': 'تقدر تعاود تجرّب نهار {date}.'},
  'lesson.quizRequired': {'en': 'Pass it to complete the lesson.', 'fr': 'Réussis-le pour terminer la leçon.', 'ar': 'انجح فيه باش يكمل الدرس.'},
  'lesson.quizFree': {'en': 'Take it whenever you want, even before the video.', 'fr': 'Fais-le quand tu veux, même avant la vidéo.', 'ar': 'دير وقتما حبيت، حتى قبل الفيديو.'},
  'lesson.bestScore': {'en': 'Best score: {n}%', 'fr': 'Meilleur score : {n} %', 'ar': 'أحسن نتيجة: {n}%'},
  'lesson.quizStart': {'en': 'Start the quiz', 'fr': 'Commencer', 'ar': 'ابدا الكويز'},
  'lesson.quizRetake': {'en': 'Retake', 'fr': 'Refaire', 'ar': 'عاود'},
  'lesson.previous': {'en': 'Previous lesson', 'fr': 'Leçon précédente', 'ar': 'الدرس اللي قبل'},
  'lesson.next': {'en': 'Next lesson', 'fr': 'Leçon suivante', 'ar': 'الدرس الجاي'},
  'lesson.completed': {'en': 'Completed', 'fr': 'Terminée', 'ar': 'كمّل'},
  'lesson.durationPending': {'en': 'Duration pending', 'fr': 'Durée à venir', 'ar': 'المدة مازالت'},
  'lives.eyebrow': {'en': 'Live learning', 'fr': 'En direct', 'ar': 'لايف'},
  'lives.title': {'en': '*Lives*', 'fr': 'Les *directs*', 'ar': 'الحصص *اللايف*'},
  'lives.lead': {'en': 'Join the live classes of your Units and see what is coming next.', 'fr': 'Rejoignez les lives de vos unités et voyez les prochains.', 'ar': 'ادخل للحصص اللايف تاع دروسك وشوف واش جاي.'},
  'lives.missedTitle': {'en': 'Missed a live class?', 'fr': 'Tu as raté un live ?', 'ar': 'فاتك لايف؟'},
  'lives.missedText': {'en': 'Every live class that ends becomes a lesson of its Unit, with the other lessons.', 'fr': 'Chaque live terminé devient une leçon de son unité, avec les autres leçons.', 'ar': 'كل لايف يكمل يولّي درس في الوحدة تاعو، مع الدروس لوخرين.'},
  'lives.empty': {'en': 'No live sessions here', 'fr': 'Aucun live ici', 'ar': 'ما كاين حتى لايف هنا'},
  'lives.emptyText': {'en': 'Live classes for your Units will show up here.', 'fr': 'Les lives de vos unités apparaîtront ici.', 'ar': 'الحصص اللايف تاع دروسك يبانو هنا.'},
  'lives.join': {'en': 'Join the live', 'fr': 'Rejoindre', 'ar': 'ادخل للايف'},
  'lives.scheduled': {'en': 'Scheduled', 'fr': 'Programmé', 'ar': 'مبرمج'},
  'lives.onNow': {'en': 'Live now', 'fr': 'En direct', 'ar': 'راهو لايف'},

  // D-133: the website’s sign-in and register wording.
  'auth.eyebrow': {'en': 'Built for your next result', 'fr': 'Avec vous jusqu’au BAC', 'ar': 'معاك حتى لنهار الباك'},
  'auth.haveAccount': {'en': 'Already have an account?', 'fr': 'Déjà un compte ?', 'ar': 'عندك حساب من قبل؟'},

  // D-133: the Account tab, as the website’s account pages.
  'account.eyebrow': {'en': 'My account', 'fr': 'Mon compte', 'ar': 'الحساب تاعي'},
  'account.title': {'en': 'My *account*', 'fr': 'Mon *compte*', 'ar': '*حسابي*'},
  'account.lead': {'en': 'Your orders, your points, your notifications and your settings.', 'fr': 'Vos commandes, vos points, vos notifications et vos paramètres.', 'ar': 'الطلبات، النقاط، الإشعارات والإعدادات تاعك.'},
  'account.schoolManaged': {'en': 'School-managed', 'fr': 'Gérée par l’école', 'ar': 'المدرسة تسيّرو'},

  // D-134: "continue without an account" (App Store 5.1.1(v)); account features ask to sign in.
  'gateway.guestTag': {'en': 'I just want to look around', 'fr': 'Je veux juste regarder', 'ar': 'نحب نشوف برك'},
  'gateway.guestText': {'en': 'See the units, offers and teachers without an account. You create one when you want to buy or study.', 'fr': 'Parcourez les unités, les offres et les enseignants sans compte. Vous en créerez un pour acheter ou étudier.', 'ar': 'شوف الوحدات والعروض والأساتذة بلا حساب. تدير حساب كي تحب تشري ولا تقرا.'},
  'gateway.guestCta': {'en': 'Continue without an account', 'fr': 'Continuer sans compte', 'ar': 'كمّل بلا حساب'},
  'guest.message': {'en': 'Sign in or create your account to use this part of NOVA. Units and offers can be seen without an account.', 'fr': 'Connectez-vous ou créez votre compte pour utiliser cette partie de NOVA. Les unités et les offres se consultent sans compte.', 'ar': 'ادخل لحسابك ولا دير حساب باش تستعمل هاد الجزء من نوفا. الوحدات والعروض تتشافو بلا حساب.'},
  'guest.lessons': {'en': 'Your lessons', 'fr': 'Vos leçons', 'ar': 'دروسك'},
  'guest.lives': {'en': 'Your live classes', 'fr': 'Vos lives', 'ar': 'اللايفات تاعك'},
  'guest.cart': {'en': 'Your cart', 'fr': 'Votre panier', 'ar': 'السلة تاعك'},
  'guest.account': {'en': 'Your account', 'fr': 'Votre compte', 'ar': 'حسابك'},
  'guest.signIn': {'en': 'Sign in', 'fr': 'Connexion', 'ar': 'دخول'},
  'guest.eyebrow': {'en': 'Browsing without an account', 'fr': 'Visite sans compte', 'ar': 'راك تشوف بلا حساب'},
  'guest.homeTitle': {'en': 'Hello! *Discover* NOVA', 'fr': 'Bonjour ! *Découvrez* NOVA', 'ar': 'أهلا! *اكتشف* نوفا'},
  'guest.homeText': {'en': 'Look at the units and offers of your level. Create your account when you are ready.', 'fr': 'Regardez les unités et les offres de votre niveau. Créez votre compte quand vous êtes prêt.', 'ar': 'شوف الوحدات والعروض تاع المستوى تاعك. دير حسابك كي تكون واجد.'},
};

extension NovaTr on BuildContext {
  /// Localized string for [key] in the active language.
  String tr(String key) {
    final NovaLang lang = AppScope.of(this).lang;
    return K[key]?[lang.name] ?? K[key]?['en'] ?? key;
  }

  /// Localized string with `{token}` replacement.
  String trf(String key, Map<String, String> params) {
    String value = tr(key);
    params.forEach((String token, String replacement) {
      value = value.replaceAll('{$token}', replacement);
    });
    return value;
  }
}
