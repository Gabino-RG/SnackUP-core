import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:snackup/student/student_api.dart';
import 'package:snackup/student/student_widgets.dart';
import 'package:snackup/theme/student_colors.dart';
import 'package:snackup/theme/student_text.dart';

import 'rate_order_screen.dart';
import 'student_chat_screen.dart';
import 'package:snackup/student/product_reviews.dart';

class ShowQrScreen extends StatefulWidget {
  final String orderId;
  const ShowQrScreen({super.key, required this.orderId});

  @override
  State<ShowQrScreen> createState() => _ShowQrScreenState();
}

class _ShowQrScreenState extends State<ShowQrScreen> {
  StudentApi? _api;
  String? _ownerId;
  int _revision = -1;
  Future<Map<String, dynamic>>? _future;

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

  Future<Map<String, dynamic>> _load() async {
    final user = _ownerId;
    if (user != _api!.user?['id']) {
      throw const ApiException(
        401,
        'SESSION_CHANGED',
        'Tu sesión cambió. Vuelve a abrir tu pedido.',
      );
    }
    final order = await _api!.getObject('/orders/${widget.orderId}');
    if (user == null || user != _api!.user?['id'] || order['userId'] != user) {
      throw const ApiException(
        403,
        'NOT_OWN_ORDER',
        'Este pedido no pertenece a tu cuenta.',
      );
    }
    return order;
  }

  void _reload() => setState(() {
    _future = _load();
  });

  String _explanation(String status) => switch (status) {
    'pending' => 'El negocio recibió tu solicitud y todavía debe aceptarla.',
    'accepted' =>
      'El negocio aceptó tu pedido. Pronto comenzará su preparación.',
    'preparing' =>
      'El negocio está preparando tu comida. Te avisaremos cuando esté lista.',
    'ready' =>
      'Tu pedido está listo. Muestra este código únicamente al personal del negocio al recogerlo.',
    'completed' => 'Este pedido ya fue entregado. Gracias por usar SnackUP.',
    'cancelled' =>
      'Este pedido fue cancelado y su código ya no puede usarse para recoger.',
    _ => 'Actualiza para consultar el estado más reciente de tu pedido.',
  };

