import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'api_client.dart';

enum PortalSessionPhase { restoring, signedOut, signingIn, authenticated, unavailable, signingOut }

abstract class SessionIntentStore {
  Future<bool> readLogoutPending();
  Future<void> writeLogoutPending(bool pending);
}

class MemorySessionIntentStore implements SessionIntentStore {
  bool pending = false;
  @override
  Future<bool> readLogoutPending() async => pending;
  @override
  Future<void> writeLogoutPending(bool value) async { pending = value; }
}

class PortalAccount {
  const PortalAccount({required this.id, required this.role, required this.displayName, this.businessId});
  final String id, role, displayName;
  final String? businessId;
  bool get isBusiness => role == 'business' && (businessId?.isNotEmpty ?? false);
  // The admin role is a proposed extension to v3 and must be assigned by the server.
  bool get isAdmin => role == 'admin';
  String get identity => '$id:$role:${businessId ?? ''}';

  factory PortalAccount.fromJson(dynamic data) {
    if (data is! Map || data['id'] is! String || (data['id'] as String).isEmpty ||
        data['role'] is! String || data['displayName'] is! String ||
        (data['businessId'] != null && data['businessId'] is! String)) {
      throw const ApiException('El servidor no devolvió un perfil completo.', code: 'INVALID_PROFILE');
    }
    return PortalAccount(id: data['id'] as String, role: data['role'] as String,
      displayName: data['displayName'] as String, businessId: data['businessId'] as String?);
  }
}

class _AccessToken {
  const _AccessToken(this.value, this.expiresAt);
  final String value;
  final DateTime expiresAt;
  factory _AccessToken.fromJson(dynamic data, DateTime now) {
    final tokens = data is Map ? data['tokens'] : null;
    final value = tokens is Map ? tokens['accessToken'] : null;
    final expiry = tokens is Map ? tokens['accessTokenExpiresAt'] : null;
    final date = expiry is String ? DateTime.tryParse(expiry)?.toUtc() : null;
    if (value is! String || value.isEmpty || date == null || !date.isAfter(now)) {
      throw const ApiException('El servidor no devolvió una sesión válida.', code: 'INVALID_SESSION');
    }
    // refreshToken is deliberately neither read nor persisted in browser code.
    return _AccessToken(value, date);
  }
}

class RestSession extends ChangeNotifier {
  RestSession({required Uri baseUri, required http.Client client, DateTime Function()? now, SessionIntentStore? intentStore})
      : rawClient = client, api = ApiClient(baseUri: baseUri, client: client),
        intentStore = intentStore ?? MemorySessionIntentStore(),
        _now = now ?? (() => DateTime.now().toUtc());
  final http.Client rawClient;
  final ApiClient api;
  final SessionIntentStore intentStore;
  final DateTime Function() _now;
  PortalSessionPhase phase = PortalSessionPhase.restoring;
  PortalAccount? account;
  String? message;
  bool logoutPending = false;
  _AccessToken? _token;
  Future<bool>? _refreshing;
  Future<void> _cookieTail = Future<void>.value();
  int _generation = 0;
  bool _disposed = false;
  int get generation => _generation;
  bool _current(int generation) => !_disposed && generation == _generation;
  void _changed() { if (!_disposed) notifyListeners(); }

  Future<dynamic> _cookiePost(String path, Map<String, dynamic> body, {Map<String, String> headers = const {}}) {
    final next = _cookieTail.then((_) => api.json('POST', path, body: body, headers: headers));
    _cookieTail = next.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return next;
  }

  Future<PortalAccount> _profile(_AccessToken token) async => PortalAccount.fromJson(
    await api.json('GET', 'users/me', headers: {'Authorization': 'Bearer ${token.value}'}));

