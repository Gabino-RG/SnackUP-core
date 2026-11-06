import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:snackup/api/api_client.dart';
import 'package:snackup/api/rest_session.dart';

const origin = 'http://localhost:18080';

/// Shares the real server cookie between the two logins, as browser tabs do.
class _SharedLocalCookieClient extends http.BaseClient {
  final _inner = IOClient(HttpClient()..findProxy = (_) => 'DIRECT');
  String? _cookie;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.url.origin != origin) {
      throw StateError('Se requiere el servidor local de integración.');
    }
    request.headers['Origin'] = origin;
    if (_cookie != null) request.headers['Cookie'] = _cookie!;
    final response = await _inner.send(request);
    final assigned = response.headers['set-cookie'];
    if (assigned != null) _cookie = assigned.split(';').first;
    return response;
  }

  @override
  void close() => _inner.close();
}

void main() {
  test(
    'una renovación conserva la cocina propia y rechaza la de otra pestaña',
    () async {
      final env = Platform.environment;
      final loginA = env['SNACKUP_QA_OPERATOR'];
      final loginB = env['SNACKUP_QA_OTHER_OPERATOR'];
      final passwordA = env['SNACKUP_QA_OPERATOR_PASSWORD'];
      final passwordB = env['SNACKUP_QA_OTHER_OPERATOR_PASSWORD'];
      if ([
        loginA,
        loginB,
        passwordA,
        passwordB,
      ].any((v) => v == null || v.isEmpty)) {
        fail(
          'Configura dos operadores locales distintos y sus credenciales de prueba.',
        );
      }
      final base = Uri.parse('$origin/api/legacy/v1/');
      final session = RestSession(
        baseUri: base,
        client: _SharedLocalCookieClient(),
      );
      String? tokenA;
      addTearDown(() async {
        try {
          // Close both test logins even if an assertion failed after rotation.
          await session.api.json(
            'POST',
            'auth/logout',
            body: {},
            headers: {if (tokenA != null) 'Authorization': 'Bearer $tokenA'},
          );
        } finally {
          session.dispose();
        }
      });

      await session.signIn(loginA!, passwordA!);
      expect(session.phase, PortalSessionPhase.authenticated);
      tokenA = await session.accessToken();
      final accountA = session.account!;
      final originalPanel = SessionHttpClient(session);
      expect(await session.refresh(), isTrue);
      expect(session.account!.id == accountA.id, isTrue);

      final login = await session.api.json(
        'POST',
        'auth/login',
        body: {'email': loginB, 'password': passwordB},
      );
      final headersB = {
        'Authorization': 'Bearer ${login['tokens']['accessToken']}',
      };
      final accountB = await session.api.json(
        'GET',
        'users/me',
        headers: headersB,
      );
      expect(accountB['id'] != accountA.id, isTrue);
      expect(accountB['businessId'] != accountA.businessId, isTrue);
      expect(await session.refresh(), isFalse);
      expect(session.account, isNull);
      expect(session.phase, PortalSessionPhase.signedOut);
      await expectLater(
        originalPanel.get(base.resolve('users/me')),
        throwsA(
          isA<ApiException>().having((e) => e.code, 'code', 'SESSION_CHANGED'),
        ),
      );
      final stillSignedIn = await session.api.json(
        'GET',
        'users/me',
        headers: headersB,
      );
      expect(stillSignedIn['id'] == accountB['id'], isTrue);
    },
  );
}
