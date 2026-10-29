import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:snackup/api/api_client.dart';
import 'package:snackup/api/rest_session.dart';

void main() {
  final base = Uri.parse('https://snackup.example/api/legacy/v1/');
  http.Response json(
    Object body, [
    int status = 200,
    Map<String, String>? headers,
  ]) => http.Response(jsonEncode(body), status, headers: headers ?? {});
  for (final role in ['business', 'admin']) {
    for (final failure in ['busy', 'network', 'rate-limit', 'profile']) {
      test(
        '$role preserves session on $failure, waits and resumes without replaying writes',
        () async {
          var now = DateTime.utc(2026, 10, 28);
          var failing = false, refreshes = 0, writes = 0;
          final session = RestSession(
            baseUri: base,
            now: () => now,
            client: MockClient((r) async {
              http.Response unavailable() {
                if (failure == 'network') throw http.ClientException('offline');
                return json(
                  {
                    'error': {
                      'code': failure == 'rate-limit'
                          ? 'RATE_LIMITED'
                          : 'SERVICE_BUSY',
                    },
                  },
                  failure == 'rate-limit' ? 429 : 503,
                  {'retry-after': '5'},
                );
              }

              if (r.url.path.endsWith('auth/login') ||
                  r.url.path.endsWith('auth/refresh')) {
                if (r.url.path.endsWith('auth/refresh')) {
                  refreshes++;
                  if (failing && failure != 'profile') return unavailable();
                }
                return json({
                  'tokens': {
                    'accessToken': 'token-$refreshes',
                    'accessTokenExpiresAt': now
                        .add(const Duration(minutes: 1))
                        .toIso8601String(),
                  },
                });
              }
              if (r.url.path.endsWith('users/me')) {
                if (failing && failure == 'profile') return unavailable();
                return json({
                  'id': 'staff',
                  'role': role,
                  'displayName': 'Personal',
                  'businessId': role == 'business' ? 'local' : null,
                });
              }
              writes++;
              return json({'ok': true});
            }),
          );
          addTearDown(session.dispose);
          await session.signIn('staff@example.test', 'secret');
          final generation = session.generation;
          final client = ApiClient(
            baseUri: base,
            client: SessionHttpClient(session),
          );
          now = now.add(const Duration(minutes: 2));
          failing = true;
          for (var i = 0; i < 2; i++) {
            await expectLater(
              client.json('POST', 'mutation', body: {}),
              throwsA(
                isA<ApiException>().having(
                  (e) => e.isTransient,
                  'transient',
                  true,
                ),
              ),
            );
          }
          expect(refreshes, 1);
          expect(writes, 0);
          expect(session.generation, generation);
          expect(session.phase, PortalSessionPhase.authenticated);
          expect(session.account!.role, role);
          failing = false;
          now = now.add(const Duration(seconds: 6));
          expect(await client.json('POST', 'mutation', body: {}), {'ok': true});
          expect(refreshes, 2);
          expect(writes, 1);
          expect(session.message, isNull);
        },
      );
    }
  }
  test(
    'simultaneous expired responses share a failed refresh and do not replay mutations',
    () async {
      final now = DateTime.utc(2026, 10, 28);
      final pending = Completer<http.Response>();
      var writes = 0, refreshes = 0;
      final session = RestSession(
        baseUri: base,
        now: () => now,
        client: MockClient((r) async {
          if (r.url.path.endsWith('auth/login'))
            return json({
              'tokens': {
                'accessToken': 'token',
                'accessTokenExpiresAt': now
                    .add(const Duration(minutes: 10))
                    .toIso8601String(),
              },
            });
          if (r.url.path.endsWith('users/me'))
            return json({
              'id': 'staff',
              'role': 'business',
              'displayName': 'Cocina',
              'businessId': 'local',
            });
          if (r.url.path.endsWith('auth/refresh')) {
            refreshes++;
            return pending.future;
          }
          writes++;
          return json({
            'error': {'code': 'TOKEN_EXPIRED'},
          }, 401);
        }),
      );
      addTearDown(session.dispose);
      await session.signIn('staff@example.test', 'secret');
      final api = ApiClient(baseUri: base, client: SessionHttpClient(session));
      final checks = List.generate(
        2,
        (_) => expectLater(
          api.json('POST', 'mutation'),
          throwsA(
            isA<ApiException>().having((e) => e.code, 'code', 'SERVICE_BUSY'),
          ),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      pending.complete(
        json(
          {
            'error': {'code': 'SERVICE_BUSY'},
          },
          503,
          {'retry-after': '1'},
        ),
      );
      await Future.wait(checks);
      expect(refreshes, 1);
      expect(writes, 2);
      expect(session.phase, PortalSessionPhase.authenticated);
    },
  );
  for (final code in ['SERVICE_BUSY', 'DATABASE_UNAVAILABLE']) {
    test('$code has an actionable message and never replays a write', () async {
      var writes = 0;
      final api = ApiClient(
        baseUri: base,
        client: MockClient((r) async {
          writes++;
          return json(
            {
              'error': {'code': code},
            },
            503,
            {'retry-after': '1'},
          );
        }),
      );
      await expectLater(
        api.json('POST', 'mutation'),
        throwsA(
          isA<ApiException>()
              .having(
                (e) => e.message,
                'message',
                contains(
                  code == 'SERVICE_BUSY' ? 'ocupado' : 'antes de repetir',
                ),
              )
              .having(
                (e) => e.retryAfter,
                'retry delay',
                const Duration(seconds: 1),
              ),
        ),
      );
      expect(writes, 1);
    });
  }
}
