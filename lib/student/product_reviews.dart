import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'student_api.dart';
import 'student_widgets.dart';

class PublicProductReviews extends StatefulWidget {
  const PublicProductReviews({super.key, required this.productId});
  final String productId;
  @override
  State<PublicProductReviews> createState() => _PublicProductReviewsState();
}

class _PublicProductReviewsState extends State<PublicProductReviews> {
  StudentApi? _api;
  int _revision = -1;
  int _page = 1;
  Future<Map<String, dynamic>>? _future;

  Future<Map<String, dynamic>> _load() => _api!.getObject(
    '/products/${Uri.encodeComponent(widget.productId)}/reviews',
    query: {'page': '$_page', 'limit': '5'},
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final api = context.watch<StudentApi>();
    if (api != _api || api.revision != _revision) {
      _api = api;
      _revision = api.revision;
      _page = 1;
      _future = _load();
    }
  }

  void _go(int page) => setState(() {
    _page = page;
    _future = _load();
  });

  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, dynamic>>(
    future: _future,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return const Padding(
          padding: EdgeInsets.all(16),
          child: LinearProgressIndicator(),
        );
      }
      if (snapshot.hasError) {
        return Column(
          children: [
            Text(friendlyError(snapshot.error!)),
            TextButton(
              onPressed: () => _go(_page),
              child: const Text('Reintentar reseñas'),
            ),
          ],
        );
      }
      final data = snapshot.data!;
      final rows = (data['data'] as List).cast<Map>();
      final pages = (data['pagination'] as Map)['totalPages'] as int;
      if (rows.isEmpty) {
        return const Padding(
          padding: EdgeInsets.all(16),
          child: Text('Aún no hay reseñas de este platillo.'),
        );
      }
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final row in rows) ...[
              Text(
                '★ ${row['rating']}/5 · ${dateText(row['createdAt'])}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              if ((row['comment'] as String? ?? '').isNotEmpty)
                Text(row['comment'] as String),
              const Divider(height: 24),
            ],
            if (pages > 1)
              Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  TextButton(
                    onPressed: _page > 1 ? () => _go(_page - 1) : null,
                    child: const Text('Anteriores'),
                  ),
                  Text('$_page / $pages'),
                  TextButton(
                    onPressed: _page < pages ? () => _go(_page + 1) : null,
                    child: const Text('Siguientes'),
                  ),
                ],
              ),
          ],
        ),
      );
    },
  );
}

class RateProductScreen extends StatefulWidget {
  const RateProductScreen({super.key, required this.orderId});
  final String orderId;
  @override
  State<RateProductScreen> createState() => _RateProductScreenState();
}

class _RateProductScreenState extends State<RateProductScreen> {
  final _comment = TextEditingController();
  final _reviewed = <String>{};
  StudentApi? _api;
  String? _owner;
  int _revision = -1;
  Future<Map<String, dynamic>>? _future;
  String? _product;
  int? _rating;
  bool _busy = false;
  Object? _error;
  String? _notice;

  Future<Map<String, dynamic>> _load() async {
    if (_owner == null || _owner != _api!.user?['id']) {
      throw const ApiException(
        401,
        'SESSION_CHANGED',
        'Tu sesión cambió. Vuelve a abrir el pedido.',
      );
    }
    final order = await _api!.getObject(
      '/orders/${Uri.encodeComponent(widget.orderId)}',
    );
    if (_owner != _api!.user?['id'] || order['userId'] != _owner) {
      throw const ApiException(
        403,
        'NOT_OWN_ORDER',
        'Este pedido no pertenece a tu cuenta.',
      );
    }
    return order;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final api = context.watch<StudentApi>();
    _owner ??= api.user?['id'] as String?;
    if (api != _api || api.revision != _revision) {
      _api = api;
      _revision = api.revision;
      _future = _load();
    }
  }

  void _reload() => setState(() {
    _future = _load();
  });

  void _done(String product, String notice) {
    _reviewed.add(product);
    _product = null;
    _rating = null;
    _comment.clear();
    _notice = notice;
  }

