import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class RoleSelectionScreen extends StatelessWidget {
  final String userId;
  const RoleSelectionScreen({super.key, required this.userId});

  Future<void> _selectRole(String role) async {
    // Guardamos el rol y el email en Firestore
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    await FirebaseFirestore.instance.collection('users').doc(userId).set({
      'role': role,
      'email': user.email, // Guardamos el email para referencia
      'displayName': user.displayName, // Y el nombre de Google
      'createdAt': FieldValue.serverTimestamp(),
    });
    // El AuthWrapper/RoleGate detectará el cambio y navegará
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Completa tu registro')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('¿Quién eres?', style: TextStyle(fontSize: 24)),
            const SizedBox(height: 30),
            ElevatedButton(
              onPressed: () => _selectRole('user'),
              child: const Text('Soy Alumno / Personal'),
            ),
            const SizedBox(height: 20),
             const Text(
                'Si eres un negocio, contacta al administrador.',
                style: TextStyle(fontStyle: FontStyle.italic, color: Colors.grey),
              ),
          ],
        ),
      ),
    );
  }
}