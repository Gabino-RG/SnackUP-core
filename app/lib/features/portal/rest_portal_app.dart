import '../../api/access_repository.dart';
import '../../api/external_login.dart';
import 'request_access_screen.dart';
import '../operations/access_requests_screen.dart';
import 'package:flutter/material.dart';
import '../../api/api_client.dart';
import '../../api/rest_session.dart';
import '../../api/reset_location.dart';
import 'reset_access_screen.dart';
import '../../catalog/rest_catalog_repository.dart';
import '../../operations/operations_repository.dart';
import '../../operations/models.dart';
import '../operations/business_portal.dart';
import '../operations/admin_management.dart';
import '../admin/admin_dashboard_screen.dart';
import '../admin/admin_theme.dart';
import '../admin/data/rest_admin_repository.dart';

class RestPortalApp extends StatefulWidget {
  const RestPortalApp({
    super.key,
    required this.session,
    this.restoreOnStart = true,
    this.businessBuilder,
    this.adminBuilder,
    this.resetToken,
  });
  final RestSession session;
  final bool restoreOnStart;
  final String? resetToken;
  final Widget Function(PortalAccount)? businessBuilder, adminBuilder;
  @override
  State<RestPortalApp> createState() => _RestPortalAppState();
}

class _RestPortalAppState extends State<RestPortalApp> {
  SessionHttpClient? _client;
  RestCatalogRepository? _catalog;
  RestAdminRepository? _admin;
  OperationsRepository? _operations;
  int? _dataGeneration;
  bool _resetFinished = false;
  @override
  void initState() {
    super.initState();
    if (widget.restoreOnStart && widget.resetToken == null)
      widget.session.restore();
  }

  void _prepareDataSession() {
    if (_dataGeneration == widget.session.generation) return;
    _client?.close();
    _dataGeneration = widget.session.generation;
    _client = SessionHttpClient(widget.session);
    _catalog = RestCatalogRepository(
      baseUri: widget.session.api.baseUri,
      client: _client!,
      accessToken: widget.session.accessToken,
    );
    final api = ApiClient(
      baseUri: widget.session.api.baseUri,
      client: _client!,
    );
    _admin = RestAdminRepository(api);
    _operations = OperationsRepository(api);
  }

  @override
  void dispose() {
    _client?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.session,
    builder: (context, _) {
      final session = widget.session;
      final account = session.account;
      final authenticated =
          session.phase == PortalSessionPhase.authenticated && account != null;
      if (authenticated) _prepareDataSession();
      // Replacing the root Navigator removes every protected route and dialog.
      final navigationKey = authenticated
          ? 'private:${session.generation}:${account.identity}'
          : 'public';
      final Widget home;
      if (widget.resetToken != null && !_resetFinished) {
        home = ResetAccessScreen(
          api: session.api,
          token: widget.resetToken!,
          onDone: () {
            clearResetLocation();
            setState(() => _resetFinished = true);
            session.restore();
          },
        );
      } else if (session.phase == PortalSessionPhase.restoring ||
          session.phase == PortalSessionPhase.signingOut) {
        home = const Scaffold(body: Center(child: CircularProgressIndicator()));
      } else if (session.phase == PortalSessionPhase.unavailable) {
        home = _AccessNotice(
          message: session.message ?? 'No se pudo contactar con el servidor.',
          action: 'Reintentar conexión',
          onAction: session.restore,
        );
      } else if (authenticated && account.isBusiness) {
        home =
            widget.businessBuilder?.call(account) ??
            BusinessPortal(
              businessId: account.businessId!,
              catalog: _catalog!,
              repository: _operations!,
              token: session.accessToken,
              onSignOut: session.signOut,
            );
      } else if (authenticated && account.isAdmin) {
        home =
            widget.adminBuilder?.call(account) ??
            AdminDashboardScreen(
              repository: _admin!,
              onSignOut: session.signOut,
              isMaster: account.canManageAccounts,
              autoRefresh: true,
              onOpenBusiness: !account.canManageAccounts
                  ? null
                  : (context) async {
                      final selected = await Navigator.of(context)
                          .push<BusinessRecord>(
                            MaterialPageRoute(
                              builder: (_) => AdminManagement(
                                repository: _operations!,
                                currentUserId: account.id,
                                canManageAccounts: true,
                                selectBusiness: true,
                              ),
                            ),
                          );
                      if (!context.mounted ||
                          selected == null ||
                          session.account?.canManageAccounts != true)
                        return;
                      await Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (localContext) => BusinessPortal(
                            businessId: selected.id,
                            catalog: _catalog!,
                            repository: _operations!,
                            token: session.accessToken,
                            onSignOut: session.signOut,
                            onReturnToAdmin: () =>
                                Navigator.of(localContext).pop(),
                          ),
                        ),
                      );
                    },
              onAccessRequests: !account.canManageAccounts
                  ? null
                  : (context) async {
                      await Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              AccessRequestsScreen(repository: _operations!),
                        ),
                      );
                    },
              onCreateAccount: !account.canManageAccounts
                  ? null
                  : (context) async {
                      await Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => AdminManagement(
                            repository: _operations!,
                            currentUserId: account.id,
                            canManageAccounts: true,
                            createAccountOnOpen: true,
                          ),
                        ),
                      );
                    },
              onManage: (context) async {
                await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => AdminManagement(
                      repository: _operations!,
                      currentUserId: account.id,
                      canManageAccounts: account.canManageAccounts,
                    ),
                  ),
                );
              },
            );
      } else if (authenticated) {
        home = _AccessNotice(
          message: account.role == 'business'
              ? 'Tu cuenta todavía no tiene un local asignado. Solicita la asignación a administración.'
              : 'Este acceso es para negocios y administración. Tu cuenta no tiene un rol habilitado para estos paneles.',
          action: 'Cerrar sesión',
          onAction: session.signOut,
        );
      } else {
        home = _PortalLogin(session: session);
      }
      return MaterialApp(
        key: ValueKey(navigationKey),
        title: 'SnackUP · Paneles',
        debugShowCheckedModeBanner: false,
        theme: adminTheme(),
        home: home,
        builder: (context, child) => const bool.fromEnvironment('REVIEW_MODE')
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Material(
                    color: const Color(0xFFFFEDBA),
                    child: SafeArea(
                      bottom: false,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        child: Text(
                          'VERSIÓN DE REVISIÓN · Datos de prueba guardados en esta PC',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 11,
                            color: Color(0xFF493500),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Expanded(child: child!),
                ],
              )
            : child!,
      );
    },
  );
}

