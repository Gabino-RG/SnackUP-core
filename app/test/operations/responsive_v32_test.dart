import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snackup/features/operations/v32_screens.dart';
import 'v32_features_test.dart' show FakeV32;

class ResponsiveRepository extends FakeV32 {
  @override
  Future<Map<String, dynamic>> orders(
    String businessId, {
    String? date,
    int page = 1,
  }) async => {
    'data': [],
    'pagination': {'totalPages': 0},
  };
  @override
  Future<Map<String, dynamic>> stats(
    String businessId,
    String from,
    String to,
  ) async => {
    'completed': 25,
    'cancelled': 2,
    'totalSold': 12345.50,
    'paymentMethods': [
      {'paymentMethod': 'ValeComida', 'completed': 25, 'totalSold': 12345.50},
    ],
    'topProducts': [
      {
        'name': 'Torta especial con nombre largo de producto',
        'quantity': 25,
        'totalSold': 12345.50,
      },
    ],
    'daily': [
      {
        'date': '2026-10-26',
        'completed': 25,
        'cancelled': 2,
        'totalSold': 12345.50,
      },
    ],
  };
}

void main() {
  for (final size in [
    const Size(320, 640),
    const Size(390, 844),
    const Size(844, 390),
    const Size(768, 1024),
    const Size(1440, 900),
  ]) {
    for (final scale in [1.0, 1.5]) {
      testWidgets('V3.2 views fit $size at text scale $scale', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final repo = ResponsiveRepository();
        final views = <Widget>[
          KitchenChatScreen(repository: repo, businessId: 'b', orderId: 'o'),
          ClosingScreen(repository: repo, businessId: 'b'),
          ClosingScreen(repository: repo, businessId: 'b', readOnly: true),
          SpecialOrdersScreen(repository: repo, businessId: 'b'),
          DetailedStatsScreen(repository: repo, businessId: 'b'),
        ];
        for (final view in views) {
          await tester.pumpWidget(
            MaterialApp(
              home: MediaQuery(
                data: MediaQueryData(
                  size: size,
                  textScaler: TextScaler.linear(scale),
                ),
                child: Scaffold(
                  appBar: AppBar(title: const Text('SnackUP')),
                  body: view,
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(
            tester.takeException(),
            isNull,
            reason: view.runtimeType.toString(),
          );
          await tester.pumpWidget(const SizedBox());
        }
      });
    }
  }
  testWidgets('chat composer remains reachable with mobile keyboard open', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = const FakeViewPadding(bottom: 320);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: AppBar(title: const Text('Conversación')),
          body: KitchenChatScreen(
            repository: ResponsiveRepository(),
            businessId: 'b',
            orderId: 'o',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.byType(TextField));
    await tester.enterText(find.byType(TextField), 'Mensaje desde móvil');
    await tester.ensureVisible(find.text('Enviar mensaje'));
    await tester.pumpAndSettle();
    expect(find.text('Enviar mensaje').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
