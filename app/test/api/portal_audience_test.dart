import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:snackup/api/api_client.dart';
import 'package:snackup/api/portal_audience.dart';
import 'package:snackup/api/rest_session.dart';
import 'package:snackup/features/admin/panel_appearance.dart';
import 'package:snackup/features/portal/rest_portal_app.dart';
import 'package:snackup/features/portal/request_access_screen.dart';
import 'package:snackup/api/access_repository.dart';

final now = DateTime.utc(2026, 11, 13);
http.Response reply(Object value, [int status = 200]) => http.Response(
  jsonEncode(value),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
Map<String, Object> token([String value = 'first']) => {
  'tokens': {
    'accessToken': value,
    'accessTokenExpiresAt': now
        .add(const Duration(minutes: 15))
        .toIso8601String(),
  },
};
Map<String, Object> profile(String role) => {
  'id': 'account',
  'role': role,
  'displayName': 'Cuenta autorizada',
  if (role == 'business') 'businessId': 'local-1',
};

void main() {
  test(
    'each build refuses the other entry URL and cross-origin or scoped APIs',
    () {
      for (final audience in PortalAudience.values) {
        final location = Uri.parse(
          'https://${audience.configurationValue}.snackup.example/',
        );
        expect(
          PortalAudience.forLocation(
            location,
            configured: audience.configurationValue,
          ),
          audience,
        );
        expect(
          audience.acceptsApiBase(location, location.resolve('api/legacy/v1/')),
          true,
        );
        expect(
          audience.acceptsApiBase(
            location,
            location.resolve('${audience.entryPath}api/legacy/v1/'),
          ),
          false,
        );
        expect(
          audience.acceptsApiBase(
            location,
            Uri.parse('https://other.example/api/legacy/v1/'),
          ),
          false,
        );
        final other = PortalAudience.values.firstWhere(
          (value) => value != audience,
        );
        expect(
          () => PortalAudience.forLocation(
            location,
            configured: other.configurationValue,
          ),
          throwsArgumentError,
        );
        expect(
          audience.acceptsApiBase(
            location,
            Uri.parse(
              'https://${other.configurationValue}.snackup.example/api/legacy/v1/',
            ),
          ),
          false,
        );
      }
      expect(
        PortalAudience.fromUri(
          Uri.parse('https://snackup.example/cocina-falsa/'),
        ),
        isNull,
      );
      expect(
        () => PortalAudience.forLocation(
          Uri.parse('https://snackup.example/'),
          configured: 'admin',
        ),
        throwsArgumentError,
      );
    },
  );

  for (final audience in PortalAudience.values) {
    final wrongRole = audience == PortalAudience.kitchen ? 'admin' : 'business';
    RestSession sessionFor(
      Future<http.Response> Function(http.Request) handle,
    ) => RestSession(
      baseUri: Uri.parse(
        'https://${audience.configurationValue}.snackup.example/api/legacy/v1/',
      ),
      audience: audience,
      client: MockClient(handle),
      now: () => now,
    );

    test(
      '${audience.name} rejects a different verified role at login',
      () async {
        final session = sessionFor(
          (request) async => request.url.path.endsWith('users/me')
              ? reply(profile(wrongRole))
              : reply(token()),
        );
        addTearDown(session.dispose);
        await session.signIn('person@example.edu', 'correct-password');
        expect(session.phase, PortalSessionPhase.signedOut);
        expect(session.account, isNull);
        expect(session.message, audience.accessNotice);
        await expectLater(session.accessToken(), throwsA(isA<ApiException>()));
      },
    );

    test(
      '${audience.name} cannot restore the other role or expose its token',
      () async {
        final session = sessionFor(
          (request) async => request.url.path.endsWith('users/me')
              ? reply(profile(wrongRole))
              : reply(token()),
        );
        addTearDown(session.dispose);
        await session.restore();
        expect(session.phase, PortalSessionPhase.signedOut);
        expect(session.account, isNull);
        expect(session.message, audience.accessNotice);
        await expectLater(session.accessToken(), throwsA(isA<ApiException>()));
      },
    );

    test(
      '${audience.name} hides the authenticated panel if renewal changes role',
      () async {
        var renewed = false;
        final session = sessionFor((request) async {
          if (request.url.path.endsWith('users/me')) {
            return reply(profile(renewed ? wrongRole : audience.role));
          }
          if (request.url.path.endsWith('auth/refresh')) renewed = true;
          return reply(token(renewed ? 'second' : 'first'));
        });
        addTearDown(session.dispose);
        await session.signIn('person@example.edu', 'correct-password');
        expect(session.phase, PortalSessionPhase.authenticated);
        expect(await session.refresh(), false);
        expect(session.phase, PortalSessionPhase.signedOut);
        expect(session.account, isNull);
        await expectLater(session.accessToken(), throwsA(isA<ApiException>()));
      },
    );

    test('${audience.name} explains a server-side portal mismatch', () async {
      final session = sessionFor(
        (request) async => reply({
          'error': {'code': 'PORTAL_ROLE_MISMATCH'},
        }, 403),
      );
      addTearDown(session.dispose);
      await session.signIn('person@example.edu', 'correct-password');
      expect(session.message, audience.accessNotice);
      await session.restore();
      expect(session.message, audience.accessNotice);
    });

    testWidgets(
      '${audience.name} login has its own identity and no other-panel entry',
      (tester) async {
        final session = sessionFor(
          (request) async => request.url.path.endsWith('auth/options')
              ? reply({
                  'passwordLogin': true,
                  'selfRegistration': true,
                  'googleEnabled': false,
                })
              : reply({
                  'error': {'code': 'UNAUTHENTICATED'},
                }, 401),
        );
        addTearDown(session.dispose);
        await tester.pumpWidget(RestPortalApp(session: session));
        await tester.pumpAndSettle();
        expect(find.text(audience.loginTitle), findsOneWidget);
        expect(find.textContaining('Locales y administración'), findsNothing);
        final other = PortalAudience.values.firstWhere(
          (value) => value != audience,
        );
        expect(find.text(other.loginTitle), findsNothing);
        expect(
          tester.widget<MaterialApp>(find.byType(MaterialApp)).title,
          audience.applicationTitle,
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      '${audience.name} registration has no switch to request the other role',
      (tester) async {
        Map<String, dynamic>? submitted;
        final client = MockClient((request) async {
          submitted = jsonDecode(request.body) as Map<String, dynamic>;
          return reply({'status': 'received'});
        });
        addTearDown(client.close);
        await tester.pumpWidget(
          MaterialApp(
            home: RequestAccessScreen(
              audience: audience,
              repository: AccessRepository(
                ApiClient(
                  baseUri: Uri.parse('https://snackup.example/'),
                  client: client,
                ),
              ),
            ),
          ),
        );
        expect(
          find.text('Solicitud de acceso a ${audience.label}'),
          findsOneWidget,
        );
        expect(find.byType(DropdownButtonFormField<String>), findsNothing);
        final fields = find.byType(TextFormField);
        for (final field in <(int, String)>[
          (0, 'Operador de prueba'),
          (1, 'person@example.edu'),
          (2, 'Solicitud autorizada para este servicio.'),
          (3, 'password-for-test-123'),
          (4, 'password-for-test-123'),
        ]) {
          await tester.ensureVisible(fields.at(field.$1));
          await tester.enterText(fields.at(field.$1), field.$2);
          await tester.pumpAndSettle();
        }
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Solicitar acceso'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Solicitar acceso'));
        await tester.pumpAndSettle();
        expect(submitted?['requestedRole'], audience.role);
        expect(find.text('Solicitud recibida'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  test(
    'changing kitchen appearance does not alter administration preferences',
    () async {
      SharedPreferences.setMockInitialValues({});
      final kitchen = PanelAppearance(namespace: PortalAudience.kitchen.name);
      final admin = PanelAppearance(
        namespace: PortalAudience.administration.name,
      );
      addTearDown(kitchen.dispose);
      addTearDown(admin.dispose);
      kitchen.toggle();
      await kitchen.saved;
      await admin.restore();
      expect(kitchen.dark, true);
      expect(admin.dark, false);
    },
  );
}
