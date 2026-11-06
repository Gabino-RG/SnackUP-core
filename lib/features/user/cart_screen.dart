import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:snackup/student/checkout.dart';
import 'package:snackup/student/student_api.dart';
import 'package:snackup/student/student_widgets.dart';
import 'package:snackup/theme/student_colors.dart';
import 'package:snackup/theme/student_text.dart';

import 'show_qr_screen.dart';

class CartScreen extends StatefulWidget {
  const CartScreen({super.key});

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartData {
  final List<Map<String, dynamic>> rows;
  final Map<String, Map<String, dynamic>> businesses;
  final Map<String, CheckoutIntent> intents;
  const _CartData(this.rows, this.businesses, this.intents);
}

class _ConfirmedCartError implements Exception {
  final Object cause;
  const _ConfirmedCartError(this.cause);
}

class _CartScreenState extends State<CartScreen> {
  StudentApi? _api;
  String? _ownerId;
  int _revision = -1;
  Future<_CartData>? _future;
  String? _busyBusiness;
  String? _notice;
  Object? _operationError;

  CheckoutLedger get _ledger => CheckoutLedger(
    storage: PreferencesCheckoutStorage(),
    namespace: '${_api!.baseUrl}|${_ownerId ?? ''}',
  );

  void _requireOwner() {
    if (_ownerId == null || _api!.user?['id'] != _ownerId) {
      throw const ApiException(
        401,
        'SESSION_CHANGED',
        'Tu sesión cambió. Vuelve a abrir el carrito desde tu cuenta.',
      );
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final api = context.watch<StudentApi>();
    _ownerId ??= api.user?['id'] as String?;
    if (!identical(api, _api) || _revision != api.revision) {
      _api = api;
      _revision = api.revision;
      _future = _load();
    }
  }

  Future<_CartData> _load() async {
    _requireOwner();
    final results = await Future.wait([
      _api!.getAll('/users/me/cart/items'),
      _api!.getAll('/businesses'),
    ]);
    final intents = await _ledger.intents();
    return _CartData(results[0], {
      for (final business in results[1]) business['id'] as String: business,
    }, intents);
  }

  Future<void> _reload() async {
    final next = _load();
    setState(() {
      _future = next;
    });
    await next;
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Map<String, dynamic>? _product(Map<String, dynamic> row) =>
      row['product'] is Map
      ? Map<String, dynamic>.from(row['product'] as Map)
      : null;

  int _quantity(Map<String, dynamic> row) =>
      (row['quantity'] as num?)?.toInt() ?? 1;

  int _cents(List<Map<String, dynamic>> rows) => rows.fold(0, (sum, row) {
    final price = (_product(row)?['price'] as num?)?.toDouble() ?? 0;
    return sum + (price * 100).round() * _quantity(row);
  });

  bool _available(Map<String, dynamic> row) {
    final product = _product(row);
    final stock = product?['stock'] as num?;
    return product != null &&
        row['available'] == true &&
        product['isAvailable'] == true &&
        (stock == null || stock >= _quantity(row));
  }

  Future<void> _edit(
    Map<String, dynamic> row, {
    int? quantity,
    String? notes,
  }) async {
    if (_busyBusiness != null) return;
    setState(() {
      _busyBusiness = 'editing';
      _operationError = null;
    });
    try {
      _requireOwner();
      await _api!.request(
        'PATCH',
        '/users/me/cart/items/${row['id']}',
        body: {
          if (quantity != null) 'quantity': quantity,
          if (notes != null) 'notes': notes,
        },
      );
    } catch (error) {
      if (mounted) setState(() => _operationError = error);
    } finally {
      if (mounted) {
        setState(() => _busyBusiness = null);
        _refreshQuietly();
      }
    }
  }

  Future<void> _notes(Map<String, dynamic> row) async {
    final controller = TextEditingController(
      text: row['notes'] as String? ?? '',
    );
    final dialog = DialogRoute<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Indicaciones para este producto'),
        content: SizedBox(
          width: 420,
          child: TextField(
            controller: controller,
            maxLength: 500,
            maxLines: 4,
            decoration: const InputDecoration(
              hintText: 'Por ejemplo: sin cebolla',
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Volver'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    final result = await Navigator.of(context).push(dialog);
    await dialog.completed;
    controller.dispose();
    if (result != null && mounted) await _edit(row, notes: result);
  }

  Future<void> _remove(Map<String, dynamic> row) async {
    if (_busyBusiness != null) return;
    setState(() {
      _busyBusiness = 'editing';
      _operationError = null;
    });
    try {
      _requireOwner();
      await _api!.request('DELETE', '/users/me/cart/items/${row['id']}');
    } catch (error) {
      if (mounted) setState(() => _operationError = error);
    } finally {
      if (mounted) {
        setState(() => _busyBusiness = null);
        _refreshQuietly();
      }
    }
  }

  void _refreshQuietly() {
    if (mounted) {
      setState(() {
        _future = _load();
      });
    }
  }

  Future<Map<String, dynamic>?> _reviewPurchase(
    String businessId,
    String name,
    List<Map<String, dynamic>> rows,
    Map<String, dynamic>? business,
  ) {
    var payment = 'Efectivo';
    var scheduled = false;
    var submitted = false;
    TimeOfDay? time;
    String? error;
    final total = _cents(rows) / 100;
    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, update) => AlertDialog(
          title: Text('Pedido en $name'),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  ...rows.map(
                    (row) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        '${_quantity(row)} × ${_product(row)?['name']?.toString() ?? 'Producto'} · ${money(((_product(row)?['price'] as num?) ?? 0) * _quantity(row))}',
                      ),
                    ),
                  ),
                  Text('Total: ${money(total)}', style: AppText.h3),
                  const SizedBox(height: 20),
                  DropdownButtonFormField<String>(
                    value: payment,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Forma de pago',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'Efectivo',
                        child: Text('Efectivo'),
                      ),
                      DropdownMenuItem(
                        value: 'Transferencia',
                        child: Text('Transferencia'),
                      ),
                      DropdownMenuItem(
                        value: 'Tarjeta',
                        child: Text('Tarjeta'),
                      ),
                      DropdownMenuItem(
                        value: 'ValeComida',
                        child: Text('Vale de comida'),
                      ),
                    ],
                    onChanged: (value) =>
                        update(() => payment = value ?? 'Efectivo'),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Elige el método que usarás con el negocio. Esta confirmación no realiza un cargo.',
                    style: AppText.notes,
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Programar recogida'),
                    subtitle: const Text(
                      'Para hoy, con al menos 5 minutos de anticipación',
                    ),
                    value: scheduled,
                    onChanged: (value) => update(() {
                      scheduled = value;
                      error = null;
                    }),
                  ),
                  if (scheduled) ...[
                    OutlinedButton.icon(
                      icon: const Icon(Icons.schedule),
                      label: Text(
                        time == null
                            ? 'Elegir hora'
                            : time!.format(dialogContext),
                      ),
                      onPressed: () async {
                        final picked = await showTimePicker(
                          context: dialogContext,
                          builder: (context, child) => MediaQuery(
                            // Keep the text validator aligned with the 24-hour
                            // clock used by the Spanish (Mexico) locale.
                            data: MediaQuery.of(
                              context,
                            ).copyWith(alwaysUse24HourFormat: true),
                            child: child!,
                          ),
                          initialTime:
                              time ??
                              TimeOfDay.fromDateTime(
                                DateTime.now().add(const Duration(minutes: 15)),
                              ),
                        );
                        if (picked != null) {
                          update(() {
                            time = picked;
                            error = null;
                          });
                        }
                      },
                    ),
                    Text(
                      'Hora de este dispositivo (${DateTime.now().timeZoneName}). El negocio validará su horario${business?['timezone'] == null ? '.' : ': ${business!['timezone']}.'}',
                      style: AppText.notes,
                    ),
                  ],
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        error!,
                        style: const TextStyle(color: AppColors.error),
                      ),
                    ),
                  const SizedBox(height: 14),
                  const Text(
                    'Solo se compran los productos de este negocio. Los demás permanecerán en tu carrito.',
                    style: AppText.notes,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Volver'),
            ),
            FilledButton(
              onPressed: () {
                if (submitted) return;
                DateTime? pickup;
                if (scheduled) {
                  if (time == null) {
                    update(() => error = 'Elige una hora de recogida.');
                    return;
                  }
                  final now = DateTime.now();
                  pickup = DateTime(
                    now.year,
                    now.month,
                    now.day,
                    time!.hour,
                    time!.minute,
                  );
                  if (pickup.isBefore(now.add(const Duration(minutes: 5)))) {
                    update(
                      () => error =
                          'La recogida debe ser al menos 5 minutos después de ahora.',
                    );
                    return;
                  }
                }
                final items =
                    rows
                        .map(
                          (row) => <String, dynamic>{
                            'productId': row['productId'],
                            'quantity': _quantity(row),
                            'notes': row['notes'] ?? '',
                          },
                        )
                        .toList()
                      ..sort(
                        (a, b) => (a['productId'] as String).compareTo(
                          b['productId'] as String,
                        ),
                      );
                submitted = true;
                Navigator.pop(dialogContext, <String, dynamic>{
                  'businessId': businessId,
                  'items': items,
                  'cartRows': [
                    for (final row in checkoutSnapshot(rows))
                      {'id': row['id'], 'updatedAt': row['updatedAt']},
                  ],
                  'paymentMethod': payment,
                  'expectedTotal': total,
                  if (pickup != null)
                    'scheduledPickupTime': pickup.toUtc().toIso8601String(),
                });
              },
              child: const Text('Confirmar pedido'),
            ),
          ],
        ),
      ),
    );
  }

  bool _definitiveRejection(Object error) =>
      error is ApiException &&
      error.status >= 400 &&
      error.status < 500 &&
      ![401, 403, 408, 425, 429].contains(error.status) &&
      error.code != 'IDEMPOTENCY_CONFLICT';

  Future<void> _checkout(
    String businessId,
    String name,
    List<Map<String, dynamic>> rows,
    Map<String, dynamic>? business,
  ) async {
    if (_busyBusiness != null) return;
    setState(() {
      _busyBusiness = businessId;
      _operationError = null;
      _notice = null;
    });
    CheckoutIntent? intent;
    final ledger = _ledger;
    try {
      final payload = await _reviewPurchase(businessId, name, rows, business);
      if (payload == null || !mounted) return;
      _requireOwner();
      intent = await ledger.prepare(
        businessId: businessId,
        payload: payload,
        rows: rows,
      );
      await _sendIntent(ledger, intent);
    } catch (error) {
      await _purchaseError(ledger, intent, error);
    } finally {
      if (mounted) {
        setState(() => _busyBusiness = null);
        _refreshQuietly();
      }
    }
  }

  Future<void> _retry(CheckoutIntent intent) async {
    if (_busyBusiness != null) return;
    setState(() {
      _busyBusiness = intent.businessId;
      _operationError = null;
      _notice = null;
    });
    final ledger = _ledger;
    try {
      if (!intent.confirmed) {
        final proceed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Comprobar compra pendiente'),
            content: Text(
              'Se volverá a confirmar tu compra de ${money(intent.payload['expectedTotal'])}, con pago ${paymentLabel(intent.payload['paymentMethod'])}${intent.payload['scheduledPickupTime'] == null ? '.' : ' y recogida ${dateText(intent.payload['scheduledPickupTime'])}.'} Si ya se registró, verás el mismo pedido.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Volver'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Comprobar'),
              ),
            ],
          ),
        );
        if (proceed != true || !mounted) return;
      }
      _requireOwner();
      await _sendIntent(ledger, intent);
    } catch (error) {
      await _purchaseError(ledger, intent, error);
    } finally {
      if (mounted) {
        setState(() => _busyBusiness = null);
        _refreshQuietly();
      }
    }
  }

  Future<void> _purchaseError(
    CheckoutLedger ledger,
    CheckoutIntent? intent,
    Object error,
  ) async {
    if (error is _ConfirmedCartError) {
      if (mounted) {
        setState(() {
          _notice =
              'Tu pedido está confirmado. Quedó pendiente revisar los productos del carrito; no se hará otra compra.';
          _operationError = error.cause;
        });
      }
      return;
    }
    if (error is CheckoutPendingException) {
      if (mounted) {
        setState(() {
          _operationError = null;
          _notice =
              'Ya hay una compra pendiente para este local. Comprueba el intento guardado antes de hacer otro pedido.';
        });
      }
      return;
    }
    if (intent != null && !intent.confirmed && _definitiveRejection(error)) {
      await ledger.forget(intent);
      if (mounted) {
        setState(
          () => _notice = error is ApiException && error.code == 'CART_CHANGED'
              ? 'El carrito cambió en otra pantalla. Revisa tus pedidos antes de confirmar otra compra.'
              : 'El pedido no se creó. Revisa los precios, existencias y horario actualizados antes de confirmar otra vez.',
        );
      }
    } else if (intent != null && mounted) {
      setState(
        () => _notice =
            'Esta compra necesita comprobarse. Se conservó el mismo intento para evitar un pedido duplicado.',
      );
    }
    if (mounted) setState(() => _operationError = error);
  }

  Future<void> _sendIntent(CheckoutLedger ledger, CheckoutIntent intent) async {
    _requireOwner();
    final api = _api!;
    final account = api.user?['id'];
    final generation = api.sessionGeneration;
    final confirmed = await ledger.send(intent, (payload, key) async {
      _requireOwner();
      Future<dynamic> submit() => api.request(
        'POST',
        '/orders',
        body: payload,
        headers: {'Idempotency-Key': key},
      );
      dynamic result;
      try {
        result = await submit();
      } on ApiException catch (error) {
        final seconds = error.retryAfterSeconds;
        if (error.status != 503 ||
            error.code != 'SERVICE_BUSY' ||
            seconds == null ||
            seconds < 0 ||
            seconds > 5) {
          rethrow;
        }
        // Admission rejected this request before checkout. Spread retries across
        // purchases, keeping the original payload and idempotency key.
        if (!mounted || ModalRoute.of(context)?.isCurrent != true) rethrow;
        _message(
          'Hay muchas compras al mismo tiempo. Reintentaremos tu pedido en un momento.',
        );
        await Future<void>.delayed(
          Duration(seconds: seconds, milliseconds: key.hashCode % 1500),
        );
        if (!mounted ||
            ModalRoute.of(context)?.isCurrent != true ||
            WidgetsBinding.instance.lifecycleState !=
                AppLifecycleState.resumed ||
            !identical(api, _api) ||
            api.sessionGeneration != generation ||
            api.user?['id'] != account) {
          rethrow;
        }
        result = await submit();
      }
      return Map<String, dynamic>.from(result as Map);
    });
    if (api.user?['id'] != account || !mounted) return;
    try {
      var changed = false;
      if (!confirmed.payload.containsKey('cartRows')) {
        // Only previously saved purchases need a separate cart cleanup. The
        // server checks the saved timestamp while it holds the cart write lock.
        final current = await api.getAll('/users/me/cart/items');
        final removable = unchangedPurchasedRows(confirmed, current).toSet();
        final currentIds = current.map((row) => row['id']).toSet();
        for (final row in confirmed.cartSnapshot) {
          if (!removable.contains(row['id'])) {
            changed = changed || currentIds.contains(row['id']);
            continue;
          }
          _requireOwner();
          final timestamp = row['updatedAt'];
          if (timestamp is! String || timestamp.isEmpty) {
            changed = true;
            continue;
          }
          try {
            await api.request(
              'DELETE',
              '/users/me/cart/items/${row['id']}',
              query: {'expectedUpdatedAt': timestamp},
            );
          } on ApiException catch (error) {
            if (error.code == 'CART_CHANGED') {
              changed = true;
            } else if (error.status != 404) {
              rethrow;
            }
          }
        }
      }
      await ledger.forget(confirmed);
      if (!mounted || api.user?['id'] != account) return;
      _message(
        changed
            ? 'Pedido confirmado. Conservamos los productos que cambiaste para que los revises.'
            : 'Pedido confirmado. Puedes consultar su estado y código de recogida.',
      );
      await Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => ShowQrScreen(orderId: confirmed.orderId!),
        ),
      );
    } catch (error) {
      throw _ConfirmedCartError(error);
    }
  }

  Widget _pendingCard(CheckoutIntent intent, _CartData data) => Card(
    color: intent.confirmed
        ? AppColors.success.withValues(alpha: .08)
        : AppColors.warning.withValues(alpha: .13),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            intent.confirmed
                ? 'Pedido confirmado'
                : 'Compra pendiente de comprobar',
            style: AppText.h3,
          ),
          const SizedBox(height: 6),
          Text(
            data.businesses[intent.businessId]?['name']?.toString() ??
                'Negocio',
          ),
          Text(
            '${money(intent.payload['expectedTotal'])} · ${dateText(intent.createdAt)}',
          ),
          const SizedBox(height: 8),
          Text(
            intent.confirmed
                ? 'La compra ya se registró. Continúa para consultar el pedido.'
                : 'La respuesta de esta compra no está confirmada. Comprueba el mismo intento antes de hacer otro pedido en este negocio.',
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: _busyBusiness == null ? () => _retry(intent) : null,
                icon: const Icon(Icons.sync),
                label: Text(
                  intent.confirmed ? 'Continuar' : 'Comprobar compra',
                ),
              ),
              if (intent.orderId != null)
                OutlinedButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => ShowQrScreen(orderId: intent.orderId!),
                    ),
                  ),
                  child: const Text('Ver pedido'),
                ),
            ],
          ),
        ],
      ),
    ),
  );

  Widget _row(Map<String, dynamic> row, bool locked) {
    final product = _product(row);
    final quantity = _quantity(row);
    final price = product?['price'];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: StudentImage(
                  url: product?['imageUrl'],
                  width: 68,
                  height: 68,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product?['name']?.toString() ??
                          'Producto ya no disponible',
                      style: AppText.body.copyWith(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      price == null
                          ? 'Precio no disponible'
                          : '${money(price)} por unidad',
                      style: AppText.notes,
                    ),
                    if (!_available(row))
                      const Text(
                        'Revisa disponibilidad o cantidad',
                        style: TextStyle(color: AppColors.error),
                      ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Eliminar del carrito',
                onPressed: locked ? null : () => _remove(row),
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
          if ((row['notes'] as String? ?? '').isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('Notas: ${row['notes']}'),
            ),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 4,
            children: [
              IconButton(
                tooltip: 'Restar una unidad',
                onPressed: locked || quantity <= 1
                    ? null
                    : () => _edit(row, quantity: quantity - 1),
                icon: const Icon(Icons.remove_circle_outline),
              ),
              Text(
                '$quantity',
                style: AppText.body.copyWith(fontWeight: FontWeight.w700),
              ),
              IconButton(
                tooltip: 'Sumar una unidad',
                onPressed: locked || quantity >= 99
                    ? null
                    : () => _edit(row, quantity: quantity + 1),
                icon: const Icon(Icons.add_circle_outline),
              ),
              TextButton.icon(
                onPressed: locked ? null : () => _notes(row),
                icon: const Icon(Icons.edit_note),
                label: const Text('Indicaciones'),
              ),
              if (price is num)
                Text(money(price * quantity), style: AppText.body),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.componentBase,
    appBar: AppBar(title: const Text('Mi carrito')),
    body: RefreshIndicator(
      onRefresh: () async {
        try {
          await _reload();
        } catch (_) {
          /* FutureBuilder shows the error. */
        }
      },
      child: FutureBuilder<_CartData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.hasError && !snapshot.hasData) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                ErrorPanel(error: snapshot.error!, onRetry: _refreshQuietly),
              ],
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snapshot.data!;
          final groups = <String, List<Map<String, dynamic>>>{};
          for (final row in data.rows) {
            final id =
                _product(row)?['businessId']?.toString() ?? 'unavailable';
            groups.putIfAbsent(id, () => []).add(row);
          }
          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
              if (snapshot.connectionState == ConnectionState.waiting ||
                  _busyBusiness != null)
                const LinearProgressIndicator(),
              const Text(
                'Tus productos y notas se guardan en tu cuenta. Confirma un negocio a la vez.',
                style: AppText.notes,
              ),
              const SizedBox(height: 16),
              if (_notice != null)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(_notice!),
                  ),
                ),
              if (_operationError != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    friendlyError(_operationError!),
                    style: const TextStyle(color: AppColors.error),
                  ),
                ),
              if (snapshot.hasError)
                ErrorPanel(error: snapshot.error!, onRetry: _refreshQuietly),
              ...data.intents.values.map(
                (intent) => _pendingCard(intent, data),
              ),
              if (data.rows.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 48),
                  child: Column(
                    children: [
                      Icon(
                        Icons.shopping_bag_outlined,
                        size: 64,
                        color: AppColors.primary,
                      ),
                      SizedBox(height: 16),
                      Text('Tu carrito está vacío', style: AppText.h3),
                      SizedBox(height: 8),
                      Text(
                        'Explora los negocios y añade lo que se te antoje.',
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ...groups.entries.map((entry) {
                final id = entry.key;
                final rows = entry.value;
                final business = data.businesses[id];
                final name =
                    business?['name']?.toString() ??
                    'Productos sin negocio disponible';
                final hasIntent = data.intents.containsKey(id);
                final enabled =
                    _busyBusiness == null &&
                    !hasIntent &&
                    rows.length <= 50 &&
                    rows.every(_available);
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name, style: AppText.h3),
                        ...rows.map(
                          (row) =>
                              _row(row, _busyBusiness != null || hasIntent),
                        ),
                        const Divider(),
                        Text(
                          'Total del negocio: ${money(_cents(rows) / 100)}',
                          style: AppText.h3,
                        ),
                        if (rows.length > 50)
                          const Text(
                            'Un pedido admite hasta 50 productos distintos.',
                            style: TextStyle(color: AppColors.error),
                          ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: enabled
                                ? () => _checkout(id, name, rows, business)
                                : null,
                            icon: const Icon(Icons.shopping_bag_outlined),
                            label: Text(
                              hasIntent
                                  ? 'Resuelve la compra pendiente'
                                  : 'Revisar pedido de este negocio',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
              const SizedBox(height: 24),
            ],
          );
        },
      ),
    ),
  );
}
