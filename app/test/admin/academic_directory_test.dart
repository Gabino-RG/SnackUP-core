import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:snackup/api/api_client.dart';
import 'package:snackup/api/rest_session.dart';
import 'package:snackup/features/admin/academic_picker.dart';
import 'package:snackup/features/admin/admin_dashboard_screen.dart';
import 'package:snackup/features/admin/data/admin_repository.dart';
import 'package:snackup/features/admin/data/demo_admin_repository.dart';
import 'package:snackup/features/admin/domain/academic_directory.dart';
import 'package:snackup/features/admin/domain/admin_models.dart';
import 'package:snackup/operations/portal_configuration.dart';

const configuration = PortalConfiguration(
  universityName: 'Universidad de prueba',
  cafeteriaId: 'cafeteria',
  cafeteriaName: 'Cafetería universitaria',
  adminEmailDomains: ['utsjr.edu.mx'],
);
AcademicDirectory directory() => AcademicDirectory(const [
  AcademicEntry(id: 'software', name: 'Desarrollo de Software', kind: 'career'),
  AcademicEntry(id: 'admin', name: 'Administración', kind: 'career'),
  AcademicEntry(
    id: 'software-1',
    name: 'Grupo 1',
    kind: 'group',
    careerId: 'software',
  ),
  AcademicEntry(
    id: 'admin-1',
    name: 'Grupo 1',
    kind: 'group',
    careerId: 'admin',
  ),
  AcademicEntry(
    id: 'software-100',
    name: 'DSM-100 sin opiniones',
    kind: 'group',
    careerId: 'software',
  ),
]);

class LiveReferences extends DemoAdminRepository
    implements AdminReferenceSource {
  int rating = 2;
  @override
  bool get isDemo => false;
  @override
  Future<AdminReferenceData> loadReferences() async =>
      AdminReferenceData(configuration, directory());
  @override
  Future<AdminPage> loadNextPage({bool reset = false}) async => AdminPage(
    businesses: const [AdminBusiness(id: 'local', name: 'Local dinámico')],
    reviews: List.generate(
      2,
      (i) => AdminReview(
        id: 'r$i',
        businessId: 'local',
        rating: rating,
        career: 'Desarrollo de Software',
        group: 'Grupo 1',
        careerId: 'software',
        groupId: 'software-1',
        createdAt: DateTime.now().toUtc().subtract(Duration(days: i + 1)),
      ),
    ),
  );
}

class CareerIdentityReferences extends LiveReferences {
  @override
  Future<AdminReferenceData> loadReferences() async => AdminReferenceData(
    configuration,
    AcademicDirectory(const [
      AcademicEntry(id: 'career-a', name: 'Carrera vigente', kind: 'career'),
      AcademicEntry(id: 'career-b', name: 'Carrera vigente', kind: 'career'),
    ]),
  );
  @override
  Future<AdminPage> loadNextPage({bool reset = false}) async => AdminPage(
    businesses: const [AdminBusiness(id: 'local', name: 'Local dinámico')],
    reviews: [
      for (final row in [
        ('old', 'career-a', 'Nombre anterior', 0),
        ('new', 'career-a', 'Carrera vigente', 4),
        ('other', 'career-b', 'Carrera vigente', 5),
        ('legacy', null, 'Carrera histórica', 2),
      ])
        AdminReview(
          id: row.$1,
          businessId: 'local',
          careerId: row.$2,
          career: row.$3,
          rating: row.$4,
          createdAt: DateTime.now().toUtc().subtract(const Duration(days: 1)),
        ),
    ],
  );
}

class SparseTrendReferences extends LiveReferences {
  @override
  Future<AdminPage> loadNextPage({bool reset = false}) async {
    final anchor = DateTime.now().toUtc().subtract(const Duration(days: 8));
    final first = DateTime.utc(anchor.year, anchor.month, anchor.day, 12);
    return AdminPage(
      businesses: const [AdminBusiness(id: 'local', name: 'Local dinámico')],
      reviews: [
        for (final row in [('a', 0, 0), ('b', 0, 4), ('c', 3, 0), ('d', 7, 5)])
          AdminReview(
            id: row.$1,
            businessId: 'local',
            rating: row.$3,
            createdAt: first.add(Duration(days: row.$2)),
          ),
      ],
    );
  }
}

class MissingDimensionReferences extends LiveReferences {
  int? dimension;
  @override
  Future<AdminPage> loadNextPage({bool reset = false}) async => AdminPage(
    businesses: const [AdminBusiness(id: 'local', name: 'Local dinámico')],
    reviews: [
      AdminReview(
        id: 'zero',
        businessId: 'local',
        rating: 0,
        serviceRating: dimension,
        foodRating: dimension,
        createdAt: DateTime.now().toUtc().subtract(const Duration(days: 1)),
      ),
    ],
  );
}

