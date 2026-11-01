import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:snackup/features/user/cart_screen.dart';
import 'package:snackup/features/user/profile_orders_screen.dart';
import 'package:snackup/features/user/rate_order_screen.dart';
import 'package:snackup/features/user/show_qr_screen.dart';
import 'package:snackup/student/checkout.dart';
import 'package:snackup/student/student_api.dart';

class _MemoryStorage implements CheckoutStorage {
  final Map<String, Map<String, dynamic>> data = {};
  bool failWrites = false;

  @override
  Future<Map<String, dynamic>> read(String namespace) async =>
      Map<String, dynamic>.from(
        jsonDecode(jsonEncode(data[namespace] ?? {})) as Map,
      );

  @override
  Future<void> put(
    String namespace,
    String businessId,
    Map<String, dynamic> value,
  ) async {
    if (failWrites) throw StateError('Storage unavailable');
    (data[namespace] ??= {})[businessId] = jsonDecode(jsonEncode(value));
  }

  @override
  Future<void> remove(String namespace, String businessId) async {
    data[namespace]?.remove(businessId);
  }
}

Map<String, dynamic> _payload({
  String business = 'business-1',
  double total = 25,
}) => {
  'businessId': business,
  'paymentMethod': 'Efectivo',
  'expectedTotal': total,
  'items': [
    {'productId': 'product-1', 'quantity': 2, 'notes': 'Sin cebolla'},
  ],
};

List<Map<String, dynamic>> _rows({String updated = '2026-10-31T10:00:00Z'}) => [
  {
    'id': 'cart-1',
    'productId': 'product-1',
    'quantity': 2,
    'notes': 'Sin cebolla',
    'updatedAt': updated,
  },
];

Map<String, dynamic> _order({
  String status = 'ready',
  String user = 'student-1',
}) => {
  'id': 'order-1',
  'orderNumber': 17,
  'businessId': 'business-1',
  'userId': user,
  'customerNumeroDeControl': 'PRIVATE-CONTROL',
  'pickupCode': 'Z7K2Q9',
  'status': status,
  'isRated': false,
  'version': 7,
  'total': 25,
  'paymentMethod': 'Efectivo',
  'paymentStatus': 'pay_at_pickup',
  'createdAt': '2026-10-31T10:00:00Z',
  'scheduledPickupTime': null,
  'items': [
    {
      'productId': 'product-1',
      'name': 'Taco',
      'quantity': 2,
      'price': 12.5,
      'notes': 'Sin cebolla',
    },
  ],
};

class _OrdersApi extends StudentApi {
  _OrdersApi(this.order)
    : super(baseUrl: 'http://localhost/api/v1', realtimeEnabled: false);
  Map<String, dynamic> order;
  Map<String, dynamic>? ratingBody;
  int ratingPosts = 0;
  int _testRevision = 0;
  String accountId = 'student-1';

  @override
  int get revision => _testRevision;
  @override
  Map<String, dynamic> get user => {'id': accountId, 'role': 'ALUMNO'};
  @override
  Future<Map<String, dynamic>> getObject(
    String path, {
    Map<String, String>? query,
    bool authenticated = true,
  }) async => Map<String, dynamic>.from(order);
  @override
  Future<dynamic> request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
    Map<String, String>? headers,
    bool authenticated = true,
  }) async {
    if (path.endsWith('/rating')) {
      ratingBody = body;
      ratingPosts++;
      order = {...order, 'isRated': true};
      _testRevision++;
      notifyListeners();
      return {'id': 'rating-1'};
    }
    throw StateError('Unexpected request: $path');
  }

  void changeAccount(String id) {
    accountId = id;
    _testRevision++;
    notifyListeners();
  }
}

class _CartApi extends _OrdersApi {
  _CartApi() : super(_order());
  final List<Map<String, dynamic>> posts = [];
  final List<String> keys = [];
  List<Map<String, dynamic>> cart = [
    {
      ..._rows().first,
      'available': true,
      'product': {
        'id': 'product-1',
        'businessId': 'business-1',
        'name': 'Taco',
        'price': 12.5,
        'stock': 20,
        'isAvailable': true,
      },
    },
    {
      'id': 'cart-2',
      'productId': 'product-2',
      'quantity': 1,
      'notes': '',
      'updatedAt': '2026-10-31T10:00:00Z',
      'available': true,
      'product': {
        'id': 'product-2',
        'businessId': 'business-2',
        'name': 'Agua',
        'price': 10.0,
        'stock': 20,
        'isAvailable': true,
      },
    },
  ];

