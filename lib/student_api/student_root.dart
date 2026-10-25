import '../api/platform_http.dart'
    if (dart.library.js_interop) '../api/platform_http_web.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/student_store.dart';
import '../theme/app_colors.dart';
import 'order_screens.dart';
import 'catalog_screens.dart';
import 'auth_screen.dart';

Future<bool> studentAction(
  BuildContext context,
  Future<void> Function() work, {
  String? success,
}) async {
  try {
    await work();
    if (context.mounted && success != null)
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(success)));
    return true;
  } catch (error) {
    if (context.mounted)
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString()),
          duration: const Duration(seconds: 8),
        ),
      );
    return false;
  }
}

String money(dynamic value) =>
    '\$${((value as num?) ?? 0).toStringAsFixed(2)} MXN';
Widget studentCard(Widget child) => Card(
  margin: const EdgeInsets.only(bottom: 16),
  child: Padding(padding: const EdgeInsets.all(20), child: child),
);
Widget studentPhoto(BuildContext context, String? path, {double size = 78}) {
  final api = context.read<StudentStore>().api;
  final url = path == null || path.isEmpty
      ? null
      : api.base.resolve(path).toString();
  final placeholder = Container(
    width: size,
    height: size,
    color: AppColors.background,
    child: const Icon(
      Icons.restaurant_rounded,
      color: AppColors.tertiary,
      size: 30,
    ),
  );
  return ClipRRect(
    borderRadius: BorderRadius.circular(16),
    child: url == null
        ? placeholder
        : Image.network(
            url,
            width: size,
            height: size,
            fit: BoxFit.cover,
            errorBuilder: (_, error, stack) => placeholder,
          ),
  );
}

void openStudent(BuildContext context, Widget screen) =>
    Navigator.push(context, MaterialPageRoute<void>(builder: (_) => screen));

class ApiStudentRoot extends StatefulWidget {
  const ApiStudentRoot({super.key});
  @override
  State<ApiStudentRoot> createState() => _ApiStudentRootState();
}

class _ApiStudentRootState extends State<ApiStudentRoot>
    with WidgetsBindingObserver {
  String? _resetToken;
  @override
  void initState() {
    super.initState();
    _resetToken = takeResetToken();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        mounted &&
        context.read<StudentStore>().user != null) {
      final store = context.read<StudentStore>();
      store.refresh().catchError((Object e) {
        store.error = e.toString();
        store.changed();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<StudentStore>();
    if (_resetToken != null)
      return StudentResetPasswordScreen(
        token: _resetToken,
        onDone: () => setState(() => _resetToken = null),
      );
    if (store.busy)
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (store.user == null) {
      if (Navigator.of(context).canPop())
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
        });
      return const StudentAuthScreen();
    }
    return const StudentDashboard();
  }
}

class StudentDashboard extends StatefulWidget {
  const StudentDashboard({super.key});
  @override
  State<StudentDashboard> createState() => _StudentDashboardState();
}

class _StudentDashboardState extends State<StudentDashboard> {
  int _index = 0;
  @override
  Widget build(BuildContext context) {
    final store = context.watch<StudentStore>();
    return Scaffold(
      appBar: AppBar(
        leading: const Icon(
          Icons.restaurant_rounded,
          color: AppColors.tertiary,
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(['SnackUP', 'Mis pedidos', 'Favoritos', 'Mi perfil'][_index]),
            const Text(
              'CAMPUS DINING',
              style: TextStyle(fontSize: 10, letterSpacing: 1.5),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            onPressed: () => studentAction(context, store.refresh),
            icon: const Icon(Icons.refresh_rounded),
          ),
          Badge(
            isLabelVisible: store.cartCount > 0,
            label: Text('${store.cartCount}'),
            child: IconButton(
              tooltip: 'Mi carrito',
              onPressed: () => openStudent(context, const StudentCartScreen()),
              icon: const Icon(Icons.shopping_bag_outlined),
            ),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: Column(
        children: [
          if (store.error != null)
            MaterialBanner(
              content: Text(store.error!),
              actions: [
                TextButton(
                  onPressed: () => studentAction(context, store.refresh),
                  child: const Text('Reintentar'),
                ),
              ],
            ),
          if (!store.connected)
            Container(
              width: double.infinity,
              color: AppColors.tertiary.withValues(alpha: .08),
              padding: const EdgeInsets.all(8),
              child: const Text(
                'Avisos en vivo desconectados. Puedes actualizar los pedidos manualmente.',
                style: TextStyle(fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ),
          Expanded(
            child: IndexedStack(
              index: _index,
              children: [
                const StudentCatalogScreen(),
                const StudentOrdersScreen(),
                const StudentCatalogScreen(favorites: true),
                StudentProfileScreen(
                  onOrders: () => setState(() => _index = 1),
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        backgroundColor: Colors.white,
        indicatorColor: AppColors.accent,
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
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
}

class StudentProfileScreen extends StatelessWidget {
  final VoidCallback onOrders;
  const StudentProfileScreen({super.key, required this.onOrders});
  @override
  Widget build(BuildContext context) {
    final store = context.watch<StudentStore>();
    final user = store.user ?? {};
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 700),
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            studentCard(
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const CircleAvatar(
                    radius: 32,
                    child: Icon(Icons.person_rounded, size: 36),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    user['displayName']?.toString() ?? 'Mi perfil',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  Text(user['email']?.toString() ?? ''),
                  if (user['numeroDeControl'] != null)
                    Text('Matrícula: ${user['numeroDeControl']}'),
                  const SizedBox(height: 12),
                  const Chip(label: Text('Comunidad universitaria')),
                ],
              ),
            ),
            studentCard(
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.receipt_long_rounded),
                title: const Text('Historial de consumo'),
                subtitle: const Text('Consulta tus pedidos y valora tu comida'),
                onTap: onOrders,
                trailing: const Icon(Icons.chevron_right_rounded),
              ),
            ),
            studentCard(
              const Text(
                'El carrito y tus favoritos se guardan por cuenta en este dispositivo. Los pedidos y las valoraciones se guardan en el servidor.',
              ),
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.logout_rounded),
              label: const Text('Cerrar sesión'),
              onPressed: () async {
                final yes = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('¿Cerrar sesión?'),
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
                if (yes == true && context.mounted)
                  await studentAction(context, store.logout);
              },
            ),
          ],
        ),
      ),
    );
  }
}
