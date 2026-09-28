import 'package:flutter/widgets.dart';

import '../../data/models.dart';
import 'nova_strings.dart';

/// A pack's offer type in the app language, in the website's wording.
String offerTypeText(BuildContext context, Pack pack) {
  final String key = 'offer.type_${pack.type}';
  return K.containsKey(key) ? context.tr(key) : pack.offerType;
}

/// A points ledger line: the school's own reason as written, otherwise
/// the ledger type in the app language.
String pointsEntryText(BuildContext context, PointsEntry entry) {
  final String key = 'points.type_${entry.type}';
  return entry.hasReason || !K.containsKey(key) ? entry.label : context.tr(key);
}

/// The fixed English labels the models build for orders and the cart
/// ("Offer", "Card"…) in the app language; anything else as is.
String modelLabelText(BuildContext context, String label) {
  final String? key = _modelLabels[label];
  return key == null ? label : context.tr(key);
}

const Map<String, String> _modelLabels = <String, String>{
  'Offer': 'kind.offer',
  'Course': 'kind.course',
  'Individual Course': 'kind.individualCourse',
  'Card': 'method.card',
  'Points': 'method.points',
};