  @override
  Future<List<Map<String, dynamic>>> getAll(
    String path, {
    Map<String, String>? query,
  }) async {
    if (path == '/users/me/cart/items') {
      return (jsonDecode(jsonEncode(cart)) as List)
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList();
    }
    if (path == '/businesses') {
      return [
        {
          'id': 'business-1',
          'name': 'Tacos',
          'timezone': 'America/Mexico_City',
        },
        {
          'id': 'business-2',
          'name': 'Bebidas',
          'timezone': 'America/Mexico_City',
        },
      ];
    }
    return [];
  }

  @override
  Future<dynamic> request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
    Map<String, String>? headers,
    bool authenticated = true,
  }) async {
    if (method == 'POST' && path == '/orders') {
      posts.add(Map<String, dynamic>.from(body!));
      keys.add(headers!['Idempotency-Key']!);
      if (posts.length == 1) {
        throw const ApiException(
          0,
          'REQUEST_TIMEOUT',
          'No se recibió respuesta',
        );
      }
      return order;
    }
    if (method == 'DELETE' && path.startsWith('/users/me/cart/items/')) {
      cart.removeWhere((row) => path.endsWith('/${row['id']}'));
      return null;
    }
    throw StateError('Unexpected request: $method $path');
  }
}

class _ProfileApi extends _OrdersApi {
  _ProfileApi() : super(_order(status: 'pending'));
  Map<String, dynamic>? cancellation;
  @override
  Future<List<Map<String, dynamic>>> getAll(
    String path, {
    Map<String, String>? query,
  }) async {
    if (path.endsWith('/orders/active')) {
      return cancellation == null ? [order] : [];
    }
    if (path == '/businesses') {
      return [
        {'id': 'business-1', 'name': 'Tacos'},
      ];
    }
    return [];
  }

  @override
  Future<Map<String, dynamic>> getObject(
    String path, {
    Map<String, String>? query,
    bool authenticated = true,
  }) async {
    if (path == '/users/me') {
      return {
        'id': 'student-1',
        'displayName': 'Alumno',
        'email': 'student@example.edu',
        'emailVerified': true,
      };
    }
    if (path.endsWith('/orders/history')) {
      return {
        'data': [],
        'pagination': {'totalPages': 0},
      };
    }
    return super.getObject(path, query: query, authenticated: authenticated);
  }

  @override
  Future<dynamic> request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
    Map<String, String>? headers,
    bool authenticated = true,
  }) async {
    if (path.endsWith('/cancel')) {
      cancellation = body;
      return {...order, 'status': 'cancelled'};
    }
    return super.request(
      method,
      path,
      body: body,
      query: query,
      headers: headers,
      authenticated: authenticated,
    );
  }
}

