import 'api_client.dart';
import '../operations/models.dart';

String? accessReturnMessage(String fragment) => switch (fragment) {
  '/access-pending' =>
    'Tu solicitud está pendiente de autorización por la cuenta maestra. Google no concede acceso a los paneles por sí solo.',
  '/access-rejected' =>
    'Tu solicitud no fue autorizada. Contacta a la cuenta maestra.',
  '/google-error' =>
    'No se pudo completar el acceso con Google. Intenta de nuevo o usa tu cuenta de SnackUP.',
  '/account-link-required' =>
    'Ya existe una cuenta con ese correo. Entra con tu contraseña y solicita la vinculación a la cuenta maestra.',
  _ => null,
};

class AccessOptions {
  const AccessOptions({
    this.passwordLogin = true,
    this.selfRegistration = false,
    this.googleEnabled = false,
  });
  final bool passwordLogin, selfRegistration, googleEnabled;
  factory AccessOptions.fromJson(dynamic value) {
    final d = object(value);
    for (final key in ['passwordLogin', 'selfRegistration', 'googleEnabled']) {
      if (d[key] is! bool)
        throw const ApiException(
          'La configuración de acceso está incompleta.',
          code: 'INVALID_RESPONSE',
        );
    }
    return AccessOptions(
      passwordLogin: d['passwordLogin'],
      selfRegistration: d['selfRegistration'],
      googleEnabled: d['googleEnabled'],
    );
  }
}

class AccessRepository {
  const AccessRepository(this.api);
  final ApiClient api;
  Future<AccessOptions> options() async =>
      AccessOptions.fromJson(await api.json('GET', 'auth/options'));
  Future<void> register({
    required String name,
    required String email,
    required String password,
    required String requestedRole,
    required String context,
  }) async {
    final d = object(
      await api.json(
        'POST',
        'auth/register',
        body: {
          'displayName': name.trim(),
          'email': email.trim().toLowerCase(),
          'password': password,
          'requestedRole': requestedRole,
          'context': context.trim(),
        },
      ),
    );
    if (d['status'] != 'received')
      throw const ApiException(
        'No se pudo confirmar la recepción de la solicitud.',
        code: 'INVALID_RESPONSE',
      );
  }

  // Fixed backend-owned route: no tokens, role or arbitrary redirect in the URL.
  Uri get googleStart => api.baseUri.resolve('auth/google/start');
}
