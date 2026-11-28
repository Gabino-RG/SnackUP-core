import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

Future<void> showPasswordRecovery(
  BuildContext context, {
  required String initialEmail,
  Future<void> Function(String email)? sendResetEmail,
}) {
  final messenger = ScaffoldMessenger.of(context);
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _PasswordRecoveryDialog(
      initialEmail: initialEmail,
      sendResetEmail:
          sendResetEmail ??
          (email) => FirebaseAuth.instance.sendPasswordResetEmail(email: email),
      onSent: () {
        if (messenger.mounted) {
          messenger.showSnackBar(
            const SnackBar(
              content: Text(
                'Si el correo tiene una cuenta, recibirás un enlace para restablecer tu contraseña. Revisa también spam.',
              ),
            ),
          );
        }
      },
    ),
  );
}

class _PasswordRecoveryDialog extends StatefulWidget {
  final String initialEmail;
  final Future<void> Function(String email) sendResetEmail;
  final VoidCallback onSent;

  const _PasswordRecoveryDialog({
    required this.initialEmail,
    required this.sendResetEmail,
    required this.onSent,
  });

  @override
  State<_PasswordRecoveryDialog> createState() =>
      _PasswordRecoveryDialogState();
}

class _PasswordRecoveryDialogState extends State<_PasswordRecoveryDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _emailController = TextEditingController(
    text: widget.initialEmail.trim(),
  );
  bool _isSending = false;
  bool _isClosing = false;
  String? _errorMessage;

  void _close() {
    _isClosing = true;
    Navigator.of(context).pop();
  }

  void _showError(String message) {
    if (!mounted || _isClosing) return;
    setState(() {
      _isSending = false;
      _errorMessage = message;
    });
  }

  Future<void> _send() async {
    if (_isSending || !_formKey.currentState!.validate()) return;
    setState(() {
      _isSending = true;
      _errorMessage = null;
    });
    try {
      await widget.sendResetEmail(_emailController.text.trim());
    } on FirebaseAuthException catch (error) {
      // La misma confirmación para cuentas existentes y desconocidas.
      if (error.code != 'user-not-found') {
        _showError(
          error.code == 'invalid-email'
              ? 'Ingresa un correo válido.'
              : error.code == 'too-many-requests'
              ? 'Espera unos minutos antes de volver a intentarlo.'
              : 'No se pudo enviar el correo. Revisa tu conexión e inténtalo de nuevo.',
        );
        return;
      }
    } catch (_) {
      _showError('No se pudo enviar el correo. Inténtalo de nuevo.');
      return;
    }
    if (!mounted || _isClosing) return;
    _close();
    widget.onSent();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_isSending,
    onPopInvokedWithResult: (didPop, _) {
      if (didPop) _isClosing = true;
    },
    child: AlertDialog(
      scrollable: true,
      title: const Text('Recuperar contraseña'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Escribe el correo con el que registraste tu cuenta.'),
            const SizedBox(height: 16),
            TextFormField(
              controller: _emailController,
              enabled: !_isSending,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              decoration: const InputDecoration(
                labelText: 'Correo electrónico',
              ),
              validator: (value) =>
                  RegExp(
                    r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
                  ).hasMatch(value?.trim() ?? '')
                  ? null
                  : 'Ingresa un correo válido',
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 12),
              Text(
                _errorMessage!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSending ? null : _close,
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _isSending ? null : _send,
          child: _isSending
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Enviar enlace'),
        ),
      ],
    ),
  );

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }
}
