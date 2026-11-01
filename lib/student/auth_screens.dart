import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'student_api.dart';
import 'student_widgets.dart';
import 'local_demo.dart';
import 'email_policy.dart';
import 'registration_privacy.dart';
import 'package:snackup/theme/student_colors.dart';

const _studentDomain = localRegistrationDemo
    ? 'students.example.edu'
    : institutionalStudentDomain;

String? _emailError(String? value) =>
    studentEmailError(value, domain: _studentDomain);

String? _newPasswordError(String? value) =>
    (value?.length ?? 0) >= 12 && (value?.length ?? 0) <= 128
    ? null
    : 'Usa entre 12 y 128 caracteres.';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  Future<Map<String, dynamic>>? _options;
  bool _busy = false;
  bool _hide = true;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _options ??= context.read<StudentApi>().getObject(
      '/auth/options',
      authenticated: false,
    );
  }

  Future<void> _login() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<StudentApi>().login(
        _email.text.trim(),
        _password.text,
      );
    } catch (error) {
      if (mounted) setState(() => _error = friendlyError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _mailAction(bool resend) async {
    final controller = TextEditingController(text: _email.text.trim());
    final form = GlobalKey<FormState>();
    var sending = false;
    String? message;
    var sent = false;
    final api = context.read<StudentApi>();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(resend ? 'Confirmar mi correo' : 'Recuperar contraseña'),
          content: SizedBox(
            width: 380,
            child: Form(
              key: form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!sent)
                    TextFormField(
                      controller: controller,
                      autofocus: true,
                      keyboardType: TextInputType.emailAddress,
                      validator: _emailError,
                      decoration: const InputDecoration(
                        labelText: 'Correo institucional',
                      ),
                    ),
                  if (message != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(message!),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: sending ? null : () => Navigator.pop(dialogContext),
              child: Text(sent ? 'Entendido' : 'Cancelar'),
            ),
            if (!sent)
              FilledButton(
                onPressed: sending
                    ? null
                    : () async {
                        if (!form.currentState!.validate()) return;
                        setDialogState(() {
                          sending = true;
                          message = null;
                        });
                        try {
                          await api.request(
                            'POST',
                            resend
                                ? '/auth/resend-verification'
                                : '/auth/forgot-password',
                            body: {'email': controller.text.trim()},
                            authenticated: false,
                          );
                          if (!dialogContext.mounted) return;
                          setDialogState(() {
                            sent = true;
                            message =
                                'Solicitud recibida. Si tu cuenta corresponde, recibirás un enlace en tu correo. Revisa también la carpeta de spam.';
                          });
                        } catch (error) {
                          if (dialogContext.mounted) {
                            setDialogState(
                              () => message = friendlyError(error),
                            );
                          }
                        } finally {
                          if (dialogContext.mounted) {
                            setDialogState(() => sending = false);
                          }
                        }
                      },
                child: Text(sending ? 'Enviando…' : 'Enviar enlace'),
              ),
          ],
        ),
      ),
    );
    // Wait for the dialog's exit animation before releasing its text controller.
    await Future<void>.delayed(const Duration(milliseconds: 250));
    controller.dispose();
  }

  @override
  Widget build(BuildContext context) => StudentAuthLayout(
    title: 'Bienvenido a SnackUP',
    subtitle: 'Pide en tu cafetería y sigue tu pedido desde aquí.',
    child: Form(
      key: _form,
      child: AutofillGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _email,
              enabled: !_busy,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.username],
              validator: _emailError,
              decoration: const InputDecoration(
                labelText: 'Correo institucional',
                prefixIcon: Icon(Icons.alternate_email),
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _password,
              enabled: !_busy,
              obscureText: _hide,
              autofillHints: const [AutofillHints.password],
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _login(),
              validator: (value) => value == null || value.isEmpty
                  ? 'Escribe tu contraseña.'
                  : null,
              decoration: InputDecoration(
                labelText: 'Contraseña',
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  tooltip: _hide ? 'Mostrar contraseña' : 'Ocultar contraseña',
                  onPressed: () => setState(() => _hide = !_hide),
                  icon: Icon(
                    _hide
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                  ),
                ),
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _busy ? null : _login,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(_busy ? 'Iniciando sesión…' : 'Iniciar sesión'),
              ),
            ),
            const SizedBox(height: 12),
            FutureBuilder<Map<String, dynamic>>(
              future: _options,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Column(
                    children: [
                      Text(
                        friendlyError(snapshot.error!),
                        textAlign: TextAlign.center,
                      ),
                      TextButton(
                        onPressed: () => setState(() {
                          _options = context.read<StudentApi>().getObject(
                            '/auth/options',
                            authenticated: false,
                          );
                        }),
                        child: const Text('Reintentar conexión'),
                      ),
                    ],
                  );
                }
                final available = snapshot.data?['selfRegistration'] == true;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    OutlinedButton(
                      onPressed: !_busy && available
                          ? () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => const RegisterScreen(),
                              ),
                            )
                          : null,
                      child: const Text('Crear cuenta de alumno'),
                    ),
                    if (snapshot.hasData && !available)
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Text(
                          'El registro y la recuperación por correo aún no están habilitados. Puedes entrar con una cuenta ya autorizada.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    TextButton(
                      onPressed: !_busy && available
                          ? () => _mailAction(false)
                          : null,
                      child: const Text('Olvidé mi contraseña'),
                    ),
                    TextButton(
                      onPressed: !_busy && available
                          ? () => _mailAction(true)
                          : null,
                      child: const Text('Reenviar confirmación de correo'),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    ),
  );

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }
}

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});
  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _control = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  bool _received = false;
  bool _acceptedDocuments = false;
  String? _error;

  Future<void> _register() async {
    if (_busy || !_acceptedDocuments || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<StudentApi>().register(
        email: _email.text.trim(),
        password: _password.text,
        displayName: _name.text.trim(),
        numeroDeControl: _control.text.trim(),
      );
      if (mounted) setState(() => _received = true);
    } catch (error) {
      if (mounted) setState(() => _error = friendlyError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => StudentAuthLayout(
    title: _received ? 'Solicitud recibida' : 'Tu cuenta de alumno',
    subtitle: _received
        ? 'Si tu correo y matrícula corresponden al padrón autorizado, recibirás un enlace para confirmar tu correo antes de iniciar sesión.'
        : 'Tu correo @$_studentDomain y tu matrícula deben estar previamente autorizados en el padrón de SnackUP.',
    child: _received
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Padding(
                padding: EdgeInsets.only(bottom: 20),
                child: Text(
                  'Revisa también tu carpeta de correo no deseado. Si no recibes el enlace, comprueba tu correo y matrícula y consulta al equipo de SnackUP para revisar tu autorización.',
                ),
              ),
              if (localRegistrationDemo)
                const Padding(
                  padding: EdgeInsets.only(bottom: 20),
                  child: Column(
                    children: [
                      Text(
                        'Abre el buzón local y confirma el enlace del correo dirigido a tu cuenta.',
                      ),
                      SizedBox(height: 10),
                      SelectableText('http://localhost:8025'),
                    ],
                  ),
                ),
              FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Volver a iniciar sesión'),
              ),
            ],
          )
        : Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (localRegistrationDemo) const LocalRegistrationHint(),
                TextFormField(
                  controller: _name,
                  enabled: !_busy,
                  textCapitalization: TextCapitalization.words,
                  maxLength: 160,
                  decoration: const InputDecoration(
                    labelText: 'Nombre completo',
                  ),
                  validator: (value) => (value?.trim().isEmpty ?? true)
                      ? 'Escribe tu nombre.'
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _control,
                  enabled: !_busy,
                  maxLength: 50,
                  decoration: const InputDecoration(
                    labelText: 'Matrícula o número de control',
                    helperText: 'Escríbela como aparece en tu registro escolar',
                    helperMaxLines: 2,
                  ),
                  validator: (value) => (value?.trim().isEmpty ?? true)
                      ? 'Escribe tu matrícula.'
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _email,
                  enabled: !_busy,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Correo institucional',
                    helperText: 'Solo correos @$_studentDomain',
                  ),
                  validator: _emailError,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _password,
                  enabled: !_busy,
                  obscureText: true,
                  autofillHints: const [AutofillHints.newPassword],
                  decoration: const InputDecoration(
                    labelText: 'Contraseña',
                    helperText: 'Entre 12 y 128 caracteres',
                  ),
                  validator: _newPasswordError,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _confirm,
                  enabled: !_busy,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Confirmar contraseña',
                  ),
                  validator: (value) => value == _password.text
                      ? null
                      : 'Las contraseñas no coinciden.',
                ),
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
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.borders),
                  ),
                  child: const Text(
                    registrationDataNotice,
                    textAlign: TextAlign.justify,
                    style: TextStyle(fontSize: 14, height: 1.6),
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 12,
                  runSpacing: 4,
                  children: [
                    TextButton.icon(
                      key: const ValueKey('open-data-protection'),
                      onPressed: () => showRegistrationDocument(
                        context,
                        RegistrationDocument.protection,
                      ),
                      icon: const Icon(Icons.shield_outlined, size: 20),
                      label: const Text('Protección de Datos'),
                    ),
                    TextButton.icon(
                      key: const ValueKey('open-privacy-policy'),
                      onPressed: () => showRegistrationDocument(
                        context,
                        RegistrationDocument.privacy,
                      ),
                      icon: const Icon(Icons.privacy_tip_outlined, size: 20),
                      label: const Text('Política de Privacidad'),
                    ),
                  ],
                ),
                CheckboxListTile(
                  key: const ValueKey('registration-consent'),
                  value: _acceptedDocuments,
                  onChanged: _busy
                      ? null
                      : (value) =>
                            setState(() => _acceptedDocuments = value ?? false),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    registrationConsentLabel,
                    style: TextStyle(fontSize: 14, height: 1.6),
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  key: const ValueKey('create-student-account'),
                  onPressed: _busy || !_acceptedDocuments ? null : _register,
                  child: Text(_busy ? 'Creando cuenta…' : 'Crear cuenta'),
                ),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.paleBlue,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(
                            Icons.verified_user_outlined,
                            color: AppColors.tertiary,
                            size: 22,
                          ),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Verificación de estudiante',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        localRegistrationDemo
                            ? 'Esta prueba usa un padrón ficticio. En el registro institucional se verificará tu número de control.'
                            : 'Tu correo y matrícula se comprobarán contra el padrón autorizado. Si aún no estás incluido, consulta al equipo de SnackUP antes de crear tu cuenta.',
                        style: const TextStyle(fontSize: 13, height: 1.5),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: _busy ? null : () => Navigator.pop(context),
                  child: const Text('Ya tengo una cuenta'),
                ),
              ],
            ),
          ),
  );

  @override
  void dispose() {
    for (final controller in [_name, _control, _email, _password, _confirm]) {
      controller.dispose();
    }
    super.dispose();
  }
}

