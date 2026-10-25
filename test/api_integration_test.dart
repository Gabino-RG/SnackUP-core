import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:snackup/api/api_client.dart';
import 'package:snackup/api/student_repository.dart';
import 'package:snackup/api/student_store.dart';
import 'package:snackup/student_api/catalog_screens.dart';
import 'package:snackup/student_api/order_screens.dart';

const shop = {
  'id': 'cafe',
  'name': 'Cafetería Central',
  'isOpen': true,
  'isActive': true,
};
const food = {
  'id': 'food',
  'businessId': 'cafe',
  'name': 'Chilaquiles',
  'description': 'Salsa verde',
  'category': 'Desayunos',
  'stock': 10,
  'isAvailable': true,
  'isFeatured': true,
  'price': 35.5,
  'version': 1,
  'imageUrl': null,
};
Json orderFixture({
  String status = 'ready',
  bool rated = false,
  int version = 1,
}) => {
  'id': 'order',
  'businessId': 'cafe',
  'orderNumber': 12,
  'version': version,
  'status': status,
  'isRated': rated,
  'total': 35.5,
  'paymentMethod': 'Efectivo',
  'pickupCode': 'AB12CD',
  'createdAt': '2026-10-24T12:00:00Z',
  'items': [
    {
      'productId': 'food',
      'name': 'Chilaquiles',
      'quantity': 1,
      'price': 35.5,
      'notes': 'Sin cebolla',
    },
  ],
};
http.Response response(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);
Json page(List<Json> rows, {int current = 1, int totalPages = 1}) => {
  'data': rows,
  'pagination': {
    'page': current,
    'limit': 100,
    'total': rows.length,
    'totalPages': totalPages,
  },
};
ApiClient client(FutureOr<http.Response> Function(http.Request) handler) =>
    ApiClient(
      base: Uri.parse('https://campus.test/api/v1/'),
      web: true,
      transport: MockClient((request) async => await handler(request)),
    );
Json tokenResponse(String token) => {
  'tokens': {
    'accessToken': token,
    'accessTokenExpiresAt': '2035-01-01T00:00:00Z',
    'refreshTokenExpiresAt': '2035-02-01T00:00:00Z',
  },
};
http.Response defaultResponse(http.Request req) {
  if (req.url.path == '/api/v1/businesses') return response(page([shop]));
  if (req.url.path == '/api/v1/businesses/cafe/products')
    return response(page([food]));
  if (req.url.path == '/api/legacy/v1/student/orders')
    return response(page([]));
  if (req.url.path == '/api/v1/users/me/orders/active')
    return response(page([]));
  if (req.url.path == '/api/v1/products/food') return response(food);
  if (req.url.path == '/api/v1/orders/order') return response(orderFixture());
  return response({
    'error': {'code': 'UNEXPECTED_ROUTE', 'message': req.url.path},
  }, 404);
}

