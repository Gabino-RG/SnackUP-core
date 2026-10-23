import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../theme/app_colors.dart';
import 'review_service.dart';

class RateOrderScreen extends StatefulWidget {
  final String orderId;
  final String businessId;
  final String businessName;
  const RateOrderScreen({
    super.key,
    required this.orderId,
    required this.businessId,
    required this.businessName,
  });
  @override
  State<RateOrderScreen> createState() => _RateOrderScreenState();
}

class _RateOrderScreenState extends State<RateOrderScreen> {
  final _comment = TextEditingController();
  late final Future<List<Map<String, dynamic>>> _items = _loadItems();
  String? _productId;
  int _rating = 0;
  bool _anonymous = false;
  bool _saving = false;

  Future<List<Map<String, dynamic>>> _loadItems() async {
    final order = await FirebaseFirestore.instance
        .collection('orders')
        .doc(widget.orderId)
        .get();
    final data = order.data();
    if (data == null ||
        data['userId'] != FirebaseAuth.instance.currentUser?.uid ||
        data['status'] != 'completed') {
      throw StateError('Solo puedes valorar tus pedidos entregados.');
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
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || _productId == null || _rating == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Selecciona un platillo y sus estrellas.'),
        ),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await ReviewService(FirebaseFirestore.instance).save(
        orderId: widget.orderId,
        productId: _productId!,
        userId: user.uid,
        rating: _rating,
        comment: _comment.text,
        anonymous: _anonymous,
        userName: user.displayName ?? 'Estudiante',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('¡Gracias! Tu valoración se guardó.')),
      );
      Navigator.of(context).pop();
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No se pudo guardar. Revisa tu conexión e intenta de nuevo.',
            ),
          ),
        );
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
    appBar: AppBar(title: const Text('Calificar comida')),
    body: FutureBuilder<List<Map<String, dynamic>>>(
      future: _items,
      builder: (context, snapshot) {
        if (snapshot.hasError)
          return const Center(
            child: Text('No se pudo cargar el pedido entregado.'),
          );
        if (!snapshot.hasData)
          return const Center(child: CircularProgressIndicator());
        final items = snapshot.data!;
        if (items.isEmpty)
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
                        'Ayúdanos a mejorar el menú de ${widget.businessName}.',
                      ),
                    ],
                  ),
                ),
                _card(
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('PLATILLO A CALIFICAR'),
                      const SizedBox(height: 12),
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
                        '¿Qué tal estuvo el sabor y la temperatura?',
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
                        decoration: const InputDecoration(
                          hintText:
                              'Cuéntanos sobre el sabor, la porción y la presentación…',
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
