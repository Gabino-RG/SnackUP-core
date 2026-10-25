import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'platform_http.dart'
    if (dart.library.js_interop) 'platform_http_web.dart';

typedef Json = Map<String, dynamic>;

class ApiException implements Exception {
  final int status;
  final String code;
  final String message;
  const ApiException(this.code, this.message, {this.status = 0});
  @override
  String toString() => '$message ($code)';
}

class ApiClient extends ChangeNotifier {
  final Uri base;
  final http.Client transport;
  final bool web;
  final FlutterSecureStorage? storage;
  final Duration timeout;
  String? accessToken;
  String? _refreshToken;
  Json? user;
  Future<void>? _renewing;
  Future<void> _credentialWrites = Future<void>.value();
  Timer? _refreshTimer;
  int _generation = 0;
  bool _disposed = false;
  String get _storageKey => 'snackup.refresh.$base';

  ApiClient({
    required this.base,
    http.Client? transport,
    bool? web,
    FlutterSecureStorage? storage,
    this.timeout = const Duration(seconds: 20),
  }) : transport = transport ?? createPlatformClient(),
       web = web ?? kIsWeb,
       storage = (web ?? kIsWeb)
           ? null
           : (storage ?? const FlutterSecureStorage());

  static Uri configuredBase() {
    const configured = String.fromEnvironment('API_BASE_URL');
    final uri = configured.isEmpty
        ? (kIsWeb
              ? Uri.base.resolve('/api/v1/')
              : Uri.parse('http://localhost:8000/api/v1/'))
        : Uri.parse(configured);
    if (!uri.hasAuthority ||
        !['http', 'https'].contains(uri.scheme) ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw const ApiException(
        'INVALID_API_URL',
        'Configura una dirección HTTP o HTTPS válida para la API.',
      );
    }
    final path = uri.path.isEmpty || uri.path == '/' ? '/api/v1/' : uri.path;
    return uri.replace(path: path.endsWith('/') ? path : '$path/');
  }

  Uri url(String path, {Map<String, String>? query, bool legacy = false}) {
    final root = legacy ? base.resolve('/api/legacy/v1/') : base;
    return root.resolve(path).replace(queryParameters: query);
  }

  Future<Json> _send(
    String method,
    String path, {
    Json? body,
    Map<String, String>? query,
    Map<String, String>? headers,
    bool legacy = false,
    bool authenticated = true,
  }) async {
    final request = http.Request(
      method,
      url(path, query: query, legacy: legacy),
    );
    request.headers.addAll({
      'Accept': 'application/json',
      if (body != null) 'Content-Type': 'application/json',
      if (authenticated && accessToken != null)
        'Authorization': 'Bearer $accessToken',
      ...?headers,
    });
    if (body != null) request.body = jsonEncode(body);
    try {
      final response = await http.Response.fromStream(
        await transport.send(request),
      ).timeout(timeout);
      Json data = {};
      if (response.body.isNotEmpty) {
        final decoded = jsonDecode(utf8.decode(response.bodyBytes));
        if (decoded is! Map<String, dynamic>) {
          throw const ApiException(
            'INVALID_RESPONSE',
            'La API devolvió una respuesta inesperada.',
          );
        }
        data = decoded;
      }
      if (response.statusCode >= 400) {
        final error = data['error'] is Map ? data['error'] as Map : const {};
        throw ApiException(
          error['code']?.toString() ?? 'HTTP_${response.statusCode}',
          error['message']?.toString() ??
              'La API no pudo completar la solicitud.',
          status: response.statusCode,
        );
      }
      return data;
    } on TimeoutException {
      throw const ApiException(
        'TIMEOUT',
        'La API tardó demasiado. Si estabas confirmando un pedido, reintenta el mismo pedido.',
      );
    } on http.ClientException {
      throw const ApiException(
        'API_UNREACHABLE',
        'No se pudo contactar con la API. Revisa que esté encendida y que su dirección y origen estén configurados.',
      );
    } on FormatException {
      throw const ApiException(
        'INVALID_RESPONSE',
        'La API no devolvió JSON válido. Revisa la dirección del servidor.',
      );
    }
  }

  Future<Json> request(
    String method,
    String path, {
    Json? body,
    Map<String, String>? query,
    Map<String, String>? headers,
    bool legacy = false,
    bool authenticated = true,
  }) async {
    final generation = _generation;
    try {
      final result = await _send(
        method,
        path,
        body: body,
        query: query,
        headers: headers,
        legacy: legacy,
        authenticated: authenticated,
      );
      if (authenticated && generation != _generation) {
        throw const ApiException(
          'SESSION_CHANGED',
          'La sesión cambió. Vuelve a cargar la pantalla.',
        );
      }
      return result;
    } on ApiException catch (error) {
      if (!authenticated || error.status != 401) rethrow;
      if (generation != _generation) rethrow;
      await renew();
      final result = await _send(
        method,
        path,
        body: body,
        query: query,
        headers: headers,
        legacy: legacy,
      );
      if (generation != _generation)
        throw const ApiException('SESSION_CHANGED', 'La sesión cambió.');
      return result;
    }
  }

