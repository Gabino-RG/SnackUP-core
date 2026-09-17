import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'add_edit_product_screen.dart';
import 'package:snackup/theme/app_colors.dart';
import 'package:snackup/theme/app_text.dart';

class ManageMenuScreen extends StatelessWidget {
  final String businessId;
  const ManageMenuScreen({super.key, required this.businessId});

  @override
  Widget build(BuildContext context) {
    final Stream<QuerySnapshot> productsStream = FirebaseFirestore.instance
        .collection('products')
        .where('businessId', isEqualTo: businessId)
        .orderBy('category')
        .orderBy('name')
        .snapshots();

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Mi Menú',
          style: AppText.h3.copyWith(
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        backgroundColor: AppColors.background,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: productsStream,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _buildErrorState('Error al cargar productos');
          }
          
          if (snapshot.connectionState == ConnectionState.waiting) {
            return _buildLoadingState();
          }
          
          if (snapshot.data!.docs.isEmpty) {
            return _buildEmptyState(context);
          }

          final docs = snapshot.data!.docs;
          return _buildProductList(context, docs);
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.of(context).push(MaterialPageRoute(
            builder: (context) => AddEditProductScreen(
              businessId: businessId,
            ),
          ));
        },
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 4,
        child: const Icon(Icons.add_rounded, size: 28),
      ),
    );
  }

  Widget _buildErrorState(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: 64,
              color: AppColors.error.withOpacity(0.7),
            ),
            const SizedBox(height: 16),
            Text(
              message,
              style: AppText.body.copyWith(
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Verifica tu conexión e intenta nuevamente',
              style: AppText.notes.copyWith(
                color: AppColors.textSecondary.withOpacity(0.7),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(
            color: AppColors.primary,
          ),
          const SizedBox(height: 16),
          Text(
            'Cargando menú...',
            style: AppText.body.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              color: AppColors.componentBase,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.restaurant_menu_rounded,
              size: 50,
              color: AppColors.textSecondary.withOpacity(0.5),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Tu menú está vacío',
            style: AppText.h3.copyWith(
              color: AppColors.textPrimary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(
            'Agrega tu primer producto para comenzar a recibir pedidos',
            style: AppText.body.copyWith(
              color: AppColors.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).push(MaterialPageRoute(
                builder: (context) => AddEditProductScreen(
                  businessId: businessId,
                ),
              ));
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.add_rounded, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Agregar Primer Producto',
                  style: AppText.body.copyWith(
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProductList(BuildContext context, List<QueryDocumentSnapshot> docs) {
    return CustomScrollView(
      slivers: [
        // HEADER INFORMATIVO
        SliverToBoxAdapter(
          child: Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.tertiary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: AppColors.tertiary.withOpacity(0.3),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.tips_and_updates_rounded,
                  color: AppColors.tertiary,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Organiza tus productos por categorías para una mejor experiencia',
                    style: AppText.notes.copyWith(
                      color: AppColors.tertiary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        // LISTA DE PRODUCTOS AGRUPADOS
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              final product = docs[index].data()! as Map<String, dynamic>;
              final String category = product['category'] ?? 'SIN CATEGORÍA';
              
              bool isNewCategory = index == 0 || 
                  (docs[index-1].data()! as Map<String, dynamic>)['category'] != category;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ENCABEZADO DE CATEGORÍA
                  if (isNewCategory)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              category,
                              style: AppText.body.copyWith(
                                fontWeight: FontWeight.w700,
                                color: AppColors.primary,
                                fontSize: 14,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Container(
                              height: 2,
                              color: AppColors.borders,
                            ),
                          ),
                        ],
                      ),
                    ),
                  
                  // TARJETA DE PRODUCTO
                  _buildProductCard(context, docs[index]),
                ],
              );
            },
            childCount: docs.length,
          ),
        ),

        // ESPACIO FINAL PARA FAB
        const SliverToBoxAdapter(
          child: SizedBox(height: 80),
        ),
      ],
    );
  }

  Widget _buildProductCard(BuildContext context, DocumentSnapshot doc) {
    final product = doc.data()! as Map<String, dynamic>;
    final price = product['price'] ?? 0.0;
    final bool isAvailable = product['isAvailable'] ?? false;
    final bool isFeatured = product['isFeatured'] ?? false;
    final String imageUrl = product['imageUrl'] ?? '';
    final int stock = product['stock'] ?? 0;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Material(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(16),
        elevation: 1,
        child: InkWell(
          onTap: () {
            Navigator.of(context).push(MaterialPageRoute(
              builder: (context) => AddEditProductScreen(
                businessId: product['businessId'],
                productId: doc.id,
              ),
            ));
          },
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // IMAGEN DEL PRODUCTO
                Container(
                  width: 70,
                  height: 70,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: AppColors.componentBase,
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: imageUrl.isNotEmpty
                        ? Image.network(
                            imageUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) =>
                                _buildImagePlaceholder(),
                          )
                        : _buildImagePlaceholder(),
                  ),
                ),

                const SizedBox(width: 16),

                // INFORMACIÓN DEL PRODUCTO
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              product['name'] ?? 'Sin Nombre',
                              style: AppText.body.copyWith(
                                fontWeight: FontWeight.w600,
                                color: isAvailable
                                    ? AppColors.textPrimary
                                    : AppColors.textSecondary,
                                decoration: !isAvailable
                                    ? TextDecoration.lineThrough
                                    : null,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (isFeatured) ...[
                            const SizedBox(width: 8),
                            Icon(
                              Icons.star_rounded,
                              color: AppColors.warning,
                              size: 16,
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        product['description'] ?? 'Sin descripción',
                        style: AppText.notes.copyWith(
                          color: AppColors.textSecondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          // PRECIO
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.success.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '\$${price.toStringAsFixed(2)}',
                              style: AppText.notes.copyWith(
                                fontWeight: FontWeight.w700,
                                color: AppColors.success,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          // STOCK
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: _getStockColor(stock).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'Stock: $stock',
                              style: AppText.notes.copyWith(
                                fontWeight: FontWeight.w600,
                                color: _getStockColor(stock),
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 12),

                // INDICADOR DE ESTADO Y EDITAR
                Column(
                  children: [
                    // INDICADOR DE DISPONIBILIDAD
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: isAvailable
                            ? AppColors.success
                            : AppColors.error,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: AppColors.textSecondary.withOpacity(0.5),
                      size: 20,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildImagePlaceholder() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.componentBase,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Center(
        child: Icon(
          Icons.fastfood_rounded,
          color: AppColors.textSecondary.withOpacity(0.4),
          size: 30,
        ),
      ),
    );
  }

  Color _getStockColor(int stock) {
    if (stock == 0) return AppColors.error;
    if (stock <= 5) return AppColors.warning;
    return AppColors.success;
  }
}