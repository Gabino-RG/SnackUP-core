import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:snackup/api/api_client.dart';
import 'package:snackup/api/access_repository.dart';
import 'package:snackup/api/rest_session.dart';
import 'package:snackup/features/portal/request_access_screen.dart';

void main() {
  test(
    'provider availability comes from the API and Google uses a fixed backend route',
    () async {
      final repository = AccessRepository(
        ApiClient(
          baseUri: Uri.parse('https://snackup.example/api/v1/'),
          client: MockClient((r) async {
            expect(r.url.path, '/api/v1/auth/options');
            return http.Response(
              '{"passwordLogin":true,"selfRegistration":true,"googleEnabled":false}',
              200,
            );
          }),
        ),
      );
      final options = await repository.options();
      expect(options.googleEnabled, false);
      expect(options.selfRegistration, true);
      expect(
        repository.googleStart.toString(),
        'https://snackup.example/api/v1/auth/google/start',
      );
      expect(
        () => AccessOptions.fromJson({'googleEnabled': true}),
        throwsA(isA<ApiException>()),
      );
      expect(accessReturnMessage('/access-pending'), contains('pendiente'));
      expect(accessReturnMessage('/grant-admin'), isNull);
    },
  );
  test(
    'pending credentials display approval state and never obtain a session',
    () async {
      final session = RestSession(
        baseUri: Uri.parse('https://snackup.example/api/v1/'),
        client: MockClient(
          (r) async =>
              http.Response('{"error":{"code":"ACCESS_PENDING"}}', 403),
        ),
      );
      addTearDown(session.dispose);
      await session.signIn('person@example.test', 'Example-Password');
      expect(session.account, isNull);
      expect(session.phase, PortalSessionPhase.signedOut);
      expect(session.message, contains('pendiente de autorización'));
    },
  );
  for (final width in [320.0, 768.0, 1440.0]) {
    testWidgets(
      'request form fits ${width.toInt()}px and sends no granted permissions',
      (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        Map<String, dynamic>? sent;
        final repository = AccessRepository(
          ApiClient(
            baseUri: Uri.parse('https://example.test/api/v1/'),
            client: MockClient((r) async {
              sent = jsonDecode(r.body) as Map<String, dynamic>;
              return http.Response('{"status":"received"}', 202);
            }),
          ),
        );
        await tester.pumpWidget(
          MaterialApp(home: RequestAccessScreen(repository: repository)),
        );
        await tester.pumpAndSettle();
        final fields = find.byType(TextFormField);
        final values = [
          'Operador',
          'persona@example.test',
          'Local o área que revisará la cuenta maestra',
          'Clave-Nueva-12345',
          'Clave-Nueva-12345',
        ];
        for (var i = 0; i < values.length; i++) {
          await tester.ensureVisible(fields.at(i));
          await tester.enterText(fields.at(i), values[i]);
        }
        await tester.ensureVisible(find.text('Solicitar acceso'));
        await tester.tap(find.text('Solicitar acceso'));
        await tester.pumpAndSettle();
        expect(find.text('Solicitud recibida'), findsOneWidget);
        expect(sent!['requestedRole'], 'business');
        expect(
          sent!.keys,
          unorderedEquals([
            'displayName',
            'email',
            'password',
            'requestedRole',
            'context',
          ]),
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
