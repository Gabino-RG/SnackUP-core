import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'business_order_workflow.dart';
import 'package:snackup/theme/app_colors.dart';
import 'package:snackup/theme/app_text.dart';

class OrderDetailScreen extends StatefulWidget {
  final String orderId;
  final String businessId;
  const OrderDetailScreen({
    super.key,
    required this.orderId,
    required this.businessId,
  });

  @override
  State<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends State<OrderDetailScreen> {
  bool _updating = false;
  DocumentReference<Map<String, dynamic>> get _orderRef =>
      FirebaseFirestore.instance.collection('orders').doc(widget.orderId);

  void _showMessage(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? AppColors.error : AppColors.success,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _updateOrderStatus(
    String newStatus, {
    String? deliveryCode,
  }) async {
    if (_updating) return;
    setState(() => _updating = true);
    try {
      final firestore = FirebaseFirestore.instance;
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) throw StateError('Inicia sesión de nuevo.');
      await firestore.runTransaction((transaction) async {
        final snapshot = await transaction.get(_orderRef);
        final order = snapshot.data();
        if (order == null || order['businessId'] != widget.businessId) {
          throw StateError('El pedido no pertenece a este negocio.');
        }
        final business = await transaction.get(
          firestore.collection('businesses').doc(widget.businessId),
        );
        if (business.data()?['ownerId'] != uid) {
          throw StateError('Tu cuenta no administra este negocio.');
        }
        validateBusinessOrderTransition(
          orderId: widget.orderId,
          order: order,
          newStatus: newStatus,
          deliveryCode: deliveryCode,
        );
        if (newStatus == 'preparing') {
          final quantities = stockQuantitiesForOrder(order);
          final remainingStock =
              <DocumentReference<Map<String, dynamic>>, int>{};
          for (final entry in quantities.entries) {
            final reference = firestore.collection('products').doc(entry.key);
            final snapshot = await transaction.get(reference);
            final product = snapshot.data();
            final stock = product?['stock'];
            if (product == null ||
                product['businessId'] != widget.businessId ||
                product['isAvailable'] != true ||
                stock is! int ||
                stock < entry.value) {
              throw StateError(
                'No hay stock disponible para todos los productos. Ajusta el menú o cancela este pedido.',
              );
            }
            remainingStock[reference] = stock - entry.value;
          }
          // Firestore transactions require every read before the first write.
          for (final entry in remainingStock.entries) {
            transaction.update(entry.key, {
              'stock': entry.value,
              'updatedAt': FieldValue.serverTimestamp(),
            });
          }
        }
        transaction.update(_orderRef, {
          'status': newStatus,
          if (newStatus == 'preparing') 'stockReserved': true,
          'updatedAt': FieldValue.serverTimestamp(),
          if (newStatus == 'completed')
            'completedAt': FieldValue.serverTimestamp(),
          if (newStatus == 'cancelled')
            'cancelledAt': FieldValue.serverTimestamp(),
        });
      });
      if (!mounted) return;
      _showMessage('Pedido ${_getStatusText(newStatus).toLowerCase()}.');
      if ((newStatus == 'completed' || newStatus == 'cancelled') &&
          Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    } catch (error) {
      _showMessage(
        error is StateError
            ? error.message.toString()
            : 'No se pudo actualizar el pedido. Revisa tu conexión y permisos.',
        error: true,
      );
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }

  Future<void> _confirmCancellation() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Cancelar pedido'),
        content: const Text(
          'El alumno verá el pedido como cancelado. El inventario reservado no se repone automáticamente: ajusta el stock si los alimentos aún pueden venderse. Si ya hubo un cobro, gestiona la devolución con el alumno.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Volver'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Cancelar pedido'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) await _updateOrderStatus('cancelled');
  }

  Future<void> _startScanner(BuildContext context, String expectedCode) async {
    final captured = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const _DeliveryScannerScreen()),
    );
    if (!mounted || captured == null) return;
    if (captured.trim() != expectedCode) {
      _showMessage(
        'QR incorrecto. Abre el código de este pedido en la app del alumno.',
        error: true,
      );
      return;
    }
    await _updateOrderStatus('completed', deliveryCode: captured.trim());
  }

  Future<void> _showManualInputDialog(String expectedCode) async {
    final entered = await showDialog<String>(
      context: context,
      builder: (_) => const _DeliveryCodeDialog(),
    );
    if (!mounted || entered == null) return;
    if (entered.isEmpty || entered != expectedCode) {
      _showMessage('Código de entrega incorrecto.', error: true);
      return;
    }
    await _updateOrderStatus('completed', deliveryCode: entered);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Detalle del Pedido',
          style: AppText.h3.copyWith(
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        backgroundColor: AppColors.background,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: _orderRef.snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            );
          }
          if (snapshot.hasError) {
            return const Center(
              child: Text(
                'No se pudo cargar el pedido. Revisa tu conexión y permisos.',
              ),
            );
          }
          if (!snapshot.hasData || !snapshot.data!.exists) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.error_outline_rounded,
                    size: 64,
                    color: AppColors.error.withOpacity(0.7),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Pedido no encontrado',
                    style: AppText.h3.copyWith(color: AppColors.textPrimary),
                  ),
                ],
              ),
            );
          }

          final order = snapshot.data!.data() as Map<String, dynamic>;
          if (order['businessId'] != widget.businessId) {
            return const Center(
              child: Text('Este pedido no pertenece a tu negocio.'),
            );
          }
          final String status = order['status'] ?? 'pending';
          final String numeroDeControl =
              order['userNumeroDeControl'] ?? 'Sin registrar';
          final List<dynamic> items = order['items'] ?? [];
          final Timestamp? timestamp = order['createdAt'];
          final DateTime? orderTime = timestamp?.toDate();

          return Column(
            children: [
              // HEADER CON ESTADO
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: _getStatusColor(status).withOpacity(0.1),
                  border: Border(
                    bottom: BorderSide(color: AppColors.borders, width: 1),
                  ),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Pedido #${widget.orderId.substring(0, 8)}',
                          style: AppText.h3.copyWith(
                            color: AppColors.textPrimary,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: _getStatusColor(status),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            _getStatusText(status),
                            style: AppText.notes.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (orderTime != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        '${orderTime.hour.toString().padLeft(2, '0')}:${orderTime.minute.toString().padLeft(2, '0')} - ${orderTime.day}/${orderTime.month}/${orderTime.year}',
                        style: AppText.notes.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // INFORMACIÓN DEL CLIENTE
                      _buildInfoSection(
                        title: 'Información del Cliente',
                        children: [
                          _buildInfoRow(
                            icon: Icons.person_rounded,
                            label: 'Nombre',
                            value: order['userDisplayName'] ?? 'N/A',
                          ),
                          _buildInfoRow(
                            icon: Icons.badge_rounded,
                            label: 'No. Control',
                            value: numeroDeControl,
                          ),
                          _buildInfoRow(
                            icon: Icons.payment_rounded,
                            label: 'Método de Pago',
                            value: order['paymentMethod'] ?? 'N/A',
                          ),
                        ],
                      ),

                      const SizedBox(height: 24),

                      // PRODUCTOS
                      _buildInfoSection(
                        title: 'Productos',
                        children: [
                          ...items
                              .map((item) => _buildProductItem(item))
                              .toList(),
                        ],
                      ),

                      const SizedBox(height: 24),

                      // TOTAL
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.componentBase,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Total:',
                              style: AppText.h3.copyWith(
                                color: AppColors.textPrimary,
                              ),
                            ),
                            Text(
                              '\$${(order['totalPrice'] ?? 0.0).toStringAsFixed(2)}',
                              style: AppText.h1.copyWith(
                                color: AppColors.success,
                                fontSize: 24,
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 32),

                      // BOTONES DE ACCIÓN
                      _buildActionButtons(
                        status,
                        deliveryCodeForOrder(widget.orderId, order),
                        deliveryQrForOrder(widget.orderId, order),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildInfoSection({
    required String title,
    required List<Widget> children,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: AppText.h3.copyWith(
            color: AppColors.textPrimary,
            fontSize: 18,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.componentBase,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(children: children),
        ),
      ],
    );
  }

  Widget _buildInfoRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppColors.textSecondary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: AppText.body.copyWith(
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              value,
              style: AppText.body.copyWith(color: AppColors.textSecondary),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProductItem(dynamic item) {
    final String notes = item['notes'] ?? '';
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borders),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              '${item['quantity']}x',
              style: AppText.body.copyWith(
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item['name'] ?? 'Producto',
                  style: AppText.body.copyWith(
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                if (notes.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    notes,
                    style: AppText.notes.copyWith(
                      color: AppColors.error,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Text(
            '\$${(item['price'] ?? 0.0).toStringAsFixed(2)}',
            style: AppText.body.copyWith(
              fontWeight: FontWeight.w600,
              color: AppColors.success,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(
    String status,
    String numeroDeControl,
    String qrPayload,
  ) {
    if (status == 'pending') {
      return Column(
        children: [
          ElevatedButton(
            onPressed: _updating ? null : () => _updateOrderStatus('preparing'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 56),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.check_circle_rounded, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Aceptar Pedido',
                  style: AppText.body.copyWith(
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: _updating ? null : _confirmCancellation,
            child: Text(
              'Cancelar Pedido',
              style: AppText.body.copyWith(
                color: AppColors.error,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      );
    }

    if (status == 'preparing') {
      return Column(
        children: [
          ElevatedButton(
            onPressed: _updating ? null : () => _updateOrderStatus('ready'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.warning,
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 56),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.restaurant_rounded, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Marcar como Listo',
                  style: AppText.body.copyWith(
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: _updating ? null : _confirmCancellation,
            child: Text(
              'Cancelar Pedido',
              style: AppText.body.copyWith(
                color: AppColors.error,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      );
    }

    if (status == 'ready') {
      return Column(
        children: [
          ElevatedButton(
            onPressed: _updating
                ? null
                : () => _startScanner(context, qrPayload),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.success,
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 56),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.qr_code_scanner_rounded, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Escanear QR para Entregar',
                  style: AppText.body.copyWith(
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: _updating
                ? null
                : () => _showManualInputDialog(numeroDeControl),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.textSecondary,
              minimumSize: const Size(double.infinity, 56),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              side: BorderSide(color: AppColors.borders),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.keyboard_alt_rounded, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Entrega Manual',
                  style: AppText.body.copyWith(
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.componentBase,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline_rounded, color: AppColors.tertiary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              status == 'completed'
                  ? 'Pedido completado y entregado'
                  : 'Pedido cancelado',
              style: AppText.body.copyWith(color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'pending':
        return AppColors.warning;
      case 'preparing':
        return AppColors.tertiary;
      case 'ready':
        return AppColors.primary;
      case 'completed':
        return AppColors.success;
      case 'cancelled':
        return AppColors.error;
      default:
        return AppColors.textSecondary;
    }
  }

  String _getStatusText(String status) {
    switch (status) {
      case 'pending':
        return 'PENDIENTE';
      case 'preparing':
        return 'PREPARANDO';
      case 'ready':
        return 'LISTO';
      case 'completed':
        return 'COMPLETADO';
      case 'cancelled':
        return 'CANCELADO';
      default:
        return status.toUpperCase();
    }
  }
}

class _DeliveryScannerScreen extends StatefulWidget {
  const _DeliveryScannerScreen();

  @override
  State<_DeliveryScannerScreen> createState() => _DeliveryScannerScreenState();
}

class _DeliveryScannerScreenState extends State<_DeliveryScannerScreen> {
  final _controller = MobileScannerController(
    formats: [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  bool _captured = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Escanear QR de entrega')),
    body: Column(
      children: [
        Expanded(
          child: MobileScanner(
            controller: _controller,
            errorBuilder: (context, error) => const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No se pudo acceder a la cámara. Habilita su permiso o vuelve y usa Entrega Manual.',
                ),
              ),
            ),
            onDetect: (capture) {
              if (_captured || !mounted) return;
              for (final barcode in capture.barcodes) {
                final value = barcode.rawValue;
                if (value == null || value.trim().isEmpty) continue;
                _captured = true;
                Navigator.of(context).pop(value);
                break;
              }
            },
          ),
        ),
        const Padding(
          padding: EdgeInsets.all(20),
          child: Text('Escanea el QR de este pedido en la app del alumno.'),
        ),
      ],
    ),
  );
}

class _DeliveryCodeDialog extends StatefulWidget {
  const _DeliveryCodeDialog();
  @override
  State<_DeliveryCodeDialog> createState() => _DeliveryCodeDialogState();
}

class _DeliveryCodeDialogState extends State<_DeliveryCodeDialog> {
  final _controller = TextEditingController();
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Confirmar entrega'),
    content: TextField(
      controller: _controller,
      autofocus: true,
      decoration: const InputDecoration(
        labelText: 'Código de entrega del pedido',
        helperText: 'Pide al alumno el código que aparece junto a su QR.',
        helperMaxLines: 3,
      ),
      onSubmitted: (value) => Navigator.pop(context, value.trim()),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, _controller.text.trim()),
        child: const Text('Confirmar'),
      ),
    ],
  );
}
