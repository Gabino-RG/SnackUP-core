import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:snackup/student/student_api.dart';
import 'package:snackup/student/student_widgets.dart';
import 'package:snackup/theme/student_colors.dart';
import 'package:snackup/theme/student_text.dart';

import 'cart_screen.dart';
import 'package:snackup/student/product_reviews.dart';

class ProductDetailScreen extends StatefulWidget {
  final String productId;
  const ProductDetailScreen({super.key, required this.productId});

  @override
  State<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen> {
  final _notes = TextEditingController();
  StudentApi? _api;
  int _revision = -1;
  int _generation = 0;
  int _quantity = 1;
  bool _loading = true;
  bool _busy = false;
  bool _refreshPending = false;
  bool _initialized = false;
  Object? _error;
  Map<String, dynamic>? _product;
  Map<String, dynamic>? _business;
  Map<String, dynamic>? _favorite;
  Map<String, dynamic>? _cart;

  String get _encodedId => Uri.encodeComponent(widget.productId);
  int get _limit {
    final stock = _product?['stock'];
    return stock is num ? stock.toInt().clamp(0, 99) : 99;
  }

  bool get _available =>
      _product?['isAvailable'] == true &&
      _business?['isOpen'] == true &&
      _business?['isActive'] == true &&
      _limit > 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final api = context.watch<StudentApi>();
    if (_api != api || _revision != api.revision) {
      _api = api;
      _revision = api.revision;
      if (_busy) {
        _refreshPending = true;
      } else {
        _load();
      }
    }
  }

  Map<String, dynamic>? _saved(List<Map<String, dynamic>> rows, String id) {
    for (final row in rows) {
      if (row['productId'] == id) return row;
    }
    return null;
  }

  Future<void> _load() async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final product = await _api!.getObject('/products/$_encodedId');
      final result = await Future.wait<dynamic>([
        _api!.getObject(
          '/businesses/${Uri.encodeComponent(product['businessId'] as String)}',
        ),
        _api!.getAll('/users/me/favorites'),
        _api!.getAll('/users/me/cart/items'),
      ]);
      if (!mounted || generation != _generation) return;
      setState(() {
        _product = product;
        _business = result[0] as Map<String, dynamic>;
        _favorite = _saved(
          result[1] as List<Map<String, dynamic>>,
          widget.productId,
        );
        _cart = _saved(
          result[2] as List<Map<String, dynamic>>,
          widget.productId,
        );
        if (!_initialized) {
          _notes.text = (_cart?['notes'] ?? _favorite?['notes'] ?? '')
              .toString();
          _quantity = (_cart?['quantity'] as num?)?.toInt() ?? 1;
          _initialized = true;
        }
        _loading = false;
      });
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  void _message(String text, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: error ? AppColors.error : AppColors.success,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _finishMutation() {
    if (!mounted) return;
    setState(() => _busy = false);
    if (_refreshPending) {
      _refreshPending = false;
      _load();
    }
  }

  Future<void> _favoriteAction({bool updateNotes = false}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (_favorite != null && !updateNotes) {
        await _api!.request('DELETE', '/users/me/favorites/$_encodedId');
        if (!mounted) return;
        setState(() => _favorite = null);
        _message('Quitado de tus favoritos');
      } else {
        final value = await _api!.request(
          'PUT',
          '/users/me/favorites/$_encodedId',
          body: {'notes': _notes.text.trim()},
        );
        if (!mounted) return;
        setState(() => _favorite = Map<String, dynamic>.from(value as Map));
        _message(
          updateNotes
              ? 'Notas de favorito guardadas'
              : 'Guardado en tus favoritos',
        );
      }
    } catch (error) {
      _message(friendlyError(error), error: true);
    } finally {
      _finishMutation();
    }
  }

