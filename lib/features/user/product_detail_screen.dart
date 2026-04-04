import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:snackup/theme/app_colors.dart';
import 'package:snackup/theme/app_text.dart';

class ProductDetailScreen extends StatefulWidget {
  final Map<String, dynamic> product;
  final String productId;

  const ProductDetailScreen({
    super.key,
    required this.product,
    required this.productId,
  });

  @override
  State<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen> {
  int _quantity = 1;
  final _notesController = TextEditingController();
  bool _isLoading = false;
  bool _isFavorite = false;
  late DocumentReference _favoriteRef;

  @override
  void initState() {
    super.initState();
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId != null) {
      _favoriteRef = FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('favorites')
          .doc(widget.productId);
    }
  }

  Future<void> _toggleFavorite() async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return;

    setState(() => _isLoading = true);

    try {
      if (_isFavorite) {
        await _favoriteRef.delete();
        _showSuccess('Quitado de Favoritos');
      } else {
        final favoriteData = {
          'productId': widget.productId,
          'businessId': widget.product['businessId'],
          'name': widget.product['name'],
          'price': widget.product['price'],
          'imageUrl': widget.product['imageUrl'] ?? '',
          'notes': _notesController.text.trim(),
          'addedAt': FieldValue.serverTimestamp(),
        };
        await _favoriteRef.set(favoriteData);
        _showSuccess('Añadido a Favoritos');
      }
    } catch (e) {
      _showError('Error al guardar favorito: ${e.toString()}');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _increment() {
    setState(() => _quantity++);
  }

  void _decrement() {
    if (_quantity > 1) {
      setState(() => _quantity--);
    }
  }

  Future<void> _addToCart() async {
    setState(() => _isLoading = true);
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) {
      _showError('Error: Usuario no encontrado.');
      setState(() => _isLoading = false);
      return;
    }
    
    try {
      final cartRef = FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('cart')
          .doc(widget.productId);
      
      final cartItem = {
        'productId': widget.productId,
        'businessId': widget.product['businessId'],
        'name': widget.product['name'],
        'price': widget.product['price'],
        'imageUrl': widget.product['imageUrl'] ?? '',
        'quantity': _quantity,
        'notes': _notesController.text.trim(),
        'addedAt': FieldValue.serverTimestamp(),
      };
      
      await cartRef.set(cartItem);
      if (mounted) {
        _showSuccess('¡Añadido al carrito!');
        Navigator.of(context).pop();
      }
    } catch (e) {
      _showError('Error al añadir: ${e.toString()}');
    }
    
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  void _showSuccess(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.success,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final price = widget.product['price'] ?? 0.0;
    final String imageUrl = widget.product['imageUrl'] ?? '';
    final String description = widget.product['description'] ?? '';
    final double totalPrice = price * _quantity;
    final int stock = widget.product['stock'] ?? 0;
    final bool isSoldOut = stock <= 0;
    final bool isFeatured = widget.product['isFeatured'] ?? false;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.product['name'] ?? 'Detalle',
          style: AppText.h3.copyWith(
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        backgroundColor: AppColors.background,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
        actions: [
          // BOTÓN DE FAVORITOS MEJORADO
          StreamBuilder<DocumentSnapshot>(
            stream: _favoriteRef.snapshots(),
            builder: (context, snapshot) {
              _isFavorite = snapshot.hasData && snapshot.data!.exists;
              return IconButton(
                icon: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _isFavorite 
                        ? AppColors.error.withOpacity(0.1)
                        : AppColors.componentBase,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                    color: _isFavorite ? AppColors.error : AppColors.textSecondary,
                    size: 20,
                  ),
                ),
                onPressed: _isLoading ? null : _toggleFavorite,
                tooltip: _isFavorite ? 'Quitar de Favoritos' : 'Añadir a Favoritos',
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // IMAGEN PRINCIPAL
                  Stack(
                    children: [
                      Container(
                        height: 280,
                        width: double.infinity,
                        color: AppColors.componentBase,
                        child: Image.network(
                          imageUrl.isNotEmpty ? imageUrl : 'https://via.placeholder.com/400x280',
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return Container(
                              color: AppColors.componentBase,
                              child: Icon(
                                Icons.fastfood_rounded,
                                size: 80,
                                color: AppColors.textSecondary.withOpacity(0.4),
                              ),
                            );
                          },
                        ),
                      ),
                      // BADGES SUPERPUESTOS
                      Positioned(
                        top: 16,
                        left: 16,
                        child: Row(
                          children: [
                            if (isFeatured)
                              _buildBadge(
                                'DESTACADO',
                                AppColors.warning,
                                Icons.star_rounded,
                              ),
                            if (isSoldOut)
                              _buildBadge(
                                'AGOTADO',
                                AppColors.error,
                                Icons.cancel_rounded,
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  // INFORMACIÓN DEL PRODUCTO
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // NOMBRE Y PRECIO
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    widget.product['name'] ?? 'Producto',
                                    style: AppText.h1.copyWith(
                                      fontSize: 28,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 8,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppColors.success.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      '\$${price.toStringAsFixed(2)}',
                                      style: AppText.h3.copyWith(
                                        color: AppColors.success,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 20),

                        // DESCRIPCIÓN
                        if (description.isNotEmpty) ...[
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Descripción',
                                style: AppText.h3.copyWith(
                                  color: AppColors.textPrimary,
                                  fontSize: 18,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                description,
                                style: AppText.body.copyWith(
                                  color: AppColors.textSecondary,
                                  height: 1.5,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),
                        ],

                        // NOTAS ESPECIALES
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Notas Especiales',
                              style: AppText.h3.copyWith(
                                color: AppColors.textPrimary,
                                fontSize: 18,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Añade instrucciones especiales para tu pedido',
                              style: AppText.notes.copyWith(
                                color: AppColors.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _notesController,
                              style: AppText.body,
                              decoration: InputDecoration(
                                hintText: 'Ej. Sin cebolla, sin cilantro, extra salsa...',
                                hintStyle: AppText.notes.copyWith(
                                  color: AppColors.textSecondary.withOpacity(0.6),
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide.none,
                                ),
                                filled: true,
                                fillColor: AppColors.componentBase,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 14,
                                ),
                              ),
                              maxLines: 3,
                            ),
                          ],
                        ),

                        const SizedBox(height: 32),

                        // SELECTOR DE CANTIDAD
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Cantidad',
                              style: AppText.h3.copyWith(
                                color: AppColors.textPrimary,
                                fontSize: 18,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: AppColors.componentBase,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  // BOTÓN DISMINUIR
                                  IconButton.filled(
                                    onPressed: _decrement,
                                    style: IconButton.styleFrom(
                                      backgroundColor: AppColors.primary,
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                    icon: const Icon(Icons.remove_rounded),
                                  ),
                                  
                                  const SizedBox(width: 24),
                                  
                                  // CANTIDAD
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 24,
                                      vertical: 12,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppColors.background,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: AppColors.borders,
                                      ),
                                    ),
                                    child: Text(
                                      '$_quantity',
                                      style: AppText.h1.copyWith(
                                        fontSize: 24,
                                        color: AppColors.textPrimary,
                                      ),
                                    ),
                                  ),
                                  
                                  const SizedBox(width: 24),
                                  
                                  // BOTÓN AUMENTAR
                                  IconButton.filled(
                                    onPressed: _increment,
                                    style: IconButton.styleFrom(
                                      backgroundColor: AppColors.primary,
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                    icon: const Icon(Icons.add_rounded),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 100), // Espacio para el botón fijo
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // BOTÓN FIJO DE AÑADIR AL CARRITO
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.background,
              border: Border(
                top: BorderSide(
                  color: AppColors.borders,
                  width: 1,
                ),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 10,
                  offset: const Offset(0, -5),
                ),
              ],
            ),
            child: SafeArea(
              child: ElevatedButton(
                onPressed: isSoldOut ? null : (_isLoading ? null : _addToCart),
                style: ElevatedButton.styleFrom(
                  backgroundColor: isSoldOut 
                      ? AppColors.textSecondary 
                      : AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 2,
                  shadowColor: AppColors.primary.withOpacity(0.3),
                ),
                child: _isLoading
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          isSoldOut ? Icons.cancel_rounded : Icons.shopping_cart_rounded,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          isSoldOut 
                              ? 'Producto Agotado'
                              : 'Añadir $_quantity al Carrito - \$${totalPrice.toStringAsFixed(2)}',
                          style: AppText.body.copyWith(
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBadge(String text, Color color, IconData icon) {
    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            color: Colors.white,
            size: 12,
          ),
          const SizedBox(width: 4),
          Text(
            text,
            style: AppText.notes.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }
}