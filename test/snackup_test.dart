import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:snackup/features/user/product_detail_screen.dart';
import 'package:snackup/features/user/cart_screen.dart';

void main() {
  late FakeFirebaseFirestore db;
  late MockFirebaseAuth auth;

  setUp(() {
    db = FakeFirebaseFirestore();
    auth = MockFirebaseAuth(
      signedIn: true,
      mockUser: MockUser(uid: 'alumno_prueba'),
    );
  });

  Future<void> openDetail(WidgetTester tester, double price) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      home: ProductDetailScreen(
        productId: 'producto_1',
        product: {'name': 'Sandwich', 'price': price, 'stock': 10,
          'businessId': 'tienda_A'},
        auth: auth,
        firestore: db,
      ),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> seedCart({required bool mixed}) async {
    await db.collection('users').doc('alumno_prueba').set({
      'displayName': 'Alumno Prueba', 'numeroDeControl': '1234',
    });
    final cart = db.collection('users').doc('alumno_prueba').collection('cart');
    await cart.doc('p1').set({
      'productId': 'p1', 'name': 'Sandwich', 'businessId': 'tienda_A',
      'price': 25.0, 'quantity': 2,
    });
    await cart.doc('p2').set({
      'productId': 'p2', 'name': 'Agua',
      'businessId': mixed ? 'tienda_B' : 'tienda_A',
      'price': 15.0, 'quantity': 1,
    });
  }

  Future<void> openCart(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      home: CartScreen(auth: auth, firestore: db),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('CP-01: aumentar cantidad de 1 a 2', (tester) async {
    // ARRANGE: producto disponible a 25 pesos.
    await openDetail(tester, 25.0);
    // ACT: aumentar una unidad.
    await tester.tap(find.byIcon(Icons.add_rounded));
    await tester.pump();
    // ASSERT: cantidad y total visibles correctos.
    expect(find.text('2'), findsOneWidget);
    expect(find.text('Añadir 2 al Carrito - \$50.00'), findsOneWidget);
  });

  testWidgets('CP-02: la cantidad no baja de uno', (tester) async {
    // ARRANGE: cantidad inicial de una unidad.
    await openDetail(tester, 25.0);
    // ACT: intentar disminuir dos veces.
    await tester.tap(find.byIcon(Icons.remove_rounded));
    await tester.tap(find.byIcon(Icons.remove_rounded));
    await tester.pump();
    // ASSERT: se conserva la cantidad minima y el total.
    expect(find.text('1'), findsOneWidget);
    expect(find.text('Añadir 1 al Carrito - \$25.00'), findsOneWidget);
  });

  testWidgets('CP-03: total con precio decimal', (tester) async {
    // ARRANGE: producto con precio 18.50.
    await openDetail(tester, 18.5);
    // ACT: seleccionar tres unidades.
    await tester.tap(find.byIcon(Icons.add_rounded));
    await tester.tap(find.byIcon(Icons.add_rounded));
    await tester.pump();
    // ASSERT: total 55.50 con dos decimales.
    expect(find.text('Añadir 3 al Carrito - \$55.50'), findsOneWidget);
  });

  testWidgets('CP-04: rechazar productos de varias tiendas', (tester) async {
    // ARRANGE: usuario con productos de dos tiendas.
    await seedCart(mixed: true);
    await openCart(tester);
    // ACT: intentar confirmar el pedido.
    await tester.tap(find.text('Confirmar Pedido'));
    await tester.pumpAndSettle();
    // ASSERT: mensaje de rechazo, sin pedidos y carrito intacto.
    expect(find.text('Tu carrito tiene productos de varias tiendas. Por favor, haz pedidos separados.'), findsOneWidget);
    expect((await db.collection('orders').get()).docs, isEmpty);
    expect((await db.collection('users').doc('alumno_prueba')
        .collection('cart').get()).docs, hasLength(2));
  });

  testWidgets('CP-05: crear pedido y vaciar carrito', (tester) async {
    // ARRANGE: perfil y productos de una misma tienda; total 65 pesos.
    await seedCart(mixed: false);
    await openCart(tester);
    // ACT: confirmar el pedido con pago predeterminado.
    await tester.tap(find.text('Confirmar Pedido'));
    await tester.pumpAndSettle();
    // ASSERT: pedido persistido correctamente y carrito vacio.
    final orders = await db.collection('orders').get();
    expect(orders.docs, hasLength(1));
    final order = orders.docs.single.data();
    expect(order['businessId'], 'tienda_A');
    expect(order['userId'], 'alumno_prueba');
    expect(order['status'], 'pending');
    expect(order['totalPrice'], 65.0);
    expect(order['paymentMethod'], 'Efectivo');
    expect(order['scheduledPickupTime'], isNull);
    expect(order['items'], hasLength(2));
    final items = order['items'] as List;
    expect(items.singleWhere((item) => item['productId'] == 'p1')['quantity'], 2);
    expect(items.singleWhere((item) => item['productId'] == 'p2')['quantity'], 1);
    expect((await db.collection('users').doc('alumno_prueba')
        .collection('cart').get()).docs, isEmpty);
    expect(find.text('¡Pedido realizado con éxito!'), findsOneWidget);
  });
}

