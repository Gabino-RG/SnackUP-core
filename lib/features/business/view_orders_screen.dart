import 'package:flutter/material.dart';
import 'order_list_tab.dart';
import 'package:snackup/theme/app_colors.dart';
import 'package:snackup/theme/app_text.dart';

class ViewOrdersScreen extends StatefulWidget {
  final String businessId;
  const ViewOrdersScreen({super.key, required this.businessId});

  @override
  State<ViewOrdersScreen> createState() => _ViewOrdersScreenState();
}

class _ViewOrdersScreenState extends State<ViewOrdersScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Gestión de Pedidos',
          style: AppText.h3.copyWith(
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        backgroundColor: AppColors.background,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Container(
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: AppColors.borders,
                  width: 1,
                ),
              ),
            ),
            child: TabBar(
              controller: _tabController,
              labelColor: AppColors.primary,
              unselectedLabelColor: AppColors.textSecondary,
              indicatorColor: AppColors.primary,
              indicatorWeight: 3,
              indicatorSize: TabBarIndicatorSize.label,
              labelStyle: AppText.body.copyWith(
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
              unselectedLabelStyle: AppText.body.copyWith(
                fontWeight: FontWeight.w500,
                fontSize: 14,
              ),
              isScrollable: true,
              tabs: [
                _buildTab('Programados', Icons.schedule_rounded),
                _buildTab('Nuevos', Icons.access_time_rounded),
                _buildTab('Preparando', Icons.restaurant_rounded),
                _buildTab('Listos', Icons.check_circle_rounded),
              ],
            ),
          ),
        ),
      ),
      body: Container(
        color: AppColors.background,
        child: TabBarView(
          controller: _tabController,
          children: [
            // Pestaña 1: Pedidos Programados
            _buildTabContent(
              status: 'pending',
              orderType: 'scheduled',
              icon: Icons.schedule_rounded,
              title: 'Pedidos Programados',
              description: 'Pedidos agendados para recoger en el futuro',
            ),

            // Pestaña 2: Pedidos Nuevos (ASAP)
            _buildTabContent(
              status: 'pending',
              orderType: 'asap',
              icon: Icons.access_time_rounded,
              title: 'Pedidos Nuevos',
              description: 'Pedidos para preparar inmediatamente',
              isUrgent: true,
            ),

            // Pestaña 3: Pedidos en Preparación
            _buildTabContent(
              status: 'preparing',
              orderType: 'all',
              icon: Icons.restaurant_rounded,
              title: 'En Preparación',
              description: 'Pedidos que están siendo preparados',
            ),

            // Pestaña 4: Pedidos Listos
            _buildTabContent(
              status: 'ready',
              orderType: 'all',
              icon: Icons.check_circle_rounded,
              title: 'Listos para Recoger',
              description: 'Pedidos listos para entrega',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTab(String text, IconData icon) {
    return Tab(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 18,
          ),
          const SizedBox(width: 6),
          Text(text),
        ],
      ),
    );
  }

  Widget _buildTabContent({
    required String status,
    required String orderType,
    required IconData icon,
    required String title,
    required String description,
    bool isUrgent = false,
  }) {
    return Column(
      children: [
        // HEADER INFORMATIVO DE LA PESTAÑA
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: _getTabColor(status, orderType).withOpacity(0.1),
            border: Border(
              bottom: BorderSide(
                color: AppColors.borders,
                width: 1,
              ),
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _getTabColor(status, orderType),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppText.h3.copyWith(
                        color: _getTabColor(status, orderType),
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: AppText.notes.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (isUrgent) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppColors.warning.withOpacity(0.4),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.notifications_active_rounded,
                        color: AppColors.warning,
                        size: 16,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Urgente',
                        style: AppText.notes.copyWith(
                          color: AppColors.warning,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),

        // CONTENIDO DE LA PESTAÑA
        Expanded(
          child: OrderListTab(
            businessId: widget.businessId,
            status: status,
            orderType: orderType,
          ),
        ),
      ],
    );
  }

  Color _getTabColor(String status, String orderType) {
    if (status == 'pending' && orderType == 'asap') {
      return AppColors.warning; // Color para pedidos urgentes
    } else if (status == 'pending' && orderType == 'scheduled') {
      return AppColors.tertiary; // Color para programados
    } else if (status == 'preparing') {
      return AppColors.primary; // Color para preparación
    } else if (status == 'ready') {
      return AppColors.success; // Color para listos
    }
    return AppColors.textSecondary; // Color por defecto
  }
}