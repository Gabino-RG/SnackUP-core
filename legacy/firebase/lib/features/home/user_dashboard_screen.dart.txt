import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'user_home_screen.dart';
import '../user/search_screen.dart';
import '../user/cart_screen.dart';
import '../user/profile_orders_screen.dart';
import '../user/customer_profile_screen.dart';
import '../../theme/app_colors.dart';

class UserDashboardScreen extends StatefulWidget {
  const UserDashboardScreen({super.key});
  @override
  State<UserDashboardScreen> createState() => _UserDashboardScreenState();
}

class _UserDashboardScreenState extends State<UserDashboardScreen> {
  int _index = 0;
  static const _titles = ['SnackUP', 'Mis pedidos', 'Favoritos', 'Mi perfil'];
  void _open(Widget screen) => Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => screen));
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      leading: Padding(
        padding: const EdgeInsets.all(10),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(
            Icons.local_dining_rounded,
            color: AppColors.accent,
            size: 22,
          ),
        ),
      ),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _titles[_index],
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 21),
          ),
          const Text(
            'CAMPUS DINING',
            style: TextStyle(
              fontSize: 10,
              letterSpacing: 1.5,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
      actions: [
        IconButton(
          tooltip: 'Buscar comida',
          icon: const Icon(Icons.search_rounded),
          onPressed: () => _open(const SearchScreen()),
        ),
        IconButton(
          tooltip: 'Mi carrito',
          icon: const Icon(Icons.shopping_bag_outlined),
          onPressed: () => _open(const CartScreen()),
        ),
        IconButton(
          tooltip: 'Mi perfil',
          icon: CircleAvatar(
            radius: 16,
            backgroundColor: AppColors.tertiary.withOpacity(.12),
            child: Text(
              (FirebaseAuth.instance.currentUser?.email ?? 'U')
                  .substring(0, 1)
                  .toUpperCase(),
              style: const TextStyle(color: AppColors.primary),
            ),
          ),
          onPressed: () => setState(() => _index = 3),
        ),
        const SizedBox(width: 8),
      ],
    ),
    body: IndexedStack(
      index: _index,
      children: [
        const UserHomeScreen(),
        const ProfileOrdersScreen(),
        const ProfileOrdersScreen(initialTab: 2, favoritesOnly: true),
        CustomerProfileScreen(onOrders: () => setState(() => _index = 1)),
      ],
    ),
    bottomNavigationBar: NavigationBar(
      backgroundColor: Colors.white,
      indicatorColor: AppColors.accent,
      selectedIndex: _index,
      onDestinationSelected: (index) => setState(() => _index = index),
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.storefront_outlined),
          label: 'Inicio',
        ),
        NavigationDestination(
          icon: Icon(Icons.receipt_long_outlined),
          label: 'Pedidos',
        ),
        NavigationDestination(
          icon: Icon(Icons.favorite_border_rounded),
          label: 'Favoritos',
        ),
        NavigationDestination(
          icon: Icon(Icons.person_outline_rounded),
          label: 'Perfil',
        ),
      ],
    ),
  );
}
