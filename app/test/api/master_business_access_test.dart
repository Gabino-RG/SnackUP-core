import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:snackup/api/rest_session.dart';
import 'package:snackup/features/portal/rest_portal_app.dart';
import 'package:snackup/features/operations/business_portal.dart';

void main() {
  for (final master in [true, false]) {
    testWidgets(
      master
          ? 'master opens and returns from a local on mobile without changing identity; revocation removes it'
          : 'ordinary administrator has no local operation entry',
      (tester) async {
        tester.view.physicalSize = const Size(360, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final localRequests = <String>[];
        final local = {
          'id': 'local-1',
          'name': 'Local propio',
          'isActive': true,
          'isOpen': false,
          'version': 1,
        };
        final session = RestSession(
          baseUri: Uri.parse('https://snackup.example/api/v1/'),
          client: MockClient((r) async {
            Object data;
            final path = r.url.path;
            if (path.endsWith('/auth/options')) {
              data = {
                'passwordLogin': true,
                'selfRegistration': true,
                'googleEnabled': false,
              };
            } else if (path.endsWith('/auth/refresh')) {
              data = {
                'tokens': {
                  'accessToken': 'admin-token',
                  'accessTokenExpiresAt': DateTime.now()
                      .toUtc()
                      .add(const Duration(minutes: 15))
                      .toIso8601String(),
                },
              };
            } else if (path.endsWith('/users/me')) {
              data = {
                'id': 'master',
                'role': 'admin',
                'displayName': 'Cuenta maestra',
                'isMaster': master,
              };
            } else {
              expect(r.headers['Authorization'], 'Bearer admin-token');
              expect(
                r.method,
                'GET',
                reason:
                    'Opening a panel must not create an account or modify the local',
              );
              if (path.contains('/businesses/local-1')) localRequests.add(path);
              if (path.endsWith('/institution')) {
                data = {
                  'university': {'name': 'UTSJR'},
                  'cafeteria': {'id': 'caf', 'name': 'Cafetería universitaria'},
                  'adminEmailDomains': ['utsjr.edu.mx'],
                };
              } else if (path.endsWith('/businesses/local-1')) {
                data = local;
              } else {
                final rows = path.endsWith('/admin/businesses')
                    ? [
                        local,
                        {
                          ...local,
                          'id': 'closed',
                          'name': 'Local inactivo',
                          'isActive': false,
                        },
                      ]
                    : [];
                data = {
                  'data': rows,
                  'pagination': {
                    'page': 1,
                    'totalPages': rows.isEmpty ? 0 : 1,
                    'total': rows.length,
                  },
                };
              }
            }
            return http.Response(
              jsonEncode(data),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }),
        );
        addTearDown(session.dispose);
        await tester.pumpWidget(RestPortalApp(session: session));
        await tester.pumpAndSettle();
        final entry = find.text('Entrar al panel del local');
        if (!master) {
          expect(entry, findsNothing);
        } else {
          await tester.ensureVisible(entry);
          await tester.tap(entry);
          await tester.pumpAndSettle();
          final inactive = find.widgetWithText(
            FilledButton,
            'Entrar a Local inactivo',
          );
          expect(tester.widget<FilledButton>(inactive).onPressed, isNull);
          await tester.tap(find.text('Entrar a Local propio'));
          await tester.pumpAndSettle();
          expect(find.byType(BusinessPortal), findsOneWidget);
          expect(
            localRequests,
            contains('/api/v1/businesses/local-1/orders/active'),
          );
          expect(session.account!.role, 'admin');
          expect(session.account!.businessId, isNull);
          await tester.tap(find.byTooltip('Volver a Administración'));
          await tester.pumpAndSettle();
          expect(find.byType(BusinessPortal), findsNothing);
          await tester.ensureVisible(entry);
          await tester.tap(entry);
          await tester.pumpAndSettle();
          await tester.tap(find.text('Entrar a Local propio'));
          await tester.pumpAndSettle();
          session.invalidate('Acceso revocado.');
          await tester.pumpAndSettle();
          expect(find.byType(BusinessPortal), findsNothing);
          expect(find.byKey(const ValueKey('portal-login')), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
