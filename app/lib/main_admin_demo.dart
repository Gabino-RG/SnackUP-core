import 'package:flutter/material.dart';
import 'features/admin/admin_dashboard_screen.dart';
import 'features/admin/admin_theme.dart';
import 'features/admin/data/admin_repository.dart';

// Standalone offline preview: deliberately does not initialize Firebase.
void main() => runApp(const SnackUpAdminDemo());

class SnackUpAdminDemo extends StatelessWidget {
  const SnackUpAdminDemo({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'SnackUP · Administración (demo)',
    debugShowCheckedModeBanner: false,
    theme: adminTheme(),
    home: AdminDashboardScreen(repository: DemoAdminRepository()),
  );
}
