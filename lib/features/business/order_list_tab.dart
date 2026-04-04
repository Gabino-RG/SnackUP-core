import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:audioplayers/audioplayers.dart';
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
  int _previousOrderCount = -1;
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _soundPlayedForThisBatch = false;

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  void _checkAndPlaySound(int currentOrderCount) {
    if (widget.status == 'pending' && widget.orderType == 'asap') {
      if (_previousOrderCount != -1 && 
          currentOrderCount > _previousOrderCount && 
          !_soundPlayedForThisBatch) {
        print("🔔 Nuevo pedido detectado! Reproduciendo sonido...");
        try {
          _audioPlayer.play(AssetSource('sounds/notification_bell.mp3'));
          _soundPlayedForThisBatch = true;
          Future.delayed(const Duration(seconds: 5), () => _soundPlayedForThisBatch = false);
        } catch (e) {
          print("Error al reproducir sonido: $e");
        }
      }
      _previousOrderCount = currentOrderCount;
    }
  }

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

  Color _getStatusColor() {
    switch (widget.status) {
      case 'pending': return AppColors.warning;
      case 'preparing': return AppColors.tertiary;
      case 'ready': return AppColors.primary;
      case 'completed': return AppColors.success;
      case 'cancelled': return AppColors.error;
      default: return AppColors.textSecondary;
    }
  }

  IconData _getStatusIcon() {
    switch (widget.status) {
      case 'pending': return Icons.access_time_rounded;
      case 'preparing': return Icons.restaurant_rounded;
      case 'ready': return Icons.check_circle_rounded;
      case 'completed': return Icons.done_all_rounded;
      case 'cancelled': return Icons.cancel_rounded;
      default: return Icons.receipt_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    Query query = FirebaseFirestore.instance
        .collection('orders')
        .where('businessId', isEqualTo: widget.businessId)
        .where('status', isEqualTo: widget.status);

    String emptyMessage = 'No hay pedidos ${_getTabTitle().toLowerCase()}';
    String emptySubtitle = 'Los nuevos pedidos aparecerán aquí';

    if (widget.orderType == 'asap') {
      query = query.where('scheduledPickupTime', isEqualTo: null)
                   .orderBy('createdAt', descending: true);
      emptyMessage = 'No hay pedidos nuevos';
      emptySubtitle = 'Los pedidos para ahora aparecerán aquí';

    } else if (widget.orderType == 'scheduled') {
      query = query.where('scheduledPickupTime', isGreaterThan: Timestamp.now())
                   .orderBy('scheduledPickupTime', descending: false);
      emptyMessage = 'No hay pedidos programados';
      emptySubtitle = 'Los pedidos programados aparecerán aquí';

    } else {
      query = query.orderBy('createdAt', descending: true);
    }

    final Stream<QuerySnapshot> ordersStream = query.snapshots();

    return StreamBuilder<QuerySnapshot>(
      stream: ordersStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _buildErrorState();
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildLoadingState();
        }

        final docs = snapshot.data?.docs ?? [];

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _checkAndPlaySound(docs.length);
          }
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
              style: AppText.h3.copyWith(
                color: AppColors.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Verifica tu conexión e intenta nuevamente',
              style: AppText.body.copyWith(
                color: AppColors.textSecondary,
              ),
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
          CircularProgressIndicator(
            color: AppColors.primary,
          ),
          const SizedBox(height: 16),
          Text(
            'Cargando pedidos...',
            style: AppText.body.copyWith(
              color: AppColors.textSecondary,
            ),
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
              style: AppText.h3.copyWith(
                color: AppColors.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: AppText.body.copyWith(
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOrderList(BuildContext context, List<QueryDocumentSnapshot> docs) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: docs.map((doc) {
        final order = doc.data()! as Map<String, dynamic>;
        final total = order['totalPrice'] ?? 0.0;
        final items = order['items'] as List<dynamic>? ?? [];
        final Timestamp? pickupTime = order['scheduledPickupTime'] as Timestamp?;
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
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (context) => OrderDetailScreen(orderId: doc.id),
                ));
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
                            text: 'Recoger: ${_formatTime(pickupTime.toDate())}',
                            color: AppColors.primary,
                          ),
                        ],
                      ],
                    ),

                    // INDICADOR DE NUEVO PEDIDO (solo para pendientes ASAP)
                    if (widget.status == 'pending' && widget.orderType == 'asap') ...[
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

    final totalItems = items.fold(0, (sum, item) => sum + ((item['quantity'] as int?) ?? 1));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          itemsSummary,
          style: AppText.body.copyWith(
            color: AppColors.textPrimary,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        if (items.length > 3) ...[
          const SizedBox(height: 4),
          Text(
            '+ ${items.length - 3} productos más',
            style: AppText.notes.copyWith(
              color: AppColors.textSecondary,
            ),
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
          Icon(
            icon,
            size: 12,
            color: color ?? AppColors.textSecondary,
          ),
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