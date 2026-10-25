import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../api/student_store.dart';
import '../theme/app_colors.dart';
import 'student_root.dart';

class StudentAuthScreen extends StatefulWidget {
  const StudentAuthScreen({super.key});
  @override
  State<StudentAuthScreen> createState() => _StudentAuthScreenState();
}

class _StudentAuthScreenState extends State<StudentAuthScreen> {
  final _email = TextEditingController(),
      _password = TextEditingController(),
      _name = TextEditingController(),
      _control = TextEditingController();
  bool _register = false, _busy = false, _hidden = true;
  String? _message;
  @override
  void dispose() {
    for (final c in [_email, _password, _name, _control]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (_email.text.trim().isEmpty ||
        _password.text.isEmpty ||
        (_register &&
            (_name.text.trim().isEmpty ||
                _control.text.trim().isEmpty ||
                _password.text.length < 12))) {
      setState(
        () => _message = _register
            ? 'Completa tus datos y usa una contraseña de al menos 12 caracteres.'
            : 'Escribe tu correo y contraseña.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    final store = context.read<StudentStore>();
    try {
      if (_register) {
        await store.api.request(
          'POST',
          'auth/register',
          authenticated: false,
          body: {
            'email': _email.text.trim(),
            'password': _password.text,
            'displayName': _name.text.trim(),
            'numeroDeControl': _control.text.trim(),
          },
        );
        if (mounted)
          setState(() {
            _register = false;
            _message =
                'Solicitud recibida. Si tus datos cumplen los requisitos, recibirás un correo de confirmación. Después podrás iniciar sesión.';
          });
      } else {
        await store.login(_email.text, _password.text);
      }
    } catch (error) {
      if (mounted) setState(() => _message = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _emailAction(String path, String title) async {
    if (_email.text.trim().isEmpty) {
      setState(() => _message = 'Escribe primero tu correo institucional.');
      return;
    }
    setState(() => _busy = true);
    try {
      await context.read<StudentStore>().api.request(
        'POST',
        path,
        authenticated: false,
        body: {'email': _email.text.trim()},
      );
      if (mounted)
        setState(
          () => _message =
              '$title. Si corresponde, recibirás instrucciones por correo.',
        );
    } catch (e) {
      if (mounted) setState(() => _message = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<StudentStore>();
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.all(24),
              children: [
                const Icon(
                  Icons.restaurant_rounded,
                  color: AppColors.tertiary,
                  size: 64,
                ),
                const SizedBox(height: 18),
                Text(
                  'SnackUP',
                  style: Theme.of(context).textTheme.displayMedium,
                  textAlign: TextAlign.center,
                ),
                const Text(
                  'Tu comida favorita en el campus',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 28),
                studentCard(
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        _register
                            ? 'Crear cuenta de alumno'
                            : 'Bienvenido de nuevo',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 20),
                      TextField(
                        controller: _email,
                        enabled: !_busy,
                        keyboardType: TextInputType.emailAddress,
                        autofillHints: const [AutofillHints.username],
                        decoration: const InputDecoration(
                          labelText: 'Correo institucional',
                        ),
                      ),
                      const SizedBox(height: 14),
                      if (_register) ...[
                        TextField(
                          controller: _name,
                          enabled: !_busy,
                          decoration: const InputDecoration(
                            labelText: 'Nombre completo',
                          ),
                        ),
                        const SizedBox(height: 14),
                        TextField(
                          controller: _control,
                          enabled: !_busy,
                          decoration: const InputDecoration(
                            labelText: 'Matrícula / número de control',
                          ),
                        ),
                        const SizedBox(height: 14),
                      ],
                      TextField(
                        controller: _password,
                        enabled: !_busy,
                        obscureText: _hidden,
                        autofillHints: [
                          _register
                              ? AutofillHints.newPassword
                              : AutofillHints.password,
                        ],
                        decoration: InputDecoration(
                          labelText: 'Contraseña',
                          suffixIcon: IconButton(
                            tooltip: 'Mostrar contraseña',
                            onPressed: () => setState(() => _hidden = !_hidden),
                            icon: Icon(
                              _hidden
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                          ),
                        ),
                        onSubmitted: (_) {
                          if (!_busy) _submit();
                        },
                      ),
                      if (_register)
                        const Padding(
                          padding: EdgeInsets.only(top: 12),
                          child: Text(
                            'Verificaremos tus datos con el padrón institucional. Confirma tu correo antes de acceder.',
                          ),
                        ),
                      if (_message != null || store.error != null)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          child: SelectableText(_message ?? store.error!),
                        ),
                      const SizedBox(height: 20),
                      FilledButton(
                        onPressed: _busy ? null : _submit,
                        child: Text(
                          _busy
                              ? 'Espera…'
                              : _register
                              ? 'Solicitar registro'
                              : 'Iniciar sesión',
                        ),
                      ),
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () => setState(() {
                                _register = !_register;
                                _message = null;
                              }),
                        child: Text(
                          _register ? 'Ya tengo cuenta' : 'Crear cuenta nueva',
                        ),
                      ),
                      if (!_register) ...[
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => _emailAction(
                                  'auth/forgot-password',
                                  'Solicitud recibida',
                                ),
                          child: const Text('Olvidé mi contraseña'),
                        ),
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => _emailAction(
                                  'auth/resend-verification',
                                  'Solicitud de confirmación recibida',
                                ),
                          child: const Text('Reenviar confirmación de correo'),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class StudentResetPasswordScreen extends StatefulWidget {
  final String? token;
  final VoidCallback onDone;
  const StudentResetPasswordScreen({
    super.key,
    this.token,
    required this.onDone,
  });
  @override
  State<StudentResetPasswordScreen> createState() =>
      _StudentResetPasswordScreenState();
}

class _StudentResetPasswordScreenState
    extends State<StudentResetPasswordScreen> {
  late final _token = TextEditingController(text: widget.token);
  final _password = TextEditingController(),
      _confirmation = TextEditingController();
  bool _busy = false, _done = false;
  String? _error;
  @override
  void dispose() {
    _token.dispose();
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  Future<void> _reset() async {
    if (_token.text.trim().isEmpty ||
        _password.text.length < 12 ||
        _password.text != _confirmation.text) {
      setState(
        () => _error =
            'Usa al menos 12 caracteres y confirma la misma contraseña.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final api = context.read<StudentStore>().api;
    try {
      await api.request(
        'POST',
        'auth/reset-password',
        authenticated: false,
        body: {'token': _token.text.trim(), 'newPassword': _password.text},
      );
      await api.clear();
      _token.clear();
      _password.clear();
      _confirmation.clear();
      if (mounted) setState(() => _done = true);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Restablecer contraseña')),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(24),
          children: [
            if (_done) ...[
              const Text(
                'Tu contraseña fue actualizada. Inicia sesión de nuevo.',
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: widget.onDone,
                child: const Text('Ir al acceso'),
              ),
            ] else ...[
              const Text(
                'El enlace de recuperación es privado y solo puede utilizarse una vez.',
              ),
              const SizedBox(height: 20),
              if (widget.token == null)
                TextField(
                  controller: _token,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Token del enlace de recuperación',
                  ),
                ),
              const SizedBox(height: 12),
              TextField(
                controller: _password,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Nueva contraseña',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _confirmation,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Confirmar contraseña',
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: SelectableText(_error!),
                ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _busy ? null : _reset,
                child: Text(_busy ? 'Actualizando…' : 'Guardar contraseña'),
              ),
              TextButton(
                onPressed: _busy ? null : widget.onDone,
                child: const Text('Volver al acceso'),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}
