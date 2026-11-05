import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:snackup/student/student_api.dart';
import 'package:snackup/theme/student_colors.dart';
import 'package:snackup/theme/student_text.dart';
import '../user/cart_screen.dart';
import '../user/profile_orders_screen.dart';
import '../user/search_screen.dart';
import 'user_home_screen.dart';

class UserDashboardScreen extends StatefulWidget {
  const UserDashboardScreen({super.key});
  @override
  State<UserDashboardScreen> createState() => _UserDashboardScreenState();
}

class _UserDashboardScreenState extends State<UserDashboardScreen> {
  int _selectedIndex = 0;

  Future<void> _logout() async {
    final api = context.read<StudentApi>();
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cerrar sesión'),
        content: const Text('¿Quieres salir de tu cuenta de alumno?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Cerrar sesión'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await api.logout();
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Saliste de esta aplicación. No pudimos confirmar el cierre en el servidor.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<StudentApi>().user;
    final orders = _selectedIndex == 1;
    final desktopOrders = orders && MediaQuery.sizeOf(context).width >= 800;
    final pages = <Widget>[
      const UserHomeScreen(),
      const ProfileOrdersScreen(
        key: ValueKey('orders'),
        initialTab: 0,
        embedded: true,
      ),
      const ProfileOrdersScreen(
        key: ValueKey('favorites'),
        initialTab: 2,
        embedded: true,
      ),
      const ProfileOrdersScreen(
        key: ValueKey('profile'),
        initialTab: 3,
        embedded: true,
      ),
    ];
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: orders ? 68 : 76,
        titleSpacing: orders ? 10 : 16,
        backgroundColor: orders ? AppColors.background : null,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        title: Row(
          children: [
            Tooltip(
              message: 'Inicio',
              child: InkWell(
                onTap: () => setState(() => _selectedIndex = 0),
                borderRadius: BorderRadius.circular(15),
                child: Container(
                  width: orders ? 44 : 38,
                  height: orders ? 44 : 38,
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(orders ? 15 : 12),
                  ),
                  child: Icon(
                    orders
                        ? Icons.restaurant_menu_rounded
                        : Icons.lunch_dining_rounded,
                    color: AppColors.accent,
                    size: orders ? 28 : 25,
                  ),
                ),
              ),
            ),
            SizedBox(width: orders ? 32 : 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (orders)
                    Text(
                      'Mis pedidos',
                      style: AppText.h3.copyWith(fontSize: 26),
                    )
                  else
                    RichText(
                      text: TextSpan(
                        style: AppText.h3.copyWith(fontSize: 22),
                        children: const [
                          TextSpan(text: 'Snack'),
                          TextSpan(
                            text: 'UP',
                            style: TextStyle(color: AppColors.tertiary),
                          ),
                        ],
                      ),
                    ),
                  Text(
                    orders ? 'CAMPUS DINING' : 'Tu cafetería, a un toque',
                    style: orders
                        ? AppText.notes.copyWith(
                            letterSpacing: 1.5,
                            fontSize: 13,
                          )
                        : AppText.notes,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Buscar comida',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => Scaffold(
                  appBar: AppBar(title: const Text('Buscar comida')),
                  body: const SearchScreen(),
                ),
              ),
            ),
            icon: const Icon(Icons.search_rounded),
          ),
          IconButton(
            tooltip: 'Mi carrito',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(builder: (_) => const CartScreen()),
            ),
            icon: const Icon(Icons.shopping_bag_outlined),
          ),
          PopupMenuButton<String>(
            tooltip: 'Mi cuenta',
            onSelected: (value) {
              if (value == 'profile') {
                setState(() => _selectedIndex = 3);
              } else {
                _logout();
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'profile',
                child: Text(user?['displayName']?.toString() ?? 'Mi perfil'),
              ),
              const PopupMenuItem(
                value: 'logout',
                child: Text('Cerrar sesión'),
              ),
            ],
            icon: CircleAvatar(
              radius: orders ? 20 : 16,
              backgroundColor: AppColors.paleBlue,
              child: Text(
                (user?['displayName']?.toString() ?? 'A').characters.first
                    .toUpperCase(),
                style: const TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: pages[_selectedIndex],
      bottomNavigationBar: desktopOrders
          ? null
          : Container(
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: AppColors.borders)),
              ),
              child: BottomNavigationBar(
                currentIndex: _selectedIndex,
                onTap: (index) => setState(() => _selectedIndex = index),
                items: const [
                  BottomNavigationBarItem(
                    icon: Icon(Icons.storefront_outlined),
                    activeIcon: Icon(Icons.storefront),
                    label: 'Inicio',
                  ),
                  BottomNavigationBarItem(
                    icon: Icon(Icons.receipt_long_outlined),
                    activeIcon: Icon(Icons.receipt_long),
                    label: 'Pedidos',
                  ),
                  BottomNavigationBarItem(
                    icon: Icon(Icons.favorite_outline),
                    activeIcon: Icon(Icons.favorite),
                    label: 'Favoritos',
                  ),
                  BottomNavigationBarItem(
                    icon: Icon(Icons.person_outline),
                    activeIcon: Icon(Icons.person),
                    label: 'Perfil',
                  ),
                ],
              ),
            ),
    );
  }
}
