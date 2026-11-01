import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:snackup/student/student_api.dart';
import 'package:snackup/student/student_widgets.dart';
import 'package:snackup/theme/student_colors.dart';
import 'package:snackup/theme/student_text.dart';

import 'product_detail_screen.dart';

class MenuScreen extends StatefulWidget {
  final String businessId;
  final String businessName;

  const MenuScreen({
    super.key,
    required this.businessId,
    required this.businessName,
  });

  @override
  State<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends State<MenuScreen> {
  StudentApi? _api;
  Future<List<dynamic>>? _data;
  int _revision = -1;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final api = context.watch<StudentApi>();
    if (_api != api || _revision != api.revision) {
      _api = api;
      _revision = api.revision;
      _data = _fetch();
    }
  }

  Future<List<dynamic>> _fetch() => Future.wait<dynamic>([
    _api!.getObject('/businesses/${Uri.encodeComponent(widget.businessId)}'),
    _api!.getAll(
      '/businesses/${Uri.encodeComponent(widget.businessId)}/products',
      query: {'isAvailable': 'true'},
    ),
  ]);

  Future<void> _reload() async {
    final future = _fetch();
    setState(() {
      _data = future;
    });
    // The FutureBuilder presents request failures, including pull-to-refresh.
    await future.then<void>((_) {}, onError: (Object _, StackTrace __) {});
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.background,
    appBar: AppBar(title: Text(widget.businessName, style: AppText.h3)),
    body: FutureBuilder<List<dynamic>>(
      future: _data,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return ErrorPanel(error: snapshot.error!, onRetry: _reload);
        }
        final business = snapshot.data![0] as Map<String, dynamic>;
        final published = snapshot.data![1] as List<Map<String, dynamic>>;
        final products = published.where((product) {
          final stock = product['stock'];
          return product['isAvailable'] == true &&
              (stock == null || stock is num && stock > 0);
        }).toList();
        final open = business['isOpen'] == true && business['isActive'] == true;
        final categories = <String, List<Map<String, dynamic>>>{};
        for (final product in products) {
          final category = (product['category'] as String?)?.trim();
          categories
              .putIfAbsent(
                category == null || category.isEmpty ? 'Menú' : category,
                () => [],
              )
              .add(product);
        }
        return RefreshIndicator(
          onRefresh: _reload,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 900),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: .08),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.storefront_rounded,
                              color: open
                                  ? AppColors.primary
                                  : AppColors.textSecondary,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                open
                                    ? 'Elige tus favoritos y personaliza tu pedido.'
                                    : 'Este local está cerrado. Puedes explorar su menú.',
                                style: AppText.body,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (products.isEmpty)
                        const CatalogEmpty(
                          icon: Icons.restaurant_menu_rounded,
                          title: 'Sin platillos disponibles por ahora',
                          message:
                              'Vuelve más tarde para consultar las opciones de este local.',
                        ),
                      for (final entry in categories.entries) ...[
                        Padding(
                          padding: const EdgeInsets.only(top: 24, bottom: 12),
                          child: Text(entry.key, style: AppText.h3),
                        ),
                        for (final product in entry.value)
                          CatalogProductCard(
                            product: product,
                            businessOpen: open,
                          ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    ),
  );
}

/// Shared catalogue card. Only the current server ID is passed to detail.
class CatalogProductCard extends StatelessWidget {
  final Map<String, dynamic> product;
  final bool businessOpen;
  const CatalogProductCard({
    super.key,
    required this.product,
    this.businessOpen = true,
  });

  @override
  Widget build(BuildContext context) {
    final available = product['isAvailable'] == true && businessOpen;
    final stock = product['stock'];
    final id = product['id'] as String?;
    return Card(
      color: AppColors.componentBase,
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: AppColors.borders),
      ),
      elevation: 0,
      child: InkWell(
        onTap: id == null
            ? null
            : () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ProductDetailScreen(productId: id),
                ),
              ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: StudentImage(
                  url: product['imageUrl'],
                  width: 84,
                  height: 84,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product['name']?.toString() ?? 'Producto',
                      style: AppText.h3.copyWith(fontSize: 18),
                    ),
                    if ((product['description']?.toString() ?? '')
                        .isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        product['description'].toString(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.notes,
                      ),
                    ],
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 12,
                      runSpacing: 4,
                      children: [
                        Text(
                          money(product['price']),
                          style: AppText.body.copyWith(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (!available || (stock is num && stock <= 0))
                          Text(
                            !businessOpen ? 'Local cerrado' : 'No disponible',
                            style: AppText.notes.copyWith(
                              color: AppColors.error,
                            ),
                          ),
                        if (product['isFeatured'] == true)
                          const Icon(
                            Icons.star_rounded,
                            color: AppColors.accent,
                            size: 18,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const CircleAvatar(
                radius: 18,
                backgroundColor: AppColors.accent,
                child: Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class CatalogEmpty extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  const CatalogEmpty({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 52, color: AppColors.primary.withValues(alpha: .6)),
        const SizedBox(height: 16),
        Text(title, textAlign: TextAlign.center, style: AppText.h3),
        const SizedBox(height: 8),
        Text(message, textAlign: TextAlign.center, style: AppText.notes),
      ],
    ),
  );
}
