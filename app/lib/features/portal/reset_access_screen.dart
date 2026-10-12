import 'package:flutter/material.dart';
import '../../api/api_client.dart';

class ResetAccessScreen extends StatefulWidget {
  const ResetAccessScreen({
    super.key,
    required this.api,
    required this.token,
    required this.onDone,
  });
  final ApiClient api;
  final String token;
  final VoidCallback onDone;
  @override
  State<ResetAccessScreen> createState() => _ResetAccessScreenState();
}

class _ResetAccessScreenState extends State<ResetAccessScreen> {
  final _form = GlobalKey<FormState>();
  final _password = TextEditingController(),
      _confirmation = TextEditingController();
  bool _busy = false, _done = false;
  String? _error;
  @override
  void dispose() {
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.api.json(
        'POST',
        'auth/reset-password',
        body: {'token': widget.token, 'newPassword': _password.text},
      );
      if (mounted)
        setState(() {
          _done = true;
          _password.clear();
          _confirmation.clear();
        });
    } catch (e) {
      if (mounted)
        setState(
          () => _error = e is ApiException && e.status == 422
              ? 'El enlace expiró o ya fue utilizado. Solicita uno nuevo desde el acceso.'
              : e is ApiException
              ? e.message
              : 'No se pudo cambiar la contraseña.',
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _form,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        _done
                            ? 'Contraseña actualizada'
                            : 'Restablecer contraseña',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 20),
                      if (_done)
                        const Text(
                          'Ya puedes iniciar sesión con tu nueva contraseña.',
                        )
                      else ...[
                        TextFormField(
                          controller: _password,
                          enabled: !_busy,
                          obscureText: true,
                          autocorrect: false,
                          enableSuggestions: false,
                          maxLength: 128,
                          decoration: const InputDecoration(
                            labelText: 'Nueva contraseña',
                          ),
                          validator: (v) => (v?.length ?? 0) < 12
                              ? 'Utiliza al menos 12 caracteres.'
                              : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _confirmation,
                          enabled: !_busy,
                          obscureText: true,
                          autocorrect: false,
                          enableSuggestions: false,
                          maxLength: 128,
                          decoration: const InputDecoration(
                            labelText: 'Repetir contraseña',
                          ),
                          validator: (v) => v != _password.text
                              ? 'Las contraseñas no coinciden.'
                              : null,
                        ),
                        if (_error != null)
                          Text(
                            _error!,
                            style: const TextStyle(color: Colors.red),
                          ),
                        const SizedBox(height: 20),
                        FilledButton(
                          onPressed: _busy ? null : _save,
                          child: Text(
                            _busy ? 'Guardando…' : 'Guardar contraseña',
                          ),
                        ),
                      ],
                      TextButton(
                        onPressed: _busy ? null : widget.onDone,
                        child: const Text('Ir al acceso'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
