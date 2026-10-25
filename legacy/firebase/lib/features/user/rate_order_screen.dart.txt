import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../theme/app_colors.dart';
import 'review_service.dart';
import 'review_error.dart';
import 'package:flutter/foundation.dart';

class RateOrderScreen extends StatefulWidget {
  final String orderId;
  final String businessId;
  final String businessName;
  final bool restaurant;
  final FirebaseFirestore? firestore;
  final String? userId;
  final ReviewService? reviewService;
  const RateOrderScreen({
    super.key,
    required this.orderId,
    required this.businessId,
    required this.businessName,
    this.restaurant = false,
    this.firestore,
    this.userId,
    this.reviewService,
  });
  @override
  State<RateOrderScreen> createState() => _RateOrderScreenState();
}

class _RateOrderScreenState extends State<RateOrderScreen> {
  final _comment = TextEditingController();
  late final Future<List<Map<String, dynamic>>> _items = _loadItems();
  String? _productId;
  String? _restaurantName;
  int _rating = 0;
  bool _anonymous = false;
  bool _saving = false;
  String? _error;

  FirebaseFirestore get _db => widget.firestore ?? FirebaseFirestore.instance;
  String? get _userId =>
      widget.userId ?? FirebaseAuth.instance.currentUser?.uid;

  Future<List<Map<String, dynamic>>> _loadItems() async {
    final order = await _db.collection('orders').doc(widget.orderId).get();
    final data = order.data();
    if (data == null ||
        data['userId'] != _userId ||
        data['status'] != 'completed') {
      throw StateError('Solo puedes valorar tus pedidos entregados.');
    }
    if (widget.restaurant) {
      final businessId = data['businessId'];
      if (businessId is String && businessId.isNotEmpty) {
        try {
          final business = await _db
              .collection('businesses')
              .doc(businessId)
              .get();
          _restaurantName = business.data()?['name'] as String?;
        } catch (_) {
          // The order can still be rated if the public restaurant name is unavailable.
        }
      }
      return [];
    }
    final products = <String, Map<String, dynamic>>{};
    for (final item in (data['items'] as List? ?? []).whereType<Map>()) {
      final id = item['productId'];
      if (id is String && id.isNotEmpty)
        products[id] = Map<String, dynamic>.from(item);
    }
    return products.values.toList();
  }

  Future<void> _submit() async {
    final userId = _userId;
    if (userId == null) {
      setState(
        () => _error =
            'Tu sesión ya no está activa. Inicia sesión de nuevo para valorar.',
      );
      return;
    }
    if ((!widget.restaurant && _productId == null) || _rating == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.restaurant
                ? 'Selecciona de 1 a 5 estrellas para el restaurante.'
                : 'Selecciona un platillo y sus estrellas.',
          ),
        ),
      );
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await (widget.reviewService ?? ReviewService(_db)).save(
        orderId: widget.orderId,
        productId: widget.restaurant ? null : _productId!,
        userId: userId,
        rating: _rating,
        comment: _comment.text,
        anonymous: _anonymous,
        userName: widget.userId != null
            ? 'Estudiante'
            : FirebaseAuth.instance.currentUser?.displayName ?? 'Estudiante',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('¡Gracias! Tu valoración se guardó.')),
      );
      if (Navigator.of(context).canPop()) Navigator.of(context).pop();
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint('Error al guardar valoración: $error');
        debugPrintStack(stackTrace: stackTrace);
      }
      if (mounted) {
        final message = reviewErrorMessage(error);
        setState(() => _error = message);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Widget _card(Widget child) => Container(
    width: double.infinity,
    margin: const EdgeInsets.only(bottom: 16),
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: AppColors.borders.withOpacity(.45)),
    ),
    child: child,
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        widget.restaurant ? 'Valorar restaurante' : 'Calificar comida',
      ),
    ),
    body: FutureBuilder<List<Map<String, dynamic>>>(
      future: _items,
      builder: (context, snapshot) {
        if (snapshot.hasError)
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: SelectableText(reviewErrorMessage(snapshot.error!)),
            ),
          );
        if (!snapshot.hasData)
          return const Center(child: CircularProgressIndicator());
        final items = snapshot.data!;
        if (!widget.restaurant && items.isEmpty)
          return const Center(
            child: Text('Este pedido no tiene platillos para valorar.'),
          );
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                _card(
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.stars_rounded,
                        color: AppColors.tertiary,
                        size: 36,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Tus reseñas alimentan el campus',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        widget.restaurant
                            ? 'Comparte tu experiencia en ${widget.businessName}.'
                            : 'Ayúdanos a mejorar el menú de ${widget.businessName}.',
                      ),
                    ],
                  ),
                ),
                _card(
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (widget.restaurant)
                        Text(
                          _restaurantName ?? widget.businessName,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      if (!widget.restaurant)
                        const Text('PLATILLO A CALIFICAR'),
                      const SizedBox(height: 12),
                      if (!widget.restaurant)
                        DropdownButtonFormField<String>(
                          isExpanded: true,
                          value: _productId,
                          hint: const Text('Selecciona tu platillo'),
                          items: items
                              .map(
                                (item) => DropdownMenuItem<String>(
                                  value: item['productId'] as String,
                                  child: Text(
                                    item['name'] as String? ?? 'Platillo',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: _saving
                              ? null
                              : (id) => setState(() {
                                  _productId = id;
                                  _rating = 0;
                                  _comment.clear();
                                }),
                        ),
                      const SizedBox(height: 24),
                      Text(
                        widget.restaurant
                            ? '¿Cómo fue tu experiencia con el restaurante?'
                            : '¿Qué tal estuvo el sabor y la temperatura?',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: List.generate(
                          5,
                          (index) => Flexible(
                            child: IconButton(
                              tooltip: '${index + 1} de 5 estrellas',
                              onPressed: _saving
                                  ? null
                                  : () => setState(() => _rating = index + 1),
                              icon: Icon(
                                index < _rating
                                    ? Icons.star_rounded
                                    : Icons.star_border_rounded,
                                color: index < _rating
                                    ? const Color(0xFFAEC500)
                                    : AppColors.textSecondary,
                                size: 36,
                              ),
                            ),
                          ),
                        ),
                      ),
                      Center(
                        child: Text(
                          _rating == 0
                              ? 'Toca las estrellas para calificar'
                              : '$_rating de 5 estrellas',
                        ),
                      ),
                    ],
                  ),
                ),
                _card(
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Escribe tu opinión',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _comment,
                        enabled: !_saving,
                        maxLength: 300,
                        maxLines: 4,
                        decoration: InputDecoration(
                          hintText: widget.restaurant
                              ? 'Cuéntanos sobre el servicio, la atención y tu experiencia en el local…'
                              : 'Cuéntanos sobre el sabor, la porción y la presentación…',
                          fillColor: AppColors.background,
                        ),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Publicar de forma anónima'),
                        subtitle: const Text(
                          'Tu nombre no se mostrará en la reseña.',
                        ),
                        value: _anonymous,
                        onChanged: _saving
                            ? null
                            : (value) => setState(() => _anonymous = value),
                      ),
                    ],
                  ),
                ),
                if (_error != null)
                  _card(
                    SelectableText(
                      _error!,
                      style: const TextStyle(color: AppColors.error),
                    ),
                  ),
                FilledButton(
                  onPressed: _saving ? null : _submit,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 56),
                  ),
                  child: Text(_saving ? 'Guardando…' : 'Enviar calificación'),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Puedes actualizar tu valoración volviendo a este pedido.',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}
