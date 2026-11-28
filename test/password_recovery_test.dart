import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snackup/features/auth/password_recovery.dart';

Widget recoveryHost({
  required Future<void> Function(String email) sendResetEmail,
  String initialEmail = 'estudiante@utsjr.edu.mx',
  GlobalKey<NavigatorState>? navigatorKey,
}) => MaterialApp(
  navigatorKey: navigatorKey,
  home: Scaffold(
    body: Builder(
      builder: (context) => FilledButton(
        onPressed: () => showPasswordRecovery(
          context,
          initialEmail: initialEmail,
          sendResetEmail: sendResetEmail,
        ),
        child: const Text('Abrir recuperación'),
      ),
    ),
  ),
);

Future<void> openRecovery(WidgetTester tester, Widget host) async {
  await tester.pumpWidget(host);
  await tester.tap(find.text('Abrir recuperación'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('un correo inválido no envía una solicitud', (tester) async {
    var requests = 0;
    await openRecovery(
      tester,
      recoveryHost(
        initialEmail: 'correo inválido',
        sendResetEmail: (_) async {
          requests++;
        },
      ),
    );

    await tester.tap(find.text('Enviar enlace'));
    await tester.pumpAndSettle();

    expect(requests, 0);
    expect(find.text('Ingresa un correo válido'), findsOneWidget);
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('envía el correo sin espacios y confirma el resultado', (
    tester,
  ) async {
    String? sentEmail;
    await openRecovery(
      tester,
      recoveryHost(
        initialEmail: '  estudiante@utsjr.edu.mx  ',
        sendResetEmail: (email) async {
          sentEmail = email;
        },
      ),
    );

    await tester.tap(find.text('Enviar enlace'));
    await tester.pumpAndSettle();

    expect(sentEmail, 'estudiante@utsjr.edu.mx');
    expect(find.byType(AlertDialog), findsNothing);
    expect(
      find.textContaining('Si el correo tiene una cuenta'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('un fallo de red permite reintentar el envío', (tester) async {
    var requests = 0;
    await openRecovery(
      tester,
      recoveryHost(
        sendResetEmail: (_) async {
          requests++;
          if (requests == 1)
            throw FirebaseAuthException(code: 'network-request-failed');
        },
      ),
    );

    await tester.tap(find.text('Enviar enlace'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Revisa tu conexión'), findsOneWidget);
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(
      tester.widget<TextFormField>(find.byType(TextFormField)).enabled,
      isTrue,
    );

    await tester.tap(find.text('Enviar enlace'));
    await tester.pumpAndSettle();
    expect(requests, 2);
    expect(find.byType(AlertDialog), findsNothing);
    expect(
      find.textContaining('Si el correo tiene una cuenta'),
      findsOneWidget,
    );
  });

  testWidgets('un correo desconocido recibe la misma confirmación', (
    tester,
  ) async {
    await openRecovery(
      tester,
      recoveryHost(
        sendResetEmail: (_) async {
          throw FirebaseAuthException(code: 'user-not-found');
        },
      ),
    );

    await tester.tap(find.text('Enviar enlace'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(
      find.textContaining('Si el correo tiene una cuenta'),
      findsOneWidget,
    );
    expect(find.textContaining('user-not-found'), findsNothing);
  });

  testWidgets(
    'bloquea envíos duplicados y atrás mientras espera la respuesta',
    (tester) async {
      final pending = Completer<void>();
      final navigatorKey = GlobalKey<NavigatorState>();
      var requests = 0;
      await openRecovery(
        tester,
        recoveryHost(
          navigatorKey: navigatorKey,
          sendResetEmail: (_) {
            requests++;
            return pending.future;
          },
        ),
      );

      await tester.tap(find.text('Enviar enlace'));
      await tester.pump();
      expect(
        tester.widget<TextFormField>(find.byType(TextFormField)).enabled,
        isFalse,
      );
      final sendButton = tester.widget<FilledButton>(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(FilledButton),
        ),
      );
      expect(sendButton.onPressed, isNull);
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Cancelar'))
            .onPressed,
        isNull,
      );
      await navigatorKey.currentState!.maybePop();
      await tester.pump();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(requests, 1);

      pending.complete();
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'una respuesta después de cerrar no vuelve a navegar ni muestra mensajes',
    (tester) async {
      final pending = Completer<void>();
      final navigatorKey = GlobalKey<NavigatorState>();
      await openRecovery(
        tester,
        recoveryHost(
          navigatorKey: navigatorKey,
          sendResetEmail: (_) => pending.future,
        ),
      );

      await tester.tap(find.text('Enviar enlace'));
      await tester.pump();
      // Un cambio externo de navegación puede cerrar incluso con una solicitud activa.
      navigatorKey.currentState!.pop();
      await tester.pump();
      pending.complete();
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Abrir recuperación'), findsOneWidget);
      expect(
        find.textContaining('Si el correo tiene una cuenta'),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'un error inesperado no cierra el diálogo ni expone detalles internos',
    (tester) async {
      await openRecovery(
        tester,
        recoveryHost(
          sendResetEmail: (_) async {
            throw StateError('detalle interno');
          },
        ),
      );

      await tester.tap(find.text('Enviar enlace'));
      await tester.pumpAndSettle();

      expect(
        find.text('No se pudo enviar el correo. Inténtalo de nuevo.'),
        findsOneWidget,
      );
      expect(find.textContaining('detalle interno'), findsNothing);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
