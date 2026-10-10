import 'package:flutter/material.dart';
import '../../catalog/catalog.dart';
import '../catalog/catalog_screen.dart';

class ManageMenuScreen extends StatelessWidget {
  const ManageMenuScreen({super.key, required this.businessId});
  final String businessId;
  @override
  Widget build(BuildContext context) => CatalogScreen(
    businessId: businessId, repository: CatalogScope.of(context),
  );
}
