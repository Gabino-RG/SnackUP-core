import 'rate_order_screen.dart';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:snackup/theme/app_colors.dart';
import 'package:snackup/theme/app_text.dart';

class ShowQrScreen extends StatelessWidget {
  final String orderId;
  final String qrData;
  final FirebaseFirestore? firestore;

  const ShowQrScreen({
    super.key,
    required this.orderId,
    required this.qrData,
    this.firestore,
  });

  @override
  Widget build(BuildContext context) {
    final Stream<DocumentSnapshot> orderStream =
        (firestore ?? FirebaseFirestore.instance)
            .collection('orders')
            .doc(orderId)
            .snapshots();

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Mi pedido',
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
        stream: orderStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return _buildLoadingState();
          }

          if (snapshot.hasError)
            return _buildErrorState(
              'No se pudo actualizar el pedido. Revisa tu conexión.',
            );
          if (!snapshot.hasData || !snapshot.data!.exists) {
            return _buildErrorState('Pedido no encontrado');
          }

          final order = snapshot.data!.data() as Map<String, dynamic>;
          final String status = order['status'] ?? '';
          final String numeroDeControl = order['userNumeroDeControl'] ?? '0000';
          final double totalPrice =
              (order['totalPrice'] as num?)?.toDouble() ?? 0.0;
          final List<dynamic> items = order['items'] ?? [];
          final Timestamp? createdAt = order['createdAt'] as Timestamp?;

          if (status == 'completed') {
            return _buildCompletedState(context, order);
          }
          if (status == 'cancelled') {
            return _buildErrorState(
              'Pedido cancelado. Este código ya no se puede usar.',
            );
          }

          if (status != 'ready') {
            return _buildNotReadyState(context, status);
          }

          return _buildQrContent(
            context,
            numeroDeControl,
            totalPrice,
            items,
            createdAt,
          );
        },
      ),
    );
  }

  Widget _buildCompletedState(
    BuildContext context,
    Map<String, dynamic> order,
  ) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.check_circle_rounded,
              size: 88,
              color: AppColors.success,
            ),
            const SizedBox(height: 24),
            Text(
              '¡Gracias por tu compra!',
              style: AppText.h1,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            const Text(
              'Tu pedido ya fue entregado. Esperamos que lo disfrutes.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              icon: const Icon(Icons.star_rounded),
              label: const Text('Valorar restaurante'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: AppColors.primary,
              ),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => RateOrderScreen(
                    orderId: orderId,
                    businessId: order['businessId'] as String? ?? '',
                    businessName:
                        order['businessName'] as String? ?? 'el restaurante',
                    restaurant: true,
                    firestore: firestore,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => Navigator.of(context).maybePop(),
              child: const Text('Volver a Mis Pedidos'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQrContent(
    BuildContext context,
    String numeroDeControl,
    double totalPrice,
    List<dynamic> items,
    Timestamp? createdAt,
  ) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          // HEADER INFORMATIVO
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.success.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.success.withOpacity(0.3)),
            ),
            child: Column(
              children: [
                Icon(
                  Icons.qr_code_scanner_rounded,
                  size: 40,
                  color: AppColors.success,
                ),
                const SizedBox(height: 12),
                Text(
                  'Tu pedido está listo',
                  style: AppText.h3.copyWith(color: AppColors.success),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Muestra este código QR al personal para recoger tu pedido',
                  style: AppText.body.copyWith(color: AppColors.textSecondary),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),

          const SizedBox(height: 32),

          // TARJETA DEL QR
          Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(24),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                children: [
                  // QR CODE
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppColors.borders, width: 2),
                    ),
                    child: QrImageView(
                      data: qrData,
                      version: QrVersions.auto,
                      size: 220,
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

                  const SizedBox(height: 24),

                  // NÚMERO DE CONTROL DE RESPUESTA
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.componentBase,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      children: [
                        Text(
                          'Si el QR no funciona, usa este número:',
                          style: AppText.notes.copyWith(
                            color: AppColors.textSecondary,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          numeroDeControl,
                          style: AppText.h1.copyWith(
                            color: AppColors.primary,
                            fontSize: 28,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 32),

          // INFORMACIÓN ADICIONAL DEL PEDIDO
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppColors.componentBase,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Resumen del Pedido',
                  style: AppText.h3.copyWith(
                    color: AppColors.textPrimary,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 16),

                // ITEMS DEL PEDIDO
                ...items
                    .take(3)
                    .map(
                      (item) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                '${item['quantity']}x',
                                style: AppText.notes.copyWith(
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                item['name'] ?? 'Producto',
                                style: AppText.body.copyWith(
                                  color: AppColors.textPrimary,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                if (items.length > 3) ...[
                  const SizedBox(height: 8),
                  Text(
                    '+ ${items.length - 3} productos más',
                    style: AppText.notes.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],

                const SizedBox(height: 16),
                const Divider(height: 1, color: AppColors.borders),
                const SizedBox(height: 16),

                // TOTAL
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Total:',
                      style: AppText.body.copyWith(
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Text(
                      '\$${totalPrice.toStringAsFixed(2)}',
                      style: AppText.h3.copyWith(
                        color: AppColors.success,
                        fontSize: 20,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // INSTRUCCIONES
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.tertiary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  color: AppColors.tertiary,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Acércate al mostrador y muestra este código al personal',
                    style: AppText.notes.copyWith(
                      color: AppColors.tertiary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(color: AppColors.primary),
          const SizedBox(height: 16),
          Text(
            'Cargando código de entrega...',
            style: AppText.body.copyWith(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
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
              message,
              style: AppText.h3.copyWith(color: AppColors.textPrimary),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNotReadyState(BuildContext context, String status) {
    String title = 'Pedido en proceso';
    String subtitle = 'Tu pedido está siendo preparado';
    IconData icon = Icons.access_time_rounded;
    Color color = AppColors.warning;

    if (status == 'pending') {
      title = 'Pedido Recibido';
      subtitle = 'Esperando confirmación del negocio';
      icon = Icons.pending_actions_rounded;
      color = AppColors.primary;
    } else if (status == 'preparing') {
      title = 'Preparando tu Pedido';
      subtitle = 'El negocio está cocinando tu comida';
      icon = Icons.restaurant_rounded;
      color = AppColors.tertiary;
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 50, color: color),
            ),
            const SizedBox(height: 24),
            Text(
              title,
              style: AppText.h3.copyWith(color: AppColors.textPrimary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              subtitle,
              style: AppText.body.copyWith(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
              ),
              child: Text(
                'Volver a Mis Pedidos',
                style: AppText.body.copyWith(
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