Widget _host(StudentApi api, Widget child) =>
    ChangeNotifierProvider<StudentApi>.value(
      value: api,
      child: MaterialApp(home: child),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('Safe checkout ledger', () {
    test('two tabs with the same payload and server snapshot derive one UUID', () {
      final first = checkoutKey('origin|student-1', _payload(), _rows());
      final second = checkoutKey('origin|student-1', {
        'items': [
          {'notes': 'Sin cebolla', 'quantity': 2, 'productId': 'product-1'},
        ],
        'expectedTotal': 25.0,
        'paymentMethod': 'Efectivo',
        'businessId': 'business-1',
      }, _rows());
      // Numeric JSON values must use the same canonical type; UI totals are double.
      expect(
        first,
        matches(
          RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-8[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
          ),
        ),
      );
      expect(first, second);
      expect(
        checkoutKey('origin|student-2', _payload(), _rows()),
        isNot(first),
      );
    });

    test('editing or recreating a cart row produces a fresh intent key', () {
      final original = checkoutKey('origin|student-1', _payload(), _rows());
      expect(
        checkoutKey(
          'origin|student-1',
          _payload(),
          _rows(updated: '2026-10-31T10:01:00Z'),
        ),
        isNot(original),
      );
      expect(
        checkoutKey('origin|student-1', _payload(), [
          {..._rows().first, 'id': 'new-cart-row'},
        ]),
        isNot(original),
      );
    });

    test(
      'lost response survives reloading and retries the exact saved payload/key',
      () async {
        final storage = _MemoryStorage();
        final firstTab = CheckoutLedger(
          storage: storage,
          namespace: 'api|student-1',
        );
        final prepared = await firstTab.prepare(
          businessId: 'business-1',
          payload: _payload(),
          rows: _rows(),
        );
        await expectLater(
          firstTab.send(
            prepared,
            (_, _) async =>
                throw const ApiException(0, 'REQUEST_TIMEOUT', 'Timeout'),
          ),
          throwsA(isA<ApiException>()),
        );
        final afterReload = CheckoutLedger(
          storage: storage,
          namespace: 'api|student-1',
        );
        final restored = (await afterReload.intents())['business-1']!;
        expect(restored.key, prepared.key);
        expect(restored.payload, prepared.payload);
        final confirmed = await afterReload.send(restored, (body, key) async {
          expect(key, prepared.key);
          expect(body, _payload());
          return {
            'id': 'created-order',
            'pickupCode': 'MUST-NOT-PERSIST',
            'userId': 'student-1',
          };
        });
        expect(confirmed.orderId, 'created-order');
        expect(jsonEncode(storage.data), isNot(contains('MUST-NOT-PERSIST')));
        var sentAgain = false;
        final sameResult = await afterReload.send(confirmed, (_, _) async {
          sentAgain = true;
          return {'id': 'duplicate'};
        });
        expect(sentAgain, isFalse);
        expect(sameResult.orderId, 'created-order');
      },
    );

    test(
      'an unresolved purchase refuses a changed payload instead of a new UUID',
      () async {
        final ledger = CheckoutLedger(
          storage: _MemoryStorage(),
          namespace: 'api|student-1',
        );
        final old = await ledger.prepare(
          businessId: 'business-1',
          payload: _payload(),
          rows: _rows(),
        );
        await expectLater(
          ledger.prepare(
            businessId: 'business-1',
            payload: _payload(total: 30),
            rows: _rows(),
          ),
          throwsA(isA<CheckoutPendingException>()),
        );
        expect((await ledger.intents())['business-1']!.key, old.key);
      },
    );

    test(
      'cleanup keeps rows changed in quantity, notes or server update timestamp',
      () async {
        final ledger = CheckoutLedger(
          storage: _MemoryStorage(),
          namespace: 'api|student-1',
        );
        final intent = await ledger.prepare(
          businessId: 'business-1',
          payload: _payload(),
          rows: _rows(),
        );
        expect(unchangedPurchasedRows(intent, _rows()), ['cart-1']);
        for (final changed in [
          {..._rows().first, 'quantity': 3},
          {..._rows().first, 'notes': 'Con cebolla'},
          {..._rows().first, 'updatedAt': '2026-10-31T10:02:00Z'},
          {..._rows().first, 'id': 'replacement'},
        ]) {
          expect(unchangedPurchasedRows(intent, [changed]), isEmpty);
        }
      },
    );

    test(
      'confirmed cleanup failure leaves the order reusable without sending POST',
      () async {
        final storage = _MemoryStorage();
        final ledger = CheckoutLedger(
          storage: storage,
          namespace: 'api|student-1',
        );
        final prepared = await ledger.prepare(
          businessId: 'business-1',
          payload: _payload(),
          rows: _rows(),
        );
        final confirmed = await ledger.send(
          prepared,
          (_, _) async => {'id': 'order-1'},
        );
        final restored = (await ledger.intents())['business-1']!;
        expect(restored.confirmed, isTrue);
        expect(restored.orderId, confirmed.orderId);
        await ledger.forget(confirmed);
        expect(await ledger.intents(), isEmpty);
      },
    );

    test('failure to persist prevents starting a purchase', () async {
      final storage = _MemoryStorage()..failWrites = true;
      final ledger = CheckoutLedger(
        storage: storage,
        namespace: 'api|student-1',
      );
      await expectLater(
        ledger.prepare(
          businessId: 'business-1',
          payload: _payload(),
          rows: _rows(),
        ),
        throwsA(isA<StateError>()),
      );
      expect(await ledger.intents(), isEmpty);
    });

    test(
      'different businesses retain independent unresolved purchases',
      () async {
        final storage = _MemoryStorage();
        final one = CheckoutLedger(
          storage: storage,
          namespace: 'api|student-1',
        );
        final two = CheckoutLedger(
          storage: storage,
          namespace: 'api|student-1',
        );
        await Future.wait([
          one.prepare(
            businessId: 'business-1',
            payload: _payload(),
            rows: _rows(),
          ),
          two.prepare(
            businessId: 'business-2',
            payload: _payload(business: 'business-2'),
            rows: [
              {..._rows().first, 'id': 'cart-2'},
            ],
          ),
        ]);
        expect(
          (await one.intents()).keys,
          containsAll(['business-1', 'business-2']),
        );
      },
    );
  });

  testWidgets(
    'accepted orders explain their state and do not expose the pickup secret',
    (tester) async {
      final api = _OrdersApi(_order(status: 'accepted'));
      await tester.pumpWidget(
        _host(api, const ShowQrScreen(orderId: 'order-1')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Aceptado'), findsOneWidget);
      expect(find.text('Z7K2Q9'), findsNothing);
      expect(find.textContaining('PRIVATE-CONTROL'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      api.dispose();
    },
  );

  testWidgets(
    'ready orders show their server pickupCode, never student control number',
    (tester) async {
      final api = _OrdersApi(_order());
      await tester.pumpWidget(
        _host(api, const ShowQrScreen(orderId: 'order-1')),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('pickup-code')), findsOneWidget);
      expect(find.text('Z7K2Q9'), findsOneWidget);
      expect(find.textContaining('PRIVATE-CONTROL'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      api.dispose();
    },
  );

  testWidgets('another account cannot render a pickup code', (tester) async {
    final api = _OrdersApi(_order(user: 'someone-else'));
    await tester.pumpWidget(_host(api, const ShowQrScreen(orderId: 'order-1')));
    await tester.pumpAndSettle();
    expect(find.text('Este pedido no pertenece a tu cuenta.'), findsOneWidget);
    expect(find.byKey(const ValueKey('pickup-code')), findsNothing);
    await tester.pumpWidget(const SizedBox());
    api.dispose();
  });

  testWidgets(
    'account changes hide a previously displayed secret immediately',
    (tester) async {
      final api = _OrdersApi(_order());
      await tester.pumpWidget(
        _host(api, const ShowQrScreen(orderId: 'order-1')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Z7K2Q9'), findsOneWidget);
      api.changeAccount('new-account');
      await tester.pumpAndSettle();
      expect(find.text('Z7K2Q9'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      api.dispose();
    },
  );

  testWidgets('zero stars is an explicit valid completed-order rating', (
    tester,
  ) async {
    final api = _OrdersApi(_order(status: 'completed'));
    await tester.pumpWidget(
      _host(api, const RateOrderScreen(orderId: 'order-1')),
    );
    await tester.pumpAndSettle();
    final button = find.byKey(const ValueKey('submit-rating'));
    expect(tester.widget<FilledButton>(button).onPressed, isNull);
    await tester.tap(find.byKey(const ValueKey('rating-0')));
    await tester.ensureVisible(button);
    await tester.pump();
    expect(tester.widget<FilledButton>(button).onPressed, isNotNull);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(api.ratingPosts, 1);
    expect(api.ratingBody, {'stars': 0, 'comment': ''});
    await tester.pumpWidget(const SizedBox());
    api.dispose();
  });

  testWidgets('pending orders cannot be rated', (tester) async {
    final api = _OrdersApi(_order(status: 'pending'));
    await tester.pumpWidget(
      _host(api, const RateOrderScreen(orderId: 'order-1')),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('submit-rating')), findsNothing);
    expect(api.ratingPosts, 0);
    await tester.pumpWidget(const SizedBox());
    api.dispose();
  });

  testWidgets(
    'a lost checkout response restores the same attempt and only clears its business',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final api = _CartApi();
      await tester.pumpWidget(_host(api, const CartScreen()));
      await tester.pumpAndSettle();
      final review = find.text('Revisar pedido de este negocio').first;
      await tester.ensureVisible(review);
      await tester.tap(review);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Confirmar pedido'));
      await tester.pumpAndSettle();
      expect(api.posts, hasLength(1));
      expect(api.posts.first, _payload());
      expect(api.cart, hasLength(2));
      expect(find.text('Compra pendiente de comprobar'), findsOneWidget);

      // A fresh widget tree models a browser reload: only persisted intent remains.
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(_host(api, const CartScreen()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Comprobar compra'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Comprobar'));
      await tester.pumpAndSettle();
      expect(api.posts, hasLength(2));
      expect(api.posts[1], api.posts[0]);
      expect(api.keys[1], api.keys[0]);
      expect(api.cart.map((row) => row['id']), ['cart-2']);
      expect(find.text('Pedido #17'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      api.dispose();
    },
  );

  testWidgets(
    'student cancellation sends the required reason notes and expectedVersion',
    (tester) async {
      final api = _ProfileApi();
      await tester.pumpWidget(_host(api, const ProfileOrdersScreen()));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('order-summary-order-1')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Cancelar'));
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Ya no podré recoger');
      await tester.pump();
      await tester.tap(find.text('Cancelar pedido'));
      await tester.pumpAndSettle();
      expect(api.cancellation, {
        'reason': 'user_other',
        'notes': 'Ya no podré recoger',
        'expectedVersion': 7,
      });
      await tester.pumpWidget(const SizedBox());
      api.dispose();
    },
  );
}
