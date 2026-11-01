import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:snackup/student/product_reviews.dart';
import 'package:snackup/student/student_api.dart';

class ReviewApi extends StudentApi {
  ReviewApi() : super(realtimeEnabled: false);
  String account = 'student';
  String owner = 'student';
  String status = 'completed';
  bool duplicate = false;
  int _version = 0;
  final posts = <Map<String, dynamic>>[];
  final pages = <String>[];
  @override
  Map<String, dynamic> get user => {'id': account, 'role': 'ALUMNO'};
  @override
  int get revision => _version;
  void switchAccount() {
    account = 'another';
    _version++;
    notifyListeners();
  }

  @override
  Future<Map<String, dynamic>> getObject(
    String path, {
    Map<String, String>? query,
    bool authenticated = true,
  }) async {
    if (path.startsWith('/orders/')) {
      return {
        'id': 'order',
        'userId': owner,
        'status': status,
        'orderNumber': 9,
        'isRated': true,
        'items': [
          {'productId': 'food', 'name': 'Taco'},
          {'productId': 'food', 'name': 'Taco'},
        ],
      };
    }
    if (path == '/products/food/reviews') {
      pages.add(query!['page']!);
      return {
        'data': [
          {
            'id': 'review',
            'rating': 4,
            'comment': 'Opinión página ${query['page']}',
            'createdAt': '2026-10-31T10:00:00Z',
          },
        ],
        'pagination': {'page': int.parse(query['page']!), 'totalPages': 2},
      };
    }
    throw StateError(path);
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
    posts.add({'method': method, 'path': path, 'body': body});
    if (duplicate) throw const ApiException(409, 'REVIEW_EXISTS', 'Ya existe.');
    return {
      'data': [
        {'id': 'review'},
      ],
    };
  }
}

void main() {
  Future<void> open(WidgetTester tester, ReviewApi api, Widget screen) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      api.dispose();
    });
    await tester.pumpWidget(
      ChangeNotifierProvider<StudentApi>.value(
        value: api,
        child: MaterialApp(home: screen),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> choose(WidgetTester tester) async {
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Taco').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('product-rating-0')));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'review sends purchased product and zero score without author or business rating fields',
    (tester) async {
      final api = ReviewApi();
      await open(tester, api, const RateProductScreen(orderId: 'order'));
      final submit = find.byKey(const ValueKey('submit-product-review'));
      expect(tester.widget<FilledButton>(submit).onPressed, isNull);
      await choose(tester);
      await tester.enterText(find.byType(TextField), 'Muy rico');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tester.ensureVisible(submit);
      await tester.tap(submit);
      await tester.pumpAndSettle();
      expect(api.posts, [
        {
          'method': 'POST',
          'path': '/orders/order/reviews',
          'body': {
            'reviews': [
              {'productId': 'food', 'rating': 0, 'comment': 'Muy rico'},
            ],
          },
        },
      ]);
      expect(find.byType(DropdownButtonFormField<String>), findsNothing);
      expect(find.textContaining('quedó guardada'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'pending and foreign orders never expose the product rating form',
    (tester) async {
      final api = ReviewApi()..status = 'pending';
      await open(tester, api, const RateProductScreen(orderId: 'order'));
      expect(find.byType(DropdownButtonFormField<String>), findsNothing);
      expect(api.posts, isEmpty);
      api.status = 'completed';
      api.owner = 'other';
      api.switchAccount();
      await tester.pumpAndSettle();
      expect(find.byType(DropdownButtonFormField<String>), findsNothing);
      expect(api.posts, isEmpty);
    },
  );

  testWidgets(
    'duplicate review is reconciled without enabling another submission',
    (tester) async {
      final api = ReviewApi()..duplicate = true;
      await open(tester, api, const RateProductScreen(orderId: 'order'));
      await choose(tester);
      final submit = find.byKey(const ValueKey('submit-product-review'));
      await tester.ensureVisible(submit);
      await tester.tap(submit);
      await tester.pumpAndSettle();
      expect(api.posts, hasLength(1));
      expect(find.textContaining('ya tenía una reseña tuya'), findsOneWidget);
      expect(find.byKey(const ValueKey('submit-product-review')), findsNothing);
    },
  );

  testWidgets('account switch removes the previous order rating controls', (
    tester,
  ) async {
    final api = ReviewApi();
    await open(tester, api, const RateProductScreen(orderId: 'order'));
    await choose(tester);
    api.switchAccount();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('submit-product-review')), findsNothing);
    expect(find.textContaining('Tu sesión cambió'), findsOneWidget);
    expect(api.posts, isEmpty);
  });

  testWidgets('public product reviews page through API and render comments', (
    tester,
  ) async {
    final api = ReviewApi();
    await open(
      tester,
      api,
      const Scaffold(body: PublicProductReviews(productId: 'food')),
    );
    expect(find.text('Opinión página 1'), findsOneWidget);
    await tester.tap(find.text('Siguientes'));
    await tester.pumpAndSettle();
    expect(find.text('Opinión página 2'), findsOneWidget);
    expect(find.text('Opinión página 1'), findsNothing);
    expect(api.pages, ['1', '2']);
  });
}