  Future<void> _persistNative(String? value, int generation) {
    final previous = _credentialWrites;
    return _credentialWrites = () async {
      try {
        await previous;
      } catch (_) {
        /* A later clear must still run. */
      }
      if (generation != _generation) return;
      if (value == null) {
        await storage!.delete(key: _storageKey);
      } else {
        await storage!.write(key: _storageKey, value: value);
      }
    }();
  }

  Future<void> _tokens(Json response, int generation) async {
    if (generation != _generation)
      throw const ApiException('SESSION_CHANGED', 'La sesión cambió.');
    final tokens = response['tokens'] as Map?;
    if (tokens == null || tokens['accessToken'] is! String) {
      throw const ApiException(
        'INVALID_RESPONSE',
        'La API no entregó una sesión válida.',
      );
    }
    accessToken = tokens['accessToken'] as String;
    if (!web) {
      _refreshToken = tokens['refreshToken'] as String?;
      if (_refreshToken == null)
        throw const ApiException(
          'INVALID_RESPONSE',
          'Falta la renovación de la sesión nativa.',
        );
      await _persistNative(_refreshToken, generation);
    }
    if (generation != _generation)
      throw const ApiException('SESSION_CHANGED', 'La sesión cambió.');
    _refreshTimer?.cancel();
    final expires = DateTime.tryParse(
      tokens['accessTokenExpiresAt']?.toString() ?? '',
    );
    if (expires != null) {
      final delay =
          expires.difference(DateTime.now()) - const Duration(seconds: 30);
      _refreshTimer = Timer(
        delay.isNegative ? const Duration(seconds: 1) : delay,
        () async {
          try {
            await renew();
          } on ApiException {
            /* The next request reports the failure. */
          }
        },
      );
    }
    if (!_disposed) notifyListeners();
  }

  Future<void> login(String email, String password) async {
    final generation = ++_generation;
    await withSessionLock(() async {
      final response = await _send(
        'POST',
        'auth/login',
        body: {'email': email.trim(), 'password': password},
        authenticated: false,
      );
      final profile = response['user'];
      if (profile is! Map || profile['role'] != 'ALUMNO') {
        final tokens = response['tokens'] as Map?;
        await _send(
          'POST',
          'auth/logout',
          authenticated: false,
          body: {
            if (!web && tokens?['refreshToken'] != null)
              'refreshToken': tokens!['refreshToken'],
          },
        );
        throw const ApiException(
          'STUDENT_REQUIRED',
          'Esta aplicación es para alumnos. Usa el portal del personal para otra cuenta.',
        );
      }
      await _tokens(response, generation);
      user = Map<String, dynamic>.from(profile);
      if (!_disposed) notifyListeners();
    });
  }

  Future<void> restore() async {
    if (!web) {
      _refreshToken = await storage!.read(key: _storageKey);
      if (_refreshToken == null) return;
    }
    try {
      await renew();
      final profile = await request('GET', 'users/me');
      if (profile['role'] != 'ALUMNO') {
        await logout();
        return;
      }
      user = profile;
      if (!_disposed) notifyListeners();
    } on ApiException catch (error) {
      if (error.status == 401 || error.status == 403) {
        await clear();
        return;
      }
      rethrow;
    }
  }

  Future<void> renew() =>
      _renewing ??= _doRenew().whenComplete(() => _renewing = null);
  Future<void> _doRenew() async {
    final generation = _generation;
    final identity = user?['id'];
    try {
      final response = await withSessionLock(
        () => _send(
          'POST',
          'auth/refresh',
          authenticated: false,
          body: {
            if (!web && _refreshToken != null) 'refreshToken': _refreshToken,
          },
        ),
      );
      if (generation != _generation)
        throw const ApiException('SESSION_CHANGED', 'La sesión cambió.');
      Json? profile;
      if (identity != null) {
        final token = (response['tokens'] as Map?)?['accessToken'];
        if (token is! String)
          throw const ApiException(
            'INVALID_RESPONSE',
            'La API no entregó una sesión válida.',
          );
        profile = await _send(
          'GET',
          'users/me',
          authenticated: false,
          headers: {'Authorization': 'Bearer $token'},
        );
        if (generation != _generation)
          throw const ApiException('SESSION_CHANGED', 'La sesión cambió.');
        if (profile['id'] != identity || profile['role'] != 'ALUMNO') {
          await clear();
          throw const ApiException(
            'SESSION_CHANGED',
            'La cuenta cambió en otra pestaña. Inicia sesión de nuevo para continuar.',
          );
        }
      }
      await _tokens(response, generation);
      if (profile != null) {
        user = profile;
        if (!_disposed) notifyListeners();
      }
    } on ApiException catch (error) {
      if (generation == _generation &&
          (error.status == 401 || error.status == 403))
        await clear();
      rethrow;
    }
  }

  Future<void> clear() async {
    ++_generation;
    accessToken = null;
    _refreshToken = null;
    user = null;
    _refreshTimer?.cancel();
    if (!web) await _persistNative(null, _generation);
    if (!_disposed) notifyListeners();
  }

  Future<void> logout() async {
    try {
      await withSessionLock(
        () => _send(
          'POST',
          'auth/logout',
          body: {
            if (!web && _refreshToken != null) 'refreshToken': _refreshToken,
          },
        ),
      );
    } finally {
      await clear();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _refreshTimer?.cancel();
    transport.close();
    super.dispose();
  }
}
