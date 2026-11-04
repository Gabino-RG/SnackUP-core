import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'api/api_client.dart';
import 'api/platform_http_client.dart';
import 'api/rest_session.dart';
import 'api/preferences_session_intent.dart';
import 'features/portal/rest_portal_app.dart';

void main() => runApiPortal();

void runApiPortal() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const _PortalLauncher());
}

class _PortalLauncher extends StatefulWidget {
  const _PortalLauncher();
  @override
  State<_PortalLauncher> createState() => _PortalLauncherState();
}

class _PortalLauncherState extends State<_PortalLauncher> {
  RestSession? _session;
  String? _configurationError, _resetToken;
  @override
  void initState() {
    super.initState();
    try {
      if (!kIsWeb)
        throw const ApiException(
          'Abre el portal desde el navegador del equipo.',
        );
      MobileScannerPlatform.instance.setBarcodeLibraryScriptUrl(
        Uri.base.resolve('vendor/zxing-0.21.3.min.js').toString(),
      );
      final fragment = Uri.tryParse(Uri.base.fragment);
      if (fragment?.path == '/reset-password')
        _resetToken = fragment!.queryParameters['token'];
      const configured = String.fromEnvironment(
        'API_BASE_URL',
        defaultValue: '/api/legacy/v1/',
      );
      final base = apiBaseUri(Uri.base.resolve(configured));
      _session = RestSession(
        baseUri: base,
        client: createPortalHttpClient(),
        intentStore: PreferencesSessionIntentStore(base.toString()),
      );
    } catch (_) {
      _configurationError =
          'No se pudo iniciar el portal. Revisa la dirección de la API y utiliza la versión web.';
    }
  }

  @override
  void dispose() {
    _session?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _session != null
      ? RestPortalApp(session: _session!, resetToken: _resetToken)
      : MaterialApp(
          home: Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(_configurationError!, textAlign: TextAlign.center),
              ),
            ),
          ),
        );
}
