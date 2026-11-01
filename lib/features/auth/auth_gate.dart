import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:snackup/student/auth_link.dart';
import 'package:snackup/student/auth_screens.dart';
import 'package:snackup/student/student_api.dart';
import 'package:snackup/student/student_widgets.dart';
import '../home/user_dashboard_screen.dart';

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  String? _resetToken;
  String? _seenUserId;
  bool _observedIdentity = false;

  @override
  void initState() {
    super.initState();
    final fragment = Uri.tryParse(Uri.base.fragment);
    if (fragment?.path == '/reset-password') {
      _resetToken = fragment?.queryParameters['token'] ?? '';
      clearAuthFragment();
    }
  }

  @override
  Widget build(BuildContext context) {
    final api = context.watch<StudentApi>();
    final userId = api.user?['id'] as String?;
    if (_observedIdentity && userId != _seenUserId) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          Navigator.of(context, rootNavigator: true).popUntil((route) => route.isFirst);
        }
      });
    }
    _observedIdentity = true;
    _seenUserId = userId;
    if (_resetToken != null) {
      return PasswordResetScreen(
        token: _resetToken!,
        onDone: () => setState(() => _resetToken = null),
      );
    }
    if (api.restoring) return const LoadingScreen();
    if (api.restoreError != null) {
      return Scaffold(
        body: ErrorPanel(error: api.restoreError!, onRetry: api.restore),
      );
    }
    if (!api.signedIn) return const LoginScreen();
    if (api.user?['role'] != 'ALUMNO') {
      return StudentAuthLayout(
        title: 'Portal de alumnos',
        subtitle:
            'Esta cuenta pertenece a otro perfil. Usa el portal de Cocina o Administración de tu equipo.',
        child: OutlinedButton(
          onPressed: () async {
            try {
              await api.logout();
            } catch (_) {
              /* Local session is cleared even when offline. */
            }
          },
          child: const Text('Volver al inicio de sesión'),
        ),
      );
    }
    return UserDashboardScreen(key: ValueKey(api.user!['id']));
  }
}

class LoadingScreen extends StatelessWidget {
  const LoadingScreen({super.key});
  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: CircularProgressIndicator()));
}