  Future<void> restore() async {
    if (logoutPending) { await signOut(); return; }
    final generation = ++_generation;
    _refreshing = null;
    _token = null; account = null; phase = PortalSessionPhase.restoring; message = null; _changed();
    try {
      final pending = await intentStore.readLogoutPending();
      if (!_current(generation)) return;
      if (pending) { logoutPending = true; await signOut(); return; }
      final token = _AccessToken.fromJson(await _cookiePost('auth/refresh', {}), _now());
      if (!_current(generation)) return;
      final profile = await _profile(token);
      if (!_current(generation)) return;
      _token = token; account = profile; phase = PortalSessionPhase.authenticated; _changed();
    } catch (error) {
      if (!_current(generation)) return;
      if (error is ApiException && (error.status == 401 || error.status == 403)) {
        phase = PortalSessionPhase.signedOut; message = null;
      } else {
        phase = PortalSessionPhase.unavailable;
        message = error is ApiException ? error.message : 'No se pudo comprobar la sesión.';
      }
      _changed();
    }
  }

  Future<void> signIn(String email, String password) async {
    if (phase == PortalSessionPhase.signingIn || phase == PortalSessionPhase.signingOut || logoutPending) return;
    final normalized = email.trim().toLowerCase();
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(normalized) || password.isEmpty) {
      throw const ApiException('Escribe tu correo y contraseña.');
    }
    final generation = ++_generation;
    _refreshing = null;
    _token = null; account = null; message = null; phase = PortalSessionPhase.signingIn; _changed();
    try {
      final token = _AccessToken.fromJson(await _cookiePost('auth/login',
        {'email': normalized, 'password': password}), _now());
      if (!_current(generation)) return;
      final profile = await _profile(token);
      if (!_current(generation)) return;
      _token = token; account = profile; phase = PortalSessionPhase.authenticated; _changed();
    } catch (error) {
      if (!_current(generation)) return;
      _token = null; account = null; phase = PortalSessionPhase.signedOut;
      message = error is ApiException ? error.message : 'No se pudo iniciar sesión.';
      _changed();
    }
  }

  Future<void> forgotPassword(String email) async {
    final normalized = email.trim().toLowerCase();
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(normalized)) {
      throw const ApiException('Escribe un correo válido para recuperar el acceso.');
    }
    await api.json('POST', 'auth/forgot-password', body: {'email': normalized});
  }

  Future<String> accessToken() async {
    if (_token == null || phase != PortalSessionPhase.authenticated) {
      throw const ApiException('Vuelve a iniciar sesión.', code: 'UNAUTHENTICATED');
    }
    if (!_token!.expiresAt.isAfter(_now().add(const Duration(seconds: 30)))) {
      if (!await refresh(expectedToken: _token!.value)) {
        throw const ApiException('Tu sesión terminó.', code: 'UNAUTHENTICATED');
      }
    }
    final token = _token;
    if (token == null) throw const ApiException('Tu sesión terminó.', code: 'UNAUTHENTICATED');
    return token.value;
  }

  Future<bool> refresh({String? expectedToken}) {
    if (_token == null || phase != PortalSessionPhase.authenticated) return Future.value(false);
    if (expectedToken != null && _token!.value != expectedToken) return Future.value(true);
    final running = _refreshing;
    if (running != null) return running;
    final future = _renew();
    _refreshing = future;
    return future.whenComplete(() {
      if (identical(_refreshing, future)) _refreshing = null;
    });
  }

  Future<bool> _renew() async {
    final generation = _generation;
    try {
      final token = _AccessToken.fromJson(await _cookiePost('auth/refresh', {}), _now());
      if (!_current(generation)) return false;
      final profile = await _profile(token);
      if (!_current(generation)) return false;
      if (profile.identity != account?.identity) _generation++;
      _token = token; account = profile; _changed();
      return true;
    } catch (_) {
      if (_current(generation)) invalidate('No se pudo renovar tu sesión. Vuelve a iniciar sesión.');
      return false;
    }
  }

  void invalidate(String reason) {
    if (_disposed) return;
    _generation++; _refreshing = null; _token = null; account = null; phase = PortalSessionPhase.signedOut;
    message = reason; _changed();
  }

  Future<void> signOut() async {
    if (phase == PortalSessionPhase.signingOut) return;
    final token = _token?.value;
    final generation = ++_generation;
    _refreshing = null;
    _token = null; account = null; phase = PortalSessionPhase.signingOut; message = null;
    logoutPending = true; _changed();
    try {
      await intentStore.writeLogoutPending(true);
      if (!_current(generation)) return;
      // Logout follows in-flight cookie rotations so a late login cannot undo it.
      await _cookiePost('auth/logout', {},
        headers: {if (token != null) 'Authorization': 'Bearer $token'});
      if (!_current(generation)) return;
      await intentStore.writeLogoutPending(false);
      if (!_current(generation)) return;
      logoutPending = false;
    } on ApiException catch (error) {
      if (!_current(generation)) return;
      if (error.status == 401) {
        try { await intentStore.writeLogoutPending(false); logoutPending = false; }
        catch (_) { message = 'Reintenta para completar el cierre en este dispositivo.'; }
      } else {
        message = 'Se ocultaron los datos, pero el servidor no confirmó el cierre de sesión. Reintenta para completarlo.';
      }
    } catch (_) {
      if (!_current(generation)) return;
      message = 'El servidor no confirmó el cierre de sesión. Reintenta para completarlo.';
    }
    if (_current(generation)) { phase = PortalSessionPhase.signedOut; _changed(); }
  }

  @override
  void dispose() {
    _disposed = true; _generation++; _token = null; account = null;
    rawClient.close(); super.dispose();
  }
}

