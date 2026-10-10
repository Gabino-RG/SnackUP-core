import 'package:flutter/material.dart';
import '../../catalog/catalog.dart';
import '../catalog/catalog_screen.dart';

class AddEditProductScreen extends StatelessWidget {
  const AddEditProductScreen({super.key, required this.businessId, this.productId});
  final String businessId;
  final String? productId;
  @override
  Widget build(BuildContext context) => CatalogEditorScreen(
    businessId: businessId, productId: productId, repository: CatalogScope.of(context),
  );
}
