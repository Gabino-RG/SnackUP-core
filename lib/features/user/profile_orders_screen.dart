import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:snackup/student/student_api.dart';
import 'package:snackup/student/student_widgets.dart';
import 'package:snackup/student/push_notifications.dart';
import 'package:snackup/theme/student_colors.dart';
import 'package:snackup/theme/student_text.dart';

import 'cart_screen.dart';
import 'product_detail_screen.dart';
import 'rate_order_screen.dart';
import 'show_qr_screen.dart';
import 'student_chat_screen.dart';
import 'package:snackup/student/product_reviews.dart';
import 'package:snackup/student/order_summary.dart';

class ProfileOrdersScreen extends StatefulWidget {
  const ProfileOrdersScreen({
    super.key,
    this.initialTab = 0,
    this.embedded = false,
  });
  final int initialTab;
  final bool embedded;

  @override
  State<ProfileOrdersScreen> createState() => _ProfileOrdersScreenState();
}

List<Map<String, dynamic>> _pageRows(Map<String, dynamic> page) =>
    (page['data'] as List)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();

class _ProfileData {
  final List<Map<String, dynamic>> active;
  final List<Map<String, dynamic>> history;
  final List<Map<String, dynamic>> favorites;
  final Map<String, dynamic> user;
  final Map<String, String> businessNames;
  final int historyPages;
  const _ProfileData(
    this.active,
    this.history,
    this.favorites,
    this.user,
    this.businessNames,
    this.historyPages,
  );
}