/// One refresh for simultaneous expirations. Network failures never replay writes.
class SessionHttpClient extends http.BaseClient {
  SessionHttpClient(this.session);
  final RestSession session;
  bool _closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (_closed || !belongsToApi(session.api.baseUri, request.url)) {
      throw const ApiException('La solicitud no pertenece a la API configurada.', code: 'CONFIGURATION');
    }
    final generation = session.generation;
    final bytes = await request.finalize().toBytes();
    for (var attempt = 0; attempt < 2; attempt++) {
      final token = await session.accessToken();
      if (generation != session.generation) throw const ApiException('La sesión cambió.', code: 'SESSION_CHANGED');
      final abort = Completer<void>();
      final outgoing = http.AbortableRequest(request.method, request.url, abortTrigger: abort.future)
        ..followRedirects = false
        ..headers.addAll(request.headers)
        ..headers['Authorization'] = 'Bearer $token'
        ..bodyBytes = bytes;
      final response = await (() async => http.Response.fromStream(await session.rawClient.send(outgoing)))()
          .timeout(const Duration(seconds: 20), onTimeout: () {
            if (!abort.isCompleted) abort.complete();
            throw TimeoutException('La API tardó demasiado.');
          });
      if (_closed || generation != session.generation) {
        throw const ApiException('La sesión cambió.', code: 'SESSION_CHANGED');
      }
      final code = response.statusCode == 401 || response.statusCode == 403 ? responseErrorCode(response) : '';
      if (response.statusCode == 401 && code == 'TOKEN_EXPIRED' && attempt == 0) {
        if (await session.refresh(expectedToken: token)) continue;
      } else if (response.statusCode == 401) {
        session.invalidate('Tu sesión terminó. Vuelve a iniciar sesión.');
      } else if (response.statusCode == 403 && ['ROLE_REVOKED', 'ACCESS_REVOKED'].contains(code)) {
        session.invalidate('Tu acceso cambió. Vuelve a iniciar sesión.');
      }
      return http.StreamedResponse(Stream.value(response.bodyBytes), response.statusCode,
        headers: response.headers, reasonPhrase: response.reasonPhrase, request: request);
    }
    throw const ApiException('Tu sesión terminó.', code: 'UNAUTHENTICATED');
  }

  @override
  void close() { _closed = true; }
}
