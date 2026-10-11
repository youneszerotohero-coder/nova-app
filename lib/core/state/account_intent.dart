import '../../data/models.dart';

/// What a visitor asked for before signing in (D-134, after D-127): once
/// signed in, the Student space carries it out.
sealed class AccountIntent {
  const AccountIntent();
}

/// A tab of the Student space (My lessons, Live, Cart, Account).
final class OpenTab extends AccountIntent {
  const OpenTab(this.tab);

  final int tab;
}

/// "Buy now" / "Add to cart": the item goes in the cart and the cart opens.
final class AddToCart extends AccountIntent {
  const AddToCart(this.kind, this.id);

  final String kind;
  final int id;
}

final class OpenNotifications extends AccountIntent {
  const OpenNotifications();
}

/// "Join for free" / "Open the Unit": its page opens again, now with the
/// Student's own button.
final class OpenCourse extends AccountIntent {
  const OpenCourse(this.course);

  final Course course;
}
