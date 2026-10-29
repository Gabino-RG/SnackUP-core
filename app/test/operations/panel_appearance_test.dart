import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:snackup/api/rest_session.dart';
import 'package:snackup/features/admin/admin_theme.dart';
import 'package:snackup/features/admin/panel_appearance.dart';
import 'package:snackup/features/admin/admin_dashboard_screen.dart';
import 'package:snackup/features/admin/data/demo_admin_repository.dart';
import 'package:snackup/features/portal/rest_portal_app.dart';
import 'package:snackup/features/operations/v32_screens.dart';
import 'responsive_v32_test.dart' show ResponsiveRepository;

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('last appearance choice is restored after rapid toggles', () async {
    final appearance = PanelAppearance();
    await appearance.restore();
    expect(appearance.dark, isFalse);
    appearance.toggle();
    appearance.toggle();
    appearance.toggle();
    await appearance.saved;
    appearance.dispose();
    final restored = PanelAppearance();
    await restored.restore();
    expect(restored.dark, isTrue);
    restored.dispose();
  });

  testWidgets('switch keeps login draft and persists without a backend write', (
    tester,
  ) async {
    final session = RestSession(
      baseUri: Uri.parse('https://test.example/api/legacy/v1/'),
      client: MockClient((request) async {
        expect(request.method, 'GET');
        return http.Response(
          '{"passwordLogin":true,"selfRegistration":false,"googleEnabled":false}',
          200,
        );
      }),
    );
    addTearDown(session.dispose);
    session.invalidate('');
    await tester.pumpWidget(
      RestPortalApp(session: session, restoreOnStart: false),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('portal-email')),
      'operator@example.edu',
    );
    await tester.tap(find.byTooltip('Activar modo oscuro'));
    await tester.pumpAndSettle();
    expect(
      Theme.of(
        tester.element(find.byKey(const ValueKey('portal-email'))),
      ).brightness,
      Brightness.dark,
    );
    expect(
      tester
          .widget<TextFormField>(find.byKey(const ValueKey('portal-email')))
          .controller!
          .text,
      'operator@example.edu',
    );
    expect(
      (await SharedPreferences.getInstance()).getBool(
        PanelAppearance.preferenceKey,
      ),
      isTrue,
    );
    await tester.tap(find.byTooltip('Activar modo claro'));
    await tester.pumpAndSettle();
    expect(
      Theme.of(
        tester.element(find.byKey(const ValueKey('portal-email'))),
      ).brightness,
      Brightness.light,
    );
    expect(tester.takeException(), isNull);
  });

  for (final size in [const Size(390, 844), const Size(1440, 1000)]) {
    testWidgets('dark administration and operation fit $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = ResponsiveRepository();
      for (final view in <Widget>[
        AdminDashboardScreen(repository: DemoAdminRepository()),
        ClosingScreen(repository: repo, businessId: 'b'),
        KitchenChatScreen(repository: repo, businessId: 'b', orderId: 'o'),
        DetailedStatsScreen(repository: repo, businessId: 'b'),
      ]) {
        await tester.pumpWidget(
          MaterialApp(
            theme: adminDarkTheme(),
            home: Scaffold(body: view),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          Theme.of(tester.element(find.byWidget(view))).brightness,
          Brightness.dark,
        );
        expect(tester.takeException(), isNull);
      }
    });
  }

  test('dark palette keeps readable text and button contrast', () {
    final theme = adminDarkTheme(), scheme = adminDarkTheme().colorScheme;
    double contrast(Color a, Color b) {
      final x = a.computeLuminance(), y = b.computeLuminance();
      return ((x > y ? x : y) + .05) / ((x > y ? y : x) + .05);
    }

    for (final text in [
      scheme.onSurface,
      scheme.onSurfaceVariant,
      scheme.secondary,
      scheme.error,
    ]) {
      for (final surface in [
        scheme.surface,
        scheme.surfaceContainer,
        theme.scaffoldBackgroundColor,
      ]) {
        expect(contrast(text, surface), greaterThanOrEqualTo(4.5));
      }
    }
    expect(
      contrast(
        theme.filledButtonTheme.style!.foregroundColor!.resolve({})!,
        theme.filledButtonTheme.style!.backgroundColor!.resolve({})!,
      ),
      greaterThanOrEqualTo(4.5),
    );
  });
}
