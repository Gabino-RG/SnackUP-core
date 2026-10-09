import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:another_stepper/another_stepper.dart';
import 'show_qr_screen.dart';
import 'rate_order_screen.dart'; // NUEVO: Pantalla de calificación
import 'package:snackup/theme/app_colors.dart';
import 'package:snackup/theme/app_text.dart';
import 'order_checkout.dart';
import 'student_order_repository.dart';

class ProfileOrdersScreen extends StatefulWidget {
  const ProfileOrdersScreen({super.key});

  @override
  State<ProfileOrdersScreen> createState() => _ProfileOrdersScreenState();
}

class _ProfileOrdersScreenState extends State<ProfileOrdersScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late Stream<QuerySnapshot> _allOrdersStream;
  late Stream<QuerySnapshot> _favoritesStream;
  final String? userId = FirebaseAuth.instance.currentUser?.uid;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _reviewsSubscription;
  final Set<String> _reviewedOrderIds = {};
  bool _reviewsLoading = true;
  bool _reviewsFailed = false;
  bool _isOpeningReview = false;
  bool _cartBusy = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);

    if (userId == null) {
      _allOrdersStream = const Stream.empty();
      _favoritesStream = const Stream.empty();
      return;
    }
    _reviewsSubscription = FirebaseFirestore.instance
        .collection('reviews')
        .where('userId', isEqualTo: userId)
        .snapshots()
        .listen(
          (snapshot) {
            if (!mounted) return;
            setState(() {
              _reviewedOrderIds
                ..clear()
                ..addAll(
                  snapshot.docs
                      .map((doc) => doc.data()['orderId'])
                      .whereType<String>(),
                );
              _reviewsLoading = false;
              _reviewsFailed = false;
            });
          },
          onError: (Object error) {
            if (!mounted) return;
            setState(() {
              _reviewsLoading = false;
              _reviewsFailed = true;
            });
          },
        );

    _allOrdersStream = FirebaseFirestore.instance
        .collection('orders')
        .where('userId', isEqualTo: userId)
        .snapshots();

    _favoritesStream = FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection('favorites')
        .orderBy('addedAt', descending: true)
        .snapshots();
  }

  @override
  void dispose() {
    _reviewsSubscription?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (userId == null) {
      return const Scaffold(
        body: Center(child: Text('Inicia sesión para ver tus pedidos.')),
      );
    }
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Container(
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: AppColors.borders, width: 1),
              ),
            ),
            child: TabBar(
              controller: _tabController,
              labelColor: AppColors.primary,
              unselectedLabelColor: AppColors.textSecondary,
              indicatorColor: AppColors.primary,
              indicatorWeight: 3,
              labelStyle: AppText.body.copyWith(
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
              unselectedLabelStyle: AppText.body.copyWith(
                fontWeight: FontWeight.w500,
                fontSize: 14,
              ),
              tabs: const [
                Tab(text: 'Activos'),
                Tab(text: 'Historial'),
                Tab(text: 'Favoritos'),
              ],
            ),
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildActiveOrdersTab(),
          _buildHistoryTab(),
          _buildFavoritesTab(),
        ],
      ),
    );
  }

  Widget _buildActiveOrdersTab() {
    return StreamBuilder<QuerySnapshot>(
      stream: _allOrdersStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _buildErrorState('Error al cargar pedidos activos');
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildLoadingState('Cargando pedidos activos...');
        }

        final activeDocs = (snapshot.data?.docs ?? []).where((doc) {
          final status = (doc.data() as Map<String, dynamic>)['status'];
          return status == 'pending' ||
              status == 'preparing' ||
              status == 'ready';
        }).toList()..sort(_compareOrderDates);

        if (activeDocs.isEmpty) {
          return _buildEmptyState(
            icon: Icons.pending_actions_rounded,
            title: 'No tienes pedidos activos',
            subtitle: 'Los pedidos que hagas aparecerán aquí',
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.all(16),
          separatorBuilder: (context, index) => const SizedBox(height: 16),
          itemCount: activeDocs.length,
          itemBuilder: (context, index) {
            return _buildActiveOrderCard(activeDocs[index]);
          },
        );
      },
    );
  }

  Widget _buildHistoryTab() {
    return StreamBuilder<QuerySnapshot>(
      stream: _allOrdersStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _buildErrorState('Error al cargar historial');
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildLoadingState('Cargando historial...');
        }

        final historyDocs = (snapshot.data?.docs ?? []).where((doc) {
          final status = (doc.data() as Map<String, dynamic>)['status'];
          return status == 'completed' || status == 'cancelled';
        }).toList()..sort(_compareOrderDates);

        if (historyDocs.isEmpty) {
          return _buildEmptyState(
            icon: Icons.history_rounded,
            title: 'No hay historial de pedidos',
            subtitle: 'Tu historial de pedidos aparecerá aquí',
          );
        }

        return Column(
          children: [
            if (_reviewsFailed)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'No se pudieron verificar tus reseñas. Revisa tu conexión o permisos; calificar está deshabilitado hasta recuperar la conexión.',
                ),
              ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.all(16),
                separatorBuilder: (context, index) =>
                    const SizedBox(height: 12),
                itemCount: historyDocs.length,
                itemBuilder: (context, index) =>
                    _buildHistoryOrderCard(historyDocs[index]),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildFavoritesTab() {
    return StreamBuilder<QuerySnapshot>(
      stream: _favoritesStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _buildErrorState('Error al cargar favoritos');
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildLoadingState('Cargando favoritos...');
        }

        if (snapshot.data?.docs.isEmpty ?? true) {
          return _buildEmptyState(
            icon: Icons.favorite_border_rounded,
            title: 'No tienes favoritos',
            subtitle: 'Guarda tus productos favoritos para acceder rápido',
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.all(16),
          separatorBuilder: (context, index) => const SizedBox(height: 12),
          itemCount: snapshot.data!.docs.length,
          itemBuilder: (context, index) {
            return _buildFavoriteCard(snapshot.data!.docs[index]);
          },
        );
      },
    );
  }

  Widget _buildActiveOrderCard(QueryDocumentSnapshot doc) {
    final order = doc.data()! as Map<String, dynamic>;
    final String status = order['status'] ?? 'unknown';
    final double totalPrice = (order['totalPrice'] as num?)?.toDouble() ?? 0.0;
    final List<dynamic> items = order['items'] ?? [];

    // Determinar paso actual del stepper
    int currentStep = 0;
    String statusText = 'Recibido';
    Color statusColor = AppColors.primary;

    if (status == 'preparing') {
      currentStep = 1;
      statusText = 'Preparando';
      statusColor = AppColors.tertiary;
    } else if (status == 'ready') {
      currentStep = 2;
      statusText = '¡Listo!';
      statusColor = AppColors.success;
    }

    // Datos del stepper
    List<StepperData> stepperData = [
      StepperData(
        title: StepperText(
          "Recibido",
          textStyle: TextStyle(
            fontWeight: currentStep >= 0 ? FontWeight.bold : FontWeight.normal,
            color: currentStep >= 0
                ? AppColors.primary
                : AppColors.textSecondary,
          ),
        ),
        iconWidget: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: currentStep >= 0
                ? AppColors.primary
                : AppColors.componentBase,
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.receipt_long_rounded,
            color: currentStep >= 0 ? Colors.white : AppColors.textSecondary,
            size: 16,
          ),
        ),
      ),
      StepperData(
        title: StepperText(
          "Preparando",
          textStyle: TextStyle(
            fontWeight: currentStep >= 1 ? FontWeight.bold : FontWeight.normal,
            color: currentStep >= 1
                ? AppColors.tertiary
                : AppColors.textSecondary,
          ),
        ),
        iconWidget: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: currentStep >= 1
                ? AppColors.tertiary
                : AppColors.componentBase,
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.restaurant_rounded,
            color: currentStep >= 1 ? Colors.white : AppColors.textSecondary,
            size: 16,
          ),
        ),
      ),
      StepperData(
        title: StepperText(
          "¡Listo!",
          textStyle: TextStyle(
            fontWeight: currentStep >= 2 ? FontWeight.bold : FontWeight.normal,
            color: currentStep >= 2
                ? AppColors.success
                : AppColors.textSecondary,
          ),
        ),
        iconWidget: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: currentStep >= 2
                ? AppColors.success
                : AppColors.componentBase,
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.check_circle_rounded,
            color: currentStep >= 2 ? Colors.white : AppColors.textSecondary,
            size: 16,
          ),
        ),
      ),
    ];

    return Material(
      color: AppColors.background,
      borderRadius: BorderRadius.circular(16),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // HEADER DEL PEDIDO
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    statusText,
                    style: AppText.notes.copyWith(
                      color: statusColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  '\$${totalPrice.toStringAsFixed(2)}',
                  style: AppText.h3.copyWith(
                    color: AppColors.success,
                    fontSize: 18,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // RESUMEN DE PRODUCTOS
            _buildOrderItemsSummary(items),

            const SizedBox(height: 16),

            // STEPPER DE PROGRESO
            AnotherStepper(
              stepperList: stepperData,
              stepperDirection: Axis.horizontal,
              iconWidth: 32,
              iconHeight: 32,
              activeBarColor: AppColors.primary,
              inActiveBarColor: AppColors.borders,
              activeIndex: currentStep,
              barThickness: 3,
              scrollPhysics: const NeverScrollableScrollPhysics(),
            ),

            const SizedBox(height: 16),

            // BOTÓN DE QR (SOLO CUANDO ESTÉ LISTO)
            if (status == 'ready')
              Center(
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (ctx) => ShowQrScreen(
                          orderId: doc.id,
                          qrData: pickupQrData(doc.id, order),
                        ),
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.success,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.qr_code_scanner_rounded, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        'Mostrar QR para Recoger',
                        style: AppText.body.copyWith(
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildHistoryOrderCard(QueryDocumentSnapshot doc) {
    final order = doc.data()! as Map<String, dynamic>;
    final String status = order['status'] ?? 'unknown';
    final double totalPrice = (order['totalPrice'] as num?)?.toDouble() ?? 0.0;
    final List<dynamic> items = order['items'] ?? [];
    final Timestamp? createdAt = order['createdAt'] as Timestamp?;
    final String businessId = order['businessId'] ?? '';

    final bool isCompleted = status == 'completed';
    final Color statusColor = isCompleted ? AppColors.success : AppColors.error;
    final String statusText = isCompleted ? 'Completado' : 'Cancelado';
    final IconData statusIcon = isCompleted
        ? Icons.check_circle_rounded
        : Icons.cancel_rounded;

    return Material(
      color: AppColors.background,
      borderRadius: BorderRadius.circular(16),
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            // ICONO DE ESTADO
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(statusIcon, color: statusColor, size: 24),
            ),

            const SizedBox(width: 16),

            // INFORMACIÓN DEL PEDIDO
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    statusText,
                    style: AppText.body.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '\$${totalPrice.toStringAsFixed(2)}',
                    style: AppText.body.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                  if (createdAt != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      _formatDate(createdAt.toDate()),
                      style: AppText.notes.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // BOTONES DE ACCIÓN
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // BOTÓN DE REORDENAR (SOLO PARA COMPLETADOS)
                if (isCompleted)
                  IconButton(
                    icon: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.replay_rounded,
                        color: AppColors.primary,
                        size: 20,
                      ),
                    ),
                    tooltip: 'Volver a Pedir',
                    onPressed: _cartBusy
                        ? null
                        : () => _reorder(context, items),
                  ),

                // NUEVO: BOTÓN DE CALIFICAR (SOLO PARA COMPLETADOS)
                if (isCompleted)
                  IconButton(
                    icon: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.warning.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        _reviewedOrderIds.contains(doc.id)
                            ? Icons.check_circle_rounded
                            : Icons.star_rounded,
                        color: AppColors.warning,
                        size: 20,
                      ),
                    ),
                    tooltip: _reviewedOrderIds.contains(doc.id)
                        ? 'Pedido calificado'
                        : _reviewsFailed
                        ? 'No se pudieron verificar tus reseñas'
                        : _reviewsLoading
                        ? 'Verificando reseña'
                        : 'Calificar pedido',
                    onPressed:
                        _reviewsLoading ||
                            _reviewsFailed ||
                            _isOpeningReview ||
                            _reviewedOrderIds.contains(doc.id)
                        ? null
                        : () => _rateOrder(context, doc.id, businessId),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  int _compareOrderDates(QueryDocumentSnapshot a, QueryDocumentSnapshot b) {
    final x = (a.data() as Map<String, dynamic>)['createdAt'];
    final y = (b.data() as Map<String, dynamic>)['createdAt'];
    return (y is Timestamp ? y.millisecondsSinceEpoch : 0).compareTo(
      x is Timestamp ? x.millisecondsSinceEpoch : 0,
    );
  }

  Future<void> _rateOrder(
    BuildContext context,
    String orderId,
    String businessId,
  ) async {
    if (_isOpeningReview || _reviewedOrderIds.contains(orderId)) return;
    setState(() => _isOpeningReview = true);
    try {
      final business = await FirebaseFirestore.instance
          .collection('businesses')
          .doc(businessId)
          .get();
      if (!context.mounted) return;
      final submitted = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => RateOrderScreen(
            orderId: orderId,
            businessId: businessId,
            businessName: business.data()?['name'] is String
                ? business.data()!['name']
                : 'El local',
          ),
        ),
      );
      if (submitted == true && mounted) {
        setState(() => _reviewedOrderIds.add(orderId));
      }
    } catch (error) {
      if (context.mounted) {
        _showOperationMessage(context, studentOrderError(error));
      }
    } finally {
      if (mounted) setState(() => _isOpeningReview = false);
    }
  }

  Widget _buildFavoriteCard(QueryDocumentSnapshot doc) {
    final fav = doc.data()! as Map<String, dynamic>;
    final String name = fav['name'] ?? 'Producto';
    final String notes = fav['notes'] ?? '';
    final String imageUrl = fav['imageUrl'] ?? '';
    final double price = (fav['price'] as num?)?.toDouble() ?? 0.0;

    return Material(
      color: AppColors.background,
      borderRadius: BorderRadius.circular(16),
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            // IMAGEN DEL PRODUCTO
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: AppColors.componentBase,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(
                  imageUrl.isNotEmpty
                      ? imageUrl
                      : 'https://via.placeholder.com/100',
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      color: AppColors.componentBase,
                      child: Icon(
                        Icons.fastfood_rounded,
                        color: AppColors.textSecondary.withValues(alpha: 0.4),
                        size: 24,
                      ),
                    );
                  },
                ),
              ),
            ),

            const SizedBox(width: 16),

            // INFORMACIÓN DEL FAVORITO
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: AppText.body.copyWith(
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.success.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '\$${price.toStringAsFixed(2)}',
                      style: AppText.notes.copyWith(
                        color: AppColors.success,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (notes.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      notes,
                      style: AppText.notes.copyWith(
                        color: AppColors.textSecondary,
                        fontStyle: FontStyle.italic,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(width: 12),

            // BOTÓN DE AÑADIR AL CARRITO
            IconButton(
              icon: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.add_shopping_cart_rounded,
                  color: AppColors.primary,
                  size: 20,
                ),
              ),
              tooltip: 'Añadir al Carrito',
              onPressed: _cartBusy
                  ? null
                  : () => _addFavoriteToCart(context, doc),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOrderItemsSummary(List<dynamic> items) {
    final totalItems = items.fold<int>(
      0,
      (total, item) => total + (item['quantity'] as int? ?? 1),
    );
    final itemsSummary = items
        .map((item) => '${item['quantity']}x ${item['name']}')
        .take(2)
        .join(', ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Resumen del Pedido',
          style: AppText.body.copyWith(
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          itemsSummary,
          style: AppText.body.copyWith(color: AppColors.textPrimary),
        ),
        if (items.length > 2) ...[
          const SizedBox(height: 4),
          Text(
            '+ ${items.length - 2} productos más',
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

  Future<void> _reorder(BuildContext context, List<dynamic> items) async {
    if (_cartBusy) return;
    setState(() => _cartBusy = true);
    try {
      final requests = items.map((item) {
        if (item is! Map) {
          throw const OrderFlowException(
            'El pedido anterior tiene datos incompletos.',
          );
        }
        return CartProductRequest(
          validProductId(item['productId']),
          validQuantity(item['quantity']),
          validNotes(item['notes']),
        );
      }).toList();
      await StudentOrderRepository().addProducts(requests);
      if (context.mounted) {
        _showOperationMessage(
          context,
          'Productos añadidos al carrito con los precios actuales.',
          success: true,
        );
      }
    } catch (error) {
      if (context.mounted) {
        _showOperationMessage(context, studentOrderError(error));
      }
    } finally {
      if (mounted) setState(() => _cartBusy = false);
    }
  }

  Future<void> _addFavoriteToCart(
    BuildContext context,
    DocumentSnapshot doc,
  ) async {
    if (_cartBusy) return;
    setState(() => _cartBusy = true);
    try {
      final favorite = doc.data() as Map<String, dynamic>;
      await StudentOrderRepository().addProducts([
        CartProductRequest(
          validProductId(favorite['productId']),
          1,
          validNotes(favorite['notes']),
        ),
      ]);
      if (context.mounted) {
        _showOperationMessage(
          context,
          'Producto añadido con el precio actual.',
          success: true,
        );
      }
    } catch (error) {
      if (context.mounted) {
        _showOperationMessage(context, studentOrderError(error));
      }
    } finally {
      if (mounted) setState(() => _cartBusy = false);
    }
  }

  void _showOperationMessage(
    BuildContext context,
    String message, {
    bool success = false,
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: success ? AppColors.success : AppColors.error,
      ),
    );
  }

  // FUNCIONES AUXILIARES
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
              color: AppColors.error.withValues(alpha: 0.7),
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

  Widget _buildLoadingState(String message) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(color: AppColors.primary),
          const SizedBox(height: 16),
          Text(
            message,
            style: AppText.body.copyWith(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
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
                icon,
                size: 40,
                color: AppColors.textSecondary.withValues(alpha: 0.5),
              ),
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
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
}
