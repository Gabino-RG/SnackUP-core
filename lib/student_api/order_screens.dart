import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../api/api_client.dart';
import '../api/student_store.dart';
import '../theme/app_colors.dart';
import 'student_root.dart';
import 'catalog_screens.dart';

const activeStatuses = {'pending', 'accepted', 'preparing', 'ready'};
String orderStatus(String? status) =>
    const {
      'pending': 'Pedido recibido',
      'accepted': 'Aceptado por cocina',
      'preparing': 'Preparando tu pedido',
      'ready': 'Listo para recoger',
      'completed': 'Entregado',
      'cancelled': 'Cancelado',
    }[status] ??
    'Consultando estado';

class StudentOrdersScreen extends StatefulWidget {
  const StudentOrdersScreen({super.key});
  @override
  State<StudentOrdersScreen> createState() => _StudentOrdersScreenState();
}

class _StudentOrdersScreenState extends State<StudentOrdersScreen> {
  bool _history = false;
  String _query = '';
  @override
  Widget build(BuildContext context) {
    final store = context.watch<StudentStore>();
    final orders = store.orders
        .where(
          (row) =>
              (_history
                  ? !activeStatuses.contains(row['status'])
                  : activeStatuses.contains(row['status'])) &&
              '${row['orderNumber']} ${(row['items'] as List? ?? []).map((item) => item['name']).join(' ')}'
                  .toLowerCase()
                  .contains(_query.toLowerCase().trim()),
        )
        .toList();
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 750),
        child: RefreshIndicator(
          onRefresh: store.refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(20),
            children: [
              TextField(
                onChanged: (value) => setState(() => _query = value),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Buscar por platillo o número de pedido',
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                children: [
                  ChoiceChip(
                    label: const Text('Activos'),
                    selected: !_history,
                    onSelected: (_) => setState(() => _history = false),
                  ),
                  ChoiceChip(
                    label: const Text('Historial'),
                    selected: _history,
                    onSelected: (_) => setState(() => _history = true),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              if (orders.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('No hay pedidos en esta selección.'),
                ),
              ...orders.map(
                (order) => studentCard(
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 12,
                        runSpacing: 8,
                        children: [
                          Text(
                            '#${order['orderNumber']}',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          Text(
                            orderStatus(order['status'] as String?),
                            style: TextStyle(
                              color: order['status'] == 'cancelled'
                                  ? AppColors.error
                                  : AppColors.tertiary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        store.businessName(order['businessId'] as String),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        (order['items'] as List? ?? [])
                            .map(
                              (item) => '${item['quantity']}× ${item['name']}',
                            )
                            .join(', '),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        money(order['total']),
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 20,
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: () => openStudent(
                            context,
                            StudentOrderScreen(id: order['id'] as String),
                          ),
                          child: Text(
                            order['status'] == 'ready'
                                ? 'Ver código para recoger'
                                : order['status'] == 'completed'
                                ? 'Ver pedido y valorar'
                                : 'Ver seguimiento',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class StudentOrderScreen extends StatefulWidget {
  final String id;
  const StudentOrderScreen({super.key, required this.id});
  @override
  State<StudentOrderScreen> createState() => _StudentOrderScreenState();
}

class _StudentOrderScreenState extends State<StudentOrderScreen> {
  bool _loading = true;
  String? _error;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _reload());
  }

  Future<void> _reload() async {
    try {
      await context.read<StudentStore>().refreshOrder(widget.id);
      if (mounted) setState(() => _error = null);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _reorder(Json order) async {
    final store = context.read<StudentStore>();
    if (store.cart.isNotEmpty) {
      final yes = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('¿Reemplazar el carrito?'),
          content: const Text(
            'Se consultarán los precios y existencias actuales antes de reemplazarlo.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Conservar carrito'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Reemplazar'),
            ),
          ],
        ),
      );
      if (yes != true || !mounted) return;
    }
    if (!mounted) return;
    final success = await studentAction(context, () => store.reorder(order));
    if (success && mounted) openStudent(context, const StudentCartScreen());
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<StudentStore>();
    final order = store.orders.where((o) => o['id'] == widget.id).firstOrNull;
    final status = order?['status'] as String?;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mi pedido'),
        actions: [
          IconButton(
            tooltip: 'Actualizar pedido',
            onPressed: _reload,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : order == null
          ? Center(child: Text(_error ?? 'Pedido no encontrado.'))
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 700),
                child: RefreshIndicator(
                  onRefresh: _reload,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(20),
                    children: [
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: SelectableText(_error!),
                        ),
                      studentCard(
                        Column(
                          children: [
                            Icon(
                              status == 'completed'
                                  ? Icons.check_circle_rounded
                                  : status == 'cancelled'
                                  ? Icons.cancel_rounded
                                  : Icons.restaurant_rounded,
                              size: 64,
                              color: status == 'cancelled'
                                  ? AppColors.error
                                  : AppColors.tertiary,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              status == 'completed'
                                  ? '¡Gracias por tu compra!'
                                  : orderStatus(status),
                              style: Theme.of(context).textTheme.headlineSmall,
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '#${order['orderNumber']} · ${store.businessName(order['businessId'] as String)}',
                              textAlign: TextAlign.center,
                            ),
                            if (status == 'completed')
                              const Text(
                                'Tu pedido ya fue entregado. Esperamos que lo disfrutes.',
                                textAlign: TextAlign.center,
                              ),
                            if (status == 'cancelled')
                              const Text(
                                'Este pedido fue cancelado y ya no tiene código de recogida.',
                              ),
                          ],
                        ),
                      ),
                      if (_error == null &&
                          status == 'ready' &&
                          order['pickupCode'] is String &&
                          (order['pickupCode'] as String).isNotEmpty)
                        studentCard(
                          Column(
                            children: [
                              const Text(
                                'Muestra este código al personal para recoger tu pedido',
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 20),
                              QrImageView(
                                data: order['pickupCode'] as String,
                                size: 210,
                                backgroundColor: Colors.white,
                              ),
                              const SizedBox(height: 16),
                              SelectableText(
                                order['pickupCode'] as String,
                                style: const TextStyle(
                                  fontSize: 30,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 3,
                                ),
                              ),
                            ],
                          ),
                        ),
                      studentCard(
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Detalle del pedido',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 16),
                            ...(order['items'] as List? ?? []).map(
                              (item) => Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${item['quantity']}× ${item['name']}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    Text('${money(item['price'])} por unidad'),
                                    if ((item['notes'] as String? ?? '')
                                        .isNotEmpty)
                                      Text('Notas: ${item['notes']}'),
                                  ],
                                ),
                              ),
                            ),
                            const Divider(),
                            Text(
                              'Total: ${money(order['total'])}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 22,
                              ),
                            ),
                            Text(
                              'Método: ${order['paymentMethod'] == 'cash' ? 'Efectivo' : order['paymentMethod']}',
                            ),
                            const Text(
                              'El estado del pedido no es una confirmación bancaria de pago.',
                            ),
                          ],
                        ),
                      ),
                      if (status == 'pending')
                        OutlinedButton.icon(
                          icon: const Icon(Icons.close_rounded),
                          label: const Text('Cancelar pedido'),
                          onPressed: () async {
                            final yes = await showDialog<bool>(
                              context: context,
                              builder: (context) => AlertDialog(
                                title: const Text('¿Cancelar este pedido?'),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.pop(context, false),
                                    child: const Text('Conservar'),
                                  ),
                                  FilledButton(
                                    onPressed: () =>
                                        Navigator.pop(context, true),
                                    child: const Text('Cancelar pedido'),
                                  ),
                                ],
                              ),
                            );
                            if (yes != true || !context.mounted) return;
                            await studentAction(context, () async {
                              await store.repo.cancel(order);
                              await store.refreshOrder(widget.id);
                            });
                            await _reload();
                          },
                        ),
                      if (status == 'completed') ...[
                        FilledButton.icon(
                          icon: const Icon(Icons.star_rounded),
                          onPressed: order['isRated'] == true
                              ? null
                              : () async {
                                  await Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      builder: (_) => StudentRatingScreen(
                                        order: order,
                                        restaurant: true,
                                      ),
                                    ),
                                  );
                                  await _reload();
                                },
                          label: Text(
                            order['isRated'] == true
                                ? 'Restaurante valorado · ¡Gracias!'
                                : 'Valorar restaurante',
                          ),
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.restaurant_outlined),
                          label: const Text('Calificar un platillo'),
                          onPressed: () => openStudent(
                            context,
                            StudentRatingScreen(order: order),
                          ),
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.replay_rounded),
                          label: const Text('Volver a pedir'),
                          onPressed: () => _reorder(order),
                        ),
                      ],
                      if (!store.connected)
                        const Padding(
                          padding: EdgeInsets.only(top: 16),
                          child: Text(
                            'Sin avisos en vivo. Actualiza esta pantalla para consultar el estado más reciente.',
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

class StudentRatingScreen extends StatefulWidget {
  final Json order;
  final bool restaurant;
  const StudentRatingScreen({
    super.key,
    required this.order,
    this.restaurant = false,
  });
  @override
  State<StudentRatingScreen> createState() => _StudentRatingScreenState();
}

class _StudentRatingScreenState extends State<StudentRatingScreen> {
  int _rating = 0;
  String? _productId, _error;
  bool _busy = false;
  final _comment = TextEditingController();
  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_rating == 0 || (!widget.restaurant && _productId == null)) {
      setState(() => _error = 'Selecciona el platillo y de 1 a 5 estrellas.');
      return;
    }
    final store = context.read<StudentStore>();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await store.repo.rate(
        widget.order['id'] as String,
        _rating,
        _comment.text,
        productId: widget.restaurant ? null : _productId,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('¡Gracias! Tu valoración se guardó en el restaurante.'),
        ),
      );
      if (widget.restaurant) {
        final index = store.orders.indexWhere(
          (o) => o['id'] == widget.order['id'],
        );
        if (index >= 0) {
          store.orders[index] = {...store.orders[index], 'isRated': true};
          store.changed();
        }
      }
      if (Navigator.of(context).canPop()) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<StudentStore>();
    final choices = <String, String>{
      for (final item in widget.order['items'] as List? ?? [])
        item['productId'] as String: item['name'] as String,
    };
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.restaurant ? 'Valorar restaurante' : 'Calificar comida',
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              studentCard(
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.stars_rounded,
                      color: AppColors.tertiary,
                      size: 40,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Tu opinión alimenta el campus',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      store.businessName(widget.order['businessId'] as String),
                    ),
                  ],
                ),
              ),
              studentCard(
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!widget.restaurant) ...[
                      DropdownButtonFormField<String>(
                        isExpanded: true,
                        value: _productId,
                        hint: const Text('Selecciona tu platillo'),
                        items: choices.entries
                            .map(
                              (entry) => DropdownMenuItem(
                                value: entry.key,
                                child: Text(
                                  entry.value,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: _busy
                            ? null
                            : (value) => setState(() => _productId = value),
                      ),
                      const SizedBox(height: 20),
                    ],
                    Text(
                      widget.restaurant
                          ? '¿Cómo fue tu experiencia en el local?'
                          : '¿Qué tal estuvo tu platillo?',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: List.generate(
                        5,
                        (index) => Expanded(
                          child: IconButton(
                            tooltip: '${index + 1} de 5 estrellas',
                            onPressed: _busy
                                ? null
                                : () => setState(() => _rating = index + 1),
                            icon: Icon(
                              index < _rating
                                  ? Icons.star_rounded
                                  : Icons.star_border_rounded,
                              color: const Color(0xFFAEC500),
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
              studentCard(
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
                      enabled: !_busy,
                      maxLength: 300,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        hintText:
                            'Cuéntanos sobre el sabor, el servicio y tu experiencia…',
                      ),
                    ),
                    const Text(
                      'Puedes enviar una valoración por restaurante y una por platillo de cada pedido entregado. Después de enviarlas no se pueden editar.',
                    ),
                  ],
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: SelectableText(
                    _error!,
                    style: const TextStyle(color: AppColors.error),
                  ),
                ),
              FilledButton(
                onPressed: _busy ? null : _submit,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                ),
                child: Text(_busy ? 'Guardando…' : 'Enviar calificación'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
