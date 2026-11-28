import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snackup/app_bootstrap.dart';

const app = MaterialApp(home: Scaffold(body: Text('Inicio de SnackUP')));

void main() {
  testWidgets('espera a los servicios antes de mostrar la aplicación', (
    tester,
  ) async {
    final ready = Completer<void>();
    await tester.pumpWidget(
      SnackUpBootstrap(initialize: () => ready.future, child: app),
    );

    expect(find.text('Iniciando SnackUP…'), findsOneWidget);
    expect(find.text('Inicio de SnackUP'), findsNothing);

    ready.complete();
    await tester.pumpAndSettle();

    expect(find.text('Inicio de SnackUP'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('un fallo de inicio permite reintentar sin cerrar la app', (
    tester,
  ) async {
    var attempts = 0;
    final retry = Completer<void>();
    await tester.pumpWidget(
      SnackUpBootstrap(
        initialize: () async {
          attempts++;
          if (attempts == 1) throw StateError('Fallo de servicio');
          await retry.future;
        },
        child: app,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('No pudimos iniciar SnackUP'), findsOneWidget);
    expect(find.text('Inicio de SnackUP'), findsNothing);
    expect(find.textContaining('StateError'), findsNothing);

    await tester.tap(find.text('Reintentar'));
    await tester.pump();
    expect(attempts, 2);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    retry.complete();
    await tester.pumpAndSettle();
    expect(find.text('Inicio de SnackUP'), findsOneWidget);
  });

  testWidgets('reconstruir el widget no repite la inicialización', (
    tester,
  ) async {
    var attempts = 0;
    Future<void> initialize() async {
      attempts++;
    }

    await tester.pumpWidget(
      SnackUpBootstrap(initialize: initialize, child: app),
    );
    await tester.pumpAndSettle();
    await tester.pumpWidget(
      SnackUpBootstrap(initialize: initialize, child: app),
    );
    await tester.pumpAndSettle();

    expect(attempts, 1);
    expect(find.text('Inicio de SnackUP'), findsOneWidget);
  });

  testWidgets('captura también un fallo síncrono del inicializador', (
    tester,
  ) async {
    await tester.pumpWidget(
      SnackUpBootstrap(
        initialize: () => throw StateError('Configuración inválida'),
        child: app,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('No pudimos iniciar SnackUP'), findsOneWidget);
    expect(find.text('Reintentar'), findsOneWidget);
  });
}