class _AccessNotice extends StatelessWidget {
  const _AccessNotice({
    required this.message,
    required this.action,
    required this.onAction,
  });
  final String message, action;
  final VoidCallback onAction;
  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.info_outline,
                  size: 38,
                  color: AdminColors.navy,
                ),
                const SizedBox(height: 20),
                Text(message, textAlign: TextAlign.center),
                const SizedBox(height: 24),
                FilledButton(onPressed: onAction, child: Text(action)),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _PortalLogin extends StatefulWidget {
  const _PortalLogin({required this.session});
  final RestSession session;
  @override
  State<_PortalLogin> createState() => _PortalLoginState();
}

class _PortalLoginState extends State<_PortalLogin> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController(), _password = TextEditingController();
  bool _hidePassword = true, _recovering = false;
  String? _notice;
  AccessOptions? _accessOptions;
  bool _optionsFailed = false;
  @override
  void initState() {
    super.initState();
    _notice = accessReturnMessage(Uri.base.fragment);
    if (_notice != null) clearResetLocation();
    _loadOptions();
  }

  Future<void> _loadOptions() async {
    try {
      final options = await AccessRepository(widget.session.api).options();
      if (mounted)
        setState(() {
          _accessOptions = options;
          _optionsFailed = false;
        });
    } catch (_) {
      if (mounted) setState(() => _optionsFailed = true);
    }
  }

  Future<void> _google() async {
    if (_busy || _accessOptions?.googleEnabled != true) return;
    try {
      beginExternalLogin(AccessRepository(widget.session.api).googleStart);
    } catch (_) {
      if (mounted)
        setState(() => _notice = 'No se pudo abrir Google. Intenta de nuevo.');
    }
  }

  bool get _busy =>
      _recovering ||
      widget.session.phase == PortalSessionPhase.signingIn ||
      widget.session.logoutPending;
  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() => _notice = null);
    await widget.session.signIn(_email.text, _password.text);
  }

  Future<void> _recover() async {
    if (_busy) return;
    setState(() {
      _recovering = true;
      _notice = null;
    });
    try {
      await widget.session.forgotPassword(_email.text);
      if (mounted)
        setState(
          () => _notice = const bool.fromEnvironment('REVIEW_MODE')
              ? 'Solicitud de prueba recibida. Esta versión local no envía correos; utiliza las credenciales indicadas o crea otra cuenta desde administración.'
              : 'Si el correo tiene una cuenta, recibirás las instrucciones para recuperar el acceso.',
        );
    } catch (error) {
      if (mounted)
        setState(
          () => _notice = error is ApiException
              ? error.message
              : 'No se pudo solicitar la recuperación.',
        );
    } finally {
      if (mounted) setState(() => _recovering = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AdminColors.background,
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 430),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Form(
                  key: _form,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Center(
                        child: Container(
                          width: 248,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 20,
                          ),
                          decoration: BoxDecoration(
                            color: AdminColors.navy,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Image.asset(
                            'assets/institution/utsjr-logo.png',
                            width: 212,
                            fit: BoxFit.contain,
                            filterQuality: FilterQuality.high,
                            semanticLabel:
                                'Universidad Tecnológica de San Juan del Río',
                            errorBuilder: (_, __, ___) => const Text(
                              'UT San Juan',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 22,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Acceso a SnackUP',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          color: AdminColors.navy,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Cafetería universitaria · Locales y administración',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 30),
                      TextFormField(
                        key: const ValueKey('portal-email'),
                        controller: _email,
                        enabled: !_busy,
                        keyboardType: TextInputType.emailAddress,
                        autofillHints: const [AutofillHints.username],
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'Correo electrónico',
                          border: OutlineInputBorder(),
                        ),
                        validator: (v) =>
                            RegExp(
                              r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
                            ).hasMatch(v?.trim() ?? '')
                            ? null
                            : 'Escribe un correo válido.',
                      ),
                      const SizedBox(height: 18),
                      TextFormField(
                        key: const ValueKey('portal-password'),
                        controller: _password,
                        enabled: !_busy,
                        obscureText: _hidePassword,
                        autocorrect: false,
                        enableSuggestions: false,
                        autofillHints: const [AutofillHints.password],
                        onFieldSubmitted: (_) => _submit(),
                        decoration: InputDecoration(
                          labelText: 'Contraseña',
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            tooltip: _hidePassword
                                ? 'Mostrar contraseña'
                                : 'Ocultar contraseña',
                            onPressed: _busy
                                ? null
                                : () => setState(
                                    () => _hidePassword = !_hidePassword,
                                  ),
                            icon: Icon(
                              _hidePassword
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                          ),
                        ),
                        validator: (v) => v == null || v.isEmpty
                            ? 'Escribe tu contraseña.'
                            : null,
                      ),
                      if (widget.session.message != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: Text(
                            widget.session.message!,
                            style: const TextStyle(color: AdminColors.red),
                          ),
                        ),
                      if (_notice != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: Text(_notice!),
                        ),
                      const SizedBox(height: 24),
                      FilledButton(
                        key: const ValueKey('portal-login'),
                        onPressed:
                            _busy || _accessOptions?.passwordLogin == false
                            ? null
                            : _submit,
                        child: Text(
                          widget.session.phase == PortalSessionPhase.signingIn
                              ? 'Comprobando acceso…'
                              : 'Entrar',
                        ),
                      ),
                      if (widget.session.logoutPending)
                        OutlinedButton(
                          onPressed: widget.session.signOut,
                          child: const Text('Reintentar cierre de sesión'),
                        ),
                      TextButton(
                        onPressed: _busy ? null : _recover,
                        child: Text(
                          _recovering
                              ? 'Enviando solicitud…'
                              : 'Olvidé mi contraseña',
                        ),
                      ),
                      TextButton(
                        onPressed:
                            _busy || _accessOptions?.selfRegistration != true
                            ? null
                            : () async {
                                await Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => RequestAccessScreen(
                                      repository: AccessRepository(
                                        widget.session.api,
                                      ),
                                    ),
                                  ),
                                );
                              },
                        child: const Text('Crea tu cuenta'),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton(
                        onPressed:
                            _busy || _accessOptions?.googleEnabled != true
                            ? null
                            : _google,
                        child: const Text('Continuar con Google'),
                      ),
                      if (_accessOptions?.googleEnabled == false)
                        const Text(
                          'Google no está disponible en este servidor. Puedes usar una cuenta de SnackUP.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12,
                            color: AdminColors.muted,
                          ),
                        ),
                      if (_optionsFailed)
                        TextButton(
                          onPressed: _loadOptions,
                          child: const Text('Reintentar opciones de acceso'),
                        ),
                      const SizedBox(height: 12),
                      if (const bool.fromEnvironment('REVIEW_MODE'))
                        const Padding(
                          padding: EdgeInsets.only(bottom: 12),
                          child: SelectableText(
                            'Cuenta maestra: admin@snackup.test\nContraseña de prueba: SnackUP-Prueba-2026',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 12),
                          ),
                        ),
                      const Text(
                        'Solo las cuentas autorizadas por la cuenta maestra pueden entrar. Puedes solicitar acceso o pedirle que cree tu cuenta.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          color: AdminColors.muted,
                        ),
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
