import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'product_detail_screen.dart';
import 'package:snackup/theme/app_colors.dart';
import 'package:snackup/theme/app_text.dart';

class MenuScreen extends StatelessWidget {
  final String businessId;
  final String businessName;

  const MenuScreen({
    super.key,
    required this.businessId,
    required this.businessName,
  });

  @override
  Widget build(BuildContext context) {
    final Stream<QuerySnapshot> productsStream = FirebaseFirestore.instance
        .collection('products')
        .where('businessId', isEqualTo: businessId)
        .where('isAvailable', isEqualTo: true)
        .orderBy('category')
        .orderBy('name')
        .snapshots();

    return Scaffold(
      appBar: AppBar(
        title: Text(
          businessName,
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
            return _buildErrorState();
          }
          
          if (snapshot.connectionState == ConnectionState.waiting) {
            return _buildLoadingState();
          }
          
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return _buildEmptyState();
          }

          final docs = snapshot.data!.docs;
          
          return _buildMenuList(docs);
        },
      ),
    );
  }

  Widget _buildMenuList(List<QueryDocumentSnapshot> docs) {
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
                  Icons.restaurant_menu_rounded,
                  color: AppColors.tertiary,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Explora nuestro menú organizado por categorías',
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

        // LISTA DE PRODUCTOS AGRUPADOS POR CATEGORÍA
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              final doc = docs[index];
              final product = doc.data()! as Map<String, dynamic>;
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
                              horizontal: 16,
                              vertical: 8,
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
                                fontSize: 16,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
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
                  _buildProductCard(context, doc),
                ],
              );
            },
            childCount: docs.length,
          ),
        ),

        // ESPACIO FINAL
        const SliverToBoxAdapter(
          child: SizedBox(height: 20),
        ),
      ],
    );
  }

  Widget _buildProductCard(BuildContext context, DocumentSnapshot doc) {
    final product = doc.data()! as Map<String, dynamic>;
    final price = product['price'] ?? 0.0;
    final String imageUrl = product['imageUrl'] ?? '';
    final String description = product['description'] ?? '';
    final int stock = product['stock'] ?? 0;
    final bool isSoldOut = stock <= 0;
    final bool isFeatured = product['isFeatured'] ?? false;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Material(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(16),
        elevation: 1,
        child: InkWell(
          onTap: isSoldOut ? null : () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => ProductDetailScreen(
                  product: product,
                  productId: doc.id,
                ),
              ),
            );
          },
          borderRadius: BorderRadius.circular(16),
          child: Opacity(
            opacity: isSoldOut ? 0.6 : 1.0,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  // IMAGEN DEL PRODUCTO
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: AppColors.componentBase,
                    ),
                    child: Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.network(
                            imageUrl.isNotEmpty ? imageUrl : 'https://via.placeholder.com/100',
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return Container(
                                color: AppColors.componentBase,
                                child: Icon(
                                  Icons.fastfood_rounded,
                                  size: 30,
                                  color: AppColors.textSecondary.withOpacity(0.4),
                                ),
                              );
                            },
                          ),
                        ),
                        if (isFeatured)
                          Positioned(
                            top: 4,
                            left: 4,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.warning,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.star_rounded,
                                    color: Colors.white,
                                    size: 10,
                                  ),
                                  const SizedBox(width: 2),
                                  Text(
                                    'DESTACADO',
                                    style: AppText.notes.copyWith(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 8,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
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
                                product['name'] ?? 'Producto',
                                style: AppText.body.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textPrimary,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (isSoldOut) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: AppColors.error.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  'AGOTADO',
                                  style: AppText.notes.copyWith(
                                    color: AppColors.error,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 10,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        
                        if (description.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            description,
                            style: AppText.notes.copyWith(
                              color: AppColors.textSecondary,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                        
                        const SizedBox(height: 8),
                        
                        Row(
                          children: [
                            // PRECIO
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: isSoldOut 
                                    ? AppColors.textSecondary.withOpacity(0.1)
                                    : AppColors.success.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '\$${price.toStringAsFixed(2)}',
                                style: AppText.body.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: isSoldOut 
                                      ? AppColors.textSecondary
                                      : AppColors.success,
                                ),
                              ),
                            ),
                            
                            const SizedBox(width: 8),
                            
                            // STOCK DISPONIBLE
                            if (!isSoldOut && stock > 0 && stock <= 10) ...[
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: AppColors.warning.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  'Últimos $stock',
                                  style: AppText.notes.copyWith(
                                    color: AppColors.warning,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 10,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  
                  const SizedBox(width: 12),
                  
                  // INDICADOR DE NAVEGACIÓN
                  Icon(
                    Icons.chevron_right_rounded,
                    color: isSoldOut 
                        ? AppColors.textSecondary.withOpacity(0.3)
                        : AppColors.textSecondary.withOpacity(0.5),
                    size: 24,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildErrorState() {
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
              'Error al cargar el menú',
              style: AppText.h3.copyWith(
                color: AppColors.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Verifica tu conexión e intenta nuevamente',
              style: AppText.body.copyWith(
                color: AppColors.textSecondary,
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
          CircularProgressIndicator(color: AppColors.primary),
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

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
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
              'Menú no disponible',
              style: AppText.h3.copyWith(
                color: AppColors.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              'Este negocio no tiene productos disponibles en este momento',
              style: AppText.body.copyWith(
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}