import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'login_screen.dart';
import '../home/user_dashboard_screen.dart'; // <-- ¡USAMOS EL NUEVO DASHBOARD!
import '../home/business_home_screen.dart';

// --- 1. AuthWrapper (Modificado) ---
class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
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

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance.collection('users').doc(userId).get(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const LoadingScreen();
        }
        if (snapshot.hasError) {
          return const Scaffold(body: Center(child: Text("Error al cargar datos")));
        }
        if (!snapshot.data!.exists || snapshot.data!.data() == null) {
          Future.microtask(() => FirebaseAuth.instance.signOut());
          return const LoginScreen(); 
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

// --- Pantalla de Carga (Sin cambios) ---
class LoadingScreen extends StatelessWidget {
  const LoadingScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: CircularProgressIndicator(),
      ),
    );
  }
}