Future<StudentStore> readyStore(
  FutureOr<http.Response?> Function(http.Request) handler, {
  String uid = 'student',
}) async {
  final api = client((req) async => await handler(req) ?? defaultResponse(req));
  api.accessToken = 'test-access';
  api.user = {
    'id': uid,
    'role': 'ALUMNO',
    'displayName': 'Alumno',
    'email': 'student@example.test',
  };
  final store = StudentStore(
    api,
    preferences: await SharedPreferences.getInstance(),
    realtimeEnabled: false,
  );
  await store.activate();
  return store;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'V3 login accepts only ALUMNO and does not put refresh tokens in web JSON',
    () async {
      final requests = <http.Request>[];
      final api = client((req) {
        requests.add(req);
        if (req.url.path.endsWith('/login'))
          return response({
            ...tokenResponse('new-access'),
            'user': {'id': 'student', 'role': 'ALUMNO'},
          });
        return http.Response('', 204);
      });
      addTearDown(api.dispose);
      await api.login(' student@example.test ', 'private-test-password');
      expect(api.user!['role'], 'ALUMNO');
      expect(api.accessToken, 'new-access');
      expect(jsonDecode(requests.first.body), {
        'email': 'student@example.test',
        'password': 'private-test-password',
      });
      await api.logout();
      expect(jsonDecode(requests.last.body), isEmpty);
      expect(api.user, isNull);
    },
  );
  test(
    'Kitchen login is revoked instead of opening the student application',
    () async {
      var loggedOut = false;
      final api = client((req) {
        if (req.url.path.endsWith('/logout')) {
          loggedOut = true;
          return http.Response('', 204);
        }
        return response({
          ...tokenResponse('kitchen'),
          'user': {'id': 'operator', 'role': 'COCINA'},
        });
      });
      addTearDown(api.dispose);
      await expectLater(
        api.login('operator@example.test', 'test-password'),
        throwsA(
          isA<ApiException>().having((e) => e.code, 'code', 'STUDENT_REQUIRED'),
        ),
      );
      expect(loggedOut, isTrue);
      expect(api.user, isNull);
      expect(api.accessToken, isNull);
    },
  );
  test(
    'Concurrent expired requests share one refresh and retry with the new Bearer',
    () async {
      int refreshes = 0;
      final release = Completer<void>();
      final api = client((req) async {
        if (req.url.path.endsWith('/refresh')) {
          refreshes++;
          await release.future;
          expect(jsonDecode(req.body), isEmpty);
          return response(tokenResponse('renewed'));
        }
        if (req.headers['Authorization'] == 'Bearer renewed')
          return response({'id': 'student'});
        return response({
          'error': {'code': 'TOKEN_EXPIRED', 'message': 'Renovar'},
        }, 401);
      });
      addTearDown(api.dispose);
      api.accessToken = 'old';
      final first = api.request('GET', 'users/me');
      final second = api.request('GET', 'users/me');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      release.complete();
      final results = await Future.wait([first, second]);
      expect(refreshes, 1);
      expect(results.every((row) => row['id'] == 'student'), isTrue);
    },
  );
  test(
    'Catalogue follows all pages and distinguishes unlimited stock from zero',
    () async {
      final api = client(
        (req) => response(
          page(
            [
              {'id': req.url.queryParameters['page']},
            ],
            current: int.parse(req.url.queryParameters['page']!),
            totalPages: 2,
          ),
        ),
      );
      addTearDown(api.dispose);
      api.accessToken = 'test';
      final rows = await StudentRepository(api).businesses();
      expect(rows.map((r) => r['id']), ['1', '2']);
      expect(apiProductAvailable({...food, 'stock': null}), isTrue);
      expect(apiProductAvailable({...food, 'stock': 0}), isFalse);
      expect(
        apiProductAvailable({...food, 'stock': 3, 'isAvailable': false}),
        isFalse,
      );
    },
  );
  test(
    'V3 has a real legacy history bridge with the same authorization',
    () async {
      final api = client((req) {
        expect(req.url.path, '/api/legacy/v1/student/orders');
        expect(req.headers['Authorization'], 'Bearer same-session');
        return response(page([orderFixture(status: 'completed')]));
      });
      addTearDown(api.dispose);
      api.accessToken = 'same-session';
      expect(
        (await StudentRepository(api).history()).single['status'],
        'completed',
      );
    },
  );
  test(
    'A failed purchase is persisted and retried after reload with the same UUID and body',
    () async {
      final requests = <http.Request>[];
      var fail = true;
      Future<http.Response?> handler(http.Request req) async {
        if (req.method == 'POST' && req.url.path == '/api/v1/orders') {
          requests.add(req);
          if (fail) throw http.ClientException('simulated transport loss');
          return response(orderFixture(), 201);
        }
        return null;
      }

      final original = await readyStore(handler);
      await original.add(food, 1, 'Sin cebolla');
      await expectLater(
        original.checkout('Transferencia'),
        throwsA(isA<ApiException>()),
      );
      final key = original.pendingPurchase!['key'];
      expect(
        key,
        matches(
          RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
          ),
        ),
      );
      await expectLater(
        original.clearCart(),
        throwsA(
          isA<ApiException>().having((e) => e.code, 'code', 'PURCHASE_PENDING'),
        ),
      );
      original.dispose();
      fail = false;
      final restored = await readyStore(handler);
      addTearDown(restored.dispose);
      expect(restored.pendingPurchase!['key'], key);
      await restored.checkout('Efectivo');
      expect(requests.length, 2);
      expect(requests[0].body, requests[1].body);
      expect(
        requests[0].headers['Idempotency-Key'],
        requests[1].headers['Idempotency-Key'],
      );
      final body = jsonDecode(requests.last.body) as Map;
      expect(body.keys.toSet(), {
        'businessId',
        'items',
        'paymentMethod',
        'expectedTotal',
      });
      expect(body['paymentMethod'], 'Transferencia');
      expect(body['expectedTotal'], 35.5);
      expect((body['items'] as List).single, {
        'productId': 'food',
        'quantity': 1,
        'notes': 'Sin cebolla',
      });
      expect(restored.cart, isEmpty);
      expect(restored.pendingPurchase, isNull);
    },
  );
  test(
    'Price rejection preserves the basket and allows explicit repricing',
    () async {
      var price = 35.5;
      final store = await readyStore((req) {
        if (req.method == 'POST' && req.url.path == '/api/v1/orders')
          return response({
            'error': {'code': 'PRICE_CHANGED', 'message': 'El precio cambió'},
          }, 409);
        if (req.url.path == '/api/v1/products/food')
          return response({...food, 'price': price});
        return null;
      });
      addTearDown(store.dispose);
      await store.add(food, 1, '');
      await expectLater(
        store.checkout('Efectivo'),
        throwsA(
          isA<ApiException>().having((e) => e.code, 'code', 'PRICE_CHANGED'),
        ),
      );
      expect(store.cart.length, 1);
      expect(store.pendingPurchase, isNull);
      price = 40;
      await store.updateCartPrices();
      expect(store.total, 40);
    },
  );
  test(
    'Favourites and carts are separated by API user and restore notes',
    () async {
      final first = await readyStore((_) => null);
      await first.add(food, 1, 'Sin salsa');
      await first.favorite('food', notes: 'Sin salsa');
      first.dispose();
      final other = await readyStore((_) => null, uid: 'another');
      expect(other.cart, isEmpty);
      expect(other.favorites, isEmpty);
      other.dispose();
      final restored = await readyStore((_) => null);
      addTearDown(restored.dispose);
      expect(restored.cart.single['notes'], 'Sin salsa');
      expect(restored.favoriteNotes['food'], 'Sin salsa');
    },
  );
  test(
    'Business and food reviews use separate V3 payloads without Firebase identity',
    () async {
      final calls = <http.Request>[];
      final api = client((req) {
        calls.add(req);
        return response({}, 201);
      });
      addTearDown(api.dispose);
      final repo = StudentRepository(api);
      await repo.rate('order', 5, 'Muy buena atención');
      await repo.rate('order', 4, 'Muy rico', productId: 'food');
      expect(calls[0].url.path, '/api/v1/orders/order/rating');
      expect(jsonDecode(calls[0].body), {
        'rating': 5,
        'comment': 'Muy buena atención',
      });
      expect(calls[1].url.path, '/api/v1/orders/order/reviews');
      expect(jsonDecode(calls[1].body), {
        'reviews': [
          {'productId': 'food', 'rating': 4, 'comment': 'Muy rico'},
        ],
      });
    },
  );
  test(
    'Cancellation sends the server version and the permitted student reason',
    () async {
      final api = client((req) {
        expect(req.url.path, '/api/v1/orders/order/cancel');
        expect(jsonDecode(req.body), {
          'expectedVersion': 3,
          'reason': 'user_other',
        });
        return response(orderFixture(status: 'cancelled', version: 4));
      });
      addTearDown(api.dispose);
      expect(
        (await StudentRepository(
          api,
        ).cancel(orderFixture(status: 'pending', version: 3)))['status'],
        'cancelled',
      );
    },
  );
  test(
    'Renewal never applies a different account from another browser tab',
    () async {
      final api = client((req) {
        if (req.url.path.endsWith('/refresh'))
          return response(tokenResponse('account-b-token'));
        if (req.url.path.endsWith('/users/me'))
          return response({'id': 'account-b', 'role': 'ALUMNO'});
        return response({
          'error': {'code': 'TOKEN_EXPIRED', 'message': 'Renovar'},
        }, 401);
      });
      addTearDown(api.dispose);
      api.user = {'id': 'account-a', 'role': 'ALUMNO'};
      api.accessToken = 'account-a-token';
      await expectLater(
        api.request('GET', 'private'),
        throwsA(
          isA<ApiException>().having((e) => e.code, 'code', 'SESSION_CHANGED'),
        ),
      );
      expect(api.user, isNull);
      expect(api.accessToken, isNull);
    },
  );
  test(
    'Native refresh is secured and restored outside normal preferences',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      final api = ApiClient(
        base: Uri.parse('https://campus.test/api/v1/'),
        web: false,
        transport: MockClient((req) async {
          expect(req.headers.containsKey('Origin'), isFalse);
          return response({
            ...tokenResponse('native-access'),
            'tokens': {
              ...tokenResponse('native-access')['tokens'] as Map,
              'refreshToken': 'native-refresh-original',
            },
            'user': {'id': 'student', 'role': 'ALUMNO'},
          });
        }),
      );
      await api.login('student@example.test', 'private-test-password');
      expect(
        (await api.storage!.readAll()).values,
        contains('native-refresh-original'),
      );
      expect(
        (await api.storage!.readAll()).values,
        isNot(contains('native-access')),
      );
      api.dispose();
      final restored = ApiClient(
        base: Uri.parse('https://campus.test/api/v1/'),
        web: false,
        transport: MockClient((req) async {
          if (req.url.path.endsWith('/refresh')) {
            expect(jsonDecode(req.body), {
              'refreshToken': 'native-refresh-original',
            });
            return response({
              'tokens': {
                ...tokenResponse('new-native')['tokens'] as Map,
                'refreshToken': 'native-refresh-rotated',
              },
            });
          }
          if (req.url.path.endsWith('/logout')) {
            expect(jsonDecode(req.body), {
              'refreshToken': 'native-refresh-rotated',
            });
            return http.Response('', 204);
          }
          return response({'id': 'student', 'role': 'ALUMNO'});
        }),
      );
      addTearDown(restored.dispose);
      await restored.restore();
      expect(restored.user!['id'], 'student');
      await restored.logout();
      expect(await restored.storage!.readAll(), isEmpty);
    },
  );

  test(
    'A slow order response cannot restore a pickup code after delivery',
    () async {
      final store = await readyStore((_) => null);
      addTearDown(store.dispose);
      store.orders = [orderFixture(status: 'completed', version: 2)];
      final result = await store.refreshOrder('order');
      expect(result['status'], 'completed');
      expect(store.orders.single['version'], 2);
    },
  );

  testWidgets(
    'REST delivery removes pickup QR and displays thanks and rating',
    (tester) async {
      tester.view.physicalSize = const Size(390, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = await readyStore((_) => null);
      addTearDown(store.dispose);
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: store,
          child: const MaterialApp(home: StudentOrderScreen(id: 'order')),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(QrImageView), findsOneWidget);
      expect(find.text('AB12CD'), findsOneWidget);
      store.orders = [orderFixture(status: 'completed', version: 2)];
      store.changed();
      await tester.pumpAndSettle();
      expect(find.byType(QrImageView), findsNothing);
      expect(find.text('¡Gracias por tu compra!'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('REST menu hides zero stock and retains unlimited products', (
    tester,
  ) async {
    final store = await readyStore((_) => null);
    addTearDown(store.dispose);
    store.products = [
      {...food, 'stock': null},
    ];
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: store,
        child: const MaterialApp(home: Scaffold(body: StudentCatalogScreen())),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Chilaquiles'), findsWidgets);
    store.products = [
      {...food, 'stock': 0},
    ];
    store.changed();
    await tester.pumpAndSettle();
    expect(find.text('Chilaquiles'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
