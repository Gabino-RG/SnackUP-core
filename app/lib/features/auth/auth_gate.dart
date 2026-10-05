import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'login_screen.dart';
import '../home/user_dashboard_screen.dart'; // <-- ¡USAMOS EL NUEVO DASHBOARD!
import '../home/business_home_screen.dart';
import '../admin/admin_dashboard_screen.dart';

// --- 1. AuthWrapper (Modificado) ---
class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.idTokenChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const LoadingScreen();
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

  Future<({bool admin, Map<String, dynamic>? profile})?> _loadAccess() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.uid != userId) return null;
    final token = await user.getIdTokenResult();
    // Administrative access is granted by a trusted backend custom claim.
    // A self-editable Firestore profile must never grant administrative access.
    if (token.claims?['admin'] == true) return (admin: true, profile: null);
    final profile = await FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .get();
    return (admin: false, profile: profile.data());
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<({bool admin, Map<String, dynamic>? profile})?>(
      future: _loadAccess(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const LoadingScreen();
        }
        if (snapshot.hasError) {
          return const Scaffold(
            body: Center(child: Text("Error al cargar datos")),
          );
        }
        final access = snapshot.data;
        if (access?.admin == true) {
          return AdminDashboardScreen(
            onSignOut: () => FirebaseAuth.instance.signOut(),
          );
        }
        if (access?.profile == null) {
          Future.microtask(() => FirebaseAuth.instance.signOut());
          return const LoginScreen();
        }

        final data = access!.profile!;
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

// --- Pantalla de Carga (Sin cambios) ---
class LoadingScreen extends StatelessWidget {
  const LoadingScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}
