import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:snackup/api/rest_session.dart';
import 'package:snackup/features/admin/admin_dashboard_screen.dart';
import 'package:snackup/features/operations/business_portal.dart';
import 'package:snackup/features/portal/rest_portal_app.dart';

void main() {
  for (final profile in ['master', 'admin', 'business']) {
    testWidgets('$profile stays in its own panel and API scope on mobile', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final business = profile == 'business';
      final requests = <String>[];
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
                'accessToken': '$profile-token',
                'accessTokenExpiresAt': DateTime.now()
                    .toUtc()
                    .add(const Duration(minutes: 15))
                    .toIso8601String(),
              },
            };
          } else if (path.endsWith('/users/me')) {
            data = {
              'id': profile,
              'role': business ? 'business' : 'admin',
              'displayName': profile,
              'isMaster': profile == 'master',
              if (business) 'businessId': 'local-1',
            };
          } else {
            requests.add(path);
            expect(r.headers['Authorization'], 'Bearer $profile-token');
            expect(r.method, 'GET');
            if (path.endsWith('/institution')) {
              data = {
                'university': {'name': 'UTSJR'},
                'cafeteria': {'id': 'caf', 'name': 'Cafetería universitaria'},
                'adminEmailDomains': ['utsjr.edu.mx'],
              };
            } else if (path.endsWith('/businesses/local-1')) {
              data = local;
            } else {
              final rows = path.endsWith('/admin/businesses') ? [local] : [];
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
      expect(
        find.byType(BusinessPortal),
        business ? findsOneWidget : findsNothing,
      );
      expect(
        find.byType(AdminDashboardScreen),
        business ? findsNothing : findsOneWidget,
      );
      expect(find.text('Entrar al panel del local'), findsNothing);
      expect(find.byTooltip('Volver a Administración'), findsNothing);
      if (business) {
        expect(find.text('Cocina'), findsOneWidget);
        expect(find.text('Productos'), findsOneWidget);
        expect(find.text('Gestionar locales y cuentas'), findsNothing);
        expect(find.text('Crear cuenta'), findsNothing);
        expect(find.text('Solicitudes de acceso'), findsNothing);
        expect(requests, contains('/api/v1/businesses/local-1/orders/active'));
        expect(requests.where((path) => path.contains('/admin/')), isEmpty);
      } else {
        expect(find.text('Cocina'), findsNothing);
        expect(find.text('Productos'), findsNothing);
        expect(requests, contains('/api/v1/admin/businesses'));
        expect(
          requests.where(
            (path) =>
                path != '/api/v1/institution' &&
                !path.startsWith('/api/v1/admin/'),
          ),
          isEmpty,
        );
      }
      session.invalidate('Acceso revocado.');
      await tester.pumpAndSettle();
      expect(find.byType(BusinessPortal), findsNothing);
      expect(find.byType(AdminDashboardScreen), findsNothing);
      expect(find.byKey(const ValueKey('portal-login')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