  Widget _content(Map<String, dynamic> order) {
    // Recheck in the render path as well: a provider account change must never
    // keep the previous account's pickup secret visible during the next GET.
    if (_ownerId != _api!.user?['id'] || order['userId'] != _ownerId) {
      return const Center(child: Text('Este pedido no pertenece a tu cuenta.'));
    }
    final status = order['status'] as String;
    final ready = status == 'ready';
    final code = order['pickupCode'] as String?;
    final items = (order['items'] as List).cast<Map>();
    final color = status == 'cancelled'
        ? AppColors.error
        : ready || status == 'completed'
        ? AppColors.success
        : AppColors.primary;
    return ListView(
      padding: const EdgeInsets.all(20),
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Pedido #${order['orderNumber']}', style: AppText.h1),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Chip(
                    avatar: Icon(
                      ready ? Icons.check_circle_outline : Icons.receipt_long,
                      size: 18,
                      color: color,
                    ),
                    label: Text(statusLabel(status)),
                    backgroundColor: color.withValues(alpha: .1),
                  ),
                ),
                const SizedBox(height: 12),
                Text(_explanation(status), style: AppText.body),
                if (order['scheduledPickupTime'] != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(
                      'Recogida programada: ${dateText(order['scheduledPickupTime'])}',
                    ),
                  ),
                const SizedBox(height: 24),
                if (ready && code != null && code.isNotEmpty)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        children: [
                          const Text('Código de recogida', style: AppText.h3),
                          const SizedBox(height: 16),
                          LayoutBuilder(
                            builder: (context, constraints) => QrImageView(
                              data: code,
                              version: QrVersions.auto,
                              size: math.min(220.0, constraints.maxWidth),
                              backgroundColor: Colors.white,
                              eyeStyle: const QrEyeStyle(
                                eyeShape: QrEyeShape.square,
                                color: AppColors.primary,
                              ),
                              dataModuleStyle: const QrDataModuleStyle(
                                dataModuleShape: QrDataModuleShape.square,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          SelectableText(
                            code,
                            key: const ValueKey('pickup-code'),
                            textAlign: TextAlign.center,
                            style: AppText.h1.copyWith(
                              fontSize: 32,
                              letterSpacing: 4,
                              color: AppColors.primary,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Si el lector no funciona, el personal puede introducir este mismo código.',
                            style: AppText.notes,
                            textAlign: TextAlign.center,
                          ),
                          TextButton.icon(
                            onPressed: () async {
                              await Clipboard.setData(
                                ClipboardData(text: code),
                              );
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Código de recogida copiado.',
                                    ),
                                  ),
                                );
                              }
                            },
                            icon: const Icon(Icons.copy),
                            label: const Text('Copiar código'),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (ready && (code == null || code.isEmpty))
                  ErrorPanel(
                    error: const ApiException(
                      409,
                      'MISSING_PICKUP_CODE',
                      'No recibimos el código de este pedido. Actualiza antes de recogerlo.',
                    ),
                    onRetry: _reload,
                  ),
                if (!ready && !['completed', 'cancelled'].contains(status))
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(20),
                      child: Row(
                        children: [
                          Icon(
                            Icons.schedule,
                            color: AppColors.primary,
                            size: 32,
                          ),
                          SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'El código se mostrará cuando tu pedido esté listo.',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 20),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Resumen del pedido', style: AppText.h3),
                        const SizedBox(height: 16),
                        ...items.map(
                          (item) => Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('${item['quantity']} × ${item['name']}'),
                                if ((item['notes'] as String? ?? '').isNotEmpty)
                                  Text(
                                    item['notes'].toString(),
                                    style: AppText.notes,
                                  ),
                                Text(
                                  money(
                                    (item['price'] as num) *
                                        (item['quantity'] as num),
                                  ),
                                  style: AppText.notes,
                                ),
                              ],
                            ),
                          ),
                        ),
                        const Divider(),
                        Text(
                          'Total: ${money(order['total'])}',
                          style: AppText.h3,
                        ),
                        const SizedBox(height: 8),
                        Text('Forma de pago: ${order['paymentMethod']}'),
                        Text(
                          order['paymentStatus'] == 'pay_at_pickup'
                              ? 'Pago al recoger'
                              : 'Confirma el pago con el negocio',
                          style: AppText.notes,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Creado: ${dateText(order['createdAt'])}',
                          style: AppText.notes,
                        ),
                        if (order['cancelNotes'] != null &&
                            order['cancelNotes'].toString().isNotEmpty)
                          Text(
                            'Motivo de cancelación: ${order['cancelNotes']}',
                          ),
                      ],
                    ),
                  ),
                ),
                if (status == 'completed' && order['isRated'] != true)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: FilledButton.icon(
                      onPressed: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) =>
                                RateOrderScreen(orderId: widget.orderId),
                          ),
                        );
                        if (mounted) _reload();
                      },
                      icon: const Icon(Icons.star_outline),
                      label: const Text('Calificar cafetería'),
                    ),
                  ),
                if (status == 'completed')
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              RateProductScreen(orderId: widget.orderId),
                        ),
                      ),
                      icon: const Icon(Icons.restaurant_outlined),
                      label: const Text('Calificar platillos'),
                    ),
                  ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => StudentChatScreen(
                        businessId: order['businessId'] as String,
                        orderId: widget.orderId,
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.chat_bubble_outline),
                  label: const Text('Chat con Cocina'),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _reload,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Actualizar estado'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.componentBase,
    appBar: AppBar(
      title: const Text('Mi pedido'),
      backgroundColor: AppColors.background,
    ),
    body: RefreshIndicator(
      onRefresh: () async {
        final next = _load();
        setState(() {
          _future = next;
        });
        try {
          await next;
        } catch (_) {
          /* The error remains visible with retry. */
        }
      },
      child: FutureBuilder<Map<String, dynamic>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [ErrorPanel(error: snapshot.error!, onRetry: _reload)],
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          return Column(
            children: [
              if (snapshot.connectionState == ConnectionState.waiting)
                const LinearProgressIndicator(),
              Expanded(child: _content(snapshot.data!)),
            ],
          );
        },
      ),
    ),
  );
}