  Future<void> _saveCart() async {
    if (_busy || !_available || _quantity > _limit) return;
    setState(() => _busy = true);
    try {
      // Re-read price, availability, local and saved cart before overwriting.
      final current = await _api!.getObject('/products/$_encodedId');
      final values = await Future.wait<dynamic>([
        _api!.getObject(
          '/businesses/${Uri.encodeComponent(current['businessId'] as String)}',
        ),
        _api!.getAll('/users/me/cart/items'),
      ]);
      if (!mounted) return;
      final oldPrice = _product?['price'];
      setState(() {
        _product = current;
        _business = values[0] as Map<String, dynamic>;
      });
      if (!_available || _quantity > _limit) {
        _message(
          'La disponibilidad cambió. Revisa el producto y la cantidad.',
          error: true,
        );
        return;
      }
      if (oldPrice != current['price']) {
        _message(
          'El precio cambió. Revisa el total y vuelve a guardar.',
          error: true,
        );
        return;
      }
      final existing = _saved(
        values[1] as List<Map<String, dynamic>>,
        current['id'] as String,
      );
      if (existing != null) {
        final replace = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Actualizar producto en el carrito'),
            content: Text(
              'Ya tienes ${existing['quantity']} de este producto. Guardar sustituirá esa cantidad por $_quantity y actualizará sus notas.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Volver'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Guardar cambios'),
              ),
            ],
          ),
        );
        if (replace != true || !mounted) return;
      }
      final value = await _api!.request(
        'POST',
        '/users/me/cart/items',
        body: {
          'productId': current['id'],
          'quantity': _quantity,
          'notes': _notes.text.trim(),
        },
      );
      if (!mounted) return;
      setState(() => _cart = Map<String, dynamic>.from(value as Map));
      _message(
        existing == null ? '¡Añadido al carrito!' : 'Carrito actualizado',
      );
    } catch (error) {
      _message(friendlyError(error), error: true);
    } finally {
      _finishMutation();
    }
  }

  @override
  void dispose() {
    _generation++;
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.background,
    appBar: AppBar(
      title: Text(
        _product?['name']?.toString() ?? 'Detalle del producto',
        style: AppText.h3,
      ),
      actions: [
        if (!_loading && _error == null)
          IconButton(
            tooltip: _favorite == null ? 'Guardar favorito' : 'Quitar favorito',
            onPressed: _busy ? null : _favoriteAction,
            icon: Icon(
              _favorite == null
                  ? Icons.favorite_border_rounded
                  : Icons.favorite_rounded,
              color: _favorite == null
                  ? AppColors.textSecondary
                  : AppColors.error,
            ),
          ),
        IconButton(
          tooltip: 'Ver carrito',
          onPressed: _busy
              ? null
              : () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const CartScreen()),
                ),
          icon: const Icon(Icons.shopping_cart_outlined),
        ),
      ],
    ),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : _error != null
        ? ErrorPanel(error: _error!, onRetry: _load)
        : _details(),
    bottomNavigationBar: _loading || _error != null ? null : _purchaseBar(),
  );

  Widget _details() {
    final product = _product!;
    final stock = product['stock'];
    final reviewCount = product['totalReviews'] as num? ?? 0;
    final description = product['description']?.toString() ?? '';
    return RefreshIndicator(
      onRefresh: _load,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                StudentImage(
                  url: product['imageUrl'],
                  height: 260,
                  width: double.infinity,
                ),
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 10,
                        runSpacing: 6,
                        children: [
                          if (product['isFeatured'] == true)
                            const Chip(
                              avatar: Icon(
                                Icons.star_rounded,
                                size: 18,
                                color: AppColors.accent,
                              ),
                              label: Text('Destacado'),
                            ),
                          Chip(
                            label: Text(
                              _available
                                  ? 'Disponible'
                                  : _business?['isOpen'] != true
                                  ? 'Local cerrado'
                                  : 'No disponible',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(product['name'].toString(), style: AppText.h1),
                      const SizedBox(height: 6),
                      Text(
                        _business?['name']?.toString() ?? '',
                        style: AppText.notes,
                      ),
                      const SizedBox(height: 14),
                      Text(
                        money(product['price']),
                        style: AppText.h1.copyWith(color: AppColors.primary),
                      ),
                      if (description.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        Text(
                          description,
                          style: AppText.body.copyWith(height: 1.5),
                        ),
                      ],
                      const SizedBox(height: 16),
                      ExpansionTile(
                        tilePadding: EdgeInsets.zero,
                        title: const Text('Reseñas del platillo'),
                        subtitle: Text(
                          '${product['averageRating'] ?? 0}/5 · $reviewCount ${reviewCount == 1 ? 'reseña' : 'reseñas'}',
                        ),
                        children: [
                          PublicProductReviews(productId: widget.productId),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 16,
                        runSpacing: 8,
                        children: [
                          if (stock is num)
                            Text(
                              'Existencias: ${stock.toInt()}',
                              style: AppText.notes,
                            ),
                          if (product['preparationMinutes'] != null)
                            Text(
                              'Preparación: ${product['preparationMinutes']} min',
                              style: AppText.notes,
                            ),
                          if (product['calories'] != null)
                            Text(
                              '${product['calories']} kcal',
                              style: AppText.notes,
                            ),
                          if (reviewCount > 0)
                            Text(
                              '★ ${(product['averageRating'] as num).toStringAsFixed(1)} · $reviewCount ${reviewCount == 1 ? 'opinión' : 'opiniones'}',
                              style: AppText.notes,
                            ),
                        ],
                      ),
                      const SizedBox(height: 28),
                      const Text('Notas especiales', style: AppText.h3),
                      const SizedBox(height: 8),
                      const Text(
                        'Personaliza tu producto. Estas notas se guardan con él.',
                        style: AppText.notes,
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _notes,
                        enabled: !_busy,
                        onChanged: (_) => setState(() {}),
                        maxLength: 500,
                        minLines: 2,
                        maxLines: 4,
                        style: AppText.body,
                        decoration: InputDecoration(
                          hintText: 'Ej. Sin cebolla, salsa aparte…',
                          filled: true,
                          fillColor: AppColors.componentBase,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                      if (_favorite != null &&
                          _notes.text.trim() != _favorite!['notes'])
                        TextButton.icon(
                          onPressed: _busy
                              ? null
                              : () => _favoriteAction(updateNotes: true),
                          icon: const Icon(Icons.favorite_outline_rounded),
                          label: const Text('Guardar notas en mi favorito'),
                        ),
                      const SizedBox(height: 24),
                      const Text('Cantidad', style: AppText.h3),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.componentBase,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            IconButton.filled(
                              tooltip: 'Disminuir cantidad',
                              onPressed: _busy || _quantity <= 1
                                  ? null
                                  : () => setState(() => _quantity--),
                              icon: const Icon(Icons.remove_rounded),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                              ),
                              child: Text('$_quantity', style: AppText.h1),
                            ),
                            IconButton.filled(
                              tooltip: 'Aumentar cantidad',
                              onPressed:
                                  _busy || !_available || _quantity >= _limit
                                  ? null
                                  : () => setState(() => _quantity++),
                              icon: const Icon(Icons.add_rounded),
                            ),
                          ],
                        ),
                      ),
                      if (_quantity > _limit && _available)
                        Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Text(
                            'Reduce la cantidad: hay $_limit disponibles.',
                            style: AppText.notes.copyWith(
                              color: AppColors.error,
                            ),
                          ),
                        ),
                      if (_cart != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(
                            'Ya está en tu carrito. Guardar actualizará la cantidad y las notas.',
                            style: AppText.notes,
                          ),
                        ),
                      const SizedBox(height: 24),
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

  Widget _purchaseBar() {
    final total = (_product!['price'] as num).toDouble() * _quantity;
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
        decoration: const BoxDecoration(
          color: AppColors.background,
          border: Border(top: BorderSide(color: AppColors.borders)),
        ),
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 850),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _busy || !_available || _quantity > _limit
                    ? null
                    : _saveCart,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 16,
                  ),
                  backgroundColor: AppColors.primary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: _busy
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        !_available
                            ? 'Producto no disponible para ordenar'
                            : '${_cart == null ? 'Añadir al carrito' : 'Actualizar carrito'} · ${money(total)}',
                        textAlign: TextAlign.center,
                        style: AppText.body.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