class PasswordResetScreen extends StatefulWidget {
  const PasswordResetScreen({
    super.key,
    required this.token,
    required this.onDone,
  });
  final String token;
  final VoidCallback onDone;
  @override
  State<PasswordResetScreen> createState() => _PasswordResetScreenState();
}

class _PasswordResetScreenState extends State<PasswordResetScreen> {
  final _form = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  bool _done = false;
  String? _error;

  Future<void> _reset() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final api = context.read<StudentApi>();
      await api.request(
        'POST',
        '/auth/reset-password',
        body: {'token': widget.token, 'newPassword': _password.text},
        authenticated: false,
      );
      try {
        await api.logout();
      } catch (_) {
        /* All sessions were revoked by reset-password. */
      }
      if (mounted) setState(() => _done = true);
    } catch (error) {
      if (mounted) setState(() => _error = friendlyError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => StudentAuthLayout(
    title: _done ? 'Contraseña actualizada' : 'Nueva contraseña',
    subtitle: _done
        ? 'Inicia sesión con tu nueva contraseña.'
        : 'Elige una contraseña de entre 12 y 128 caracteres.',
    child: _done
        ? FilledButton(
            onPressed: widget.onDone,
            child: const Text('Ir al inicio de sesión'),
          )
        : widget.token.length < 20 || widget.token.length > 256
        ? Column(
            children: [
              const Text(
                'El enlace no es válido. Solicita un nuevo enlace de recuperación.',
              ),
              TextButton(onPressed: widget.onDone, child: const Text('Volver')),
            ],
          )
        : Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _password,
                  enabled: !_busy,
                  obscureText: true,
                  autofillHints: const [AutofillHints.newPassword],
                  validator: _newPasswordError,
                  decoration: const InputDecoration(
                    labelText: 'Nueva contraseña',
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _confirm,
                  enabled: !_busy,
                  obscureText: true,
                  validator: (value) => value == _password.text
                      ? null
                      : 'Las contraseñas no coinciden.',
                  decoration: const InputDecoration(
                    labelText: 'Confirmar contraseña',
                  ),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Text(_error!),
                  ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _busy ? null : _reset,
                  child: Text(_busy ? 'Guardando…' : 'Guardar contraseña'),
                ),
                TextButton(
                  onPressed: _busy ? null : widget.onDone,
                  child: const Text('Volver'),
                ),
              ],
            ),
          ),
  );

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }
}
