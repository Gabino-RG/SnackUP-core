import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'product_detail_screen.dart';
import 'package:snackup/theme/app_colors.dart';
import 'package:snackup/theme/app_text.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _searchController = TextEditingController();
  List<DocumentSnapshot> _results = [];
  bool _isLoading = false;
  bool _hasSearched = false;
  Timer? _debounceTimer;

  // BÚSQUEDA CON DEBOUNCE MEJORADA
  void _performSearch() {
    if (_debounceTimer?.isActive ?? false) {
      _debounceTimer?.cancel();
    }

    _debounceTimer = Timer(const Duration(milliseconds: 500), () async {
      final String query = _searchController.text.trim().toLowerCase();
      if (query.isEmpty) {
        setState(() {
          _results = [];
          _hasSearched = false;
        });
        return;
      }

      setState(() {
        _isLoading = true;
        _hasSearched = true;
      });

      try {
        final snapshot = await FirebaseFirestore.instance
            .collection('products')
            .where('isAvailable', isEqualTo: true)
            .where('name_searchable', isGreaterThanOrEqualTo: query)
            .where('name_searchable', isLessThanOrEqualTo: '$query\uf8ff')
            .limit(20)
            .get();
        
        setState(() {
          _results = snapshot.docs;
        });
        
      } catch (e) {
        print('Error en búsqueda: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Error al realizar la búsqueda'),
              backgroundColor: AppColors.error,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          );
        }
      }

      if (mounted) {
        setState(() => _isLoading = false);
      }
    });
  }

  // BÚSQUEDA EN TIEMPO REAL
  void _onSearchChanged(String value) {
    if (value.length >= 2) {
      _performSearch();
    } else {
      setState(() {
        _results = [];
        _hasSearched = false;
      });
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          // HEADER DE BÚSQUEDA
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.05),
              border: Border(
                bottom: BorderSide(
                  color: AppColors.borders,
                  width: 1,
                ),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.search_rounded,
                  color: AppColors.primary,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Encuentra tus productos favoritos',
                    style: AppText.body.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // BARRA DE BÚSQUEDA MEJORADA
          Container(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              style: AppText.body,
              decoration: InputDecoration(
                labelText: 'Buscar productos...',
                hintText: 'Ej: Taco, Hamburguesa, Café...',
                hintStyle: AppText.notes.copyWith(
                  color: AppColors.textSecondary.withOpacity(0.6),
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: AppColors.componentBase,
                prefixIcon: Icon(
                  Icons.search_rounded,
                  color: AppColors.textSecondary.withOpacity(0.8),
                ),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: Icon(
                          Icons.clear_rounded,
                          color: AppColors.textSecondary.withOpacity(0.6),
                        ),
                        onPressed: () {
                          _searchController.clear();
                          setState(() {
                            _results = [];
                            _hasSearched = false;
                          });
                        },
                      )
                    : null,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 16,
                ),
              ),
            ),
          ),

          // INDICADOR DE BÚSQUEDA
          if (_isLoading) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Buscando...',
                    style: AppText.notes.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],

          // RESULTADOS
          Expanded(
            child: _buildResultsContent(),
          ),
        ],
      ),
    );
  }

  Widget _buildResultsContent() {
    if (_isLoading) {
      return _buildLoadingState();
    }

    if (!_hasSearched) {
      return _buildInitialState();
    }

    if (_results.isEmpty) {
      return _buildEmptyState();
    }

    return _buildResultsList();
  }

  Widget _buildInitialState() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              color: AppColors.componentBase,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.search_rounded,
              size: 50,
              color: AppColors.textSecondary.withOpacity(0.4),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Busca tus productos favoritos',
            style: AppText.h3.copyWith(
              color: AppColors.textPrimary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(
            'Escribe al menos 2 letras para comenzar a buscar\n\nEjemplos: "taco", "pizza", "café", "refresco"',
            style: AppText.body.copyWith(
              color: AppColors.textSecondary,
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
        ],
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
            'Buscando productos...',
            style: AppText.body.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: AppColors.componentBase,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.search_off_rounded,
              size: 40,
              color: AppColors.textSecondary.withOpacity(0.4),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'No se encontraron resultados',
            style: AppText.h3.copyWith(
              color: AppColors.textPrimary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(
            'No hay productos que coincidan con "${_searchController.text}"\n\nIntenta con otras palabras o verifica la ortografía',
            style: AppText.body.copyWith(
              color: AppColors.textSecondary,
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () {
              _searchController.clear();
              setState(() {
                _results = [];
                _hasSearched = false;
              });
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
            child: Text(
              'Limpiar Búsqueda',
              style: AppText.body.copyWith(
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultsList() {
    return Column(
      children: [
        // HEADER DE RESULTADOS
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.componentBase,
            border: Border(
              bottom: BorderSide(color: AppColors.borders),
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.checklist_rounded,
                color: AppColors.primary,
                size: 16,
              ),
              const SizedBox(width: 8),
              Text(
                '${_results.length} producto${_results.length == 1 ? '' : 's'} encontrado${_results.length == 1 ? '' : 's'}',
                style: AppText.notes.copyWith(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),

        // LISTA DE RESULTADOS
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            separatorBuilder: (context, index) => const SizedBox(height: 12),
            itemCount: _results.length,
            itemBuilder: (context, index) {
              return _buildProductCard(_results[index]);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildProductCard(DocumentSnapshot doc) {
    final product = doc.data()! as Map<String, dynamic>;
    final price = product['price'] ?? 0.0;
    final String imageUrl = product['imageUrl'] ?? '';
    final String description = product['description'] ?? '';
    final int stock = product['stock'] ?? 0;
    final bool isSoldOut = stock <= 0;
    final bool isFeatured = product['isFeatured'] ?? false;

    return Material(
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
                  width: 70,
                  height: 70,
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
                                size: 24,
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
                            child: Icon(
                              Icons.star_rounded,
                              color: Colors.white,
                              size: 10,
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
                          
                          const Spacer(),
                          
                          // INDICADOR DE NAVEGACIÓN
                          Icon(
                            Icons.chevron_right_rounded,
                            color: isSoldOut 
                                ? AppColors.textSecondary.withOpacity(0.3)
                                : AppColors.textSecondary.withOpacity(0.5),
                            size: 20,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}