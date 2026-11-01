import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:snackup/student/auth_screens.dart';
import 'package:snackup/student/student_api.dart';

void main() {
  Future<void> openForm(WidgetTester tester, void Function() onRegister) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = StudentApi(
      realtimeEnabled: false,
      client: MockClient((request) async {
        expect(request.url.path, '/api/v1/auth/register');
        onRegister();
        expect((jsonDecode(request.body) as Map).keys.toSet(), {
          'email',
          'password',
          'displayName',
          'numeroDeControl',
        });
        return http.Response(
          '{"status":"received"}',
          202,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      api.dispose();
    });
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: api,
        child: const MaterialApp(home: RegisterScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  FilledButton createButton(WidgetTester tester) => tester.widget<FilledButton>(
    find.byKey(const ValueKey('create-student-account')),
  );

  testWidgets('personal email never reaches registration API', (tester) async {
    var registrations = 0;
    await openForm(tester, () => registrations++);
    const values = [
      'Alumno de prueba',
      'TEST-001',
      'alumno@gmail.com',
      'Example-password-123!',
      'Example-password-123!',
    ];
    for (var index = 0; index < values.length; index++) {
      await tester.enterText(
        find.byType(TextFormField).at(index),
        values[index],
      );
    }
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    final checkbox = find.descendant(
      of: find.byKey(const ValueKey('registration-consent')),
      matching: find.byType(Checkbox),
    );
    await tester.ensureVisible(checkbox);
    await tester.pumpAndSettle();
    await tester.tap(checkbox);
    await tester.pumpAndSettle();
    final submit = find.byKey(const ValueKey('create-student-account'));
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();
    expect(find.text('Usa tu correo @utsjr.edu.mx.'), findsOneWidget);
    expect(registrations, 0);
  });

  testWidgets(
    'valid form cannot register until explicit consent and unchecking blocks it again',
    (tester) async {
      var registrations = 0;
      await openForm(tester, () => registrations++);
      expect(createButton(tester).onPressed, isNull);
      const fields = [
        'Alumno de prueba',
        'TEST-001',
        'alumno@utsjr.edu.mx',
        'Example-password-123!',
        'Example-password-123!',
      ];
      for (var index = 0; index < fields.length; index++) {
        await tester.enterText(
          find.byType(TextFormField).at(index),
          fields[index],
        );
      }
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      final submit = find.byKey(const ValueKey('create-student-account'));
      await tester.ensureVisible(submit);
      await tester.tap(submit);
      await tester.pump();
      expect(registrations, 0);
      expect(createButton(tester).onPressed, isNull);
      final consent = find.descendant(
        of: find.byKey(const ValueKey('registration-consent')),
        matching: find.byType(Checkbox),
      );
      await tester.ensureVisible(consent);
      await tester.pumpAndSettle();
      await tester.tap(consent);
      await tester.pump();
      expect(createButton(tester).onPressed, isNotNull);
      await tester.tap(consent);
      await tester.pump();
      expect(createButton(tester).onPressed, isNull);
      expect(registrations, 0);
      await tester.tap(consent);
      await tester.pump();
      await tester.ensureVisible(submit);
      await tester.tap(submit);
      await tester.pumpAndSettle();
      expect(registrations, 1);
      expect(find.text('Solicitud recibida'), findsOneWidget);
    },
  );

  testWidgets(
    'both supplied documents are readable on mobile and opening them does not accept',
    (tester) async {
      var registrations = 0;
      await openForm(tester, () => registrations++);
      final cases = {
        'open-data-protection': [
          'Protección de Datos Personales',
          'Soporte.snackup@gmail.com',
          'SnackUp no solicitará datos sensibles',
        ],
        'open-privacy-policy': [
          'Política de Privacidad',
          'SnackUp no venderá, rentará ni compartirá tus datos',
          'eliminados, bloqueados o cancelados',
        ],
      };
      for (final entry in cases.entries) {
        final link = find.byKey(ValueKey(entry.key));
        await tester.ensureVisible(link);
        await tester.pumpAndSettle();
        await tester.tap(link);
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.text(entry.value[0]),
          ),
          findsOneWidget,
        );
        final text = tester
            .widget<SelectableText>(find.byType(SelectableText))
            .data!;
        expect(text, contains(entry.value[1]));
        expect(text, contains(entry.value[2]));
        expect(find.byType(SingleChildScrollView), findsWidgets);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Cerrar'));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<CheckboxListTile>(
                find.byKey(const ValueKey('registration-consent')),
              )
              .value,
          isFalse,
        );
        expect(createButton(tester).onPressed, isNull);
        expect(registrations, 0);
      }
    },
  );
}