  Future<void> _save() async {
    if (_busy || _product == null || _rating == null) return;
    final product = _product!;
    final rating = _rating!;
    final comment = _comment.text.trim();
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      final order = await _load();
      if (order['status'] != 'completed') {
        throw const ApiException(
          409,
          'ORDER_NOT_COMPLETED',
          'Solo puedes evaluar pedidos entregados.',
        );
      }
      if (!(order['items'] as List).any(
        (item) => item['productId'] == product,
      )) {
        throw const ApiException(
          422,
          'PRODUCT_NOT_PURCHASED',
          'El platillo no pertenece a este pedido.',
        );
      }
      await _api!.request(
        'POST',
        '/orders/${Uri.encodeComponent(widget.orderId)}/reviews',
        body: {
          'reviews': [
            {'productId': product, 'rating': rating, 'comment': comment},
          ],
        },
      );
      if (mounted && _owner == _api!.user?['id']) {
        setState(
          () => _done(
            product,
            '¡Gracias! Tu reseña del platillo quedó guardada.',
          ),
        );
      }
    } catch (error) {
      if (mounted && _owner == _api!.user?['id']) {
        setState(() {
          if (error is ApiException && error.code == 'REVIEW_EXISTS') {
            _done(
              product,
              'Este platillo ya tenía una reseña tuya en este pedido.',
            );
          } else {
            _error = error;
          }
        });
        _reload();
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _form(Map<String, dynamic> order) {
    if (_owner != _api!.user?['id'] || order['userId'] != _owner) {
      return const Center(child: Text('Este pedido no pertenece a tu cuenta.'));
    }
    if (order['status'] != 'completed') {
      return const Center(
        child: Text(
          'Podrás calificar tus platillos cuando el pedido sea entregado.',
        ),
      );
    }
    final items = <String, String>{};
    for (final item in (order['items'] as List).cast<Map>()) {
      if (!_reviewed.contains(item['productId'])) {
        items[item['productId'] as String] = item['name'] as String;
      }
    }
    final selection = items.containsKey(_product) ? _product : null;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Pedido #${order['orderNumber']}',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Califica cada platillo que recibiste. Tu puntuación y comentario se muestran sin tu nombre ni matrícula.',
                ),
                const SizedBox(height: 20),
                if (_notice != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Text(_notice!),
                  ),
                if (items.isEmpty)
                  const Text(
                    'Gracias por compartir tu opinión sobre estos platillos.',
                  )
                else ...[
                  DropdownButtonFormField<String>(
                    key: ValueKey('review-product-$selection-${items.length}'),
                    value: selection,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Platillo de tu pedido',
                    ),
                    items: [
                      for (final item in items.entries)
                        DropdownMenuItem(
                          value: item.key,
                          child: Text(
                            item.value,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: _busy
                        ? null
                        : (value) => setState(() => _product = value),
                  ),
                  const SizedBox(height: 20),
                  const Text('Calificación de 0 a 5 estrellas'),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: List.generate(
                      6,
                      (value) => ChoiceChip(
                        key: ValueKey('product-rating-$value'),
                        label: Text('$value ★'),
                        selected: _rating == value,
                        onSelected: _busy
                            ? null
                            : (_) => setState(() => _rating = value),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _comment,
                    enabled: !_busy,
                    maxLength: 2000,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Comentario sobre el platillo (opcional)',
                    ),
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(friendlyError(_error!)),
                    ),
                  FilledButton(
                    key: const ValueKey('submit-product-review'),
                    onPressed: _busy || selection == null || _rating == null
                        ? null
                        : _save,
                    child: Text(
                      _busy ? 'Enviando…' : 'Enviar reseña del platillo',
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Calificar platillos')),
    body: FutureBuilder<Map<String, dynamic>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return ErrorPanel(error: snapshot.error!, onRetry: _reload);
        }
        if (snapshot.connectionState != ConnectionState.done ||
            !snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        return _form(snapshot.data!);
      },
    ),
  );

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }
}
