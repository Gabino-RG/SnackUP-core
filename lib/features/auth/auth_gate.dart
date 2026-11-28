import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'login_screen.dart';
import 'complete_profile_screen.dart';
import '../home/user_dashboard_screen.dart'; // <-- ¡USAMOS EL NUEVO DASHBOARD!
import '../home/business_home_screen.dart';

// --- 1. AuthWrapper (Modificado) ---
class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  late final _authState = FirebaseAuth.instance.authStateChanges();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: _authState,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _StartupSplash();
        }
        if (snapshot.hasData) {
          return RoleGate(userId: snapshot.data!.uid);
        }
        return const LoginScreen();
      },
    );
  }
}

// --- 2. RoleGate (Modificado) ---
class RoleGate extends StatelessWidget {
  final String userId;
  const RoleGate({super.key, required this.userId});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const LoadingScreen();
        }
        if (snapshot.hasError) {
          return const Scaffold(
            body: Center(child: Text("Error al cargar datos")),
          );
        }
        if (!snapshot.hasData ||
            !snapshot.data!.exists ||
            snapshot.data!.data() == null) {
          return CompleteProfileScreen(userId: userId);
        }

        final data = snapshot.data!.data() as Map<String, dynamic>;
        final String? role = data['role'];

        if (role == 'business') {
          return const BusinessHomeScreen();
        } else if (role == 'user') {
          // --- ¡CAMBIO AQUÍ! ---
          // Mandamos al usuario al nuevo Dashboard
          return const UserDashboardScreen();
        }

        Future.microtask(() => FirebaseAuth.instance.signOut());
        return const LoginScreen();
      },
    );
  }
}

class LoadingScreen extends StatelessWidget {
  const LoadingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}

class _StartupSplash extends StatelessWidget {
  const _StartupSplash();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF4A54DF), Color(0xFFC942BA)],
          ),
        ),
        child: Center(
          child: FractionallySizedBox(
            widthFactor: 0.6,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320, maxHeight: 320),
              child: Image.asset(
                'web/logo_carga.png',
                fit: BoxFit.contain,
                semanticLabel: 'Cargando SnackUp',
              ),
            ),
          ),
        ),
      ),
    );
  }
}
