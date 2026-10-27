import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:http/http.dart' as http;
import 'package:snackup/api/api_client.dart';
import 'package:snackup/catalog/local_catalog_repository.dart';
import 'package:snackup/features/operations/business_portal.dart';
import 'package:snackup/operations/operations_repository.dart';
import 'operations_repository_test.dart' show orderData;
import 'v32_features_test.dart' show FakeV32;

void main() {
  testWidgets(
    'uncertain delivery and failed reconciliation cannot be submitted again',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 1050);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var offline = false, sends = 0;
      final api = ApiClient(
        baseUri: Uri.parse('https://test.example/api/v1/'),
        client: MockClient((r) async {
          if (r.url.path.endsWith('/complete')) {
            sends++;
            offline = true;
          }
          if (offline)
            throw http.ClientException('connection lost after commit');
          return http.Response(
            jsonEncode(
              r.url.path.endsWith('/businesses/b1')
                  ? {'id': 'b1', 'name': 'Local', 'isOpen': true, 'version': 1}
                  : {
                      'data': [orderData(status: 'ready')],
                    },
            ),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: BusinessPortal(
            businessId: 'b1',
            catalog: LocalCatalogRepository(MemoryCatalogStore()),
            repository: OperationsRepository(api),
            token: () async => 'token',
            onSignOut: () {},
            enableRealtime: false,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Verificar entrega'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('delivery-code')),
        'A9K3F1',
      );
      await tester.tap(find.text('Confirmar entrega'));
      await tester.pumpAndSettle();
      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Confirmar entrega'),
      );
      expect(
        button.onPressed,
        isNull,
        reason: 'An uncertain result must require returning to the board',
      );
      expect(sends, 1);
      await tester.pumpWidget(const SizedBox());
    },
  );
  for (final width in [320.0, 768.0, 1440.0]) {
    testWidgets(
      'peak kitchen fits ${width.toInt()}px and builds visible cards lazily',
      (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final api = ApiClient(
          baseUri: Uri.parse('https://test.example/api/v1/'),
          client: MockClient(
            (r) async => http.Response(
              jsonEncode(
                r.url.path.endsWith('/businesses/b1')
                    ? {
                        'id': 'b1',
                        'name': 'Local del equipo',
                        'isOpen': true,
                        'version': 1,
                      }
                    : {
                        'data': List.generate(
                          180,
                          (i) => {
                            ...orderData(status: 'pending'),
                            'id': 'p$i',
                            'orderNumber': 1000 + i,
                          },
                        ),
                      },
              ),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            ),
          ),
        );
        await tester.pumpWidget(
          MaterialApp(
            home: BusinessPortal(
              businessId: 'b1',
              catalog: LocalCatalogRepository(MemoryCatalogStore()),
              repository: OperationsRepository(api),
              token: () async => 'a',
              onSignOut: () {},
              enableRealtime: false,
              v32: FakeV32(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('Aceptar pedido').evaluate().length, greaterThan(0));
        expect(
          find.text('Aceptar pedido').evaluate().length,
          lessThan(25),
          reason: 'Do not build all 180 cards',
        );
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  testWidgets(
    'mobile kitchen completes a verified delivery and navigates the integrated catalog',
    (tester) async {
      tester.view.physicalSize = const Size(390, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var delivered = false;
      var attempts = 0;
      final api = ApiClient(
        baseUri: Uri.parse('https://test.example/api/v1/'),
        client: MockClient((request) async {
          Object d;
          if (request.url.path.endsWith('/businesses/b1')) {
            d = {'id': 'b1', 'name': 'Central', 'isOpen': true, 'version': 1};
          } else if (request.url.path.endsWith('/complete')) {
            attempts++;
            expect(jsonDecode(request.body)['code'], 'A9K3F1');
            delivered = true;
            d = orderData(status: 'completed', version: 2);
          } else {
            d = {
              'data': delivered ? [] : [orderData(status: 'ready')],
            };
          }
          return http.Response(
            jsonEncode(d),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: BusinessPortal(
            businessId: 'b1',
            catalog: LocalCatalogRepository(MemoryCatalogStore()),
            repository: OperationsRepository(api),
            token: () async => 'a',
            onSignOut: () {},
            enableRealtime: false,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'initial mobile board');
      await tester.tap(find.text('Listos (1)'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'ready column');
      await tester.tap(find.text('Verificar entrega'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirmar entrega'));
      await tester.pumpAndSettle();
      expect(attempts, 0);
      await tester.enterText(
        find.byKey(const ValueKey('delivery-code')),
        'A9K3F1',
      );
      await tester.tap(find.text('Confirmar entrega'));
      await tester.pumpAndSettle();
      expect(delivered, true);
      expect(find.text('Pedido #101'), findsNothing);
      await tester.tap(find.text('Productos'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
