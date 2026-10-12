import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:snackup/theme/app_colors.dart';

import 'order_checkout.dart';

class ShowQrScreen extends StatelessWidget {
  final String orderId;
  // Kept for callers from older screens. The live, owned order determines the QR.
  final String? qrData;
  const ShowQrScreen({super.key, required this.orderId, this.qrData});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return Scaffold(
      appBar: AppBar(title: const Text('Recoger pedido')),
      body: uid == null
          ? const Center(child: Text('Inicia sesión para ver tu pedido.'))
          : StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('orders')
                  .doc(orderId)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return _status(
                    context,
                    Icons.error_outline,
                    'No se pudo cargar el pedido',
                    'Revisa tu conexión y los permisos de tu cuenta.',
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final order = snapshot.data!.data();
                if (order == null || order['userId'] != uid) {
                  return _status(
                    context,
                    Icons.lock_outline,
                    'Pedido no disponible',
                    'Solo puedes recoger pedidos de tu cuenta.',
                  );
                }
                final status = order['status'];
                if (status == 'completed') {
                  return _status(
                    context,
                    Icons.check_circle_outline,
                    'Pedido entregado',
                    'Gracias por tu compra. Ya puedes calificarlo desde el historial.',
                  );
                }
                if (status == 'cancelled') {
                  return _status(
                    context,
                    Icons.cancel_outlined,
                    'Pedido cancelado',
                    'Este pedido ya no se puede recoger.',
                  );
                }
                if (status != 'ready') {
                  return _status(
                    context,
                    Icons.restaurant_outlined,
                    status == 'pending'
                        ? 'Esperando al local'
                        : 'Preparando tu pedido',
                    'El código aparecerá cuando el local marque tu pedido como listo.',
                  );
                }
                final code =
                    order['pickupCode'] is String &&
                        (order['pickupCode'] as String).isNotEmpty
                    ? order['pickupCode'] as String
                    : orderId;
                final total = (order['totalPrice'] as num?)?.toDouble() ?? 0;
                return SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 560),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Icon(
                            Icons.check_circle_outline,
                            size: 48,
                            color: AppColors.success,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Tu pedido está listo',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Muestra este código al personal del local. Es exclusivo de este pedido.',
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 24),
                          Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 300),
                              child: AspectRatio(
                                aspectRatio: 1,
                                child: QrImageView(
                                  data: pickupQrData(orderId, order),
                                  backgroundColor: Colors.white,
                                  padding: const EdgeInsets.all(16),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                          const Text(
                            'Si no se puede escanear, muestra este código de entrega:',
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8),
                          SelectableText(
                            code,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 24),
                          Text(
                            'Total: \$${total.toStringAsFixed(2)}',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'El código dejará de ser válido cuando el pedido se entregue.',
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }

  Widget _status(
    BuildContext context,
    IconData icon,
    String title,
    String message,
  ) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: AppColors.primary),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => Navigator.of(context).maybePop(),
              child: const Text('Volver a mis pedidos'),
            ),
          ],
        ),
      ),
    );
  }
}
