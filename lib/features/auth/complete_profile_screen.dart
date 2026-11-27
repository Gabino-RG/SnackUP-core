import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

/// Permite recuperar un alta interrumpida después de crear la cuenta de Auth.
class CompleteProfileScreen extends StatefulWidget {
  final String userId;
  const CompleteProfileScreen({super.key, required this.userId});

  @override
  State<CompleteProfileScreen> createState() => _CompleteProfileScreenState();
}

class _CompleteProfileScreenState extends State<CompleteProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _controlController = TextEditingController();
  bool _isSaving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _nameController.text = FirebaseAuth.instance.currentUser?.displayName ?? '';
  }

  Future<void> _save() async {
    if (_isSaving || !_formKey.currentState!.validate()) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.uid != widget.userId) return;
    setState(() {
      _isSaving = true;
      _error = null;
    });
    try {
      await user.updateDisplayName(_nameController.text.trim());
      // Una transacción evita reemplazar un perfil creado mientras se recuperaba.
      final ref = FirebaseFirestore.instance.collection('users').doc(user.uid);
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final profile = await transaction.get(ref);
        if (!profile.exists) {
          transaction.set(ref, {
            'email': user.email ?? '',
            'numeroDeControl': _controlController.text.trim(),
            'role': 'user',
            'displayName': _nameController.text.trim(),
            'createdAt': FieldValue.serverTimestamp(),
          });
        }
      });
      // RoleGate observa el perfil y abre el inicio en cuanto queda guardado.
    } on FirebaseException catch (error) {
      if (!mounted) return;
      setState(
        () => _error = error.code == 'permission-denied'
            ? 'No se pudo completar el perfil. Usa tu cuenta institucional @utsjr.edu.mx.'
            : 'No se pudo guardar el perfil. Revisa tu conexión y vuelve a intentarlo.',
      );
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'No se pudo guardar el perfil. Inténtalo de nuevo.',
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Completar registro')),
    body: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Tu cuenta ya existe. Completa los datos que faltan para entrar a SnackUp.',
              ),
              const SizedBox(height: 24),
              TextFormField(
                controller: _nameController,
                enabled: !_isSaving,
                decoration: const InputDecoration(labelText: 'Nombre completo'),
                textCapitalization: TextCapitalization.words,
                maxLength: 120,
                validator: (value) =>
                    (value?.trim().split(RegExp(r'\s+')).length ?? 0) < 2
                    ? 'Ingresa nombre y apellido'
                    : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _controlController,
                enabled: !_isSaving,
                decoration: const InputDecoration(
                  labelText: 'Número de control',
                ),
                keyboardType: TextInputType.number,
                maxLength: 20,
                validator: (value) =>
                    RegExp(r'^\d{4,20}$').hasMatch(value?.trim() ?? '')
                    ? null
                    : 'Ingresa un número de control válido',
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _isSaving ? null : _save,
                child: Text(_isSaving ? 'Guardando...' : 'Completar registro'),
              ),
              TextButton(
                onPressed: _isSaving
                    ? null
                    : () => FirebaseAuth.instance.signOut(),
                child: const Text('Cerrar sesión'),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  @override
  void dispose() {
    _nameController.dispose();
    _controlController.dispose();
    super.dispose();
  }
}
