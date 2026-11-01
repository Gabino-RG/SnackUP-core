import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:snackup/main.dart';
import 'package:snackup/student/student_api.dart';

http.Response jsonReply(Object value, [int status = 200]) => http.Response(
  jsonEncode(value),
  status,
  headers: {'content-type': 'application/json'},
);

void main() {
  Future<void> launch(WidgetTester tester, StudentApi api) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
    await tester.pumpWidget(SnackUpApp(api: api));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'student app opens without Firebase and respects disabled registration',
    (tester) async {
      final api = StudentApi(
        realtimeEnabled: false,
        client: MockClient((request) async {
          expect(request.url.path, '/api/v1/auth/options');
          return jsonReply({
            'passwordLogin': true,
            'selfRegistration': false,
            'googleEnabled': false,
          });
        }),
      );
      await launch(tester, api);
      expect(find.text('Bienvenido a SnackUP'), findsOneWidget);
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Crear cuenta de alumno'),
            )
            .onPressed,
        isNull,
      );
      expect(find.textContaining('aún no están habilitados'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('kitchen or admin login cannot enter student application', (
    tester,
  ) async {
    final api = StudentApi(
      realtimeEnabled: false,
      client: MockClient((request) async {
        if (request.url.path.endsWith('/auth/options')) {
          return jsonReply({'selfRegistration': true});
        }
        if (request.url.path.endsWith('/auth/login')) {
          return jsonReply({
            'user': {'id': 'admin', 'role': 'ADMIN'},
            'tokens': {
              'accessToken': 'test-access',
              'refreshToken': 'test-refresh',
              'accessTokenExpiresAt': DateTime.now()
                  .add(const Duration(minutes: 15))
                  .toUtc()
                  .toIso8601String(),
            },
          });
        }
        throw StateError('Unexpected request ${request.url.path}');
      }),
    );
    await launch(tester, api);
    await tester.enterText(
      find.byType(TextFormField).at(0),
      'admin@utsjr.edu.mx',
    );
    await tester.enterText(
      find.byType(TextFormField).at(1),
      'Example-password-123!',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Iniciar sesión'));
    await tester.pumpAndSettle();
    expect(find.text('Portal de alumnos'), findsOneWidget);
    expect(find.textContaining('otro perfil'), findsOneWidget);
    expect(find.byType(BottomNavigationBar), findsNothing);
  });

  testWidgets(
    'registration sends canonical fields and shows generic receipt without session',
    (tester) async {
      Map<String, dynamic>? registration;
      final api = StudentApi(
        realtimeEnabled: false,
        client: MockClient((request) async {
          if (request.url.path.endsWith('/auth/options')) {
            return jsonReply({'selfRegistration': true});
          }
          expect(request.url.path, '/api/v1/auth/register');
          registration = jsonDecode(request.body) as Map<String, dynamic>;
          return jsonReply({'status': 'received'}, 202);
        }),
      );
      await launch(tester, api);
      await tester.tap(find.text('Crear cuenta de alumno'));
      await tester.pumpAndSettle();
      const values = [
        'Alumno de prueba',
        'TEST-001',
        'alumno@utsjr.edu.mx',
        'Example-password-123!',
        'Example-password-123!',
      ];
      for (var i = 0; i < values.length; i++) {
        await tester.enterText(find.byType(TextFormField).at(i), values[i]);
      }
      final consent = find.descendant(
        of: find.byKey(const ValueKey('registration-consent')),
        matching: find.byType(Checkbox),
      );
      await tester.ensureVisible(consent);
      await tester.pumpAndSettle();
      await tester.tap(consent);
      await tester.pump();
      final submit = find.text('Crear cuenta');
      await tester.ensureVisible(submit);
      await tester.tap(submit);
      await tester.pumpAndSettle();
      expect(registration, {
        'displayName': values[0],
        'numeroDeControl': values[1],
        'email': values[2],
        'password': values[3],
      });
      expect(find.text('Solicitud recibida'), findsOneWidget);
      expect(
        find.textContaining(
          'Si tu correo y matrícula corresponden al padrón autorizado',
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining('carpeta de correo no deseado'),
        findsOneWidget,
      );
      expect(api.signedIn, isFalse);
      expect(find.byType(BottomNavigationBar), findsNothing);
    },
  );
}
