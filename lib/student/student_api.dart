import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:socket_io_client/socket_io_client.dart' as io;

import 'api_platform.dart' as platform;
import '../notifications/browser_push.dart';

class ApiException implements Exception {
  const ApiException(
    this.status,
    this.code,
    this.message, {
    this.details,
    this.retryAfterSeconds,
  });

  final int status;
  final String code;
  final String message;
  final Object? details;
  final int? retryAfterSeconds;

  @override
  String toString() => message;
}

/// The canonical student API. Tokens remain in memory; browser refresh tokens
/// are exclusively managed by the server's HttpOnly cookie.
class StudentApi extends ChangeNotifier {
  StudentApi({
    http.Client? client,
    String? baseUrl,
    bool realtimeEnabled = true,
  }) : _client = client ?? platform.createClient(),
       _ownsClient = client == null,
       _baseUrl = _resolveBaseUrl(baseUrl),
       _realtimeEnabled = realtimeEnabled;

  final http.Client _client;
  final bool _ownsClient;
  final String _baseUrl;
  final bool _realtimeEnabled;
  Map<String, dynamic>? _user;
  String? _accessToken;
  String? _refreshToken;
  DateTime? _accessExpires;
  bool _restoring = true;
  Object? _restoreError;
  int _revision = 0;
  int _generation = 0;
  bool _disposed = false;
  Future<void> _authTail = Future<void>.value();
  Future<void>? _refreshing;
  Future<void>? _restoration;
  Timer? _expiryTimer;
  io.Socket? _socket;
  final LinkedHashSet<String> _businesses = LinkedHashSet<String>();
  final LinkedHashSet<String> _seenEvents = LinkedHashSet<String>();
  Set<String> _subscribed = {};
  bool _subscribing = false;
  bool _subscriptionChanged = false;
  // Unsent messages stay in this session only, never in browser storage.
  final Map<String, String> _chatDrafts = {};
  final Set<String> _uncertainChatSends = {};

  Map<String, dynamic>? get user => _user;
  bool get restoring => _restoring;
  Object? get restoreError => _restoreError;
  bool get signedIn => _user != null && _accessToken != null;
  int get revision => _revision;
  int get sessionGeneration => _generation;
  String get baseUrl => _baseUrl;

  String chatDraft(String chatId) => _chatDrafts[chatId] ?? '';

  bool chatSendUncertain(String chatId) => _uncertainChatSends.contains(chatId);

  void setChatSendUncertain(String chatId, bool uncertain) {
    if (!signedIn) return;
    if (uncertain) {
      _uncertainChatSends.add(chatId);
    } else {
      _uncertainChatSends.remove(chatId);
    }
  }

  void saveChatDraft(String chatId, String text) {
    if (!signedIn) return;
    if (text.isEmpty) {
      _chatDrafts.remove(chatId);
    } else {
      _chatDrafts[chatId] = text;
    }
  }

  void clearChatDraft(String chatId, {String? matchingText}) {
    if (matchingText == null ||
        _chatDrafts[chatId]?.trim() == matchingText.trim()) {
      _chatDrafts.remove(chatId);
    }
  }

  static String _resolveBaseUrl(String? explicit) {
    const configured = String.fromEnvironment('SNACKUP_API_BASE_URL');
    const nativeOrigin = String.fromEnvironment(
      'SNACKUP_PUBLIC_ORIGIN',
      defaultValue: 'http://localhost:8000',
    );
    var value = explicit ?? configured;
    if (value.isEmpty) {
      value = platform.webSession ? Uri.base.origin : nativeOrigin;
    }
    value = value.replaceFirst(RegExp(r'/+$'), '');
    final uri = Uri.tryParse(value);
    if (uri != null && (uri.path.isEmpty || uri.path == '/')) {
      value = '$value/api/v1';
    }
    return value;
  }

