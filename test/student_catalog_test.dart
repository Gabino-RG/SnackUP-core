import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:snackup/features/user/product_detail_screen.dart';
import 'package:snackup/features/user/menu_screen.dart';
import 'package:snackup/features/user/search_screen.dart';
import 'package:snackup/student/student_api.dart';

class CatalogApi extends StudentApi {
  CatalogApi()
    : super(baseUrl: 'http://localhost/api/v1', realtimeEnabled: false);

  Map<String, dynamic> product = {
    'id': 'product-1',
    'businessId': 'business-1',
    'name': 'Torta',
    'description': 'Preparada al momento',
    'category': 'Comida',
    'price': 35.0,
    'stock': null,
    'imageUrl': null,
    'isAvailable': true,
    'isFeatured': false,
    'totalReviews': 0,
  };
  Map<String, dynamic> business = {
    'id': 'business-1',
    'name': 'Cafetería',
    'isOpen': true,
    'isActive': true,
  };
  final searches = <String, Completer<List<Map<String, dynamic>>>>{};
  final writes = <Map<String, dynamic>>[];
  final cart = <Map<String, dynamic>>[];
  List<Map<String, dynamic>>? menuProducts;

  @override
  Future<Map<String, dynamic>> getObject(
    String path, {
    Map<String, String>? query,
    bool authenticated = true,
  }) async {
    if (path.startsWith('/products/')) return {...product};
    if (path.startsWith('/businesses/')) return {...business};
    throw StateError('Unexpected $path');
  }

  @override
  Future<List<Map<String, dynamic>>> getAll(
    String path, {
    Map<String, String>? query,
  }) async {
    if (path == '/products/search') {
      return searches.putIfAbsent(query!['q']!, Completer.new).future;
    }
    if (path == '/users/me/favorites') return [];
    if (path == '/users/me/cart/items') return [...cart];
    if (path == '/businesses/business-1/products') {
      return menuProducts ??
          [
            {...product},
          ];
    }
    throw StateError('Unexpected $path');
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
    writes.add({'method': method, 'path': path, 'body': body});
    return {
      'id': 'saved-1',
      'productId': body?['productId'] ?? product['id'],
      'product': product,
      'quantity': body?['quantity'] ?? 1,
      'notes': body?['notes'] ?? '',
      'available': true,
    };
  }

  @override
  String mediaUrl(Object? value) => '';
}

Widget app(CatalogApi api, Widget screen) =>
    ChangeNotifierProvider<StudentApi>.value(
      value: api,
      child: MaterialApp(home: screen),
    );

