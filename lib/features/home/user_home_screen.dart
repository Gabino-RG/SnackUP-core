import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:snackup/student/student_api.dart';
import 'package:snackup/student/student_widgets.dart';
import 'package:snackup/theme/student_colors.dart';
import 'package:snackup/theme/student_text.dart';

import '../user/menu_screen.dart';
import '../user/product_detail_screen.dart';
import '../user/search_screen.dart';

class UserHomeScreen extends StatefulWidget {
  const UserHomeScreen({super.key});

  @override
  State<UserHomeScreen> createState() => _UserHomeScreenState();
}

class _UserHomeScreenState extends State<UserHomeScreen> {
  StudentApi? _api;
  int _revision = -1;
  Future<List<Map<String, dynamic>>>? _featured;
  Future<List<Map<String, dynamic>>>? _businesses;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final api = context.watch<StudentApi>();
    if (_api != api || _revision != api.revision) {
      _api = api;
      _revision = api.revision;
      _load();
    }
  }

  void _load() {
    _featured = _api!.getAll('/products/featured');
    _businesses = _api!.getAll('/businesses');
  }

  Future<void> _reload() async {
    setState(_load);
    await Future.wait([
      _featured!,
      _businesses!,
    ]).then<void>((_) {}, onError: (Object _, StackTrace __) {});
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<StudentApi>().user;
    final name = user?['displayName']?.toString().trim();
    return Scaffold(
      backgroundColor: AppColors.background,
      body: RefreshIndicator(
        onRefresh: _reload,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 28),
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.primary.withValues(alpha: .1),
                    AppColors.accent.withValues(alpha: .05),
                  ],
                ),
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(30),
                ),
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1040),
                  child: Row(
                    children: [
                      Container(
                        width: 50,
                        height: 50,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: [AppColors.primary, AppColors.accent],
                          ),
                        ),
                        child: const Icon(
                          Icons.school_rounded,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '¡Hola, ${name == null || name.isEmpty ? 'Estudiante' : name}!',
                              style: AppText.h1.copyWith(fontSize: 24),
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              '¿Qué vas a ordenar hoy?',
                              style: AppText.body,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1080),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 24),
                      Semantics(
                        button: true,
                        label: 'Buscar comida',
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute<void>(
                              builder: (_) => Scaffold(
                                appBar: AppBar(
                                  title: const Text('Buscar comida'),
                                ),
                                body: const SearchScreen(),
                              ),
                            ),
                          ),
                          child: Container(
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: AppColors.borders),
                            ),
                            child: const Row(
                              children: [
                                Icon(Icons.search, color: AppColors.primary),
                                SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    '¿Qué se te antoja hoy?',
                                    style: AppText.notes,
                                  ),
                                ),
                                Icon(Icons.tune, color: AppColors.tertiary),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      _heading(
                        'Destacados',
                        Icons.local_offer_rounded,
                        AppColors.accent,
                      ),
                      const SizedBox(height: 14),
                      FutureBuilder<List<Map<String, dynamic>>>(
                        future: _featured,
                        builder: (context, snapshot) {
                          if (snapshot.connectionState !=
                              ConnectionState.done) {
                            return const SizedBox(
                              height: 200,
                              child: Center(child: CircularProgressIndicator()),
                            );
                          }
                          if (snapshot.hasError) {
                            return ErrorPanel(
                              error: snapshot.error!,
                              onRetry: _reload,
                            );
                          }
                          final products = snapshot.data!;
                          if (products.isEmpty) {
                            return const CatalogEmpty(
                              icon: Icons.local_offer_outlined,
                              title: 'Pronto habrá más destacados',
                              message:
                                  'Mientras tanto, explora los menús de tus cafeterías.',
                            );
                          }
                          return SizedBox(
                            height: 230,
                            child: LayoutBuilder(
                              builder: (context, constraints) =>
                                  ListView.separated(
                                    scrollDirection: Axis.horizontal,
                                    itemCount: products.length,
                                    separatorBuilder: (_, _) =>
                                        const SizedBox(width: 14),
                                    itemBuilder: (context, index) => SizedBox(
                                      width: constraints.maxWidth < 380
                                          ? constraints.maxWidth
                                          : 340,
                                      child: _featuredCard(products[index]),
                                    ),
                                  ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 28),
                      _heading(
                        'Tus cafeterías',
                        Icons.storefront_rounded,
                        AppColors.primary,
                      ),
                      const SizedBox(height: 14),
                      FutureBuilder<List<Map<String, dynamic>>>(
                        future: _businesses,
                        builder: (context, snapshot) {
                          if (snapshot.connectionState !=
                              ConnectionState.done) {
                            return const SizedBox(
                              height: 150,
                              child: Center(child: CircularProgressIndicator()),
                            );
                          }
                          if (snapshot.hasError) {
                            return ErrorPanel(
                              error: snapshot.error!,
                              onRetry: _reload,
                            );
                          }
                          final businesses = [...snapshot.data!];
                          businesses.sort(
                            (a, b) => (b['isOpen'] == true ? 1 : 0).compareTo(
                              a['isOpen'] == true ? 1 : 0,
                            ),
                          );
                          if (businesses.isEmpty) {
                            return const CatalogEmpty(
                              icon: Icons.storefront_outlined,
                              title: 'Aún no hay cafeterías',
                              message:
                                  'Los locales publicados aparecerán aquí.',
                            );
                          }
                          return Column(
                            children: businesses.map(_businessCard).toList(),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _heading(String title, IconData icon, Color color) => Row(
    children: [
      Icon(icon, color: color, size: 22),
      const SizedBox(width: 10),
      Expanded(child: Text(title, style: AppText.h3)),
    ],
  );

  Widget _featuredCard(Map<String, dynamic> product) => Card(
    margin: EdgeInsets.zero,
    clipBehavior: Clip.antiAlias,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    child: InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) =>
              ProductDetailScreen(productId: product['id'] as String),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                StudentImage(url: product['imageUrl']),
                Positioned(
                  top: 10,
                  left: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.paleBlue,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'DESTACADO',
                      style: TextStyle(
                        color: AppColors.primary,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  product['name']?.toString() ?? 'Producto',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.h3.copyWith(fontSize: 18),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${money(product['price'])} MXN',
                        style: AppText.body.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const CircleAvatar(
                      radius: 17,
                      backgroundColor: AppColors.accent,
                      child: Icon(
                        Icons.add,
                        color: AppColors.primary,
                        size: 20,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  Widget _businessCard(Map<String, dynamic> business) {
    final open = business['isOpen'] == true;
    final name = business['name']?.toString() ?? 'Cafetería';
    final rating = business['averageRating'];
    return Card(
      color: AppColors.componentBase,
      margin: const EdgeInsets.only(bottom: 14),
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: AppColors.borders),
      ),
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => MenuScreen(
              businessId: business['id'] as String,
              businessName: name,
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: StudentImage(
                  url: business['imageUrl'],
                  width: 76,
                  height: 76,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: AppText.h3),
                    const SizedBox(height: 4),
                    Text(
                      business['category']?.toString() ?? '',
                      style: AppText.notes,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 12,
                      runSpacing: 4,
                      children: [
                        Text(
                          open ? 'Abierto' : 'Cerrado',
                          style: AppText.notes.copyWith(
                            color: open
                                ? AppColors.success
                                : AppColors.textSecondary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if ((business['totalRatings'] as num? ?? 0) > 0)
                          Text(
                            '★ ${(rating as num).toStringAsFixed(1)}',
                            style: AppText.notes,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppColors.primary),
            ],
          ),
        ),
      ),
    );
  }
}
