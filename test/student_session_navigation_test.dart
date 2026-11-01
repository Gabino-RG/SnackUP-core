import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:snackup/features/auth/auth_gate.dart';
import 'package:snackup/student/student_api.dart';

http.Response _json(Object? body, [int status = 200]) => http.Response(
  body == null ? '' : jsonEncode(body),
  status,
  headers: {'content-type': 'application/json'},
);

class _SessionFixture {
  _SessionFixture() {
    api = StudentApi(
      realtimeEnabled: false,
      baseUrl: 'http://localhost:8000/api/v1',
      client: MockClient((request) async {
        final path = request.url.path;
        calls.add(path);
        if (path.endsWith('/auth/login')) {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          final second = body['email'] == 'second@example.edu';
          final id = second ? 'student-b' : 'student-a';
          return _json({
            'user': {
              'id': id,
              'role': 'ALUMNO',
              'displayName': second ? 'Alumno B' : 'Alumno A',
              'email': body['email'],
            },
            'tokens': {
              'accessToken': 'access-$id',
              'refreshToken': 'refresh-$id',
              'accessTokenExpiresAt': DateTime.now()
                  .add(const Duration(minutes: 15))
                  .toUtc()
                  .toIso8601String(),
            },
          });
        }
        if (path.endsWith('/auth/logout')) {
          if (logoutUnavailable) throw http.ClientException('offline');
          return _json(null, 204);
        }
        if (path.endsWith('/auth/options')) {
          return _json({'selfRegistration': false, 'googleEnabled': false});
        }
        if (path.endsWith('/protected') || path.endsWith('/auth/refresh')) {
          return _json({
            'error': {'code': 'UNAUTHENTICATED', 'message': 'Sesión revocada.'},
          }, 401);
        }
        // The actual student home is rendered against an empty local catalog.
        // No image, font, Firebase or external API request is made by this test.
        return _json({
          'data': <Object>[],
          'pagination': {'page': 1, 'limit': 100, 'total': 0, 'totalPages': 0},
        });
      }),
    );
  }

  late final StudentApi api;
  final List<String> calls = [];
  bool logoutUnavailable = false;
  final navigator = GlobalKey<NavigatorState>();

  Future<void> openPrivateRoute(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      api.dispose();
    });
    await api.login('first@example.edu', 'Long-password-123!');
    await tester.pumpWidget(
      ChangeNotifierProvider<StudentApi>.value(
        value: api,
        child: MaterialApp(navigatorKey: navigator, home: const AuthWrapper()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Alumno A'), findsOneWidget);

    navigator.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(
          body: Center(child: Text('Pedido privado de A · retiro SECRET-A')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('SECRET-A'), findsOneWidget);
    expect(navigator.currentState!.canPop(), isTrue);
    expect(tester.takeException(), isNull);
  }

  void expectPrivateRouteClosed(WidgetTester tester) {
    // Include offstage widgets: the previous student's secret must be removed
    // from the route tree, not merely covered by the login screen.
    expect(find.textContaining('SECRET-A', skipOffstage: false), findsNothing);
    expect(find.textContaining('Alumno A', skipOffstage: false), findsNothing);
    expect(navigator.currentState!.canPop(), isFalse);
    expect(tester.takeException(), isNull);
  }
}

void main() {
  testWidgets('logout removes a private route and its cached student content', (
    tester,
  ) async {
    final fixture = _SessionFixture();
    await fixture.openPrivateRoute(tester);

    await fixture.api.logout();
    await tester.pumpAndSettle();

    fixture.expectPrivateRouteClosed(tester);
    expect(find.text('Bienvenido a SnackUP'), findsOneWidget);
    expect(fixture.api.signedIn, isFalse);
  });

  testWidgets(
    'offline logout still removes routes containing the prior student data',
    (tester) async {
      final fixture = _SessionFixture()..logoutUnavailable = true;
      await fixture.openPrivateRoute(tester);

      await expectLater(fixture.api.logout(), throwsA(isA<ApiException>()));
      await tester.pumpAndSettle();

      fixture.expectPrivateRouteClosed(tester);
      expect(find.text('Bienvenido a SnackUP'), findsOneWidget);
      expect(fixture.api.signedIn, isFalse);
    },
  );

  testWidgets(
    'server revocation closes the private route after refresh is rejected',
    (tester) async {
      final fixture = _SessionFixture();
      await fixture.openPrivateRoute(tester);

      await expectLater(
        fixture.api.getObject('/protected'),
        throwsA(isA<ApiException>()),
      );
      await tester.pumpAndSettle();

      fixture.expectPrivateRouteClosed(tester);
      expect(fixture.calls, contains('/api/v1/auth/refresh'));
      expect(find.text('Bienvenido a SnackUP'), findsOneWidget);
      expect(fixture.api.signedIn, isFalse);
    },
  );

  testWidgets(
    'switching identity disposes the previous student route before showing new home',
    (tester) async {
      final fixture = _SessionFixture();
      await fixture.openPrivateRoute(tester);

      await fixture.api.login('second@example.edu', 'Other-password-123!');
      await tester.pumpAndSettle();

      fixture.expectPrivateRouteClosed(tester);
      expect(find.textContaining('Alumno B'), findsOneWidget);
      expect(fixture.api.user!['id'], 'student-b');
      expect(fixture.api.signedIn, isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
      await fixture.api.logout();
    },
  );
}
