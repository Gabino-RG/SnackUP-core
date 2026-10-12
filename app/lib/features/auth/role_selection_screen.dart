import 'package:flutter/material.dart';
import 'auth_repository.dart';
import 'privacy_terms_widget.dart';

/// Recovery for an authenticated account whose profile has not been saved yet.
/// Public completion can only create a student profile; it never selects roles.
class RoleSelectionScreen extends StatefulWidget {
  const RoleSelectionScreen({
    super.key,
    required this.userId,
    this.repository,
    this.onSignOut,
  });
  final String userId;
  final SnackAuthRepository? repository;
  final Future<void> Function()? onSignOut;
  @override
  State<RoleSelectionScreen> createState() => _RoleSelectionScreenState();
}

class _RoleSelectionScreenState extends State<RoleSelectionScreen> {
  late final SnackAuthRepository _repository;
  final _name = TextEditingController(), _control = TextEditingController();
  bool _accepted = false, _busy = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? FirebaseSnackAuthRepository();
    _name.text = _repository.currentAccount?.displayName ?? '';
  }

  @override
  void dispose() {
    _name.dispose();
    _control.dispose();
    super.dispose();
  }

  Future<void> _complete() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_repository.currentAccount?.uid != widget.userId) {
        throw const AuthActionException(
          'La sesión cambió. Inicia sesión otra vez.',
        );
      }
      await _repository.completeStudentProfile(
        StudentProfileInput(
          name: _name.text,
          controlNumber: _control.text,
          acceptedTerms: _accepted,
        ),
      );
      // RoleGate listens to the profile stream and routes only after its write.
    } catch (error) {
      if (mounted) setState(() => _error = authErrorMessage(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _exit() async {
    try {
      await (widget.onSignOut?.call() ?? _repository.signOut());
    } catch (error) {
      if (mounted) setState(() => _error = authErrorMessage(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final canComplete = isStudentEmail(_repository.currentAccount?.email ?? '');
    return Scaffold(
      appBar: AppBar(
        title: const Text('Completa tu registro'),
        actions: [
          IconButton(
            onPressed: _busy ? null : _exit,
            tooltip: 'Cerrar sesión',
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Tu cuenta está creada.',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    canComplete
                        ? 'Falta guardar tu perfil de estudiante. Puedes completar este paso sin crear otra cuenta.'
                        : 'Tu cuenta requiere que administración habilite el acceso y asigne el local, si corresponde.',
                  ),
                  const SizedBox(height: 24),
                  if (canComplete) ...[
                    TextField(
                      controller: _name,
                      enabled: !_busy,
                      maxLength: 120,
                      decoration: const InputDecoration(
                        labelText: 'Nombre y apellido',
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _control,
                      enabled: !_busy,
                      maxLength: 20,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Número de control',
                      ),
                    ),
                    const SizedBox(height: 20),
                    PrivacyTermsWidget(
                      onAccepted: (value) => setState(() => _accepted = value),
                    ),
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: _busy || !_accepted ? null : _complete,
                      child: Text(
                        _busy ? 'Guardando…' : 'Completar perfil de estudiante',
                      ),
                    ),
                  ],
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  const SizedBox(height: 20),
                  const Text(
                    'Los negocios y administradores son habilitados por la administración de SnackUP.',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
