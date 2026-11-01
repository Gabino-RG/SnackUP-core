import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:snackup/main.dart';
import 'package:snackup/student/student_api.dart';

class _DesignApi extends StudentApi {
  List<Map<String, dynamic>> activeOrders = [];
  _DesignApi()
    : super(
        client: MockClient((_) async => http.Response('{}', 200)),
        realtimeEnabled: false,
      );
  @override
  Map<String, dynamic> get user => {
    'id': 'design-student',
    'displayName': 'Alumno de prueba',
    'email': 'design@example.edu',
    'role': 'ALUMNO',
    'numeroDeControl': 'DEMO-001',
    'emailVerified': true,
  };
  @override
  bool get signedIn => true;
  @override
  bool get restoring => false;
  @override
  Future<void> restore() async {}
  @override
  Future<List<Map<String, dynamic>>> getAll(
    String path, {
    Map<String, String>? query,
  }) async => path == '/users/me/orders/active' ? activeOrders : [];
  @override
  Future<Map<String, dynamic>> getObject(
    String path, {
    Map<String, String>? query,
    bool authenticated = true,
  }) async => path == '/users/me'
      ? user
      : {
          'data': <Map<String, dynamic>>[],
          'pagination': {'totalPages': 0},
        };
}

void main() {
  testWidgets(
    'desktop orders retain three reference tabs and aggregate the actual order quantities',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(1291, 536);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = _DesignApi()
        ..activeOrders = [
          {
            'id': 'design-order',
            'orderNumber': 1,
            'userId': 'design-student',
            'businessId': 'cafe',
            'status': 'pending',
            'total': 175,
            'items': [
              {'productId': 'taco', 'name': 'Tacos al Pastor', 'quantity': 2},
              {'productId': 'water', 'name': 'Agua de Horchata', 'quantity': 3},
            ],
          },
        ];
      await tester.pumpWidget(SnackUpApp(api: api));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pedidos'));
      await tester.pumpAndSettle();
      expect(find.text('Mis pedidos'), findsOneWidget);
      expect(find.text('CAMPUS DINING'), findsOneWidget);
      expect(find.text('Activos'), findsOneWidget);
      expect(find.text('Historial'), findsOneWidget);
      expect(find.text('Favoritos'), findsOneWidget);
      expect(find.text('Resumen del Pedido'), findsOneWidget);
      expect(
        find.text('2x Tacos al Pastor, 3x Agua de Horchata'),
        findsOneWidget,
      );
      expect(find.text('5 productos en total'), findsOneWidget);
      expect(find.text('\$175.00'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(
        find.byKey(const ValueKey('order-summary-design-order')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Ver pedido'), findsOneWidget);
      expect(find.text('Cancelar'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'mobile student navigation exposes orders favorites profile and cart',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(SnackUpApp(api: _DesignApi()));
      await tester.pumpAndSettle();
      expect(find.text('Inicio'), findsOneWidget);
      expect(find.text('Pedidos'), findsOneWidget);
      expect(find.text('Favoritos'), findsOneWidget);
      expect(find.text('Perfil'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Favoritos'));
      await tester.pumpAndSettle();
      expect(find.text('Mis favoritos'), findsOneWidget);
      await tester.tap(find.text('Perfil'));
      await tester.pumpAndSettle();
      expect(find.text('Mi perfil'), findsOneWidget);
      expect(find.textContaining('DEMO-001'), findsOneWidget);
      await tester.tap(find.text('Pedidos'));
      await tester.pumpAndSettle();
      expect(find.text('Activos'), findsOneWidget);
      expect(find.text('Historial'), findsOneWidget);
      await tester.tap(find.byTooltip('Mi carrito'));
      await tester.pumpAndSettle();
      expect(find.text('Mi carrito'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
