import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'order_detail_screen.dart';
import 'package:snackup/theme/app_colors.dart';
import 'package:snackup/theme/app_text.dart';

class OrderListTab extends StatefulWidget {
  final String businessId;
  final String status;
  final String orderType;

  const OrderListTab({
    super.key,
    required this.businessId,
    required this.status,
    required this.orderType,
  });

  @override
  State<OrderListTab> createState() => _OrderListTabState();
}

class _OrderListTabState extends State<OrderListTab> {
  String _getTabTitle() {
    switch (widget.status) {
      case 'pending':
        return widget.orderType == 'asap' ? 'Nuevos Pedidos' : 'Programados';
      case 'preparing':
        return 'En Preparación ';
      case 'ready':
        return 'Listos para Recoger';
      case 'completed':
        return 'Completados';
      case 'cancelled':
        return 'Cancelados';
      default:
        return 'Pedidos';
    }
  }

  IconData _getStatusIcon() {
    switch (widget.status) {
      case 'pending':
        return Icons.access_time_rounded;
      case 'preparing':
        return Icons.restaurant_rounded;
      case 'ready':
        return Icons.check_circle_rounded;
      case 'completed':
        return Icons.done_all_rounded;
      case 'cancelled':
        return Icons.cancel_rounded;
      default:
        return Icons.receipt_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Query only the ownership field; sort/filter locally so no composite
    // index is required and overdue scheduled orders never disappear.
    final ordersStream = FirebaseFirestore.instance
        .collection('orders')
        .where('businessId', isEqualTo: widget.businessId)
        .snapshots();
    final emptyMessage = 'No hay pedidos ${_getTabTitle().toLowerCase()}';
    const emptySubtitle =
        'Los pedidos aparecerán aquí cuando cambien a este estado';

    return StreamBuilder<QuerySnapshot>(
      stream: ordersStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _buildErrorState();
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildLoadingState();
        }

        final docs = (snapshot.data?.docs ?? []).where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          if (data['status'] != widget.status) return false;
          final scheduled = data['scheduledPickupTime'] is Timestamp;
          return widget.orderType == 'all' ||
              (widget.orderType == 'scheduled' ? scheduled : !scheduled);
        }).toList();
        docs.sort((a, b) {
          final left = a.data() as Map<String, dynamic>;
          final right = b.data() as Map<String, dynamic>;
          final field = widget.orderType == 'scheduled'
              ? 'scheduledPickupTime'
              : 'createdAt';
          final leftTime = left[field] is Timestamp
              ? (left[field] as Timestamp).millisecondsSinceEpoch
              : 0;
          final rightTime = right[field] is Timestamp
              ? (right[field] as Timestamp).millisecondsSinceEpoch
              : 0;
          return widget.orderType == 'scheduled'
              ? leftTime.compareTo(rightTime)
              : rightTime.compareTo(leftTime);
        });

        if (docs.isEmpty) {
          return _buildEmptyState(emptyMessage, emptySubtitle);
        }

        return _buildOrderList(context, docs);
      },
    );
  }

  Widget _buildErrorState() {
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
              'Error al cargar pedidos',
              style: AppText.h3.copyWith(color: AppColors.textPrimary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Verifica tu conexión e intenta nuevamente',
              style: AppText.body.copyWith(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
          ],
        ),
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
            'Cargando pedidos...',
            style: AppText.body.copyWith(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(String message, String subtitle) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: AppColors.componentBase,
                shape: BoxShape.circle,
              ),
              child: Icon(
                _getStatusIcon(),
                size: 40,
                color: AppColors.textSecondary.withOpacity(0.5),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              message,
              style: AppText.h3.copyWith(color: AppColors.textPrimary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: AppText.body.copyWith(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOrderList(
    BuildContext context,
    List<QueryDocumentSnapshot> docs,
  ) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: docs.map((doc) {
        final order = doc.data()! as Map<String, dynamic>;
        final total = order['totalPrice'] ?? 0.0;
        final items = order['items'] as List<dynamic>? ?? [];
        final Timestamp? pickupTime =
            order['scheduledPickupTime'] as Timestamp?;
        final Timestamp? createdAt = order['createdAt'] as Timestamp?;
        final String userName = order['userDisplayName'] ?? 'Cliente';

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          child: Material(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(16),
            elevation: 2,
            child: InkWell(
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => OrderDetailScreen(
                      orderId: doc.id,
                      businessId: widget.businessId,
                    ),
                  ),
                );
              },
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // HEADER DEL PEDIDO
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            'Pedido de $userName',
                            style: AppText.body.copyWith(
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.success.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '\$${total.toStringAsFixed(2)}',
                            style: AppText.body.copyWith(
                              fontWeight: FontWeight.w700,
                              color: AppColors.success,
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 12),

                    // RESUMEN DE PRODUCTOS
                    _buildItemsSummary(items),

                    const SizedBox(height: 12),

                    // INFORMACIÓN ADICIONAL
                    Row(
                      children: [
                        // HORA DE CREACIÓN
                        if (createdAt != null) ...[
                          _buildInfoChip(
                            icon: Icons.access_time_rounded,
                            text: _formatTime(createdAt.toDate()),
                          ),
                          const SizedBox(width: 8),
                        ],
                        // HORA PROGRAMADA
                        if (pickupTime != null) ...[
                          _buildInfoChip(
                            icon: Icons.schedule_rounded,
                            text:
                                'Recoger: ${_formatTime(pickupTime.toDate())}',
                            color: AppColors.primary,
                          ),
                        ],
                      ],
                    ),

                    // INDICADOR DE NUEVO PEDIDO (solo para pendientes ASAP)
                    if (widget.status == 'pending' &&
                        widget.orderType == 'asap') ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: AppColors.warning,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Nuevo pedido',
                            style: AppText.notes.copyWith(
                              color: AppColors.warning,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildItemsSummary(List<dynamic> items) {
    final String itemsSummary = items
        .map((item) {
          final name = item['name'] ?? 'Producto';
          final quantity = item['quantity'] ?? 1;
          return "${quantity}x $name";
        })
        .take(3) // Mostrar máximo 3 productos
        .join(', ');

    final totalItems = items.fold(
      0,
      (count, item) => count + ((item['quantity'] as int?) ?? 1),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          itemsSummary,
          style: AppText.body.copyWith(color: AppColors.textPrimary),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        if (items.length > 3) ...[
          const SizedBox(height: 4),
          Text(
            '+ ${items.length - 3} productos más',
            style: AppText.notes.copyWith(color: AppColors.textSecondary),
          ),
        ],
        const SizedBox(height: 4),
        Text(
          '$totalItems productos en total',
          style: AppText.notes.copyWith(
            color: AppColors.textSecondary,
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget _buildInfoChip({
    required IconData icon,
    required String text,
    Color? color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: (color ?? AppColors.textSecondary).withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color ?? AppColors.textSecondary),
          const SizedBox(width: 4),
          Text(
            text,
            style: AppText.notes.copyWith(
              color: color ?? AppColors.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime dateTime) {
    return '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
  }
}
