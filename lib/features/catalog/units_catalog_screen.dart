import 'package:flutter/material.dart';

import 'catalog_page.dart';

/// The website's `/courses` page: the Units catalogue (D-134).
class UnitsCatalogScreen extends StatelessWidget {
  const UnitsCatalogScreen({super.key});

  @override
  Widget build(BuildContext context) => const CatalogPage(kind: CatalogKind.units);
}
