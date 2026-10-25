import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../api/api_client.dart';
import '../api/student_repository.dart';
import '../api/student_store.dart';
import '../theme/app_colors.dart';
import 'student_root.dart';
import 'order_screens.dart';

class StudentCatalogScreen extends StatefulWidget {
  final bool favorites;
  final String? businessId;
  const StudentCatalogScreen({
    super.key,
    this.favorites = false,
    this.businessId,
  });
  @override
  State<StudentCatalogScreen> createState() => _StudentCatalogScreenState();
}

class _StudentCatalogScreenState extends State<StudentCatalogScreen> {
  String _query = '', _category = 'Todo';
  @override
  Widget build(BuildContext context) {
    final store = context.watch<StudentStore>();
    final all = store.availableProducts
        .where(
          (p) =>
              (widget.businessId == null ||
                  p['businessId'] == widget.businessId) &&
              (!widget.favorites || store.favorites.contains(p['id'])),
        )
        .toList();
    final categories = {
      'Todo',
      ...all.map((p) => p['category'] as String? ?? 'Otros'),
    };
    final rows = all
        .where(
          (p) =>
              (_category == 'Todo' || p['category'] == _category) &&
              '${p['name']} ${p['description']}'.toLowerCase().contains(
                _query.toLowerCase().trim(),
              ),
        )
        .toList();
    final featured = all.where((p) => p['isFeatured'] == true).take(3).toList();
    final content = RefreshIndicator(
      onRefresh: store.refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        children: [
          if (widget.favorites)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Text(
                'Favoritos guardados en este dispositivo. Solo se muestran los disponibles.',
              ),
            ),
          TextField(
            onChanged: (value) => setState(() => _query = value),
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search_rounded),
              hintText: '¿Qué se te antoja hoy en el campus?',
            ),
          ),
          if (!widget.favorites &&
              widget.businessId == null &&
              _query.isEmpty) ...[
            const SizedBox(height: 20),
            ...featured.map(
              (product) => studentCard(
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'DESTACADO EN EL CAMPUS',
                      style: TextStyle(
                        color: AppColors.tertiary,
                        fontWeight: FontWeight.bold,
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
                                product['name'] as String,
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                product['description'] as String? ?? '',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                money(product['price']),
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        studentPhoto(
                          context,
                          product['imageUrl'] as String?,
                          size: 96,
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () => openStudent(
                          context,
                          StudentProductScreen(id: product['id'] as String),
                        ),
                        child: const Text('Ver platillo →'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 20),
          Text(
            widget.favorites ? 'Tus favoritos' : 'Menú del campus',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: categories
                  .map(
                    (category) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(category),
                        selected: category == _category,
                        selectedColor: AppColors.tertiary.withValues(alpha: .2),
                        onSelected: (_) => setState(() => _category = category),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
          const SizedBox(height: 16),
          if (rows.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('No hay platillos disponibles para esta selección.'),
            ),
          ...rows.map(
            (product) => Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: InkWell(
                borderRadius: BorderRadius.circular(24),
                onTap: () => openStudent(
                  context,
                  StudentProductScreen(id: product['id'] as String),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      studentPhoto(context, product['imageUrl'] as String?),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              product['category'] as String? ?? '',
                              style: const TextStyle(
                                color: AppColors.tertiary,
                                fontSize: 11,
                              ),
                            ),
                            Text(
                              product['name'] as String,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            Text(
                              store.businessName(
                                product['businessId'] as String,
                              ),
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              money(product['price']),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      const CircleAvatar(
                        backgroundColor: AppColors.accent,
                        foregroundColor: AppColors.primary,
                        child: Icon(Icons.add_rounded),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (!widget.favorites && widget.businessId == null) ...[
            const SizedBox(height: 20),
            Text('Cafeterías', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            ...store.businesses.map(
              (shop) => Card(
                child: ListTile(
                  leading: const Icon(
                    Icons.storefront_rounded,
                    color: AppColors.tertiary,
                  ),
                  title: Text(shop['name'] as String),
                  subtitle: Text(
                    shop['isOpen'] == true
                        ? 'En servicio'
                        : 'Cerrada por ahora',
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => openStudent(
                    context,
                    Scaffold(
                      appBar: AppBar(title: Text(shop['name'] as String)),
                      body: StudentCatalogScreen(
                        businessId: shop['id'] as String,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 850),
        child: content,
      ),
    );
  }
}

class StudentProductScreen extends StatefulWidget {
  final String id;
  const StudentProductScreen({super.key, required this.id});
  @override
  State<StudentProductScreen> createState() => _StudentProductScreenState();
}

class _StudentProductScreenState extends State<StudentProductScreen> {
  final _notes = TextEditingController();
  int _quantity = 1;
  bool _notesLoaded = false;
  bool _busy = false;
  Json? _product;
  List<Json> _reviews = [];
  String? _error;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final store = context.read<StudentStore>();
    if (!_notesLoaded) {
      _notes.text = store.favoriteNotes[widget.id] ?? '';
      _notesLoaded = true;
    }
    try {
      final product = await store.repo.product(widget.id);
      if (mounted)
        setState(() {
          _product = product;
          _error = null;
        });
      final reviews = await store.repo.reviews(widget.id);
      if (mounted) setState(() => _reviews = reviews);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<StudentStore>();
    final live = store.findProduct(widget.id);
    final product =
        live != null &&
            (_product == null ||
                (live['version'] as num? ?? 0) >=
                    (_product!['version'] as num? ?? 0))
        ? live
        : _product;
    final shop = product == null
        ? null
        : store.businesses
              .where((s) => s['id'] == product['businessId'])
              .firstOrNull;
    final available =
        product != null &&
        apiProductAvailable(product) &&
        shop?['isOpen'] == true;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Detalle del platillo'),
        actions: [
          IconButton(
            tooltip: 'Actualizar platillo',
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
          IconButton(
            tooltip: 'Favorito',
            onPressed: () => studentAction(
              context,
              () => store.favorite(widget.id, notes: _notes.text.trim()),
            ),
            icon: Icon(
              store.favorites.contains(widget.id)
                  ? Icons.favorite_rounded
                  : Icons.favorite_border_rounded,
              color: AppColors.error,
            ),
          ),
        ],
      ),
      body: product == null
          ? Center(
              child: _error == null
                  ? const CircularProgressIndicator()
                  : Text(_error!),
            )
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 700),
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    Center(
                      child: studentPhoto(
                        context,
                        product['imageUrl'] as String?,
                        size: 260,
                      ),
                    ),
                    const SizedBox(height: 20),
                    studentCard(
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            product['name'] as String,
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            money(product['price']),
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            store.businessName(product['businessId'] as String),
                          ),
                          const SizedBox(height: 12),
                          Text(product['description'] as String? ?? ''),
                          const SizedBox(height: 12),
                          if (product['preparationMinutes'] != null)
                            Text(
                              'Preparación aproximada: ${product['preparationMinutes']} min',
                            ),
                          if (product['calories'] != null)
                            Text('${product['calories']} kcal'),
                          Text(
                            available
                                ? 'Disponible'
                                : 'No disponible para pedir ahora',
                            style: TextStyle(
                              color: available
                                  ? AppColors.tertiary
                                  : AppColors.error,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            '★ ${product['averageRating'] ?? 0} · ${product['totalReviews'] ?? 0} reseñas',
                          ),
                        ],
                      ),
                    ),
                    studentCard(
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Instrucciones para la cocina',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: _notes,
                            maxLength: 500,
                            maxLines: 3,
                            decoration: const InputDecoration(
                              hintText: 'Sin cebolla, salsa aparte…',
                            ),
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              IconButton(
                                tooltip: 'Menos',
                                onPressed: _quantity > 1 && !_busy
                                    ? () => setState(() => _quantity--)
                                    : null,
                                icon: const Icon(Icons.remove_rounded),
                              ),
                              Text(
                                '$_quantity',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              IconButton(
                                tooltip: 'Más',
                                onPressed: _quantity < 99 && !_busy
                                    ? () => setState(() => _quantity++)
                                    : null,
                                icon: const Icon(Icons.add_rounded),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    if (_error != null)
                      Text(
                        _error!,
                        style: const TextStyle(color: AppColors.error),
                      ),
                    if (_reviews.isNotEmpty)
                      studentCard(
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Reseñas de alumnos',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            ..._reviews
                                .take(10)
                                .map(
                                  (review) => Padding(
                                    padding: const EdgeInsets.only(top: 14),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '★ ${review['rating']}/5',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        Text(
                                          review['comment'] as String? ?? '',
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
      bottomNavigationBar: product == null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton(
                  onPressed: !available || _busy
                      ? null
                      : () async {
                          setState(() => _busy = true);
                          await studentAction(
                            context,
                            () => store.add(
                              product,
                              _quantity,
                              _notes.text.trim(),
                            ),
                            success: 'Platillo agregado al carrito',
                          );
                          if (mounted) setState(() => _busy = false);
                        },
                  child: Text(
                    _busy
                        ? 'Agregando…'
                        : 'Agregar al pedido · ${money(((product['price'] as num).toDouble() * _quantity))}',
                  ),
                ),
              ),
            ),
    );
  }
}

class StudentCartScreen extends StatefulWidget {
  const StudentCartScreen({super.key});
  @override
  State<StudentCartScreen> createState() => _StudentCartScreenState();
}

class _StudentCartScreenState extends State<StudentCartScreen> {
  String _payment = 'Efectivo';
  bool _busy = false;
  @override
  Widget build(BuildContext context) {
    final store = context.watch<StudentStore>();
    final pending = store.pendingPurchase;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mi pedido'),
        actions: [
          IconButton(
            tooltip: 'Actualizar precios',
            onPressed: _busy || pending != null
                ? null
                : () => studentAction(
                    context,
                    store.updateCartPrices,
                    success: 'Precios y existencias actualizados',
                  ),
            icon: const Icon(Icons.refresh_rounded),
          ),
          TextButton(
            onPressed: _busy || pending != null
                ? null
                : () => studentAction(context, store.clearCart),
            child: const Text('Vaciar'),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const Text(
                'Carrito guardado en este dispositivo',
                style: TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 16),
              if (store.cart.isEmpty && pending == null)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'Tu carrito está vacío. Elige un platillo del menú.',
                  ),
                ),
              if (pending != null)
                studentCard(
                  const Text(
                    'Hay una compra pendiente de respuesta. El botón reenvía el mismo pedido para evitar duplicados. No modifiques el carrito hasta resolverla.',
                  ),
                ),
              ...store.cart.asMap().entries.map((entry) {
                final index = entry.key, row = entry.value;
                final product = Map<String, dynamic>.from(
                  row['product'] as Map,
                );
                return studentCard(
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          studentPhoto(
                            context,
                            product['imageUrl'] as String?,
                            size: 64,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  product['name'] as String,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  money(
                                    (product['price'] as num).toDouble() *
                                        (row['quantity'] as int),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'Quitar del carrito',
                            onPressed: _busy || pending != null
                                ? null
                                : () => studentAction(
                                    context,
                                    () => store.quantity(index, 0),
                                  ),
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ],
                      ),
                      if ((row['notes'] as String? ?? '').isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text('Notas: ${row['notes']}'),
                        ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: _busy || pending != null
                                ? null
                                : () async {
                                    final controller = TextEditingController(
                                      text: row['notes'] as String? ?? '',
                                    );
                                    final notes = await showDialog<String>(
                                      context: context,
                                      builder: (dialog) => AlertDialog(
                                        title: const Text(
                                          'Instrucciones para la cocina',
                                        ),
                                        content: TextField(
                                          controller: controller,
                                          maxLength: 500,
                                          maxLines: 3,
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.pop(dialog),
                                            child: const Text('Cancelar'),
                                          ),
                                          FilledButton(
                                            onPressed: () => Navigator.pop(
                                              dialog,
                                              controller.text.trim(),
                                            ),
                                            child: const Text('Guardar'),
                                          ),
                                        ],
                                      ),
                                    );
                                    // Dispose after the dialog has completed its exit animation.
                                    Future<void>.delayed(
                                      const Duration(milliseconds: 300),
                                      controller.dispose,
                                    );
                                    if (notes != null && context.mounted)
                                      await studentAction(
                                        context,
                                        () => store.editNotes(index, notes),
                                      );
                                  },
                            child: const Text('Editar notas'),
                          ),
                          IconButton(
                            tooltip: 'Menos',
                            onPressed: _busy || pending != null
                                ? null
                                : () => studentAction(
                                    context,
                                    () => store.quantity(
                                      index,
                                      (row['quantity'] as int) - 1,
                                    ),
                                  ),
                            icon: const Icon(Icons.remove_circle_outline),
                          ),
                          Text('${row['quantity']}'),
                          IconButton(
                            tooltip: 'Más',
                            onPressed: _busy || pending != null
                                ? null
                                : () => studentAction(
                                    context,
                                    () => store.quantity(
                                      index,
                                      (row['quantity'] as int) + 1,
                                    ),
                                  ),
                            icon: const Icon(Icons.add_circle_outline),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              }),
              if (store.cart.isNotEmpty || pending != null)
                studentCard(
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Método de pago',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 14),
                      DropdownButtonFormField<String>(
                        value: pending == null
                            ? _payment
                            : (pending['body'] as Map)['paymentMethod']
                                  as String,
                        items: const [
                          DropdownMenuItem(
                            value: 'Efectivo',
                            child: Text('Efectivo al recoger'),
                          ),
                          DropdownMenuItem(
                            value: 'Transferencia',
                            child: Text(
                              'Transferencia · pendiente de verificar',
                            ),
                          ),
                        ],
                        onChanged: _busy || pending != null
                            ? null
                            : (value) => setState(() => _payment = value!),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'La app registra el método de pago. No realiza cobros bancarios ni confirma transferencias automáticamente.',
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'Total: ${money(pending == null ? store.total : (pending['body'] as Map)['expectedTotal'])}',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'Recolección cuando la cocina indique que está listo. Por ahora, no se puede programar una hora.',
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: _busy
                              ? null
                              : () async {
                                  setState(() => _busy = true);
                                  Json? order;
                                  final success = await studentAction(
                                    context,
                                    () async {
                                      order = await store.checkout(_payment);
                                    },
                                  );
                                  if (!mounted) return;
                                  setState(() => _busy = false);
                                  if (success &&
                                      order != null &&
                                      context.mounted)
                                    Navigator.of(context).pushReplacement(
                                      MaterialPageRoute<void>(
                                        builder: (_) => StudentOrderScreen(
                                          id: order!['id'] as String,
                                        ),
                                      ),
                                    );
                                },
                          child: Text(
                            _busy
                                ? 'Confirmando…'
                                : pending == null
                                ? 'Confirmar pedido'
                                : 'Reintentar el mismo pedido',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
