import 'package:flutter/material.dart';
import 'browser_push.dart';

typedef PushRequest =
    Future<dynamic> Function(
      String method,
      String path, {
      Map<String, dynamic>? body,
    });

/// Opt-in notifications for the current authenticated account and browser.
/// Access tokens and browser subscription credentials are never stored here.
class PushNotificationsCard extends StatefulWidget {
  const PushNotificationsCard({
    super.key,
    required this.request,
    required this.sessionKey,
    this.errorMessage,
    this.registrationIsMissing,
  });

  final PushRequest request;
  final Object sessionKey;
  final String Function(Object)? errorMessage;
  final bool Function(Object)? registrationIsMissing;

  @override
  State<PushNotificationsCard> createState() => _PushNotificationsCardState();
}

class _PushNotificationsCardState extends State<PushNotificationsCard>
    with WidgetsBindingObserver {
  bool _busy = true, _loaded = false, _supported = false;
  bool _subscribed = false, _serverEnabled = false;
  bool _remoteConfirmed = false;
  bool _cleanupPending = false;
  bool _waitingForBrowser = false;
  String _permission = 'unavailable';
  String? _publicKey, _deviceId, _error, _notice, _reason;
  int _revision = 0;

  bool get _active =>
      _subscribed &&
      _deviceId != null &&
      _permission == 'granted' &&
      _remoteConfirmed &&
      _serverEnabled;
  bool get _canDisable => _subscribed || _deviceId != null || _cleanupPending;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void didUpdateWidget(covariant PushNotificationsCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sessionKey != widget.sessionKey) {
      if (_waitingForBrowser) cancelBrowserPushActivation();
      _waitingForBrowser = false;
      _revision++;
      _loaded = false;
      _deviceId = null;
      _cleanupPending = false;
      _notice = null;
      _load();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_busy) _load();
  }

  @override
  void dispose() {
    if (_waitingForBrowser) cancelBrowserPushActivation();
    _revision++;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  bool _current(int revision) => mounted && revision == _revision;

  String _apiError(Object error) =>
      widget.errorMessage?.call(error) ??
      'No se pudo confirmar el estado de las notificaciones. Revisa tu conexión e inténtalo de nuevo.';

  String _browserError(String? code) => switch (code) {
    'PERMISSION_DENIED' =>
      'El navegador bloqueó las notificaciones. Puedes permitirlas en la configuración de este sitio y después actualizar.',
    'PERMISSION_DISMISSED' =>
      'No se activaron las notificaciones. Puedes intentarlo cuando quieras.',
    'INVALID_PUBLIC_KEY' =>
      'El servidor todavía no tiene una configuración válida de notificaciones.',
    'UNSUPPORTED' => 'Este navegador no admite notificaciones web.',
    'PUSH_TIMEOUT' =>
      'El navegador no respondió a tiempo. Revisa el aviso de permisos o abre SnackUP directamente en tu navegador y vuelve a intentarlo.',
    'PUSH_PENDING' =>
      'El navegador todavía está terminando una solicitud anterior. Revisa su aviso de permisos; si no termina, recarga la página antes de intentarlo de nuevo.',
    'PUSH_CANCELLED' => 'Se canceló la activación de las notificaciones.',
    _ =>
      'No se pudo activar el servicio de notificaciones del navegador. Revisa la conexión y vuelve a intentarlo.',
  };

  Future<void> _load({String? notice}) async {
    final revision = ++_revision;
    final request = widget.request;
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
      _remoteConfirmed = false;
    });
    try {
      final browser = await browserPushStatus();
      if (!_current(revision)) return;
      if (browser['error'] != null) {
        setState(() => _error = _browserError(browser['error'] as String?));
        return;
      }
      final supported = browser['supported'] == true;
      // Browser state is useful even when the API is offline: the user can
      // still unsubscribe locally and retry server cleanup afterward.
      setState(() {
        _loaded = true;
        _supported = supported;
        _reason = browser['reason'] as String?;
        _permission = browser['permission'] as String? ?? 'unavailable';
        _subscribed = browser['subscribed'] == true;
      });
      Map<String, dynamic> options = const {};
      dynamic device;
      if (supported) {
        options = Map<String, dynamic>.from(
          await request('GET', 'push/options') as Map,
        );
        if (!_current(revision)) return;
        device = await request('GET', 'users/me/devices/current');
        if (!_current(revision)) return;
      }
      setState(() {
        _remoteConfirmed = true;
        _notice = notice;
        _publicKey = options['webPushPublicKey'] as String?;
        _serverEnabled =
            options['enabled'] == true && _publicKey?.isNotEmpty == true;
        _deviceId =
            device is Map &&
                device['provider'] == 'webpush' &&
                device['platform'] == 'web'
            ? device['id'] as String?
            : null;
        _cleanupPending = !_subscribed && _deviceId != null;
      });
    } catch (error) {
      if (_current(revision)) setState(() => _error = _apiError(error));
    } finally {
      if (_current(revision)) setState(() => _busy = false);
    }
  }

  Future<void> _enable() async {
    if (_busy ||
        !_remoteConfirmed ||
        !_serverEnabled ||
        _publicKey == null ||
        !_supported) {
      return;
    }
    final revision = ++_revision;
    final request = widget.request;
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
      _waitingForBrowser = true;
    });
    try {
      // Invoke the JS permission request synchronously from the user's click.
      final result = await activateBrowserPush(_publicKey!);
      if (!_current(revision)) return;
      setState(() => _waitingForBrowser = false);
      if (result['error'] != null) {
        setState(() {
          _error = _browserError(result['error'] as String?);
          if (result['error'] == 'PERMISSION_DENIED') _permission = 'denied';
        });
        return;
      }
      final token = result['token'];
      if (token is! String || token.isEmpty) {
        setState(() => _error = _browserError(null));
        return;
      }
      setState(() {
        _subscribed = true;
        _permission = 'granted';
      });
      final device = await request(
        'POST',
        'users/me/devices',
        body: {'token': token, 'platform': 'web', 'provider': 'webpush'},
      );
      if (!_current(revision)) return;
      if (device is! Map || device['id'] is! String) {
        throw const FormatException('Respuesta de dispositivo incompleta.');
      }
      await _load(
        notice: 'Notificaciones activadas para esta cuenta en este navegador.',
      );
    } catch (error) {
      if (_current(revision)) setState(() => _error = _apiError(error));
    } finally {
      if (_current(revision)) {
        setState(() {
          _busy = false;
          _waitingForBrowser = false;
        });
      }
    }
  }

  Future<void> _disable() async {
    if (_busy || !_canDisable) return;
    final revision = ++_revision;
    final request = widget.request;
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      // Stop browser delivery even if the API is temporarily unreachable.
      final result = await deactivateBrowserPush();
      if (!_current(revision)) return;
      if (result['error'] != null) {
        setState(() => _error = _browserError(result['error'] as String?));
        return;
      }
      setState(() {
        _subscribed = false;
        _cleanupPending = true;
      });
      // Query the session again: a previous registration response might have
      // been lost, so an in-memory device ID alone is not authoritative.
      final device = await request('GET', 'users/me/devices/current');
      if (!_current(revision)) return;
      final deviceId =
          device is Map &&
              device['provider'] == 'webpush' &&
              device['platform'] == 'web'
          ? device['id'] as String?
          : null;
      if (deviceId != null) {
        try {
          await request(
            'DELETE',
            'users/me/devices/${Uri.encodeComponent(deviceId)}',
          );
        } catch (error) {
          if (widget.registrationIsMissing?.call(error) != true) rethrow;
        }
        if (!_current(revision)) return;
      }
      await _load(notice: 'Notificaciones desactivadas en este navegador.');
    } catch (error) {
      if (_current(revision)) {
        setState(
          () => _error = !_subscribed
              ? 'El navegador dejó de recibir avisos. Falta retirar su registro del servidor: revisa la conexión y vuelve a pulsar Desactivar.'
              : _apiError(error),
        );
      }
    } finally {
      if (_current(revision)) setState(() => _busy = false);
    }
  }

  String get _description {
    if (!_loaded) {
      return _busy
          ? 'Comprobando disponibilidad…'
          : 'No se pudo consultar la disponibilidad. Pulsa Actualizar para intentarlo de nuevo.';
    }
    if (!_supported) {
      return _reason == 'INSECURE_ORIGIN'
          ? 'Abre SnackUP mediante HTTPS o localhost para usar notificaciones.'
          : 'Este navegador no ofrece notificaciones web para SnackUP. Puedes consultar tus pedidos dentro de la aplicación.';
    }
    if (!_remoteConfirmed) {
      return _busy
          ? 'Comprobando el servicio de notificaciones…'
          : 'No se pudo confirmar el servicio de notificaciones. Revisa tu conexión y pulsa Actualizar.';
    }
    if (!_serverEnabled) {
      return 'Las notificaciones aún no están habilitadas en este servidor. Puedes seguir consultando tus pedidos dentro de SnackUP.';
    }
    if (_permission == 'denied') {
      return 'Las notificaciones están bloqueadas en el navegador. Permítelas en la configuración de este sitio y pulsa Actualizar.';
    }
    if (_active) {
      return 'Recibirás avisos de tus pedidos en este navegador mientras tu sesión siga vigente.';
    }
    return 'Activa los avisos de pedidos para esta cuenta. El navegador te pedirá permiso si todavía no lo has concedido.';
  }

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                _active
                    ? Icons.notifications_active_outlined
                    : Icons.notifications_none,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Notificaciones de pedidos',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(_description),
          if (_busy)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: LinearProgressIndicator(),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (_notice != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(_notice!),
            ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (_waitingForBrowser)
                TextButton(
                  onPressed: cancelBrowserPushActivation,
                  child: const Text('Cancelar activación'),
                ),
              if (!_active)
                FilledButton.icon(
                  onPressed:
                      _busy ||
                          !_loaded ||
                          !_supported ||
                          !_remoteConfirmed ||
                          !_serverEnabled ||
                          _permission == 'denied'
                      ? null
                      : _enable,
                  icon: const Icon(Icons.notifications_outlined),
                  label: const Text('Activar notificaciones'),
                ),
              if (_canDisable)
                OutlinedButton(
                  onPressed: _busy ? null : _disable,
                  child: const Text('Desactivar'),
                ),
              TextButton.icon(
                onPressed: _busy ? null : () => _load(),
                icon: const Icon(Icons.refresh),
                label: const Text('Actualizar'),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}