void main() {
  testWidgets(
    'menu hides zero stock and unavailable products while retaining unlimited stock',
    (tester) async {
      final api = CatalogApi();
      addTearDown(api.dispose);
      api.menuProducts = [
        {...api.product, 'name': 'Sin límite', 'stock': null},
        {...api.product, 'id': 'zero', 'name': 'Agotado', 'stock': 0},
        {
          ...api.product,
          'id': 'disabled',
          'name': 'Retirado',
          'stock': 5,
          'isAvailable': false,
        },
      ];
      await tester.pumpWidget(
        app(
          api,
          const MenuScreen(businessId: 'business-1', businessName: 'Cafetería'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Sin límite'), findsOneWidget);
      expect(find.text('Agotado'), findsNothing);
      expect(find.text('Retirado'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('search ignores an older result and clears immediately', (
    tester,
  ) async {
    final api = CatalogApi();
    addTearDown(api.dispose);
    await tester.pumpWidget(app(api, const SearchScreen()));
    await tester.enterText(find.byType(TextField), 'torta');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.enterText(find.byType(TextField), 'agua');
    await tester.pump(const Duration(milliseconds: 400));
    api.searches['agua']!.complete([
      {...api.product, 'id': 'water', 'name': 'Agua fresca'},
    ]);
    await tester.pumpAndSettle();
    expect(find.text('Agua fresca'), findsOneWidget);
    api.searches['torta']!.complete([
      {...api.product, 'name': 'Resultado antiguo'},
    ]);
    await tester.pumpAndSettle();
    expect(find.text('Resultado antiguo'), findsNothing);
    expect(find.text('Agua fresca'), findsOneWidget);
    await tester.tap(find.byTooltip('Limpiar búsqueda'));
    await tester.pumpAndSettle();
    expect(find.text('Agua fresca'), findsNothing);
    expect(find.text('Tu siguiente favorito está aquí'), findsOneWidget);
  });

  testWidgets(
    'null stock permits cart save with IDs, quantity and notes only',
    (tester) async {
      final api = CatalogApi();
      addTearDown(api.dispose);
      await tester.pumpWidget(
        app(api, const ProductDetailScreen(productId: 'product-1')),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byType(TextField));
      await tester.enterText(find.byType(TextField), 'Sin cebolla');
      await tester.ensureVisible(find.byTooltip('Aumentar cantidad'));
      await tester.tap(find.byTooltip('Aumentar cantidad'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Añadir al carrito'));
      await tester.pumpAndSettle();
      expect(api.writes, hasLength(1));
      expect(api.writes.single['path'], '/users/me/cart/items');
      expect(api.writes.single['body'], {
        'productId': 'product-1',
        'quantity': 2,
        'notes': 'Sin cebolla',
      });
    },
  );

  testWidgets('cart save stops when the current price changes', (tester) async {
    final api = CatalogApi();
    addTearDown(api.dispose);
    await tester.pumpWidget(
      app(api, const ProductDetailScreen(productId: 'product-1')),
    );
    await tester.pumpAndSettle();
    api.product['price'] = 40.0;
    await tester.tap(find.textContaining('Añadir al carrito'));
    await tester.pumpAndSettle();
    expect(api.writes, isEmpty);
    expect(
      find.text('El precio cambió. Revisa el total y vuelve a guardar.'),
      findsOneWidget,
    );
    expect(find.textContaining('40.00'), findsWidgets);
  });

  testWidgets('existing cart entry requires confirmation before replacement', (
    tester,
  ) async {
    final api = CatalogApi();
    api.cart.add({
      'id': 'cart-1',
      'productId': 'product-1',
      'quantity': 3,
      'notes': 'Salsa aparte',
    });
    addTearDown(api.dispose);
    await tester.pumpWidget(
      app(api, const ProductDetailScreen(productId: 'product-1')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Actualizar carrito'));
    // The disabled save button keeps a progress indicator behind the dialog.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Actualizar producto en el carrito'), findsOneWidget);
    expect(api.writes, isEmpty);
    await tester.tap(find.text('Volver'));
    await tester.pumpAndSettle();
    expect(api.writes, isEmpty);
    await tester.tap(find.textContaining('Actualizar carrito'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Guardar cambios'));
    await tester.pumpAndSettle();
    expect(api.writes.single['body'], {
      'productId': 'product-1',
      'quantity': 3,
      'notes': 'Salsa aparte',
    });
  });

  testWidgets('favorite uses canonical product ID and saves its notes', (
    tester,
  ) async {
    final api = CatalogApi();
    addTearDown(api.dispose);
    await tester.pumpWidget(
      app(api, const ProductDetailScreen(productId: 'product-1')),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byType(TextField));
    await tester.enterText(find.byType(TextField), 'Sin chile');
    await tester.tap(find.byTooltip('Guardar favorito'));
    await tester.pumpAndSettle();
    expect(api.writes.single, {
      'method': 'PUT',
      'path': '/users/me/favorites/product-1',
      'body': {'notes': 'Sin chile'},
    });
    expect(find.byTooltip('Quitar favorito'), findsOneWidget);
  });

  testWidgets(
    'a closed business disables cart even when product is available',
    (tester) async {
      final api = CatalogApi();
      api.business['isOpen'] = false;
      addTearDown(api.dispose);
      await tester.pumpWidget(
        app(api, const ProductDetailScreen(productId: 'product-1')),
      );
      await tester.pumpAndSettle();
      final button = tester.widget<FilledButton>(
        find.widgetWithText(
          FilledButton,
          'Producto no disponible para ordenar',
        ),
      );
      expect(button.onPressed, isNull);
      expect(find.text('Local cerrado'), findsOneWidget);
      expect(api.writes, isEmpty);
    },
  );
}
