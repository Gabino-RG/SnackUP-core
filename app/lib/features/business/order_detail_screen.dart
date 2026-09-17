import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../auth/auth_gate.dart';
import 'package:snackup/theme/app_colors.dart';
import 'package:snackup/theme/app_text.dart';

class OrderDetailScreen extends StatefulWidget {
  final String orderId;
  const OrderDetailScreen({super.key, required this.orderId});

  @override
  State<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends State<OrderDetailScreen> {
  DocumentReference get _orderRef =>
      FirebaseFirestore.instance.collection('orders').doc(widget.orderId);

  Future<void> _updateOrderStatus(String newStatus) async {
    try {
      await _orderRef.update({'status': newStatus});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Pedido marcado como "$newStatus"'),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
        if (newStatus == 'completed' || newStatus == 'cancelled') {
          await Future.delayed(const Duration(milliseconds: 500));
          if (mounted && Navigator.of(context).canPop()) {
            Navigator.of(context).pop();
          }
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al actualizar: ${e.toString()}'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
  }

  void _startScanner(BuildContext context, String numeroDeControlCorrecto) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (scannerContext) => Scaffold(
          appBar: AppBar(
            title: const Text('Escanear QR de Entrega'),
            backgroundColor: AppColors.background,
            foregroundColor: AppColors.textPrimary,
          ),
          body: Column(
            children: [
              Expanded(
                child: MobileScanner(
                  controller: MobileScannerController(
                    formats: [BarcodeFormat.qrCode],
                    detectionSpeed: DetectionSpeed.normal,
                  ),
                  onDetect: (capture) {
                    final List<Barcode> barcodes = capture.barcodes;
                    if (barcodes.isNotEmpty) {
                      final String qrValue = barcodes.first.rawValue ?? '';
                      
                      if (qrValue == numeroDeControlCorrecto) {
                        _updateOrderStatus('completed');
                        if (Navigator.of(scannerContext).canPop()) {
                          Navigator.of(scannerContext).pop();
                        }
                      } else {
                        if (Navigator.of(scannerContext).canPop()){
                          Navigator.of(scannerContext).pop();
                        }
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: const Text('QR incorrecto. Este no es el pedido.'),
                            backgroundColor: AppColors.error,
                            behavior: SnackBarBehavior.floating,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        );
                      }
                    }
                  },
                ),
              ),
              Container(
                padding: const EdgeInsets.all(20),
                color: AppColors.background,
                child: Text(
                  'Escanea el código QR del estudiante para confirmar la entrega',
                  style: AppText.body.copyWith(
                    color: AppColors.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showManualInputDialog(String numeroDeControlCorrecto) {
    final TextEditingController manualInputController = TextEditingController();
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          'Confirmar Entrega Manual',
          style: AppText.h3.copyWith(
            color: AppColors.textPrimary,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Ingresa el número de control del estudiante:',
              style: AppText.body.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: manualInputController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Número de Control',
                hintText: 'Ej. 2023143096',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
                fillColor: AppColors.componentBase,
              ),
              style: AppText.body,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(
              'Cancelar',
              style: AppText.body.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              final enteredNumber = manualInputController.text.trim();
              if (enteredNumber == numeroDeControlCorrecto) {
                Navigator.of(dialogContext).pop();
                _updateOrderStatus('completed');
              } else {
                Navigator.of(dialogContext).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text('Número de Control incorrecto'),
                    backgroundColor: AppColors.error,
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
            child: Text(
              'Confirmar Entrega',
              style: AppText.body.copyWith(
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
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
              child: CircularProgressIndicator(
                color: AppColors.primary,
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
                    style: AppText.h3.copyWith(
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
            );
          }

          final order = snapshot.data!.data() as Map<String, dynamic>;
          final String status = order['status'] ?? 'pending';
          final String numeroDeControl = order['userNumeroDeControl'] ?? '000000';
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
                    bottom: BorderSide(
                      color: AppColors.borders,
                      width: 1,
                    ),
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
                          ...items.map((item) => _buildProductItem(item)).toList(),
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
                      _buildActionButtons(status, numeroDeControl),
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

  Widget _buildInfoSection({required String title, required List<Widget> children}) {
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
          child: Column(
            children: children,
          ),
        ),
      ],
    );
  }

  Widget _buildInfoRow({required IconData icon, required String label, required String value}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(
            icon,
            size: 20,
            color: AppColors.textSecondary,
          ),
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
              style: AppText.body.copyWith(
                color: AppColors.textSecondary,
              ),
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
        border: Border.all(
          color: AppColors.borders,
        ),
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

  Widget _buildActionButtons(String status, String numeroDeControl) {
    if (status == 'pending') {
      return Column(
        children: [
          ElevatedButton(
            onPressed: () => _updateOrderStatus('preparing'),
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
            onPressed: () => _updateOrderStatus('cancelled'),
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
            onPressed: () => _updateOrderStatus('ready'),
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
            onPressed: () => _updateOrderStatus('cancelled'),
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
            onPressed: () => _startScanner(context, numeroDeControl),
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
            onPressed: () => _showManualInputDialog(numeroDeControl),
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
          Icon(
            Icons.info_outline_rounded,
            color: AppColors.tertiary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              status == 'completed' 
                  ? 'Pedido completado y entregado'
                  : 'Pedido cancelado',
              style: AppText.body.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'pending': return AppColors.warning;
      case 'preparing': return AppColors.tertiary;
      case 'ready': return AppColors.primary;
      case 'completed': return AppColors.success;
      case 'cancelled': return AppColors.error;
      default: return AppColors.textSecondary;
    }
  }

  String _getStatusText(String status) {
    switch (status) {
      case 'pending': return 'PENDIENTE';
      case 'preparing': return 'PREPARANDO';
      case 'ready': return 'LISTO';
      case 'completed': return 'COMPLETADO';
      case 'cancelled': return 'CANCELADO';
      default: return status.toUpperCase();
    }
  }
}