  Uri _uri(String path, Map<String, String>? query) {
    final base = Uri.tryParse(_baseUrl);
    if (base == null ||
        !{'http', 'https'}.contains(base.scheme) ||
        base.host.isEmpty ||
        base.userInfo.isNotEmpty ||
        base.hasQuery ||
        base.hasFragment) {
      throw const ApiException(
        0,
        'CONFIGURATION_ERROR',
        'Configura una dirección HTTP(S) válida para la API.',
      );
    }
    final originError = platform.validateOrigin(base);
    if (originError != null) {
      throw ApiException(0, 'CONFIGURATION_ERROR', originError);
    }
    final relative = Uri.tryParse(path);
    if (!path.startsWith('/') ||
        path.startsWith('//') ||
        relative == null ||
        relative.hasScheme ||
        relative.hasAuthority ||
        relative.hasFragment ||
        relative.pathSegments.any((part) => part == '..' || part == '.')) {
      throw const ApiException(
        0,
        'CONFIGURATION_ERROR',
        'Ruta de API inválida.',
      );
    }
    return Uri.parse(
      '$_baseUrl${relative.path}',
    ).replace(queryParameters: {...relative.queryParameters, ...?query});
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void invalidate() {
    if (_disposed) return;
    _revision++;
    _notify();
  }

  Future<T> _authOperation<T>(Future<T> Function() action) {
    final result = _authTail.then((_) {
      if (_disposed) throw _changed();
      return platform.withAuthLock('snackup-auth:$_baseUrl', action);
    });
    _authTail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    return result;
  }

  ApiException _changed() => const ApiException(
    401,
    'SESSION_CHANGED',
    'La sesión cambió. Actualiza antes de continuar.',
  );

  void _checkGeneration(int generation) {
    if (_disposed || generation != _generation) throw _changed();
  }

  Future<void> restore() {
    if (_restoration != null) return _restoration!;
    late Future<void> operation;
    operation = _restore().whenComplete(() {
      if (identical(_restoration, operation)) _restoration = null;
    });
    _restoration = operation;
    return operation;
  }

  Future<void> _restore() async {
    final generation = _generation;
    _restoring = true;
    _restoreError = null;
    _notify();
    try {
      if (platform.webSession || _refreshToken != null) {
        await _refresh();
        _checkGeneration(generation);
        _startSocket();
      }
    } catch (error) {
      if (generation == _generation && !_disposed) {
        if (error is ApiException && _isSessionFailure(error)) {
          _clearSession();
        } else {
          _restoreError = error;
        }
      }
    } finally {
      if (generation == _generation && !_disposed) {
        _restoring = false;
        _notify();
      }
    }
  }

  Future<void> login(String email, String password) async {
    final generation = ++_generation;
    // Do not let calls begun during an account switch use the old identity
    // while inheriting the new attempt's generation.
    _clearSession();
    _restoreError = null;
    invalidate();
    await _authOperation(() async {
      final result = _object(
        await _send(
          'POST',
          '/auth/login',
          body: {'email': email.trim(), 'password': password},
        ),
      );
      final tokens = _object(result['tokens']);
      if (_disposed || generation != _generation) {
        await _revokeResponse(tokens);
        throw _changed();
      }
      _acceptTokens(tokens);
      _user = _object(result['user']);
      _restoring = false;
      _restoreError = null;
      _businesses.clear();
      _seenEvents.clear();
      _startSocket();
      invalidate();
    });
  }

  Future<void> register({
    required String email,
    required String password,
    required String displayName,
    required String numeroDeControl,
  }) async {
    await request(
      'POST',
      '/auth/register',
      authenticated: false,
      body: {
        'email': email.trim(),
        'password': password,
        'displayName': displayName.trim(),
        'numeroDeControl': numeroDeControl.trim(),
      },
    );
  }

  Future<void> logout() async {
    final access = _accessToken;
    final refresh = _refreshToken;
    ++_generation;
    _clearSession();
    _restoring = false;
    _restoreError = null;
    invalidate();
    await _authOperation(() async {
      // End delivery on this browser even when the API is unreachable. Cleanup
      // is best effort and must never prevent revoking the session below.
      try {
        await deactivateBrowserPush().timeout(const Duration(seconds: 3));
      } catch (_) {
        // The server logout still runs if the browser cannot unsubscribe.
      }
      await _send(
        'POST',
        '/auth/logout',
        accessToken: access,
        body: platform.webSession || refresh == null
            ? <String, dynamic>{}
            : {'refreshToken': refresh},
      );
    });
  }

  Future<void> _revokeResponse(Map<String, dynamic> tokens) async {
    try {
      await _send(
        'POST',
        '/auth/logout',
        accessToken: tokens['accessToken'] as String?,
        body: platform.webSession
            ? <String, dynamic>{}
            : {'refreshToken': tokens['refreshToken']},
      );
    } catch (_) {
      // The interrupted action cannot restore local credentials. The caller
      // still receives SESSION_CHANGED and can explicitly retry logout.
    }
  }

  void _acceptTokens(Map<String, dynamic> tokens) {
    final token = tokens['accessToken'];
    if (token is! String || token.isEmpty) throw _invalidResponse();
    _accessToken = token;
    _refreshToken = platform.webSession
        ? null
        : tokens['refreshToken'] as String?;
    _accessExpires = DateTime.tryParse('${tokens['accessTokenExpiresAt']}');
    _expiryTimer?.cancel();
    if (_accessExpires != null) {
      final wait =
          _accessExpires!.difference(DateTime.now()) -
          const Duration(seconds: 30);
      _expiryTimer = Timer(wait.isNegative ? Duration.zero : wait, () {
        unawaited(_refresh().catchError((Object _) {}));
      });
    }
  }

  Future<void> _refresh() {
    if (_refreshing != null) return _refreshing!;
    final generation = _generation;
    late Future<void> operation;
    operation =
        _authOperation(() async {
          _checkGeneration(generation);
          final refresh = _refreshToken;
          if (!platform.webSession && refresh == null) throw _changed();
          try {
            final result = _object(
              await _send(
                'POST',
                '/auth/refresh',
                body: platform.webSession
                    ? <String, dynamic>{}
                    : {'refreshToken': refresh},
              ),
            );
            final tokens = _object(result['tokens']);
            if (_disposed || generation != _generation) {
              await _revokeResponse(tokens);
              throw _changed();
            }
            final newAccess = tokens['accessToken'];
            if (newAccess is! String || newAccess.isEmpty) {
              throw _invalidResponse();
            }
            // Preserve the rotated native refresh credential even if the following
            // profile read loses its connection; replaying the old one revokes it.
            if (!platform.webSession) {
              _refreshToken = tokens['refreshToken'] as String?;
            }
            final profile = _object(
              await _send('GET', '/users/me', accessToken: newAccess),
            );
            if (_disposed || generation != _generation) {
              await _revokeResponse(tokens);
              throw _changed();
            }
            // Another tab may have logged in as a different account. A refresh must
            // never silently retry a pending purchase under that new identity.
            if (_user != null && _user!['id'] != profile['id']) {
              throw _changed();
            }
            _acceptTokens(tokens);
            _user = profile;
            _startSocket();
            invalidate();
          } on ApiException catch (error) {
            if (generation == _generation && _isSessionFailure(error)) {
              ++_generation;
              _clearSession();
              _restoring = false;
              invalidate();
            }
            rethrow;
          }
        }).whenComplete(() {
          if (identical(_refreshing, operation)) _refreshing = null;
        });
    _refreshing = operation;
    return operation;
  }

  bool _isSessionFailure(ApiException error) =>
      error.status == 401 ||
      {
        'ACCESS_REVOKED',
        'ACCESS_PENDING',
        'ACCESS_REJECTED',
        'EMAIL_NOT_VERIFIED',
      }.contains(error.code);

  void _clearSession() {
    _expiryTimer?.cancel();
    _accessToken = null;
    _refreshToken = null;
    _accessExpires = null;
    _user = null;
    _chatDrafts.clear();
    _uncertainChatSends.clear();
    _businesses.clear();
    _seenEvents.clear();
    _stopSocket();
  }

  Future<dynamic> request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
    Map<String, String>? headers,
    bool authenticated = true,
  }) async {
    final verb = method.toUpperCase();
    if (!authenticated && verb == 'POST' && path == '/auth/reset-password') {
      // Reset clears the refresh cookie and revokes sessions on the server.
      // Coordinate it with restoration and other tabs just like logout.
      final resetGeneration = ++_generation;
      _clearSession();
      _restoring = false;
      _restoreError = null;
      invalidate();
      return _authOperation(() async {
        _checkGeneration(resetGeneration);
        final result = await _send(
          verb,
          path,
          body: body,
          query: query,
          headers: headers,
        );
        _checkGeneration(resetGeneration);
        invalidate();
        return result;
      });
    }
    final generation = _generation;
    if (authenticated && _accessToken == null) throw _changed();
    if (authenticated &&
        _accessExpires != null &&
        _accessExpires!.isBefore(
          DateTime.now().add(const Duration(seconds: 5)),
        )) {
      await _refresh();
    }
    _checkGeneration(generation);
    final originalAccess = _accessToken;
    dynamic result;
    try {
      result = await _send(
        verb,
        path,
        body: body,
        query: query,
        headers: headers,
        accessToken: authenticated ? originalAccess : null,
      );
    } on ApiException catch (error) {
      _checkGeneration(generation);
      if (!authenticated || error.status != 401) {
        if (authenticated && _isSessionFailure(error)) {
          ++_generation;
          _clearSession();
          _restoring = false;
          invalidate();
        }
        rethrow;
      }
      // A concurrent request may already have rotated the token. Never rotate
      // twice for the same rejected access token.
      if (originalAccess == _accessToken) await _refresh();
      _checkGeneration(generation);
      try {
        result = await _send(
          verb,
          path,
          body: body,
          query: query,
          headers: headers,
          accessToken: _accessToken,
        );
      } on ApiException catch (retryError) {
        if (generation == _generation && _isSessionFailure(retryError)) {
          ++_generation;
          _clearSession();
          _restoring = false;
          invalidate();
        }
        rethrow;
      }
    }
    _checkGeneration(generation);
    _discoverBusinesses(path, result);
    if (!{'GET', 'HEAD', 'OPTIONS'}.contains(verb)) invalidate();
    return result;
  }

  Future<dynamic> _send(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
    Map<String, String>? headers,
    String? accessToken,
  }) async {
    final uri = _uri(path, query);
    final outgoing = <String, String>{
      'Accept': 'application/json',
      if (body != null) 'Content-Type': 'application/json; charset=utf-8',
      ...?headers,
    };
    outgoing.removeWhere(
      (key, _) =>
          {'authorization', 'origin', 'cookie'}.contains(key.toLowerCase()),
    );
    if (accessToken != null) outgoing['Authorization'] = 'Bearer $accessToken';
    // The browser supplies Origin on auth POSTs. It is a forbidden request
    // header in Fetch; native requests deliberately omit it for token mode.
    http.Response response;
    final abort = Completer<void>();
    final deadline = Timer(const Duration(seconds: 25), () => abort.complete());
    try {
      final request = http.AbortableRequest(
        method,
        uri,
        abortTrigger: abort.future,
      )..headers.addAll(outgoing);
      if (body != null) request.body = jsonEncode(body);
      response =
          await (() async {
            final streamed = await _client.send(request);
            return http.Response.fromStream(streamed);
          })().timeout(
            const Duration(seconds: 25),
            onTimeout: () {
              if (!abort.isCompleted) abort.complete();
              throw TimeoutException('request');
            },
          );
    } on TimeoutException {
      throw const ApiException(
        0,
        'REQUEST_TIMEOUT',
        'La conexión tardó demasiado. Comprueba el estado antes de repetir la operación.',
      );
    } catch (_) {
      if (abort.isCompleted) {
        throw const ApiException(
          0,
          'REQUEST_TIMEOUT',
          'La conexión tardó demasiado. Comprueba el estado antes de repetir la operación.',
        );
      }
      throw const ApiException(
        0,
        'NETWORK_ERROR',
        'No se pudo conectar con el servidor. Comprueba tu conexión e inténtalo de nuevo.',
      );
    } finally {
      deadline.cancel();
    }
    final contentType = response.headers['content-type']?.toLowerCase() ?? '';
    if (path.startsWith('/auth/') &&
        (response.statusCode == 404 || contentType.contains('text/html'))) {
      throw ApiException(
        response.statusCode,
        'API_NOT_AVAILABLE',
        'No se encontró la API de SnackUP en este puerto. '
            'El servidor de Flutter solo muestra la interfaz. '
            'Inicia FastAPI y abre la aplicación mediante el servidor conjunto '
            'descrito en ALUMNOS_REST.md.',
      );
    }
    dynamic decoded;
    if (response.bodyBytes.isNotEmpty) {
      try {
        decoded = jsonDecode(utf8.decode(response.bodyBytes));
      } catch (_) {
        if (response.statusCode >= 200 && response.statusCode < 300) {
          throw _invalidResponse();
        }
      }
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final error = decoded is Map ? decoded['error'] : null;
      final code = error is Map && error['code'] is String
          ? error['code'] as String
          : response.statusCode >= 500
          ? 'SERVER_ERROR'
          : 'REQUEST_REJECTED';
      final message =
          error is Map &&
              error['message'] is String &&
              (error['message'] as String).isNotEmpty
          ? error['message'] as String
          : response.statusCode >= 500
          ? 'El servidor no pudo confirmar la operación. Comprueba su estado antes de repetirla.'
          : 'La solicitud no pudo completarse. Revisa los datos e inténtalo de nuevo.';
      throw ApiException(
        response.statusCode,
        code,
        message,
        details: error is Map ? error['details'] : null,
        retryAfterSeconds: int.tryParse(response.headers['retry-after'] ?? ''),
      );
    }
    return decoded;
  }

  ApiException _invalidResponse() => const ApiException(
    0,
    'INVALID_RESPONSE',
    'El servidor devolvió una respuesta inesperada.',
  );

  Map<String, dynamic> _object(dynamic value) {
    if (value is! Map) throw _invalidResponse();
    return Map<String, dynamic>.from(value);
  }

  Future<Map<String, dynamic>> getObject(
    String path, {
    Map<String, String>? query,
    bool authenticated = true,
  }) async => _object(
    await request('GET', path, query: query, authenticated: authenticated),
  );

  Future<List<Map<String, dynamic>>> getAll(
    String path, {
    Map<String, String>? query,
  }) async {
    final rows = <Map<String, dynamic>>[];
    var page = 1;
    while (true) {
      final response = await getObject(
        path,
        query: {...?query, 'page': '$page', 'limit': '100'},
      );
      final data = response['data'];
      final pagination = response['pagination'];
      if (data is! List ||
          pagination is! Map ||
          pagination['totalPages'] is! num) {
        throw _invalidResponse();
      }
      rows.addAll(data.map(_object));
      final totalPages = (pagination['totalPages'] as num).toInt();
      if (page >= totalPages) return rows;
      if (data.isEmpty || page >= 10000) throw _invalidResponse();
      page++;
    }
  }

  String mediaUrl(Object? value) {
    if (value is! String || value.isEmpty) return '';
    final base = Uri.tryParse(_baseUrl);
    final uri = base?.resolve(value);
    return uri != null && {'http', 'https'}.contains(uri.scheme)
        ? uri.toString()
        : '';
  }

  void _discoverBusinesses(String path, dynamic result) {
    if (result is! Map) return;
    final data = result['data'];
    final objects = data is List ? data.whereType<Map>() : [result];
    final prioritize = data is! List || path.startsWith('/businesses/');
    var changed = false;
    for (final item in objects) {
      final id =
          path == '/businesses' || RegExp(r'^/businesses/[^/]+$').hasMatch(path)
          ? item['id']
          : item['businessId'];
      if (id is String && id.isNotEmpty) {
        if (_businesses.length >= 30 &&
            !_businesses.contains(id) &&
            !prioritize) {
          continue;
        }
        changed = _businesses.add(id) || changed;
      }
    }
    // The gateway permits 64 rooms. Keep own order/chat rooms plus a bounded
    // set of recently discovered business and product rooms.
    while (_businesses.length > 30) {
      _businesses.remove(_businesses.first);
      changed = true;
    }
    if (changed) _subscribe();
  }

  Set<String> _topics() => {
    if (_user?['id'] case final String id) ...{
      'user:$id:orders',
      'user:$id:chats',
    },
    for (final id in _businesses) ...{'business:$id', 'business:$id:products'},
  };

  void _startSocket() {
    _stopSocket();
    if (!_realtimeEnabled ||
        !signedIn ||
        _user?['role'] != 'ALUMNO' ||
        _disposed) {
      return;
    }
    final base = _uri('/users/me', null);
    final socket = io.io(
      base.origin,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .setPath('/socket.io/')
          .setAuth({'token': _accessToken})
          .disableAutoConnect()
          .enableForceNew()
          .disableMultiplex()
          .setReconnectionDelay(1000)
          .setReconnectionDelayMax(10000)
          .build(),
    );
    _socket = socket;
    socket.onConnect((_) {
      if (!identical(_socket, socket)) return;
      _subscribed.clear();
      _subscribing = false;
      _subscriptionChanged = false;
      _subscribe();
    });
    socket.onDisconnect((reason) {
      if (!identical(_socket, socket)) return;
      _subscribed.clear();
      _subscribing = false;
      _subscriptionChanged = false;
      invalidate();
      if (reason == 'io server disconnect') {
        unawaited(_refresh().catchError((Object _) {}));
      }
    });
    socket.onConnectError((error) {
      if (!identical(_socket, socket)) return;
      if ([
        'TOKEN_EXPIRED',
        'UNAUTHENTICATED',
        'ACCESS_REVOKED',
      ].any((code) => '$error'.contains(code))) {
        unawaited(_refresh().catchError((Object _) {}));
      }
    });
    for (final event in [
      'order.created',
      'order.updated',
      'order.pickup_soon',
      'order.business_closed',
      'product.updated',
      'business.updated',
      'chat.opened',
      'chat.message',
      'chat.closed',
      'resync.required',
    ]) {
      socket.on(event, (dynamic payload) {
        if (!identical(_socket, socket)) return;
        final id = payload is Map ? payload['id'] : null;
        if (id is String && !_seenEvents.add(id)) return;
        while (_seenEvents.length > 1000) {
          _seenEvents.remove(_seenEvents.first);
        }
        invalidate();
      });
    }
    socket.connect();
  }

  void _subscribe() {
    final socket = _socket;
    if (socket == null || !socket.connected) return;
    if (_subscribing) {
      _subscriptionChanged = true;
      return;
    }
    final desired = _topics();
    if (setEquals(desired, _subscribed)) return;
    _subscribing = true;
    final removed = _subscribed.difference(desired).toList();
    void subscribe() {
      if (!identical(socket, _socket)) return;
      socket.emitWithAck(
        'subscribe',
        {'topics': desired.toList()},
        ack: (dynamic reply) {
          if (!identical(socket, _socket)) return;
          _subscribing = false;
          if (reply is Map && reply['ok'] == true) {
            _subscribed = desired;
            invalidate(); // Reconcile REST after the gateway acknowledges rooms.
          } else if (reply is Map &&
              reply['error'] is Map &&
              reply['error']['code'] == 'FORBIDDEN') {
            // A business can become inactive between REST discovery and ACK.
            // Preserve the student's private order/chat rooms in that case.
            _businesses.clear();
            _subscribed.clear();
            _subscriptionChanged = true;
          }
          if (_subscriptionChanged) {
            _subscriptionChanged = false;
            _subscribe();
          }
        },
      );
    }

    if (removed.isEmpty) {
      subscribe();
    } else {
      socket.emitWithAck('unsubscribe', {
        'topics': removed,
      }, ack: (dynamic _) => subscribe());
    }
  }

  void _stopSocket() {
    final socket = _socket;
    _socket = null;
    _subscribed.clear();
    _subscribing = false;
    _subscriptionChanged = false;
    socket?.dispose();
  }

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    _clearSession();
    if (_ownsClient) _client.close();
    super.dispose();
  }
}
