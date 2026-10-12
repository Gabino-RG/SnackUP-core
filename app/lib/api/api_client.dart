import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiException implements Exception {
  const ApiException(this.message, {this.code = 'API_ERROR', this.status});
  final String message, code;
  final int? status;
  @override
  String toString() => message;
}

Uri apiBaseUri(Uri uri) {
  if (!['http', 'https'].contains(uri.scheme) || uri.host.isEmpty ||
      uri.userInfo.isNotEmpty || uri.hasQuery || uri.hasFragment) {
    throw const ApiException('La dirección del servidor no es válida.', code: 'CONFIGURATION');
  }
  return uri.replace(path: '${uri.path.replaceFirst(RegExp(r'/+$'), '')}/');
}

bool belongsToApi(Uri base, Uri url) =>
    url.origin == base.origin && url.path.startsWith(base.path) && url.userInfo.isEmpty;

String responseErrorCode(http.Response response) {
  try {
    final body = jsonDecode(utf8.decode(response.bodyBytes));
    if (body is Map && body['error'] is Map) {
      return (body['error'] as Map)['code']?.toString() ?? 'HTTP_ERROR';
    }
  } catch (_) { /* A malformed error does not grant access or trigger a retry. */ }
  return 'HTTP_ERROR';
}

class ApiClient {
  ApiClient({required Uri baseUri, required this.client}) : baseUri = apiBaseUri(baseUri);
  final Uri baseUri;
  final http.Client client;

  Future<dynamic> json(String method, String path, {
    Map<String, String>? query,
    Map<String, dynamic>? body,
    Map<String, String> headers = const {},
  }) async {
    final url = baseUri.resolve(path).replace(queryParameters: query);
    if (!belongsToApi(baseUri, url)) {
      throw const ApiException('La ruta no pertenece a esta API.', code: 'CONFIGURATION');
    }
    final abort = Completer<void>();
    final request = http.AbortableRequest(method, url, abortTrigger: abort.future)
      ..followRedirects = false
      ..headers.addAll({'Accept': 'application/json', 'Content-Type': 'application/json', ...headers});
    if (body != null) request.body = jsonEncode(body);
    try {
      final response = await (() async => http.Response.fromStream(await client.send(request)))()
          .timeout(const Duration(seconds: 20));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final message = switch (response.statusCode) {
          401 => 'Tu sesión terminó o los datos de acceso no son correctos.',
          403 => 'Tu cuenta no tiene permiso para esta operación.',
          404 => 'No se encontró el registro solicitado.',
          409 => 'El registro cambió en otro dispositivo. Recarga antes de guardar.',
          422 => 'Revisa los datos del formulario.',
          429 => 'Hay demasiadas solicitudes. Espera un momento antes de reintentar.',
          _ => 'El servidor no pudo completar la operación. Inténtalo de nuevo.',
        };
        throw ApiException(message, code: responseErrorCode(response), status: response.statusCode);
      }
      if (response.bodyBytes.isEmpty) return null;
      try { return jsonDecode(utf8.decode(response.bodyBytes)); }
      catch (_) { throw const ApiException('La respuesta del servidor está incompleta.', code: 'INVALID_RESPONSE'); }
    } on TimeoutException {
      if (!abort.isCompleted) abort.complete();
      throw const ApiException('El servidor tardó demasiado. Comprueba el resultado antes de repetir un guardado.', code: 'TIMEOUT');
    } on http.ClientException {
      throw const ApiException('No se pudo conectar con el servidor local. Revisa tu conexión.', code: 'NETWORK');
    }
  }
}
