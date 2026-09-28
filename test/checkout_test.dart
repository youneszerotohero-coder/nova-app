import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nova_mobile/core/state/app_state.dart';
import 'package:nova_mobile/core/theme/nova_theme.dart';
import 'package:nova_mobile/core/utils/format_price.dart';
import 'package:nova_mobile/core/widgets/gradient_pill_button.dart';
import 'package:nova_mobile/core/widgets/nova_scene_image.dart';
import 'package:nova_mobile/core/widgets/pressable_scale.dart';
import 'package:nova_mobile/data/commerce_store.dart';
import 'package:nova_mobile/features/cart/checkout_screen.dart';

import 'fixtures/fake_api.dart';
import 'fixtures/fixture_app.dart';
import 'nova_font_loader.dart';

const CartItem _offer = CartItem(
  id: 'offer:201',
  productKind: 'offer',
  productId: 201,
  title: 'Science Track — Complete Year',
  kind: 'Offer',
  price: 18900,
  compareAtPrice: 18900,
  scene: NovaScene.sunrise,
  icon: Icons.auto_awesome_rounded,
);

/// A `POST /checkout/quote` answer in production's shape.
FakeResponse _quote({
  String referral = '0.00',
  String points = '0.00',
  String total = '18900.00',
  String commercialDiscount = 'none',
  int pointsUsed = 0,
  int maxPoints = 0,
}) {
  return FakeResponse(200, <String, Object>{
    'data': <String, Object?>{
      'academic_year': '2026/2027',
      'base_amount': '18900.00',
      'overlap_credit': '0.00',
      'referral_discount': referral,
      'promo_discount': '0.00',
      'points_discount': points,
      'final_amount': total,
      'currency': 'DZD',
      'commercial_discount': commercialDiscount,
      'points_used': pointsUsed,
      'points_balance': maxPoints,
      'max_points_usable': maxPoints,
      'points_redemption_enabled': maxPoints > 0,
    },
  });
}

void main() {
  setUpAll(loadNovaFonts);

  Future<FakeBackend> pumpCheckout(
    WidgetTester tester,
    Map<String, FakeResponse> routes,
  ) async {
    tester.view.physicalSize = const Size(1170, 4800);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final FakeBackend backend = FakeBackend(routes);
    final AppState state =
        installFixtureApp(commerce: CommerceStore(fakeApi(backend)));
    await tester.pumpWidget(
      AppScope(
        state: state,
        child: MaterialApp(
          theme: NovaTheme.light,
          home: const CheckoutScreen(item: _offer),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return backend;
  }

  List<Object?> quoteBodies(FakeBackend backend) => backend.requests
      .where((FakeRequest r) => r.method == 'POST' && r.path == '/checkout/quote')
      .map((FakeRequest r) => r.data)
      .toList();

  testWidgets(
      'no points control; the code link under the pay button re-quotes '
      'with the code', (tester) async {
    final FakeBackend backend = await pumpCheckout(tester, <String, FakeResponse>{
      'POST /checkout/quote': _quote(
        points: '750.00',
        total: '18150.00',
        pointsUsed: 750,
        maxPoints: 750,
      ),
    });

    // Points apply automatically, as on the website: a quote with no
    // points, then the same quote with the maximum the backend allows.
    expect(quoteBodies(backend), <Object>[
      <String, Object>{'offer_id': 201, 'points_to_use': 0},
      <String, Object>{'offer_id': 201, 'points_to_use': 750},
    ]);

    // No points option anywhere: no method tile, toggle or slider —
    // only the read-only line the server quote reports.
    expect(find.text('Points'), findsNothing);
    expect(find.textContaining('available'), findsNothing);
    expect(find.byType(Switch), findsNothing);
    expect(find.byType(Slider), findsNothing);
    expect(find.byType(Checkbox), findsNothing);
    final Finder pointsLine = find.text('Points (750 automatically applied)');
    expect(pointsLine, findsOneWidget);
    expect(
      find.ancestor(of: pointsLine, matching: find.byType(PressableScale)),
      findsNothing,
    );
    expect(find.text(formatDaPrice(18150)), findsOneWidget);

    // The code entry is a text link under the one primary button.
    final Finder link = find.text('Have a discount code?');
    expect(link, findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(
      tester.getRect(link).top,
      greaterThan(tester.getRect(find.byType(GradientPillButton)).bottom),
    );

    await tester.tap(link);
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    expect(
      tester.getRect(find.byType(TextField)).top,
      greaterThan(tester.getRect(find.byType(GradientPillButton)).bottom),
    );

    backend.routes['POST /checkout/quote'] = _quote(
      referral: '1890.00',
      total: '17010.00',
      commercialDiscount: 'referral',
    );
    await tester.enterText(find.byType(TextField), 'friend26');
    await tester.pump();
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();

    expect(quoteBodies(backend).last, <String, Object>{
      'offer_id': 201,
      'discount_code': 'friend26',
      'points_to_use': 0,
    });
    expect(find.text('Referral discount'), findsOneWidget);
    expect(find.text('Referral discount applied to this order.'), findsOneWidget);
    expect(find.text(formatDaPrice(17010)), findsOneWidget);
    expect(find.text('Remove'), findsOneWidget);
  });

  testWidgets(
      'a refused code keeps the quote and explains why under the field',
      (tester) async {
    final FakeBackend backend = await pumpCheckout(tester, <String, FakeResponse>{
      'POST /checkout/quote': _quote(),
    });

    await tester.tap(find.text('Have a discount code?'));
    await tester.pumpAndSettle();
    backend.routes['POST /checkout/quote'] = const FakeResponse(422, <String, Object>{
      'error': <String, Object>{
        'code': 'DISCOUNT_CODE_INVALID',
        'message': 'This discount code is not valid.',
      },
    });
    await tester.enterText(find.byType(TextField), 'NOPE');
    await tester.pump();
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();

    expect(find.text('This code is not valid for this order.'), findsOneWidget);
    expect(find.text(formatDaPrice(18900)), findsWidgets);
    expect(find.text('Remove'), findsNothing);
  });

  testWidgets(
      'a zero total skips payment methods and orders exactly what was quoted',
      (tester) async {
    final FakeBackend backend = await pumpCheckout(tester, <String, FakeResponse>{
      // A linked referral the backend applied without any code.
      'POST /checkout/quote': _quote(
        referral: '18900.00',
        total: '0.00',
        commercialDiscount: 'referral',
      ),
      'POST /orders': const FakeResponse(201, <String, Object>{
        'data': <String, Object?>{
          'id': 9,
          'order_number': 'NV-260926-TEST',
          'status': 'paid',
        },
      }),
    });

    expect(find.text('Pay by card'), findsNothing);
    expect(
      find.text('Covered entirely by your owned courses, discounts and points.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Confirm order'));
    await tester.pumpAndSettle();

    final FakeRequest order = backend.requests.firstWhere(
      (FakeRequest r) => r.method == 'POST' && r.path == '/orders',
    );
    expect(order.data, <String, Object>{
      'offer_id': 201,
      'commercial_discount': 'referral',
      'points_to_use': 0,
    });
    expect(find.text('Order paid'), findsOneWidget);
  });
}
