import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:snackup/student/student_api.dart';

Map<String, dynamic> profile([String id = 'student-1']) => {
  'id': id,
  'role': 'ALUMNO',
  'displayName': 'Estudiante',
  'email': 'alumno@example.edu',
};

Map<String, dynamic> tokens([String suffix = '1']) => {
  'accessToken': 'access-$suffix',
  'refreshToken': 'refresh-$suffix',
  'accessTokenExpiresAt': DateTime.now()
      .add(const Duration(minutes: 15))
      .toUtc()
      .toIso8601String(),
};

http.Response reply(Object? value, [int status = 200]) => http.Response(
  value == null ? '' : jsonEncode(value),
  status,
  headers: {'content-type': 'application/json'},
);

http.Response denied([String code = 'TOKEN_EXPIRED']) => reply({
  'error': {'code': code, 'message': 'La sesión requiere renovación.'},
}, 401);

StudentApi apiFor(Future<http.Response> Function(http.Request) handler) =>
    StudentApi(
      client: MockClient(handler),
      baseUrl: 'http://localhost:8000/api/v1',
      realtimeEnabled: false,
    );

void main() {
  for (final status in [200, 404]) {
    test(
      'a Flutter static server is reported as missing API ($status)',
      () async {
        final api = apiFor(
          (_) async => http.Response(
            '<html>Flutter application</html>',
            status,
            headers: {'content-type': 'text/html; charset=utf-8'},
          ),
        );
        addTearDown(api.dispose);
        await expectLater(
          api.getObject('/auth/options', authenticated: false),
          throwsA(
            isA<ApiException>()
                .having((error) => error.code, 'code', 'API_NOT_AVAILABLE')
                .having(
                  (error) => error.message,
                  'message',
                  contains('FastAPI'),
                ),
          ),
        );
      },
    );
  }
  test(
    'native login keeps credentials in memory and sends no Origin',
    () async {
      final requests = <http.Request>[];
      final api = apiFor((request) async {
        requests.add(request);
        if (request.url.path.endsWith('/auth/login')) {
          expect(jsonDecode(request.body), {
            'email': 'alumno@example.edu',
            'password': '  keep spaces  ',
          });
          return reply({'user': profile(), 'tokens': tokens()});
        }
        expect(request.headers['authorization'], 'Bearer access-1');
        return reply(profile());
      });
      addTearDown(api.dispose);

      await api.login(' alumno@example.edu ', '  keep spaces  ');
      await api.getObject('/users/me');

      expect(api.signedIn, isTrue);
      expect(api.user!['id'], 'student-1');
      expect(api.restoring, isFalse);
      expect(requests.every((r) => !r.headers.containsKey('origin')), isTrue);
      expect(requests.every((r) => !r.headers.containsKey('cookie')), isTrue);
    },
  );

  test('concurrent 401s share one refresh and retry with new bearer', () async {
    var refreshCount = 0;
    var purchaseAttempts = 0;
    var reads = 0;
    final refreshStarted = Completer<void>();
    final releaseRefresh = Completer<void>();
    final api = apiFor((request) async {
      switch (request.url.path) {
        case '/api/v1/auth/login':
          return reply({'user': profile(), 'tokens': tokens()});
        case '/api/v1/auth/refresh':
          refreshCount++;
          expect(jsonDecode(request.body), {'refreshToken': 'refresh-1'});
          refreshStarted.complete();
          await releaseRefresh.future;
          return reply({'tokens': tokens('2')});
        case '/api/v1/users/me':
          expect(request.headers['authorization'], 'Bearer access-2');
          return reply(profile());
        case '/api/v1/orders':
          purchaseAttempts++;
          expect(request.headers['idempotency-key'], 'stable-purchase-key');
          expect(jsonDecode(request.body), {'expectedTotal': 35});
          return request.headers['authorization'] == 'Bearer access-1'
              ? denied()
              : reply({'id': 'order-1'}, 201);
        default:
          reads++;
          return request.headers['authorization'] == 'Bearer access-1'
              ? denied()
              : reply({'ok': true});
      }
    });
    addTearDown(api.dispose);
    await api.login('a@example.edu', 'long-password');

    final purchase = api.request(
      'POST',
      '/orders',
      body: {'expectedTotal': 35},
      headers: {'Idempotency-Key': 'stable-purchase-key'},
    );
    final read = api.getObject('/businesses/business-1');
    await refreshStarted.future;
    releaseRefresh.complete();
    await Future.wait<dynamic>([purchase, read]);

    expect(refreshCount, 1);
    expect(purchaseAttempts, 2);
    expect(reads, 2);
    expect(api.signedIn, isTrue);
  });

  test('a lost POST response is never automatically repeated', () async {
    var purchases = 0;
    final api = apiFor((request) async {
      if (request.url.path.endsWith('/auth/login')) {
        return reply({'user': profile(), 'tokens': tokens()});
      }
      purchases++;
      throw http.ClientException('network diagnostic must stay private');
    });
    addTearDown(api.dispose);
    await api.login('a@example.edu', 'long-password');
    final revision = api.revision;

    await expectLater(
      api.request('POST', '/orders', body: {'expectedTotal': 35}),
      throwsA(
        isA<ApiException>()
            .having((e) => e.status, 'status', 0)
            .having((e) => e.code, 'code', 'NETWORK_ERROR')
            .having(
              (e) => e.message,
              'safe message',
              isNot(contains('diagnostic')),
            ),
      ),
    );
    expect(purchases, 1);
    expect(api.signedIn, isTrue);
    expect(api.revision, revision);
  });

  test(
    'restore exposes transport failures while preserving known session',
    () async {
      final api = apiFor((request) async {
        if (request.url.path.endsWith('/auth/login')) {
          return reply({'user': profile(), 'tokens': tokens()});
        }
        throw http.ClientException('offline');
      });
      addTearDown(api.dispose);
      await api.login('a@example.edu', 'long-password');

      await api.restore();

      expect(api.signedIn, isTrue);
      expect(api.restoring, isFalse);
      expect(api.restoreError, isA<ApiException>());
      expect(api.user!['id'], 'student-1');
    },
  );

  test(
    'failed profile read preserves the already rotated refresh token',
    () async {
      var refreshes = 0;
      var profiles = 0;
      final api = apiFor((request) async {
        if (request.url.path.endsWith('/auth/login')) {
          return reply({'user': profile(), 'tokens': tokens()});
        }
        if (request.url.path.endsWith('/auth/refresh')) {
          refreshes++;
          expect(jsonDecode(request.body), {
            'refreshToken': 'refresh-$refreshes',
          });
          return reply({'tokens': tokens('${refreshes + 1}')});
        }
        profiles++;
        if (profiles == 1) throw http.ClientException('offline');
        return reply(profile());
      });
      addTearDown(api.dispose);
      await api.login('a@example.edu', 'long-password');

      await api.restore();
      expect(api.restoreError, isNotNull);
      await api.restore();

      expect(refreshes, 2);
      expect(api.restoreError, isNull);
      expect(api.signedIn, isTrue);
    },
  );

  test(
    'revoked refresh signs out without retrying rejected operation',
    () async {
      var attempts = 0;
      final api = apiFor((request) async {
        if (request.url.path.endsWith('/auth/login')) {
          return reply({'user': profile(), 'tokens': tokens()});
        }
        if (request.url.path.endsWith('/auth/refresh')) {
          return denied('SESSION_REPLAY');
        }
        attempts++;
        return denied();
      });
      addTearDown(api.dispose);
      await api.login('a@example.edu', 'long-password');

      await expectLater(
        api.getObject('/users/me/orders/active'),
        throwsA(
          isA<ApiException>().having((e) => e.code, 'code', 'SESSION_REPLAY'),
        ),
      );

      expect(attempts, 1);
      expect(api.signedIn, isFalse);
      expect(api.user, isNull);
    },
  );

  test(
    'pending purchase is not retried under a different refreshed identity',
    () async {
      var purchases = 0;
      final api = apiFor((request) async {
        if (request.url.path.endsWith('/auth/login')) {
          return reply({'user': profile(), 'tokens': tokens()});
        }
        if (request.url.path.endsWith('/auth/refresh')) {
          return reply({'tokens': tokens('2')});
        }
        if (request.url.path.endsWith('/users/me')) {
          return reply(profile('other-student'));
        }
        purchases++;
        return denied();
      });
      addTearDown(api.dispose);
      await api.login('a@example.edu', 'long-password');

      await expectLater(
        api.request('POST', '/orders', body: {'expectedTotal': 35}),
        throwsA(
          isA<ApiException>().having((e) => e.code, 'code', 'SESSION_CHANGED'),
        ),
      );

      expect(purchases, 1);
      expect(api.signedIn, isFalse);
    },
  );

  test('logout cannot be undone by a delayed login response', () async {
    final loginStarted = Completer<void>();
    final loginResponse = Completer<http.Response>();
    final revocations = <http.Request>[];
    final api = apiFor((request) async {
      if (request.url.path.endsWith('/auth/login')) {
        loginStarted.complete();
        return loginResponse.future;
      }
      revocations.add(request);
      return reply(null, 204);
    });
    addTearDown(api.dispose);

    final signingIn = api.login('a@example.edu', 'long-password');
    final rejectedLogin = expectLater(
      signingIn,
      throwsA(
        isA<ApiException>().having((e) => e.code, 'code', 'SESSION_CHANGED'),
      ),
    );
    await loginStarted.future;
    final signingOut = api.logout();
    loginResponse.complete(reply({'user': profile(), 'tokens': tokens()}));
    await Future.wait<void>([rejectedLogin, signingOut]);

    expect(api.signedIn, isFalse);
    expect(revocations, hasLength(2));
    expect(revocations.first.headers['authorization'], 'Bearer access-1');
    expect(jsonDecode(revocations.first.body), {'refreshToken': 'refresh-1'});
  });

  test(
    'password reset waits for and supersedes in-flight restoration',
    () async {
      final refreshStarted = Completer<void>();
      final refreshed = Completer<http.Response>();
      final calls = <String>[];
      final api = apiFor((request) async {
        final path = request.url.path;
        calls.add(path);
        if (path.endsWith('/auth/login')) {
          return reply({'user': profile(), 'tokens': tokens()});
        }
        if (path.endsWith('/auth/refresh')) {
          refreshStarted.complete();
          return refreshed.future;
        }
        if (path.endsWith('/auth/reset-password')) {
          expect(jsonDecode(request.body), {
            'token': 'one-use-reset-token-123456',
            'newPassword': 'New-password-123!',
          });
          expect(request.headers.containsKey('authorization'), isFalse);
        }
        return reply(null, 204);
      });
      addTearDown(api.dispose);
      await api.login('a@example.edu', 'long-password');

      final restoring = api.restore();
      await refreshStarted.future;
      final resetting = api.request(
        'POST',
        '/auth/reset-password',
        authenticated: false,
        body: {
          'token': 'one-use-reset-token-123456',
          'newPassword': 'New-password-123!',
        },
      );
      expect(
        calls.where((path) => path.endsWith('/auth/reset-password')),
        isEmpty,
      );
      refreshed.complete(reply({'tokens': tokens('2')}));
      await Future.wait<dynamic>([restoring, resetting]);

      expect(calls.last, '/api/v1/auth/reset-password');
      expect(api.signedIn, isFalse);
      expect(api.restoring, isFalse);
      expect(api.restoreError, isNull);
      expect(calls.where((path) => path.endsWith('/users/me')), isEmpty);
    },
  );

  test('a pre-logout response never reaches the new session', () async {
    final started = Completer<void>();
    final response = Completer<http.Response>();
    final api = apiFor((request) async {
      if (request.url.path.endsWith('/auth/login')) {
        return reply({'user': profile(), 'tokens': tokens()});
      }
      if (request.url.path.endsWith('/auth/logout')) return reply(null, 204);
      started.complete();
      return response.future;
    });
    addTearDown(api.dispose);
    await api.login('a@example.edu', 'long-password');
    final read = api.getObject('/users/me/orders/active');
    final rejectedRead = expectLater(
      read,
      throwsA(
        isA<ApiException>().having((e) => e.code, 'code', 'SESSION_CHANGED'),
      ),
    );
    await started.future;
    await api.logout();
    response.complete(reply({'private': 'old student data'}));
    await rejectedRead;
    expect(api.signedIn, isFalse);
  });

  test('pagination consumes every page with a bounded server limit', () async {
    final pages = <String?>[];
    final api = apiFor((request) async {
      if (request.url.path.endsWith('/auth/login')) {
        return reply({'user': profile(), 'tokens': tokens()});
      }
      pages.add(request.url.queryParameters['page']);
      expect(request.url.queryParameters['limit'], '100');
      expect(request.url.queryParameters['q'], 'torta & agua');
      return reply({
        'data': [
          {'id': 'product-${pages.length}'},
        ],
        'pagination': {'totalPages': 3, 'page': pages.length},
      });
    });
    addTearDown(api.dispose);
    await api.login('a@example.edu', 'long-password');

    final all = await api.getAll(
      '/products/search',
      query: {'q': 'torta & agua'},
    );
    expect(all.map((item) => item['id']), [
      'product-1',
      'product-2',
      'product-3',
    ]);
    expect(pages, ['1', '2', '3']);
  });

  test(
    'success invalidates; server errors preserve details and safe proxy message',
    () async {
      final api = apiFor((request) async {
        if (request.url.path.endsWith('/auth/login')) {
          return reply({'user': profile(), 'tokens': tokens()});
        }
        if (request.url.path.endsWith('/proxy')) {
          return http.Response('<html>private infrastructure</html>', 502);
        }
        if (request.url.path.endsWith('/orders')) {
          return reply({
            'error': {
              'code': 'PRICE_CHANGED',
              'message': 'El precio cambió.',
              'details': {'currentTotal': 40},
            },
          }, 409);
        }
        return reply(null, 204);
      });
      addTearDown(api.dispose);
      await api.login('a@example.edu', 'long-password');
      final revision = api.revision;
      await api.request('DELETE', '/users/me/cart/items/item-1');
      expect(api.revision, revision + 1);
      await expectLater(
        api.request('POST', '/orders'),
        throwsA(
          isA<ApiException>().having((e) => e.status, 'status', 409).having(
            (e) => e.details,
            'details',
            {'currentTotal': 40},
          ),
        ),
      );
      await expectLater(
        api.getObject('/proxy'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.code, 'code', 'SERVER_ERROR')
              .having(
                (e) => e.message,
                'message',
                isNot(contains('private infrastructure')),
              ),
        ),
      );
    },
  );

  test(
    'unauthenticated requests and media URL resolution obey API origin',
    () async {
      var calls = 0;
      final api = apiFor((request) async {
        calls++;
        return reply({'googleEnabled': false});
      });
      addTearDown(api.dispose);
      await api.restore();
      expect(api.restoring, isFalse);
      expect(calls, 0);
      await expectLater(
        api.getObject('/users/me'),
        throwsA(isA<ApiException>()),
      );
      expect(calls, 0);
      expect(await api.getObject('/auth/options', authenticated: false), {
        'googleEnabled': false,
      });
      expect(
        api.mediaUrl('/media/product.webp'),
        'http://localhost:8000/media/product.webp',
      );
      expect(api.mediaUrl('javascript:alert(1)'), '');
      await expectLater(
        api.request('GET', '//external.test', authenticated: false),
        throwsA(isA<ApiException>()),
      );
      expect(calls, 1);
    },
  );
}
