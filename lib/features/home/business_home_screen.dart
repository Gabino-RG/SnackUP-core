import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:audioplayers/audioplayers.dart';
import '../business/manage_menu_screen.dart';
import '../business/view_orders_screen.dart';
import '../business/statistics_screen.dart';
import '../auth/auth_gate.dart';
import 'package:snackup/theme/app_colors.dart';
import 'package:snackup/theme/app_text.dart';

class BusinessHomeScreen extends StatefulWidget {
  const BusinessHomeScreen({super.key});

  @override
  State<BusinessHomeScreen> createState() => _BusinessHomeScreenState();
}

class _BusinessHomeScreenState extends State<BusinessHomeScreen> {
  int _selectedIndex = 0;
  String? _fetchedBusinessId;
  StreamSubscription? _newOrderSubscription;
  int _previousNewOrderCount = -1;
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _alertShownForThisBatch = false;
  int _pendingOrdersCount = 0;

  @override
  void initState() {
    super.initState();
    _fetchBusinessIdAndListen();
  }

  Future<void> _fetchBusinessIdAndListen() async {
    _fetchedBusinessId = await _getBusinessId();
    if (_fetchedBusinessId != null && mounted) {
      _listenForNewOrders(_fetchedBusinessId!);
      setState(() {});
    } else if (mounted) {
      print("Error: No se encontró businessId vinculado");
      FirebaseAuth.instance.signOut();
    }
  }

