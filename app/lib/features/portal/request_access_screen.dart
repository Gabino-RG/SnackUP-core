import 'package:flutter/material.dart';
import '../../api/access_repository.dart';
import '../../operations/kitchen_controller.dart';

class RequestAccessScreen extends StatefulWidget {
  const RequestAccessScreen({super.key, required this.repository});
  final AccessRepository repository;
  @override
  State<RequestAccessScreen> createState() => _RequestAccessScreenState();
}

class _RequestAccessScreenState extends State<RequestAccessScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController(),
      _email = TextEditingController(),
      _password = TextEditingController(),
      _context = TextEditingController(),
      _confirm = TextEditingController();
  String _role = 'business';
  String? _error;
  bool _busy = false, _sent = false, _hide = true;
  @override
  void dispose() {
    for (final c in [_name, _email, _password, _context, _confirm]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _send() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.repository.register(
        name: _name.text,
        email: _email.text,
        password: _password.text,
        requestedRole: _role,
        context: _context.text,
      );
      if (mounted) setState(() => _sent = true);
    } catch (e) {
      if (mounted) setState(() => _error = operationsMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Crea tu cuenta')),
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: _sent
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.mark_email_read_outlined, size: 48),
                      const SizedBox(height: 20),
                      Text(
                        'Solicitud recibida',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'La cuenta maestra debe revisar tus datos y autorizar tu acceso. Todavía no puedes entrar a los paneles. Si ya tenías una cuenta, conserva tu contraseña anterior.',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      FilledButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Volver al acceso'),
                      ),
                    ],
                  )
                : Form(
                    key: _form,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'Solicita acceso a SnackUP. La cuenta maestra confirmará tu identidad, tu función y el local que te corresponde.',
                        ),
                        const SizedBox(height: 20),
                        TextFormField(
                          controller: _name,
                          enabled: !_busy,
                          maxLength: 100,
                          autofillHints: const [AutofillHints.name],
                          decoration: const InputDecoration(
                            labelText: 'Nombre completo',
                          ),
                          validator: (v) => (v?.trim().isEmpty ?? true)
                              ? 'Escribe tu nombre.'
                              : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _email,
                          enabled: !_busy,
                          maxLength: 160,
                          keyboardType: TextInputType.emailAddress,
                          autofillHints: const [AutofillHints.email],
                          decoration: const InputDecoration(
                            labelText: 'Correo electrónico',
                          ),
                          validator: (v) =>
                              RegExp(
                                r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
                              ).hasMatch(v?.trim() ?? '')
                              ? null
                              : 'Escribe un correo válido.',
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          value: _role,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Acceso que solicitas',
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 'business',
                              child: Text('Operar un local'),
                            ),
                            DropdownMenuItem(
                              value: 'admin',
                              child: Text('Administración institucional'),
                            ),
                          ],
                          onChanged: _busy
                              ? null
                              : (v) => setState(() => _role = v!),
                        ),
                        const SizedBox(height: 8),
                        if (_role == 'admin')
                          const Padding(
                            padding: EdgeInsets.only(bottom: 12),
                            child: Text(
                              'Utiliza el correo institucional que te asignó la universidad.',
                            ),
                          ),
                        TextFormField(
                          controller: _context,
                          enabled: !_busy,
                          maxLength: 400,
                          minLines: 2,
                          maxLines: 3,
                          decoration: const InputDecoration(
                            labelText: 'Local o área y motivo de acceso',
                          ),
                          validator: (v) => (v?.trim().isEmpty ?? true)
                              ? 'Indica a qué local o área perteneces.'
                              : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _password,
                          enabled: !_busy,
                          obscureText: _hide,
                          autocorrect: false,
                          enableSuggestions: false,
                          maxLength: 128,
                          autofillHints: const [AutofillHints.newPassword],
                          decoration: InputDecoration(
                            labelText: 'Contraseña',
                            helperText: 'Al menos 12 caracteres.',
                            suffixIcon: IconButton(
                              tooltip: _hide
                                  ? 'Mostrar contraseña'
                                  : 'Ocultar contraseña',
                              onPressed: () => setState(() => _hide = !_hide),
                              icon: Icon(
                                _hide ? Icons.visibility_off : Icons.visibility,
                              ),
                            ),
                          ),
                          validator: (v) => (v?.length ?? 0) < 12
                              ? 'Usa al menos 12 caracteres.'
                              : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _confirm,
                          enabled: !_busy,
                          obscureText: _hide,
                          autocorrect: false,
                          enableSuggestions: false,
                          maxLength: 128,
                          decoration: const InputDecoration(
                            labelText: 'Confirmar contraseña',
                          ),
                          validator: (v) => v != _password.text
                              ? 'Las contraseñas no coinciden.'
                              : null,
                        ),
                        if (_error != null)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Text(
                              _error!,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ),
                        const SizedBox(height: 20),
                        FilledButton(
                          onPressed: _busy ? null : _send,
                          child: Text(_busy ? 'Enviando…' : 'Solicitar acceso'),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Enviar esta solicitud no concede permisos ni asigna un local.',
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
          ),
        ),
      ),
    ),
  );
}
