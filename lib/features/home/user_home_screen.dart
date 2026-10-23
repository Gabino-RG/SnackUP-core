import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../theme/app_colors.dart';
import '../user/menu_screen.dart';
import '../user/search_screen.dart';
import '../user/product_detail_screen.dart';

class UserHomeScreen extends StatefulWidget {
  final FirebaseFirestore? firestore;
  const UserHomeScreen({super.key, this.firestore});
  @override
  State<UserHomeScreen> createState() => _UserHomeScreenState();
}

class _UserHomeScreenState extends State<UserHomeScreen> {
  String _category = 'Todo';
  FirebaseFirestore get _db => widget.firestore ?? FirebaseFirestore.instance;
  late final _products = _db
      .collection('products')
      .where('isAvailable', isEqualTo: true)
      .snapshots();
  late final _businesses = _db
      .collection('businesses')
      .where('isOpen', isEqualTo: true)
      .snapshots();
  late final _promotions = _db
      .collection('products')
      .where('isFeatured', isEqualTo: true)
      .where('isAvailable', isEqualTo: true)
      .limit(5)
      .snapshots();
  void _open(Widget screen) =>
      Navigator.push(context, MaterialPageRoute<void>(builder: (_) => screen));
  Widget _photo(String url, {double width = 96, double height = 96}) =>
      ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: url.isEmpty
            ? Container(
                width: width,
                height: height,
                color: AppColors.background,
                child: const Icon(
                  Icons.restaurant_rounded,
                  color: AppColors.tertiary,
                  size: 32,
                ),
              )
            : Image.network(
                url,
                width: width,
                height: height,
                fit: BoxFit.cover,
                errorBuilder: (_, error, stack) => Container(
                  width: width,
                  height: height,
                  color: AppColors.background,
                  child: const Icon(
                    Icons.restaurant_rounded,
                    color: AppColors.tertiary,
                  ),
                ),
              ),
      );
  Widget _title(String text) => Padding(
    padding: const EdgeInsets.only(top: 24, bottom: 12),
    child: Text(text, style: Theme.of(context).textTheme.titleLarge),
  );
  Widget _notice(String text) =>
      Padding(padding: const EdgeInsets.all(20), child: Text(text));

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: () => _open(const SearchScreen()),
              child: Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.search_rounded),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '¿Qué se te antoja hoy en el campus?',
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                    ),
                    Icon(Icons.tune_rounded, color: AppColors.tertiary),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Row(
              children: [
                Icon(Icons.circle, size: 9, color: Color(0xFFAEC500)),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Encuentra tu próxima comida favorita',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            StreamBuilder<QuerySnapshot>(
              stream: _promotions,
              builder: (context, snapshot) {
                if (snapshot.hasError)
                  return _notice('No se pudieron cargar las promociones.');
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty)
                  return const SizedBox.shrink();
                return Column(
                  children: snapshot.data!.docs.take(3).map((doc) {
                    final promo = doc.data() as Map<String, dynamic>;
                    return Container(
                      margin: const EdgeInsets.only(top: 20),
                      padding: const EdgeInsets.all(22),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'PROMO ESTUDIANTIL',
                            style: TextStyle(
                              color: AppColors.tertiary,
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      promo['name'] ?? 'Promoción',
                                      style: Theme.of(
                                        context,
                                      ).textTheme.titleLarge,
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      promo['description'] ?? '',
                                      maxLines: 3,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      '\$${((promo['price'] as num?) ?? 0).toStringAsFixed(2)} MXN',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 20,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 16),
                              _photo(promo['imageUrl'] ?? ''),
                            ],
                          ),
                          const SizedBox(height: 20),
                          FilledButton(
                            onPressed: () {
                              final businessId = promo['businessId'];
                              if (businessId is String &&
                                  businessId.isNotEmpty) {
                                _open(
                                  MenuScreen(
                                    businessId: businessId,
                                    businessName: 'Menú de la cafetería',
                                  ),
                                );
                              } else {
                                _open(const SearchScreen());
                              }
                            },
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.accent,
                              foregroundColor: AppColors.primary,
                              minimumSize: const Size(double.infinity, 48),
                            ),
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Expanded(
                                  child: Text(
                                    'Ver menú de la promoción',
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                                SizedBox(width: 8),
                                Icon(Icons.arrow_forward_rounded),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                );
              },
            ),
            _title('Menú del campus'),
            StreamBuilder<QuerySnapshot>(
              stream: _products,
              builder: (context, snapshot) {
                if (snapshot.hasError)
                  return _notice(
                    'No se pudo cargar el menú. Intenta más tarde.',
                  );
                if (!snapshot.hasData)
                  return const Center(child: CircularProgressIndicator());
                final all = snapshot.data!.docs;
                final categories = <String>{
                  'Todo',
                  ...all.map(
                    (doc) =>
                        (doc.data() as Map<String, dynamic>)['category']
                            as String? ??
                        'Otros',
                  ),
                };
                final docs = all
                    .where(
                      (doc) =>
                          _category == 'Todo' ||
                          (doc.data() as Map<String, dynamic>)['category'] ==
                              _category,
                    )
                    .toList();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: categories
                            .map(
                              (category) => Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: ChoiceChip(
                                  label: Text(category),
                                  selected: _category == category,
                                  selectedColor: AppColors.tertiary.withOpacity(
                                    .18,
                                  ),
                                  onSelected: (_) =>
                                      setState(() => _category = category),
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (docs.isEmpty)
                      _notice(
                        'Todavía no hay platillos disponibles en esta categoría.',
                      ),
                    ...docs.map((doc) {
                      final product = doc.data() as Map<String, dynamic>;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Material(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(22),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(22),
                            onTap: () => _open(
                              ProductDetailScreen(
                                product: product,
                                productId: doc.id,
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Row(
                                children: [
                                  _photo(
                                    product['imageUrl'] ?? '',
                                    width: 78,
                                    height: 88,
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          product['category'] ??
                                              'Recién preparado',
                                          style: const TextStyle(
                                            color: AppColors.tertiary,
                                            fontSize: 11,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          product['name'] ?? 'Platillo',
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        Text(
                                          product['description'] ?? '',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: AppColors.textSecondary,
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          '\$${((product['price'] as num?) ?? 0).toStringAsFixed(2)} MXN',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: const BoxDecoration(
                                      color: AppColors.accent,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.add_rounded,
                                      size: 24,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ],
                );
              },
            ),
            _title('Cafeterías abiertas'),
            StreamBuilder<QuerySnapshot>(
              stream: _businesses,
              builder: (context, snapshot) {
                if (snapshot.hasError)
                  return _notice('No se pudieron cargar las cafeterías.');
                if (!snapshot.hasData)
                  return const Center(child: CircularProgressIndicator());
                if (snapshot.data!.docs.isEmpty)
                  return _notice('No hay cafeterías abiertas por ahora.');
                return Column(
                  children: snapshot.data!.docs.map((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ListTile(
                        leading: const Icon(
                          Icons.storefront_rounded,
                          color: AppColors.tertiary,
                        ),
                        title: Text(data['name'] ?? 'Cafetería'),
                        subtitle: Text(data['category'] ?? 'Menú del campus'),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => _open(
                          MenuScreen(
                            businessId: doc.id,
                            businessName: data['name'] ?? 'Cafetería',
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                );
              },
            ),
          ],
        ),
      ),
    ),
  );
}
