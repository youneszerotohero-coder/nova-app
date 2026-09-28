import 'dart:io';

import 'package:flutter/material.dart';

import '../core/api/api_exception.dart';
import '../core/api/nova_api.dart';
import '../core/widgets/nova_scene_image.dart';
import 'json.dart';
import 'models.dart';

/// One checkout-eligible program (a Course or an Offer) in the server
/// cart. Checkout processes one program at a time, per the conception.
class CartItem {
  const CartItem({
    required this.id,
    required this.title,
    required this.kind,
    required this.price,
    required this.compareAtPrice,
    required this.scene,
    required this.icon,
    this.productKind = 'course',
    this.productId = 0,
    this.meta = '',
    this.image,
  });

  factory CartItem.fromJson(Json json) {
    final String kind = json.str('kind');
    final int id = json.integer('id');
    final int price = dinars(json['price']);
    return CartItem(
      id: json.str('key', '$kind:$id'),
      productKind: kind,
      productId: id,
      title: json.str('title'),
      kind: kind == 'offer' ? 'Offer' : 'Individual Course',
      meta: json.str('meta'),
      price: price,
      compareAtPrice: price,
      scene: sceneFor(kind == 'offer' ? id + 3 : id),
      icon: kind == 'offer' ? Icons.auto_awesome_rounded : Icons.school_rounded,
      image: json.strOrNull('image'),
    );
  }

  /// Server cart key, `course:12` / `offer:3`.
  final String id;

  /// `course` | `offer` — the API product type.
  final String productKind;
  final int productId;
  final String title;
  final String kind;
  final String meta;
  final int price;
  final int compareAtPrice;
  final NovaScene scene;
  final IconData icon;

  /// Program poster; the painted [scene] stands in when absent.
  final String? image;

  int get discountPercent => compareAtPrice > price
      ? (((compareAtPrice - price) / compareAtPrice) * 100).round()
      : 0;

  /// Body for `/checkout/quote` and `/orders`.
  Map<String, Object> get productBody =>
      <String, Object>{'${productKind}_id': productId};
}

/// Server price quote; every amount is computed by the backend.
class Quote {
  const Quote(this.json);

  final Json json;

  int get base => dinars(json['base_amount']);
  int get overlapCredit => dinars(json['overlap_credit']);
  int get referralDiscount => dinars(json['referral_discount']);
  int get promoDiscount => dinars(json['promo_discount']);
  int get pointsDiscount => dinars(json['points_discount']);
  int get finalAmount => dinars(json['final_amount']);
  int get maxPointsUsable => json.integer('max_points_usable');
  bool get pointsEnabled => json.flag('points_redemption_enabled');
  int get pointsUsed => json.integer('points_used');

  /// `none` | `referral` | `promo` — the commercial discount the backend
  /// applied, including a linked referral applied without any code.
  String get commercialDiscount => json.str('commercial_discount', 'none');
}

/// Cart, checkout and the Student's orders.
class CommerceStore extends ChangeNotifier {
  CommerceStore(this._api);

  CommerceStore.seeded({
    List<CartItem> cart = const <CartItem>[],
    this._orders = const <Order>[],
  })  : _api = null,
        _items = cart;

  final NovaApi? _api;

  List<CartItem> _items = const <CartItem>[];
  List<Order> _orders = const <Order>[];

  List<CartItem> get items => _items;
  int get itemCount => _items.length;
  List<Order> get orders => _orders;

  bool contains(String key) => _items.any((CartItem i) => i.id == key);

  Future<void> load() async {
    final NovaApi? api = _api;
    if (api == null) return;
    try {
      final List<Json> bodies = await Future.wait(<Future<Json>>[
        api.get('/cart'),
        api.get('/orders'),
      ]);
      _items = bodies[0].list('data').map(CartItem.fromJson).toList();
      _orders = bodies[1].list('data').map(Order.fromJson).toList();
      notifyListeners();
    } on ApiException {
      // Screens keep the last known state; pull-to-refresh retries.
    }
  }

  /// Adds a Course or an Offer; the backend refuses free, owned or
  /// not-sold programs with a business code the caller shows.
  Future<void> add({required String kind, required int id}) async {
    final NovaApi? api = _api;
    if (api == null) return;
    final Json body = await api.post('/cart/items', <String, int>{'${kind}_id': id});
    _items = body.list('data').map(CartItem.fromJson).toList();
    notifyListeners();
  }

  Future<void> remove(CartItem item) async {
    final NovaApi? api = _api;
    if (api == null) {
      _items = _items.where((CartItem i) => i.id != item.id).toList();
      notifyListeners();
      return;
    }
    final Json body =
        await api.delete('/cart/items/${item.productKind}/${item.productId}');
    _items = body.list('data').map(CartItem.fromJson).toList();
    notifyListeners();
  }

  /// Same body as the website: the program, the code when one is being
  /// applied, and `points_to_use` always present (0 unless the caller
  /// re-quotes with the maximum the backend allows).
  Future<Quote> quote(CartItem item, {String? discountCode, int points = 0}) async {
    final NovaApi api = _api!;
    final Json body = await api.post('/checkout/quote', <String, Object?>{
      ...item.productBody,
      if (discountCode != null && discountCode.trim().isNotEmpty)
        'discount_code': discountCode.trim(),
      'points_to_use': points,
    });
    return Quote(body.obj('data') ?? <String, dynamic>{});
  }

  /// Creates the order from the quote on screen, as the website does:
  /// the applied code, or else the quote's [commercialDiscount] (`none`,
  /// or `referral` for a linked referral), and the points the quote
  /// used. A zero total comes back already paid.
  Future<Json> placeOrder(
    CartItem item, {
    String? discountCode,
    String commercialDiscount = 'none',
    int points = 0,
  }) async {
    final NovaApi api = _api!;
    final String code = discountCode?.trim() ?? '';
    final Json body = await api.post('/orders', <String, Object?>{
      ...item.productBody,
      if (code.isNotEmpty)
        'discount_code': code
      else
        'commercial_discount': commercialDiscount,
      'points_to_use': points,
    });
    await load();
    return body.obj('data') ?? <String, dynamic>{};
  }

  Future<void> uploadCcpReceipt(int orderId, File receipt) async {
    await _api!.upload('/orders/$orderId/payments/ccp', field: 'receipt', file: receipt);
    await load();
  }

  /// Chargily hosted checkout URL (opened in the browser).
  Future<Uri> chargilyCheckout(int orderId) async {
    final Json body = await _api!.post('/orders/$orderId/payments/chargily/checkout');
    return Uri.parse(body.obj('data')?.str('checkout_url') ?? '');
  }

  void clear() {
    _items = const <CartItem>[];
    _orders = const <Order>[];
    notifyListeners();
  }
}