class _ProfileOrdersScreenState extends State<ProfileOrdersScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(
    length: 4,
    vsync: this,
    initialIndex: widget.initialTab,
  );
  StudentApi? _api;
  String? _ownerId;
  int _revision = -1;
  int _generation = 0;
  Future<_ProfileData>? _future;
  final List<Map<String, dynamic>> _extraHistory = [];
  int _historyPage = 1;
  bool _loadingMore = false;
  Object? _moreError;
  String? _busy;
  Object? _actionError;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final api = context.watch<StudentApi>();
    _ownerId ??= api.user?['id'] as String?;
    if (!identical(_api, api) || _revision != api.revision) {
      _api = api;
      _revision = api.revision;
      _future = _load();
    }
  }

  Future<_ProfileData> _load() async {
    _requireOwner();
    _generation++;
    _historyPage = 1;
    _extraHistory.clear();
    _loadingMore = false;
    _moreError = null;
    final results = await Future.wait<dynamic>([
      _api!.getAll('/users/me/orders/active'),
      _api!.getObject(
        '/users/me/orders/history',
        query: {'page': '1', 'limit': '20'},
      ),
      _api!.getAll('/users/me/favorites'),
      _api!.getObject('/users/me'),
      _api!.getAll('/businesses'),
    ]);
    final history = results[1] as Map<String, dynamic>;
    return _ProfileData(
      results[0] as List<Map<String, dynamic>>,
      _pageRows(history),
      results[2] as List<Map<String, dynamic>>,
      results[3] as Map<String, dynamic>,
      {
        for (final row in results[4] as List<Map<String, dynamic>>)
          row['id'] as String: row['name'] as String,
      },
      ((history['pagination'] as Map)['totalPages'] as num).toInt(),
    );
  }

  void _reload() {
    if (mounted) {
      setState(() {
        _future = _load();
      });
    }
  }

  void _requireOwner() {
    if (_ownerId == null || _api!.user?['id'] != _ownerId) {
      throw const ApiException(
        401,
        'SESSION_CHANGED',
        'Tu sesión cambió. Vuelve a abrir tus pedidos desde tu cuenta.',
      );
    }
  }

  void _message(String message) {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _more() async {
    if (_loadingMore) return;
    final generation = _generation;
    setState(() {
      _loadingMore = true;
      _moreError = null;
    });
    try {
      _requireOwner();
      final page = await _api!.getObject(
        '/users/me/orders/history',
        query: {'page': (_historyPage + 1).toString(), 'limit': '20'},
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        _extraHistory.addAll(_pageRows(page));
        _historyPage++;
      });
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() => _moreError = error);
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loadingMore = false);
      }
    }
  }

  Future<void> _cancel(Map<String, dynamic> order) async {
    if (_busy != null) return;
    final controller = TextEditingController();
    final dialog = DialogRoute<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, update) => AlertDialog(
          title: const Text('Cancelar pedido pendiente'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'La cancelación solo es posible antes de que el negocio acepte el pedido.',
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: controller,
                  maxLength: 500,
                  maxLines: 3,
                  onChanged: (_) => update(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Cuéntanos el motivo',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Conservar pedido'),
            ),
            FilledButton(
              onPressed: controller.text.trim().isEmpty
                  ? null
                  : () => Navigator.pop(dialogContext, controller.text.trim()),
              child: const Text('Cancelar pedido'),
            ),
          ],
        ),
      ),
    );
    final notes = await Navigator.of(context).push(dialog);
    await dialog.completed;
    controller.dispose();
    if (notes == null || !mounted) return;
    setState(() {
      _busy = order['id'] as String;
      _actionError = null;
    });
    try {
      _requireOwner();
      await _api!.request(
        'POST',
        '/orders/${order['id']}/cancel',
        body: {
          'reason': 'user_other',
          'notes': notes,
          'expectedVersion': order['version'],
        },
      );
      _message('Pedido cancelado.');
    } catch (error) {
      if (mounted) setState(() => _actionError = error);
    } finally {
      if (mounted) {
        setState(() => _busy = null);
        _reload();
      }
    }
  }

  Future<void> _reorder(Map<String, dynamic> order) async {
    if (_busy != null) return;
    setState(() {
      _busy = order['id'] as String;
      _actionError = null;
    });
    try {
      _requireOwner();
      final oldItems = (order['items'] as List)
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList();
      final available = <Map<String, dynamic>>[];
      var unavailable = 0;
      // Load live products before asking for approval; historical prices never
      // enter the cart or become an authorized order amount.
      for (final item in oldItems) {
        try {
          final product = await _api!.getObject(
            '/products/${item['productId']}',
          );
          final quantity = (item['quantity'] as num).toInt();
          final stock = product['stock'] as num?;
          if (product['isAvailable'] != true ||
              (stock != null && stock < quantity)) {
            unavailable++;
          } else {
            available.add({
              'product': product,
              'quantity': quantity,
              'notes': item['notes'] ?? '',
            });
          }
        } on ApiException catch (error) {
          if (error.status == 404) {
            unavailable++;
          } else {
            rethrow;
          }
        }
      }
      final cart = await _api!.getAll('/users/me/cart/items');
      if (!mounted) return;
      if (available.isEmpty) {
        _message(
          'Los productos de ese pedido no están disponibles actualmente.',
        );
        return;
      }
      final replacing = available
          .where(
            (row) => cart.any(
              (saved) => saved['productId'] == (row['product'] as Map)['id'],
            ),
          )
          .length;
      final approved = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Volver a pedir'),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Revisa los precios actuales. Se conservarán las cantidades y notas del pedido anterior.',
                  ),
                  const SizedBox(height: 12),
                  ...available.map((row) {
                    final product = row['product'] as Map;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        '${row['quantity']} × ${product['name']} · ${money((product['price'] as num) * (row['quantity'] as int))}${(row['notes'] as String).isEmpty ? '' : '\nNotas: ${row['notes']}'}',
                      ),
                    );
                  }),
                  if (unavailable > 0)
                    Text(
                      '$unavailable productos no están disponibles y se omitirán.',
                      style: const TextStyle(color: AppColors.error),
                    ),
                  if (replacing > 0)
                    Text(
                      '$replacing productos ya están en tu carrito. Se sustituirán sus cantidades y notas por las que ves aquí.',
                      style: const TextStyle(color: AppColors.error),
                    ),
                  const SizedBox(height: 8),
                  const Text(
                    'Añadir al carrito no realiza una compra. Podrás revisar el total y el pago antes de confirmar.',
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Volver'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Añadir al carrito'),
            ),
          ],
        ),
      );
      if (approved != true || !mounted) return;
      _requireOwner();
      var added = 0;
      try {
        for (final row in available) {
          _requireOwner();
          await _api!.request(
            'POST',
            '/users/me/cart/items',
            body: {
              'productId': (row['product'] as Map)['id'],
              'quantity': row['quantity'],
              'notes': row['notes'],
            },
          );
          added++;
        }
      } catch (_) {
        _message(
          '$added productos confirmados en el carrito. Revisa el carrito antes de reintentar.',
        );
        rethrow;
      }
      _message('Productos añadidos al carrito con sus precios actuales.');
      if (mounted) {
        await Navigator.push(
          context,
          MaterialPageRoute<void>(builder: (_) => const CartScreen()),
        );
      }
    } catch (error) {
      if (mounted) setState(() => _actionError = error);
    } finally {
      if (mounted) {
        setState(() => _busy = null);
        _reload();
      }
    }
  }

  Future<void> _favoriteToCart(Map<String, dynamic> favorite) async {
    if (_busy != null) return;
    setState(() {
      _busy = favorite['id'] as String;
      _actionError = null;
    });
    try {
      _requireOwner();
      final product = await _api!.getObject(
        '/products/${favorite['productId']}',
      );
      if (product['isAvailable'] != true) {
        _message('Este producto no está disponible.');
        return;
      }
      final cart = await _api!.getAll('/users/me/cart/items');
      if (!mounted) return;
      final replacing = cart.any(
        (row) => row['productId'] == favorite['productId'],
      );
      final approved = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Añadir favorito al carrito'),
          content: Text(
            '1 × ${product['name']} · ${money(product['price'])}${(favorite['notes'] as String? ?? '').isEmpty ? '' : '\nNotas: ${favorite['notes']}'}${replacing ? '\nYa existe en tu carrito. Se sustituirá su cantidad por 1 y sus notas por las del favorito.' : ''}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Volver'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Añadir'),
            ),
          ],
        ),
      );
      if (approved != true) return;
      _requireOwner();
      await _api!.request(
        'POST',
        '/users/me/cart/items',
        body: {
          'productId': favorite['productId'],
          'quantity': 1,
          'notes': favorite['notes'] ?? '',
        },
      );
      _message('Producto guardado en el carrito.');
    } catch (error) {
      if (mounted) setState(() => _actionError = error);
    } finally {
      if (mounted) {
        setState(() => _busy = null);
        _reload();
      }
    }
  }

  Future<void> _removeFavorite(Map<String, dynamic> favorite) async {
    if (_busy != null) return;
    setState(() {
      _busy = favorite['id'] as String;
      _actionError = null;
    });
    try {
      _requireOwner();
      await _api!.request(
        'DELETE',
        '/users/me/favorites/${favorite['productId']}',
      );
    } catch (error) {
      if (mounted) setState(() => _actionError = error);
    } finally {
      if (mounted) {
        setState(() => _busy = null);
        _reload();
      }
    }
  }

  Future<void> _activeOrderActions(
    Map<String, dynamic> order,
    _ProfileData data,
  ) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text('Pedido #${order['orderNumber']}'),
              subtitle: Text(
                '${data.businessNames[order['businessId']] ?? ''} · ${statusLabel(order['status'])}',
              ),
            ),
            ListTile(
              leading: Icon(
                order['status'] == 'ready' ? Icons.qr_code : Icons.receipt_long,
              ),
              title: Text(
                order['status'] == 'ready'
                    ? 'Ver código de recogida'
                    : 'Ver pedido',
              ),
              onTap: () => Navigator.pop(sheetContext, 'details'),
            ),
            ListTile(
              leading: const Icon(Icons.chat_bubble_outline),
              title: const Text('Chat con Cocina'),
              onTap: () => Navigator.pop(sheetContext, 'chat'),
            ),
            if (order['status'] == 'pending')
              ListTile(
                leading: const Icon(Icons.cancel_outlined),
                title: const Text('Cancelar'),
                onTap: () => Navigator.pop(sheetContext, 'cancel'),
              ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (action == 'cancel') {
      await _cancel(order);
    } else if (action == 'chat') {
      await _openChat(order, data);
    } else if (action == 'details') {
      await Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => ShowQrScreen(orderId: order['id'] as String),
        ),
      );
    }
  }

  Future<void> _openChat(Map<String, dynamic> order, _ProfileData data) =>
      Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => StudentChatScreen(
            businessId: order['businessId'] as String,
            orderId: order['id'] as String,
            businessName: data.businessNames[order['businessId']],
          ),
        ),
      );

  Widget _orderTabs() => SizedBox(
    height: 74,
    child: DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFCED1D7), width: 2)),
      ),
      child: AnimatedBuilder(
        animation: _tabs,
        builder: (context, _) => Row(
          children: [
            for (final entry in const {
              0: 'Activos',
              1: 'Historial',
              2: 'Favoritos',
            }.entries)
              Expanded(
                child: Semantics(
                  button: true,
                  selected: _tabs.index == entry.key,
                  child: InkWell(
                    onTap: () => _tabs.animateTo(entry.key),
                    child: Column(
                      children: [
                        Expanded(
                          child: Align(
                            alignment: Alignment.bottomCenter,
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 18),
                              child: Text(
                                entry.value,
                                style: AppText.body.copyWith(
                                  fontSize: 16,
                                  color: _tabs.index == entry.key
                                      ? AppColors.primary
                                      : const Color(0xFF606169),
                                  fontWeight: _tabs.index == entry.key
                                      ? FontWeight.w600
                                      : FontWeight.w500,
                                ),
                              ),
                            ),
                          ),
                        ),
                        Container(
                          height: 3,
                          width: 60,
                          decoration: BoxDecoration(
                            color: _tabs.index == entry.key
                                ? AppColors.primary
                                : Colors.transparent,
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(2),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );

  Widget _orderCard(
    Map<String, dynamic> order,
    _ProfileData data, {
    required bool history,
  }) {
    if (!history) {
      return StudentOrderSummary(
        key: ValueKey('order-summary-${order['id']}'),
        order: order,
        onTap: _busy == null ? () => _activeOrderActions(order, data) : null,
      );
    }
    final status = order['status'] as String;
    final items = (order['items'] as List).cast<Map>();
    const phases = ['pending', 'accepted', 'preparing', 'ready'];
    final index = phases.indexOf(status);
    final color = status == 'cancelled'
        ? AppColors.error
        : status == 'ready' || status == 'completed'
        ? AppColors.success
        : AppColors.primary;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('Pedido #${order['orderNumber']}', style: AppText.h3),
                Chip(
                  label: Text(statusLabel(status)),
                  backgroundColor: color.withValues(alpha: .1),
                ),
              ],
            ),
            Text(
              data.businessNames[order['businessId']] ??
                  'Negocio no disponible',
              style: AppText.body.copyWith(fontWeight: FontWeight.w600),
            ),
            Text(dateText(order['createdAt']), style: AppText.notes),
            if (order['scheduledPickupTime'] != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'Recogida programada: ${dateText(order['scheduledPickupTime'])}',
                ),
              ),
            if (!history && index >= 0) ...[
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: (index + 1) / phases.length,
                minHeight: 5,
              ),
              const SizedBox(height: 6),
              const Text(
                'Recibido → Aceptado → En preparación → Listo',
                style: AppText.notes,
              ),
            ],
            const SizedBox(height: 12),
            ...items.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  '${item['quantity']} × ${item['name']}${(item['notes'] as String? ?? '').isEmpty ? '' : '\n${item['notes']}'}',
                ),
              ),
            ),
            const Divider(),
            Text(
              '${money(order['total'])} · ${paymentLabel(order['paymentMethod'])}',
              style: AppText.body.copyWith(fontWeight: FontWeight.w700),
            ),
            if (order['cancelNotes'] != null &&
                order['cancelNotes'].toString().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('Motivo de cancelación: ${order['cancelNotes']}'),
              ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _busy == null
                      ? () => Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) =>
                                ShowQrScreen(orderId: order['id'] as String),
                          ),
                        )
                      : null,
                  icon: Icon(
                    status == 'ready' ? Icons.qr_code : Icons.receipt_long,
                  ),
                  label: Text(
                    status == 'ready' ? 'Ver código de recogida' : 'Ver pedido',
                  ),
                ),
                if (!history && status == 'pending')
                  TextButton(
                    onPressed: _busy == null ? () => _cancel(order) : null,
                    child: const Text(
                      'Cancelar',
                      style: TextStyle(color: AppColors.error),
                    ),
                  ),
                if (history)
                  OutlinedButton(
                    onPressed: _busy == null ? () => _reorder(order) : null,
                    child: const Text('Volver a pedir'),
                  ),
                OutlinedButton.icon(
                  onPressed: _busy == null
                      ? () => _openChat(order, data)
                      : null,
                  icon: const Icon(Icons.chat_bubble_outline),
                  label: const Text('Chat con Cocina'),
                ),
                if (status == 'completed' && order['isRated'] != true)
                  FilledButton.icon(
                    onPressed: _busy == null
                        ? () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute<void>(
                                builder: (_) => RateOrderScreen(
                                  orderId: order['id'] as String,
                                ),
                              ),
                            );
                            _reload();
                          }
                        : null,
                    icon: const Icon(Icons.star_outline),
                    label: const Text('Calificar cafetería'),
                  ),
                if (status == 'completed')
                  OutlinedButton.icon(
                    onPressed: _busy == null
                        ? () => Navigator.push(
                            context,
                            MaterialPageRoute<void>(
                              builder: (_) => RateProductScreen(
                                orderId: order['id'] as String,
                              ),
                            ),
                          )
                        : null,
                    icon: const Icon(Icons.restaurant_outlined),
                    label: const Text('Calificar platillos'),
                  ),
                if (order['isRated'] == true)
                  const Chip(
                    label: Text('Calificado'),
                    avatar: Icon(Icons.star, size: 16),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _empty(String text, IconData icon) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 48),
    child: Column(
      children: [
        Icon(icon, size: 60, color: AppColors.primary),
        const SizedBox(height: 16),
        Text(text, style: AppText.h3, textAlign: TextAlign.center),
      ],
    ),
  );

  Widget _list(List<Widget> children) => ListView(
    padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
    physics: const AlwaysScrollableScrollPhysics(),
    children: children,
  );

  Widget _favorites(_ProfileData data) => _list([
    if (data.favorites.isEmpty)
      _empty('Todavía no tienes favoritos', Icons.favorite_border),
    ...data.favorites.map((favorite) {
      final product = favorite['product'] as Map?;
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
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
                      width: 70,
                      height: 70,
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
                          style: AppText.h3,
                        ),
                        if (product != null) Text(money(product['price'])),
                        if (favorite['available'] != true)
                          const Text(
                            'No disponible ahora',
                            style: TextStyle(color: AppColors.error),
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Quitar favorito',
                    onPressed: _busy == null
                        ? () => _removeFavorite(favorite)
                        : null,
                    icon: const Icon(Icons.favorite, color: AppColors.error),
                  ),
                ],
              ),
              if ((favorite['notes'] as String? ?? '').isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text('Notas: ${favorite['notes']}'),
                ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (product != null)
                    OutlinedButton(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => ProductDetailScreen(
                            productId: favorite['productId'] as String,
                          ),
                        ),
                      ),
                      child: const Text('Ver producto'),
                    ),
                  FilledButton(
                    onPressed: _busy == null && favorite['available'] == true
                        ? () => _favoriteToCart(favorite)
                        : null,
                    child: const Text('Añadir al carrito'),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }),
  ]);

  Widget _profile(_ProfileData data) {
    final user = data.user;
    return _list([
      Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(40),
                child: StudentImage(
                  url: user['avatarUrl'],
                  width: 80,
                  height: 80,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                user['displayName']?.toString() ?? 'Mi cuenta',
                style: AppText.h1,
              ),
              const SizedBox(height: 8),
              Text(user['email']?.toString() ?? '', style: AppText.body),
              const SizedBox(height: 8),
              Text(
                'Número de control: ${user['numeroDeControl']?.toString() ?? 'No disponible'}',
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  Chip(
                    label: Text(
                      user['emailVerified'] == true
                          ? 'Correo verificado'
                          : 'Correo por verificar',
                    ),
                  ),
                  Chip(
                    label: Text(
                      user['institutionalVerifiedAt'] != null
                          ? 'Identidad institucional validada'
                          : 'Validación institucional pendiente',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Text(
                'Tus datos académicos se verifican con el padrón de la institución.',
                style: AppText.notes,
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 16),
      Card(
        child: ListTile(
          leading: const Icon(Icons.receipt_long_outlined),
          title: const Text('Historial de consumo'),
          subtitle: const Text('Consulta tus pedidos y califica tu comida'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) => const ProfileOrdersScreen(initialTab: 1),
            ),
          ),
        ),
      ),
      const Card(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Tu opinión importa', style: AppText.h3),
              SizedBox(height: 8),
              Text(
                'Desde el historial de pedidos entregados puedes calificar los platillos y la cafetería por separado.',
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 16),
      const StudentPushNotificationsCard(),
      const SizedBox(height: 16),
      Card(
        child: ListTile(
          leading: const Icon(Icons.forum_outlined),
          title: const Text('Mis conversaciones'),
          subtitle: const Text('Consulta tus mensajes con Cocina'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute<void>(builder: (_) => const StudentChatScreen()),
          ),
        ),
      ),
      OutlinedButton.icon(
        onPressed: _busy == null
            ? () async {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (dialogContext) => AlertDialog(
                    title: const Text('Cerrar sesión'),
                    content: const Text(
                      '¿Quieres salir de tu cuenta de alumno?',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(dialogContext, false),
                        child: const Text('Cancelar'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(dialogContext, true),
                        child: const Text('Cerrar sesión'),
                      ),
                    ],
                  ),
                );
                if (confirmed != true || !mounted) return;
                try {
                  await _api!.logout();
                } catch (error) {
                  if (mounted) setState(() => _actionError = error);
                }
              }
            : null,
        icon: const Icon(Icons.logout),
        label: const Text('Cerrar sesión'),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.background,
    appBar: AppBar(
      toolbarHeight: 56,
      title: widget.embedded && widget.initialTab < 2
          ? null
          : Text(
              widget.initialTab == 2
                  ? 'Mis favoritos'
                  : widget.initialTab == 3
                  ? 'Mi perfil'
                  : 'Mis pedidos',
            ),
      automaticallyImplyLeading: !widget.embedded,
      backgroundColor: widget.initialTab < 2
          ? AppColors.background
          : AppColors.componentBase,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      bottom: widget.initialTab < 2
          ? PreferredSize(
              preferredSize: const Size.fromHeight(74),
              child: _orderTabs(),
            )
          : widget.embedded
          ? null
          : TabBar(
              controller: _tabs,
              isScrollable: true,
              labelColor: AppColors.primary,
              indicatorColor: AppColors.primary,
              tabs: const [
                Tab(text: 'Activos'),
                Tab(text: 'Historial'),
                Tab(text: 'Favoritos'),
                Tab(text: 'Perfil'),
              ],
            ),
    ),
    body: Column(
      children: [
        if (_busy != null) const LinearProgressIndicator(),
        if (_actionError != null)
          Material(
            color: AppColors.error.withValues(alpha: .08),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(child: Text(friendlyError(_actionError!))),
                  IconButton(
                    tooltip: 'Cerrar aviso',
                    onPressed: () => setState(() => _actionError = null),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
          ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async {
              final next = _load();
              setState(() {
                _future = next;
              });
              try {
                await next;
              } catch (_) {
                /* FutureBuilder displays the error. */
              }
            },
            child: FutureBuilder<_ProfileData>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return _list([
                    ErrorPanel(error: snapshot.error!, onRetry: _reload),
                  ]);
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final data = snapshot.data!;
                if (data.user['id'] != _api!.user?['id']) {
                  return const Center(
                    child: Text(
                      'Tu sesión cambió. Vuelve a abrir tus pedidos.',
                    ),
                  );
                }
                final history = <String, Map<String, dynamic>>{
                  for (final row in [...data.history, ..._extraHistory])
                    row['id'] as String: row,
                }.values.toList();
                return Column(
                  children: [
                    if (snapshot.connectionState == ConnectionState.waiting)
                      const LinearProgressIndicator(),
                    Expanded(
                      child: TabBarView(
                        controller: _tabs,
                        physics: widget.embedded
                            ? const NeverScrollableScrollPhysics()
                            : null,
                        children: [
                          _list([
                            if (data.active.isEmpty)
                              _empty(
                                'No tienes pedidos activos',
                                Icons.receipt_long_outlined,
                              ),
                            ...data.active.map(
                              (row) => _orderCard(row, data, history: false),
                            ),
                          ]),
                          _list([
                            if (history.isEmpty)
                              _empty(
                                'Tu historial aparecerá aquí',
                                Icons.history,
                              ),
                            ...history.map(
                              (row) => _orderCard(row, data, history: true),
                            ),
                            if (_moreError != null)
                              ErrorPanel(error: _moreError!, onRetry: _more),
                            if (_historyPage < data.historyPages)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                ),
                                child: OutlinedButton(
                                  onPressed: _loadingMore ? null : _more,
                                  child: Text(
                                    _loadingMore
                                        ? 'Cargando…'
                                        : 'Cargar más pedidos',
                                  ),
                                ),
                              ),
                          ]),
                          _favorites(data),
                          _profile(data),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ],
    ),
  );

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }
}
