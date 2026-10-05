import 'package:flutter/material.dart';
import 'auth_repository.dart';
import 'login_screen.dart';
import 'role_selection_screen.dart';
import '../home/user_dashboard_screen.dart';
import '../home/business_home_screen.dart';
import '../admin/admin_dashboard_screen.dart';

/// The root of all authenticated navigation; entry forms never choose a role.
class AuthWrapper extends StatefulWidget {
  const AuthWrapper({
    super.key,
    this.repository,
    this.studentBuilder,
    this.businessBuilder,
    this.adminBuilder,
  });
  final SnackAuthRepository? repository;
  final WidgetBuilder? studentBuilder, businessBuilder, adminBuilder;
  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  late final SnackAuthRepository _repository;
  late Stream<SnackAccount?> _accounts;
  String? _previousUid;
  String? _previousAccess;
  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? FirebaseSnackAuthRepository();
    _listen();
  }

  void _listen() {
    _accounts = _repository.watchAccount().map((account) {
      // Remove protected detail routes when the session ends, including logout
      // initiated from a screen deeper in the existing Navigator stack.
      if (_previousUid != null && account?.uid != _previousUid) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
        });
      }
      if (account == null) _previousAccess = null;
      _previousUid = account?.uid;
      return account;
    });
  }

  void _accessChanged(String access) {
    if (_previousAccess != null && _previousAccess != access && mounted) {
      // RoleGate invokes this after the frame; do not queue another callback
      // that could remain pending on a static protected detail screen.
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
    _previousAccess = access;
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<SnackAccount?>(
    stream: _accounts,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return AccessProblem(
          message: 'No se pudo comprobar tu sesión.',
          onRetry: () => setState(_listen),
          onSignOut: _repository.signOut,
        );
      }
      if (snapshot.connectionState == ConnectionState.waiting) {
        return const LoadingScreen();
      }
      final account = snapshot.data;
      if (account == null) return LoginScreen(repository: _repository);
      return RoleGate(
        key: ValueKey(account),
        userId: account.uid,
        onAccessChanged: _accessChanged,
        repository: _repository,
        studentBuilder: widget.studentBuilder,
        businessBuilder: widget.businessBuilder,
        adminBuilder: widget.adminBuilder,
      );
    },
  );
}

class RoleGate extends StatefulWidget {
  const RoleGate({
    super.key,
    required this.userId,
    this.repository,
    this.studentBuilder,
    this.businessBuilder,
    this.adminBuilder,
    this.onAccessChanged,
  });
  final String userId;
  final ValueChanged<String>? onAccessChanged;
  final SnackAuthRepository? repository;
  final WidgetBuilder? studentBuilder, businessBuilder, adminBuilder;
  @override
  State<RoleGate> createState() => _RoleGateState();
}

class _RoleGateState extends State<RoleGate> {
  late final SnackAuthRepository _repository;
  late Future<Map<String, dynamic>> _claims;
  late Stream<Map<String, dynamic>?> _profile;
  Future<bool>? _business;
  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? FirebaseSnackAuthRepository();
    _reload();
  }

  void _reload() {
    _claims = _repository.loadClaims(widget.userId);
    _profile = _repository.watchProfile(widget.userId);
    _business = null;
  }

  void _retry() => setState(_reload);
  Future<void> _signOut() async {
    try {
      await _repository.signOut();
      if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(authErrorMessage(error))));
      }
    }
  }

  Widget _resolved(String access, Widget screen) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onAccessChanged?.call(access);
    });
    return screen;
  }

  Widget _problem(String text) => _resolved(
    'blocked',
    AccessProblem(message: text, onRetry: _retry, onSignOut: _signOut),
  );
  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, dynamic>>(
    future: _claims,
    builder: (context, claims) {
      if (claims.connectionState != ConnectionState.done) {
        return const LoadingScreen();
      }
      if (claims.hasError) {
        return _problem(
          'No se pudo verificar tu acceso. Puedes reintentar sin perder tu sesión.',
        );
      }
      if (hasAdministrativeClaim(claims.data ?? {})) {
        return _resolved(
          'admin',
          widget.adminBuilder?.call(context) ??
              AdminDashboardScreen(onSignOut: _signOut),
        );
      }
      return StreamBuilder<Map<String, dynamic>?>(
        stream: _profile,
        builder: (context, profile) {
          if (profile.hasError) {
            return _problem(
              'No se pudo cargar tu perfil. Revisa tu conexión y permisos.',
            );
          }
          if (profile.connectionState == ConnectionState.waiting) {
            return const LoadingScreen();
          }
          switch (profileRole(profile.data)) {
            case SnackRole.incomplete:
              return _resolved(
                'incomplete',
                RoleSelectionScreen(
                  userId: widget.userId,
                  repository: _repository,
                  onSignOut: _signOut,
                ),
              );
            case SnackRole.student:
              return _resolved(
                'student',
                widget.studentBuilder?.call(context) ??
                    const UserDashboardScreen(),
              );
            case SnackRole.business:
              _business ??= _repository.ownsBusiness(widget.userId);
              return FutureBuilder<bool>(
                future: _business,
                builder: (context, business) {
                  if (business.connectionState != ConnectionState.done) {
                    return const LoadingScreen();
                  }
                  if (business.hasError) {
                    return _problem(
                      'No se pudo comprobar el local asociado. Reintenta.',
                    );
                  }
                  if (business.data != true) {
                    return _problem(
                      'Tu cuenta de negocio aún no tiene un local asignado. Contacta a administración.',
                    );
                  }
                  return _resolved(
                    'business',
                    widget.businessBuilder?.call(context) ??
                        const BusinessHomeScreen(),
                  );
                },
              );
            case SnackRole.unsupported:
              return _problem(
                'El perfil no tiene un acceso habilitado. Contacta a administración.',
              );
          }
        },
      );
    },
  );
}

class AccessProblem extends StatefulWidget {
  const AccessProblem({
    super.key,
    required this.message,
    required this.onRetry,
    required this.onSignOut,
  });
  final String message;
  final VoidCallback onRetry;
  final Future<void> Function() onSignOut;
  @override
  State<AccessProblem> createState() => _AccessProblemState();
}

class _AccessProblemState extends State<AccessProblem> {
  bool _busy = false;
  Future<void> _exit() async {
    setState(() => _busy = true);
    try {
      await widget.onSignOut();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(authErrorMessage(error))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_outline, size: 40),
              const SizedBox(height: 16),
              Text(widget.message, textAlign: TextAlign.center),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _busy ? null : widget.onRetry,
                child: const Text('Reintentar'),
              ),
              TextButton(
                onPressed: _busy ? null : _exit,
                child: Text(_busy ? 'Cerrando sesión…' : 'Cerrar sesión'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class LoadingScreen extends StatelessWidget {
  const LoadingScreen({super.key});
  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: CircularProgressIndicator()));
}
