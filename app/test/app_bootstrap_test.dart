import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snackup/app_bootstrap.dart';

void main() {
  Widget app() => const MaterialApp(home: Text('Aplicación integrada'));

  testWidgets('permite recargar web si el cargador del SDK queda suspendido', (
    tester,
  ) async {
    final ready = Completer<void>();
    var reloads = 0;
    await tester.pumpWidget(
      AppBootstrap(
        initialize: () => ready.future,
        appBuilder: app,
        timeout: const Duration(seconds: 1),
        onReload: () => reloads++,
      ),
    );
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    await tester.tap(find.text('Recargar aplicación'));
    expect(reloads, 1);
    ready.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('espera a Firebase y después muestra la aplicación', (
    tester,
  ) async {
    final ready = Completer<void>();
    await tester.pumpWidget(
      AppBootstrap(initialize: () => ready.future, appBuilder: app),
    );
    expect(find.text('Iniciando SnackUp'), findsOneWidget);
    expect(find.text('Aplicación integrada'), findsNothing);
    ready.complete();
    await tester.pumpAndSettle();
    expect(find.text('Aplicación integrada'), findsOneWidget);
  });

  testWidgets('un fallo permite reintentar sin dejar una pantalla vacía', (
    tester,
  ) async {
    var calls = 0;
    await tester.pumpWidget(
      AppBootstrap(
        initialize: () async {
          if (++calls == 1) throw StateError('connection failed');
        },
        appBuilder: app,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('No pudimos iniciar SnackUp'), findsOneWidget);
    await tester.tap(find.text('Reintentar'));
    await tester.pumpAndSettle();
    expect(find.text('Aplicación integrada'), findsOneWidget);
    expect(calls, 2);
  });

  testWidgets('un timeout no inicializa dos veces el SDK que sigue cargando', (
    tester,
  ) async {
    final ready = Completer<void>();
    var calls = 0;
    await tester.pumpWidget(
      AppBootstrap(
        initialize: () {
          calls++;
          return ready.future;
        },
        appBuilder: app,
        timeout: const Duration(seconds: 1),
      ),
    );
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    expect(find.text('Reintentar'), findsOneWidget);
    await tester.tap(find.text('Reintentar'));
    await tester.pump();
    ready.complete();
    await tester.pumpAndSettle();
    expect(find.text('Aplicación integrada'), findsOneWidget);
    expect(calls, 1);
  });
}
