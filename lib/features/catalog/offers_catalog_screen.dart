import 'package:flutter/material.dart';

import 'catalog_page.dart';

/// The website's `/bundles` page: the Offers catalogue (D-134).
class OffersCatalogScreen extends StatelessWidget {
  const OffersCatalogScreen({super.key});

  @override
  Widget build(BuildContext context) => const CatalogPage(kind: CatalogKind.offers);
}
