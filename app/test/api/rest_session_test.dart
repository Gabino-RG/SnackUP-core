import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:snackup/api/api_client.dart';
import 'package:snackup/api/rest_session.dart';

final now = DateTime.utc(2026, 10, 12);
final base = Uri.parse('https://snackup.example/api/v1/');
http.Response reply(Object? value, [int status = 200]) => http.Response(jsonEncode(value), status);
Map<String, dynamic> tokens([String value = 'access-1']) => {'tokens': {
  'accessToken': value, 'accessTokenExpiresAt': now.add(const Duration(minutes: 15)).toIso8601String(),
  'refreshToken': 'must-never-be-used-by-web-code',
}};
Map<String, dynamic> profile({String role = 'business', String? businessId = 'local-1'}) => {
  'id': 'account-1', 'displayName': 'Operador', 'role': role, 'businessId': businessId,
};
RestSession makeSession(Future<http.Response> Function(http.Request) handler) =>
  RestSession(baseUri: base, client: MockClient(handler), now: () => now);

void main() {
  test('login preserves password and routes only from the verified server profile', () async {
    final session = makeSession((r) async {
      if (r.url.path.endsWith('auth/login')) {
        expect(jsonDecode(r.body), {'email': 'owner@example.test', 'password': ' secret '});
        return reply({...tokens(), 'user': profile(role: 'admin')});
      }
      expect(r.url.path, '/api/v1/users/me');
      expect(r.headers['Authorization'], 'Bearer access-1');
      return reply(profile());
    });
    addTearDown(session.dispose);
    await session.signIn(' OWNER@example.test ', ' secret ');
    expect(session.phase, PortalSessionPhase.authenticated);
    expect(session.account!.isBusiness, true);
    expect(session.account!.isAdmin, false);
    expect(await session.accessToken(), 'access-1');
  });

  test('cookie restore distinguishes a signed out user from a network failure', () async {
    var offline = false;
    final session = makeSession((r) async {
      expect(r.url.path, '/api/v1/auth/refresh');
      expect(jsonDecode(r.body), {});
      if (offline) throw http.ClientException('offline');
      return reply({'error': {'code': 'UNAUTHENTICATED'}}, 401);
    });
    addTearDown(session.dispose);
    await session.restore();
    expect(session.phase, PortalSessionPhase.signedOut);
    offline = true;
    await session.restore();
    expect(session.phase, PortalSessionPhase.unavailable);
    expect(session.account, isNull);
  });

  test('simultaneous expired requests renew once and retry with the new token', () async {
    var refreshes = 0, expired = 0;
    final bothExpired = Completer<void>(), refreshStarted = Completer<void>();
    final renewed = Completer<http.Response>();
    final session = makeSession((r) async {
      if (r.url.path.endsWith('auth/login')) return reply(tokens());
      if (r.url.path.endsWith('users/me')) return reply(profile());
      if (r.url.path.endsWith('auth/refresh')) {
        refreshes++; refreshStarted.complete();
        expect(jsonDecode(r.body), {});
        return renewed.future;
      }
      if (r.headers['Authorization'] == 'Bearer access-1') {
        expired++;
        if (expired == 2) bothExpired.complete();
        return reply({'error': {'code': 'TOKEN_EXPIRED'}}, 401);
      }
      expect(r.headers['Authorization'], 'Bearer access-2');
      return reply({'ok': true});
    });
    addTearDown(session.dispose);
    await session.signIn('owner@example.test', 'secret');
    final client = SessionHttpClient(session);
    final pending = Future.wait([client.get(base.resolve('one')), client.get(base.resolve('two'))]);
    await bothExpired.future;
    await refreshStarted.future;
    expect(refreshes, 1);
    renewed.complete(reply(tokens('access-2')));
    expect((await pending).every((r) => r.statusCode == 200), true);
    expect(refreshes, 1);
  });

  test('failed refresh invalidates the session without retrying the mutation', () async {
    var mutations = 0;
    final session = makeSession((r) async {
      if (r.url.path.endsWith('auth/login')) return reply(tokens());
      if (r.url.path.endsWith('users/me')) return reply(profile());
      if (r.url.path.endsWith('auth/refresh')) return reply({'error': {'code': 'REVOKED'}}, 401);
      mutations++;
      return reply({'error': {'code': 'TOKEN_EXPIRED'}}, 401);
    });
    addTearDown(session.dispose);
    await session.signIn('owner@example.test', 'secret');
    final r = await SessionHttpClient(session).post(base.resolve('products'), body: '{}');
    expect(r.statusCode, 401);
    expect(mutations, 1);
    expect(session.phase, PortalSessionPhase.signedOut);
    expect(session.account, isNull);
  });

  test('late login response cannot reactivate an already closed session', () async {
    final pendingLogin = Completer<http.Response>(), started = Completer<void>();
    final session = makeSession((r) async {
      if (r.url.path.endsWith('auth/login')) { started.complete(); return pendingLogin.future; }
      expect(r.url.path.endsWith('auth/logout'), true);
      return http.Response('', 204);
    });
    addTearDown(session.dispose);
    final pending = session.signIn('owner@example.test', 'secret');
    await started.future;
    final logout = session.signOut();
    pendingLogin.complete(reply(tokens()));
    await pending;
    await logout;
    expect(session.account, isNull);
    expect(session.phase, PortalSessionPhase.signedOut);
  });

  test('responses from a previous session are discarded and foreign URLs receive no token', () async {
    var sent = 0;
    final pendingData = Completer<http.Response>(), started = Completer<void>();
    final session = makeSession((r) async {
      sent++;
      if (r.url.path.endsWith('auth/login')) return reply(tokens());
      if (r.url.path.endsWith('users/me')) return reply(profile());
      if (r.url.path.endsWith('auth/logout')) return http.Response('', 204);
      started.complete(); return pendingData.future;
    });
    addTearDown(session.dispose);
    await session.signIn('owner@example.test', 'secret');
    final client = SessionHttpClient(session);
    await expectLater(client.get(Uri.parse('https://elsewhere.example/private')),
      throwsA(isA<ApiException>().having((e) => e.code, 'code', 'CONFIGURATION')));
    expect(sent, 2);
    final old = client.get(base.resolve('products'));
    final rejected = expectLater(old, throwsA(isA<ApiException>().having((e) => e.code, 'code', 'SESSION_CHANGED')));
    await started.future;
    await session.signOut();
    pendingData.complete(reply({'private': 'old session'}));
    await rejected;
  });

  test('network errors do not repeat a write; an unconfirmed logout remains actionable', () async {
    var writes = 0, logoutAttempts = 0, logins = 0;
    final session = makeSession((r) async {
      if (r.url.path.endsWith('auth/login')) { logins++; return reply(tokens()); }
      if (r.url.path.endsWith('users/me')) return reply(profile());
      if (r.url.path.endsWith('auth/logout')) {
        logoutAttempts++;
        if (logoutAttempts == 1) throw http.ClientException('offline');
        return http.Response('', 204);
      }
      writes++; throw http.ClientException('offline');
    });
    addTearDown(session.dispose);
    await session.signIn('owner@example.test', 'secret');
    final api = ApiClient(baseUri: base, client: SessionHttpClient(session));
    await expectLater(api.json('POST', 'products', body: {'name': 'Torta'}),
      throwsA(isA<ApiException>().having((e) => e.code, 'code', 'NETWORK')));
    expect(writes, 1);
    await session.signOut();
    expect(session.account, isNull);
    expect(session.logoutPending, true);
    await session.signIn('owner@example.test', 'secret');
    expect(logins, 1);
    await session.signOut();
    expect(session.logoutPending, false);
    expect(logoutAttempts, 2);
  });

  test('role changes on renewal discard the request from the earlier context', () async {
    var renewed = false, resourceReads = 0;
    final session = makeSession((r) async {
      if (r.url.path.endsWith('auth/login')) return reply(tokens());
      if (r.url.path.endsWith('users/me')) return reply(profile(role: renewed ? 'user' : 'admin', businessId: null));
      if (r.url.path.endsWith('auth/refresh')) { renewed = true; return reply(tokens('access-2')); }
      resourceReads++; return reply({'error': {'code': 'TOKEN_EXPIRED'}}, 401);
    });
    addTearDown(session.dispose);
    await session.signIn('owner@example.test', 'secret');
    await expectLater(SessionHttpClient(session).get(base.resolve('admin/reviews')),
      throwsA(isA<ApiException>().having((e) => e.code, 'code', 'SESSION_CHANGED')));
    expect(resourceReads, 1);
    expect(session.account!.isAdmin, false);
  });

  test('unfinished logout survives a new session controller without restoring access', () async {
    final intent = MemorySessionIntentStore();
    await intent.writeLogoutPending(true);
    var logouts = 0;
    final session = RestSession(baseUri: base, now: () => now, intentStore: intent,
      client: MockClient((r) async {
        expect(r.url.path.endsWith('auth/logout'), true);
        logouts++; return http.Response('', 204);
      }));
    addTearDown(session.dispose);
    await session.restore();
    expect(logouts, 1);
    expect(await intent.readLogoutPending(), false);
    expect(session.phase, PortalSessionPhase.signedOut);
    expect(session.account, isNull);
  });

  test('authenticated multipart preserves image bytes and boundary on token renewal', () async {
    final bodies = <String>[];
    final contentTypes = <String>[];
    final session = makeSession((r) async {
      if (r.url.path.endsWith('auth/login')) return reply(tokens());
      if (r.url.path.endsWith('users/me')) return reply(profile());
      if (r.url.path.endsWith('auth/refresh')) return reply(tokens('access-2'));
      bodies.add(r.body); contentTypes.add(r.headers['content-type']!);
      return bodies.length == 1 ? reply({'error': {'code': 'TOKEN_EXPIRED'}}, 401)
        : reply({'url': 'https://snackup.example/image.png'});
    });
    addTearDown(session.dispose);
    await session.signIn('owner@example.test', 'secret');
    final request = http.MultipartRequest('POST', base.resolve('media'))
      ..fields['purpose'] = 'product'
      ..files.add(http.MultipartFile.fromString('file', 'image bytes', filename: 'image.png'));
    expect((await SessionHttpClient(session).send(request)).statusCode, 200);
    expect(bodies.length, 2);
    expect(bodies.first, bodies.last);
    expect(bodies.first, contains('image bytes'));
    expect(contentTypes.first, startsWith('multipart/form-data; boundary='));
    expect(contentTypes.first, contentTypes.last);
  });
}
