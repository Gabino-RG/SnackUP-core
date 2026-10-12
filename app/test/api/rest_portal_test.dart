import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:snackup/api/rest_session.dart';
import 'package:snackup/features/portal/rest_portal_app.dart';
import 'package:snackup/features/admin/admin_dashboard_screen.dart';
import 'package:snackup/features/catalog/catalog_screen.dart';

void main() {
  testWidgets('mobile login blocks duplicate submits and uses the assigned business', (tester) async {
    tester.view.physicalSize = const Size(360, 800); tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio);
    final login = Completer<http.Response>();
    var logins = 0;
    final session = RestSession(baseUri: Uri.parse('https://snackup.example/api/v1/'), client: MockClient((r) async {
      if (r.url.path.endsWith('auth/refresh')) return http.Response('{"error":{"code":"UNAUTHENTICATED"}}', 401);
      if (r.url.path.endsWith('auth/login')) {
        logins++; expect(jsonDecode(r.body)['password'], ' secret '); return login.future;
      }
      return http.Response('{"id":"one","role":"business","displayName":"Operador","businessId":"assigned-local"}', 200);
    }));
    addTearDown(session.dispose);
    await tester.pumpWidget(RestPortalApp(session: session,
      businessBuilder: (account) => Scaffold(body: Text('Local asignado: ${account.businessId}'))));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('portal-email')), 'owner@example.test');
    await tester.enterText(find.byKey(const ValueKey('portal-password')), ' secret ');
    await tester.ensureVisible(find.byKey(const ValueKey('portal-login')));
    await tester.tap(find.byKey(const ValueKey('portal-login'))); await tester.pump();
    await tester.tap(find.byKey(const ValueKey('portal-login'))); await tester.pump();
    expect(logins, 1);
    login.complete(http.Response(jsonEncode({'tokens': {'accessToken': 'a',
      'accessTokenExpiresAt': DateTime.now().toUtc().add(const Duration(minutes: 15)).toIso8601String()}}), 200));
    await tester.pumpAndSettle();
    expect(find.text('Local asignado: assigned-local'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('admin API panel loads and expired access removes a protected dialog', (tester) async {
    tester.view.physicalSize = const Size(360, 800); tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio);
    final session = RestSession(baseUri: Uri.parse('https://snackup.example/api/v1/'), client: MockClient((r) async {
      if (r.url.path.endsWith('auth/refresh')) return http.Response(jsonEncode({'tokens': {'accessToken': 'a',
        'accessTokenExpiresAt': DateTime.now().toUtc().add(const Duration(minutes: 15)).toIso8601String()}}), 200);
      if (r.url.path.endsWith('users/me')) return http.Response('{"id":"admin-1","role":"admin","displayName":"Administración"}', 200);
      expect(r.headers['Authorization'], 'Bearer a');
      return http.Response('{"data":[],"pagination":{"page":1,"totalPages":0}}', 200);
    }));
    addTearDown(session.dispose);
    await tester.pumpWidget(RestPortalApp(session: session)); await tester.pumpAndSettle();
    expect(find.byType(AdminDashboardScreen), findsOneWidget);
    expect(find.text('DEMO · DATOS SIMULADOS'), findsNothing);
    final context = tester.element(find.byType(AdminDashboardScreen));
    unawaited(showDialog<void>(context: context, builder: (_) => const AlertDialog(content: Text('Detalle protegido'))));
    await tester.pumpAndSettle();
    expect(find.text('Detalle protegido'), findsOneWidget);
    session.invalidate('Tu sesión terminó.'); await tester.pumpAndSettle();
    expect(find.text('Detalle protegido'), findsNothing);
    expect(find.byType(AdminDashboardScreen), findsNothing);
    expect(find.byKey(const ValueKey('portal-login')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a business without an assignment cannot open either panel', (tester) async {
    final session = RestSession(baseUri: Uri.parse('https://snackup.example/api/v1/'), client: MockClient((r) async {
      if (r.url.path.endsWith('auth/refresh')) return http.Response(jsonEncode({'tokens': {'accessToken': 'a',
        'accessTokenExpiresAt': DateTime.now().toUtc().add(const Duration(minutes: 15)).toIso8601String()}}), 200);
      return http.Response('{"id":"one","role":"business","displayName":"Operador"}', 200);
    }));
    addTearDown(session.dispose);
    await tester.pumpWidget(RestPortalApp(session: session)); await tester.pumpAndSettle();
    expect(find.textContaining('todavía no tiene un local asignado'), findsOneWidget);
    expect(find.byType(CatalogScreen), findsNothing);
    expect(find.byType(AdminDashboardScreen), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