  Future<String?> _getBusinessId() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    try {
      final query = await FirebaseFirestore.instance
          .collection('businesses')
          .where('ownerId', isEqualTo: user.uid)
          .limit(1)
          .get();
      return query.docs.isNotEmpty ? query.docs.first.id : null;
    } catch (e) {
      print("Error al obtener businessId: $e");
      return null;
    }
  }

  void _listenForNewOrders(String businessId) {
    _newOrderSubscription?.cancel();

    final query = FirebaseFirestore.instance
        .collection('orders')
        .where('businessId', isEqualTo: businessId)
        .where('status', isEqualTo: 'pending')
        .where('scheduledPickupTime', isEqualTo: null);

    _newOrderSubscription = query.snapshots().listen(
      (snapshot) {
        final currentOrderCount = snapshot.docs.length;
        _pendingOrdersCount = currentOrderCount; // Actualizar contador

        if (_previousNewOrderCount != -1 && 
            currentOrderCount > _previousNewOrderCount && 
            !_alertShownForThisBatch) {
          print("🛎️ Nuevo pedido ASAP detectado! Total: $currentOrderCount");
          _alertShownForThisBatch = true;

          try {
            _audioPlayer.play(AssetSource('sounds/notification_bell.mp3'));
          } catch (e) {
            print("Error al reproducir sonido: $e");
          }

          if (mounted) {
            _showNewOrderDialog(context, currentOrderCount);
          }

          Future.delayed(const Duration(seconds: 10), () {
            if (mounted) {
              _alertShownForThisBatch = false;
            }
          });
        }
        _previousNewOrderCount = currentOrderCount;
        
        // Actualizar UI si estamos en la pestaña de pedidos
        if (mounted && _selectedIndex == 0) {
          setState(() {});
        }
      },
      onError: (error) {
        print("Error escuchando nuevos pedidos: $error");
      },
    );
  }

  void _showNewOrderDialog(BuildContext context, int orderCount) {
    if (ModalRoute.of(context)?.isCurrent != true) return;
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          backgroundColor: AppColors.background,
          surfaceTintColor: Colors.transparent,
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.warning.withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.notifications_active_rounded,
                  color: AppColors.warning,
                  size: 28,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  "¡Nuevo Pedido!",
                  style: AppText.h3.copyWith(
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Tienes un nuevo pedido para preparar inmediatamente.",
                style: AppText.body.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.componentBase,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.receipt_long_rounded,
                      color: AppColors.primary,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      "Pedidos pendientes: $orderCount",
                      style: AppText.notes.copyWith(
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
              },
              child: Text(
                "Más tarde",
                style: AppText.body.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: () {
                Navigator.of(dialogContext).pop();
                setState(() {
                  _selectedIndex = 0;
                });
              },
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.list_alt_rounded, size: 18),
                  const SizedBox(width: 6),
                  Text(
                    "Ver Pedidos",
                    style: AppText.body.copyWith(
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  void dispose() {
    _newOrderSubscription?.cancel();
    _audioPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_fetchedBusinessId == null) {
      return const LoadingScreen();
    }

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('businesses')
          .doc(_fetchedBusinessId!)
          .snapshots(),
      builder: (context, businessSnapshot) {
        if (businessSnapshot.connectionState == ConnectionState.waiting && 
            !businessSnapshot.hasData) {
          return const LoadingScreen();
        }
        
        if (businessSnapshot.hasError || 
            !businessSnapshot.data!.exists || 
            businessSnapshot.data!.data() == null) {
          return _buildErrorState();
        }

        final businessData = businessSnapshot.data!.data() as Map<String, dynamic>;
        final bool isOpen = businessData['isOpen'] ?? false;
        final String businessName = businessData['name'] ?? 'Mi Negocio';

        final List<Widget> pages = [
          ViewOrdersScreen(businessId: _fetchedBusinessId!),
          ManageMenuScreen(businessId: _fetchedBusinessId!),
          StatisticsScreen(businessId: _fetchedBusinessId!),
        ];

        return Scaffold(
          appBar: AppBar(
            title: Text(
              businessName,
              style: AppText.h3.copyWith(
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            backgroundColor: AppColors.background,
            elevation: 0,
            foregroundColor: AppColors.textPrimary,
            actions: [
              // SWITCH ESTADO DEL NEGOCIO
              _buildBusinessStatusSwitch(isOpen),
              const SizedBox(width: 8),
              // BOTÓN DE CERRAR SESIÓN
              _buildLogoutButton(context),
            ],
          ),
          body: pages[_selectedIndex],
          bottomNavigationBar: _buildBottomNavigationBar(),
        );
      },
    );
  }

  Widget _buildBusinessStatusSwitch(bool isOpen) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.componentBase,
        borderRadius: BorderRadius.circular(25),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            isOpen ? 'Abierto' : 'Cerrado',
            style: AppText.notes.copyWith(
              fontWeight: FontWeight.w600,
              color: isOpen ? AppColors.success : AppColors.error,
            ),
          ),
          const SizedBox(width: 6),
          Switch(
            value: isOpen,
            onChanged: (newValue) {
              FirebaseFirestore.instance
                  .collection('businesses')
                  .doc(_fetchedBusinessId!)
                  .update({'isOpen': newValue});
            },
            activeColor: AppColors.success,
            inactiveThumbColor: AppColors.error,
            activeTrackColor: AppColors.success.withOpacity(0.4),
            inactiveTrackColor: AppColors.error.withOpacity(0.4),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ],
      ),
    );
  }

  Widget _buildLogoutButton(BuildContext context) {
    return IconButton(
      icon: Icon(
        Icons.logout_rounded,
        color: AppColors.textSecondary,
      ),
      tooltip: 'Cerrar Sesión',
      onPressed: () {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Text(
              'Cerrar Sesión',
              style: AppText.h3.copyWith(
                color: AppColors.textPrimary,
              ),
            ),
            content: Text(
              '¿Estás seguro de que quieres cerrar sesión?',
              style: AppText.body.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text(
                  'Cancelar',
                  style: AppText.body.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.error,
                  foregroundColor: Colors.white,
                ),
                onPressed: () {
                  Navigator.of(ctx).pop();
                  FirebaseAuth.instance.signOut();
                },
                child: Text(
                  'Cerrar Sesión',
                  style: AppText.body.copyWith(
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBottomNavigationBar() {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: AppColors.borders,
            width: 1,
          ),
        ),
      ),
      child: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        backgroundColor: AppColors.background,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: AppColors.textSecondary,
        selectedLabelStyle: AppText.notes.copyWith(
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelStyle: AppText.notes,
        showUnselectedLabels: true,
        type: BottomNavigationBarType.fixed,
        items: [
          BottomNavigationBarItem(
            icon: Stack(
              children: [
                const Icon(Icons.receipt_long_rounded),
                if (_pendingOrdersCount > 0 && _selectedIndex != 0)
                  Positioned(
                    right: 0,
                    top: 0,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: AppColors.warning,
                        shape: BoxShape.circle,
                      ),
                      constraints: const BoxConstraints(
                        minWidth: 16,
                        minHeight: 16,
                      ),
                      child: Text(
                        _pendingOrdersCount > 9 ? '9+' : _pendingOrdersCount.toString(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 8,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
              ],
            ),
            label: 'Pedidos',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.restaurant_menu_rounded),
            label: 'Menú',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.analytics_rounded),
            label: 'Estadísticas',
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Scaffold(
      body: Center(
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
                'Error al cargar el negocio',
                style: AppText.h3.copyWith(
                  color: AppColors.textPrimary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                'No se pudo cargar la información de tu negocio. Por favor, intenta nuevamente.',
                style: AppText.body.copyWith(
                  color: AppColors.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => FirebaseAuth.instance.signOut(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                ),
                child: Text(
                  'Volver al Inicio',
                  style: AppText.body.copyWith(
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}