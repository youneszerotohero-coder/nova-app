import 'package:nova_mobile/core/state/app_state.dart';
import 'package:nova_mobile/data/account_store.dart';
import 'package:nova_mobile/data/catalog_store.dart';
import 'package:nova_mobile/data/commerce_store.dart';
import 'package:nova_mobile/data/learning_store.dart';
import 'package:nova_mobile/data/live_store.dart';
import 'package:nova_mobile/data/models.dart';
import 'package:nova_mobile/data/session_store.dart';

import 'fixture_data.dart';

/// The fixture Student's cart: one Course waiting, as in the design.
final CartItem fixtureCartItem = CartItem(
  id: 'course:101',
  productKind: 'course',
  productId: 101,
  title: HomeData.popularCourses.first.title,
  kind: 'Individual Course',
  price: HomeData.popularCourses.first.price,
  compareAtPrice: HomeData.popularCourses.first.compareAtPrice,
  scene: HomeData.popularCourses.first.scene,
  icon: HomeData.popularCourses.first.icon,
  image: HomeData.popularCourses.first.image,
);

/// Installs a signed-in, offline [AppState] built from the design
/// fixtures, so widget and golden tests render real screens without a
/// backend. Every call starts from a fresh state, pinned to English
/// (the app itself starts in Arabic) so the goldens keep their text.
AppState installFixtureApp({
  CatalogStore? catalog,
  CommerceStore? commerce,
  LearningStore? learning,
  LiveStore? live,
  AccountStore? account,
}) {
  final List<Course> owned = HomeData.popularCourses
      .where((Course c) => c.owned)
      .toList();
  final AppState state = AppState.seeded(
    session: SessionStore.seeded(HomeData.student),
    catalog: catalog ??
        CatalogStore.seeded(
          courses: HomeData.popularCourses,
          offers: HomeData.featuredPacks,
          teachers: HomeData.teachers,
        ),
    learning: learning ?? LearningStore.seeded(owned: owned, lives: HomeData.lives),
    commerce: commerce ??
        CommerceStore.seeded(
          cart: <CartItem>[fixtureCartItem],
          orders: HomeData.orders,
        ),
    account: account ??
        AccountStore.seeded(
          notifications: HomeData.notifications,
          ledger: HomeData.pointsLedger,
          balance: HomeData.student.points,
        ),
    live: live,
    lang: NovaLang.en,
  );
  AppState.instance = state;
  return state;
}