void main() {
  testWidgets('trend uses daily means, zero-to-five axes and actual day gaps', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: AdminDashboardScreen(repository: SparseTrendReferences()),
      ),
    );
    await tester.pumpAndSettle();
    final chart = tester.widget<LineChart>(find.byType(LineChart)).data;
    expect(chart.minY, 0);
    expect(chart.maxY, 5);
    expect(chart.minX, 0);
    expect(chart.maxX, 7);
    expect(chart.lineBarsData.single.spots.map((s) => s.x), [0.0, 3.0, 7.0]);
    expect(chart.lineBarsData.single.spots.map((s) => s.y), [2.0, 0.0, 5.0]);
    expect(chart.lineBarsData.single.isCurved, false);
    expect(tester.takeException(), isNull);
  });
  testWidgets('missing dimension semantics differ from an actual zero rating', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final semantics = tester.ensureSemantics();
    try {
      final repo = MissingDimensionReferences();
      await tester.pumpWidget(
        MaterialApp(home: AdminDashboardScreen(repository: repo)),
      );
      await tester.pumpAndSettle();
      Finder dimension(String label) => find.byWidgetPredicate(
        (w) => w is LinearProgressIndicator && w.semanticsLabel == label,
      );
      for (final label in ['Servicio', 'Alimentos']) {
        await tester.ensureVisible(dimension(label));
        await tester.pumpAndSettle();
        expect(
          tester.getSemantics(dimension(label)).getSemanticsData().value,
          'Sin valoraciones',
        );
      }
      repo.dimension = 0;
      await tester.tap(find.byTooltip('Actualizar datos'));
      await tester.pumpAndSettle();
      for (final label in ['Servicio', 'Alimentos']) {
        await tester.ensureVisible(dimension(label));
        await tester.pumpAndSettle();
        expect(
          tester.getSemantics(dimension(label)).getSemanticsData().value,
          '0%',
        );
      }
      expect(tester.takeException(), isNull);
    } finally {
      semantics.dispose();
    }
  });
  testWidgets(
    'career chart uses readable names and preserves separate identities',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: AdminDashboardScreen(repository: CareerIdentityReferences()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Carrera vigente'), findsNWidgets(2));
      expect(find.text('Carrera histórica'), findsOneWidget);
      expect(find.text('2.0 ★ · 2'), findsOneWidget);
      expect(find.text('5.0 ★ · 1'), findsOneWidget);
      expect(find.text('Nombre anterior'), findsNothing);
      expect(find.textContaining('career-a'), findsNothing);
      expect(find.textContaining('career-b'), findsNothing);
      expect(find.textContaining('Datos autodeclarados'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  test(
    'master access is explicit, bound to admin role, and changes session identity',
    () {
      final plain = PortalAccount.fromJson({
        'id': 'a',
        'displayName': 'A',
        'role': 'admin',
      });
      final master = PortalAccount.fromJson({
        'id': 'a',
        'displayName': 'A',
        'role': 'admin',
        'isMaster': true,
      });
      expect(plain.canManageAccounts, false);
      expect(master.canManageAccounts, true);
      expect(plain.identity, isNot(master.identity));
      expect(
        const PortalAccount(
          id: 'b',
          role: 'business',
          displayName: 'B',
          isMaster: true,
        ).canManageAccounts,
        false,
      );
      expect(configuration.acceptsAdminEmail(' Persona@UTSJR.EDU.MX '), true);
      expect(
        configuration.acceptsAdminEmail('persona@utsjr.edu.mx.evil.example'),
        false,
      );
    },
  );
  test('same group name in two careers remains isolated by identifiers', () {
    expect(directory().groups(null), isEmpty);
    expect(
      directory().groups('software').keys,
      containsAll(['software-1', 'software-100']),
    );
    expect(directory().groups('software').keys, isNot(contains('admin-1')));
    final filter = AdminFilter(
      careerId: 'software',
      groupId: 'software-1',
      period: AdminPeriod.all,
    );
    expect(
      filter.matches(
        const AdminReview(
          id: 'r',
          businessId: 'b',
          careerId: 'admin',
          groupId: 'admin-1',
          group: 'Grupo 1',
        ),
        DateTime.now(),
      ),
      false,
    );
    expect(
      () => AcademicDirectory(const [
        AcademicEntry(
          id: 'orphan',
          name: '1',
          kind: 'group',
          careerId: 'missing',
        ),
      ]),
      throwsA(isA<ApiException>()),
    );
  });
  testWidgets(
    'choose a career first, search a group with no ratings, and update real chart points',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = LiveReferences();
      await tester.pumpWidget(
        MaterialApp(home: AdminDashboardScreen(repository: repo)),
      );
      await tester.pumpAndSettle();
      Finder picker(String name) =>
          find.byWidgetPredicate((w) => w is AcademicPicker && w.label == name);
      expect(tester.widget<AcademicPicker>(picker('Grupo')).enabled, false);
      expect(
        tester
            .widget<LineChart>(find.byType(LineChart))
            .data
            .lineBarsData
            .single
            .spots
            .map((s) => s.y),
        [2.0, 2.0],
      );
      repo.rating = 5;
      await tester.tap(find.byTooltip('Actualizar datos'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<LineChart>(find.byType(LineChart))
            .data
            .lineBarsData
            .single
            .spots
            .map((s) => s.y),
        [5.0, 5.0],
      );
      await tester.ensureVisible(picker('Carrera'));
      await tester.tap(picker('Carrera'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Desarrollo de Software').last);
      await tester.pumpAndSettle();
      expect(tester.widget<AcademicPicker>(picker('Grupo')).enabled, true);
      await tester.tap(picker('Grupo'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Buscar grupo'),
        'DSM-100',
      );
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Grupo 1'),
        ),
        findsNothing,
      );
      await tester.tap(find.text('DSM-100 sin opiniones'));
      await tester.pumpAndSettle();
      expect(
        find.text('No hay opiniones que coincidan con los filtros.'),
        findsOneWidget,
      );
      expect(find.byType(LineChart), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
