import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snackup/features/admin/admin_dashboard_screen.dart';
import 'package:snackup/features/admin/followup_dialog.dart';
import 'package:snackup/features/admin/data/admin_repository.dart';
import 'package:snackup/features/admin/domain/admin_models.dart';

class PartialRepository extends DemoAdminRepository {
  @override
  Future<AdminPage> loadNextPage({bool reset = false}) async {
    final data = await super.loadNextPage(reset: reset);
    return AdminPage(
      businesses: data.businesses,
      reviews: data.reviews,
      hasMore: reset,
    );
  }
}

class FailingRepository extends DemoAdminRepository {
  @override
  bool get isDemo => false;
  @override
  Future<AdminPage> loadNextPage({bool reset = false}) async =>
      throw StateError('denied');
}

void main() {
  testWidgets('demo renders four stores, filtering and explicit demo state', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: AdminDashboardScreen(repository: DemoAdminRepository()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('DEMO · DATOS SIMULADOS'), findsOneWidget);
    for (final business in DemoAdminRepository.businesses) {
      expect(find.text(business.name), findsWidgets);
    }
    expect(find.text('96'), findsOneWidget);
    await tester.enterText(
      find.byType(TextField).first,
      'no existe este comentario',
    );
    await tester.pumpAndSettle();
    expect(
      find.text('No hay opiniones que coincidan con los filtros.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'mobile empty view is usable without overflow and exposes logout',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var signedOut = false;
      await tester.pumpWidget(
        MaterialApp(
          home: AdminDashboardScreen(
            repository: DemoAdminRepository(empty: true),
            onSignOut: () => signedOut = true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Todavía no hay locales registrados.'), findsOneWidget);
      expect(
        find.text('No hay opiniones que coincidan con los filtros.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('Cerrar sesión'));
      expect(signedOut, true);
    },
  );
  testWidgets('partial data are explicitly labeled until next page is loaded', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: AdminDashboardScreen(repository: PartialRepository())),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Resultados parciales:'), findsOneWidget);
    await tester.ensureVisible(find.text('Cargar 200 más'));
    await tester.tap(find.text('Cargar 200 más'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Resultados parciales:'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('live load failure never falls back to demo records', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: AdminDashboardScreen(repository: FailingRepository())),
    );
    await tester.pumpAndSettle();
    expect(
      find.textContaining('No se pudieron actualizar los datos.'),
      findsOneWidget,
    );
    expect(find.text('Cafetería Central'), findsNothing);
    expect(find.textContaining('Modo demostración:'), findsNothing);
  });
  testWidgets('populated mobile dashboard and navigation fit 360px', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: AdminDashboardScreen(repository: DemoAdminRepository()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Cafetería Central'), findsWidgets);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Opiniones').first);
    await tester.pumpAndSettle();
    expect(find.text('Opiniones del alumnado'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    await tester.tap(find.text('Filtrar opiniones'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    await tester.enterText(
      find.byType(TextField),
      'sin coincidencias para esta búsqueda',
    );
    await tester.pumpAndSettle();
    expect(
      find.text('No hay opiniones que coincidan con los filtros.'),
      findsOneWidget,
    );
    expect(find.text('Últimos 30 días · 2 filtros activos'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('followup dialog validates, saves a note and displays history', (
    tester,
  ) async {
    final repo = DemoAdminRepository();
    final page = await repo.loadNextPage();
    final review = page.reviews.first;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showDialog<AdminFollowup>(
                context: context,
                builder: (_) => FollowupDialog(
                  review: review,
                  businessName: 'Cafetería Central',
                  repository: repo,
                ),
              ),
              child: const Text('Abrir caso'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Abrir caso'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Guardar seguimiento'));
    await tester.tap(find.text('Guardar seguimiento'));
    await tester.pumpAndSettle();
    expect(
      find.text('Indica a quién corresponde dar seguimiento.'),
      findsOneWidget,
    );
    expect((await repo.getHistory(review.id)).events, isEmpty);
    await tester.enterText(find.byType(TextFormField).at(0), 'Coordinación');
    await tester.enterText(
      find.byType(TextFormField).at(1),
      'Revisar tiempos de servicio el próximo lunes.',
    );
    await tester.ensureVisible(find.text('Guardar seguimiento'));
    await tester.tap(find.text('Guardar seguimiento'));
    await tester.pumpAndSettle();
    expect(find.byType(FollowupDialog), findsNothing);
    final history = await repo.getHistory(review.id);
    expect(history.events.single.assignee, 'Coordinación');
    await tester.tap(find.text('Abrir caso'));
    await tester.pumpAndSettle();
    expect(
      find.text('Revisar tiempos de servicio el próximo lunes.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
  test('unknown status remains pending', () {
    expect(statusFromCode('unexpected'), FollowupStatus.pending);
  });
}
