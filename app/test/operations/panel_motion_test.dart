import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snackup/features/admin/admin_theme.dart';
import 'package:snackup/features/admin/panel_motion.dart';

void main() {
  testWidgets('entrance finishes and polling does not replay it', (
    tester,
  ) async {
    final tick = ValueNotifier(0);
    addTearDown(tick.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: ValueListenableBuilder<int>(
          valueListenable: tick,
          builder: (_, value, __) => PanelEntrance(
            key: const ValueKey('same-section'),
            child: Text('Refresh $value'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    tick.value++;
    await tester.pump();
    expect(tester.widget<Opacity>(find.byType(Opacity)).opacity, 1);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('reduced motion has no entrance shift or event glow', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: PanelEntrance(
            child: PanelSignal(active: true, child: Text('Pedido nuevo')),
          ),
        ),
      ),
    );
    expect(tester.widget<Opacity>(find.byType(Opacity)).opacity, 1);
    expect(
      tester.widget<Transform>(find.byType(Transform)).transform.storage[13],
      0,
    );
    final decoration =
        tester.widget<DecoratedBox>(find.byType(DecoratedBox)).decoration
            as BoxDecoration;
    expect(decoration.boxShadow, isEmpty);
    await tester.pump(); // Flush MaterialApp's initial layout notification.
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets(
    'animated button keeps one action per tap and disabled behavior',
    (tester) async {
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: adminTheme(),
          home: Scaffold(
            body: Column(
              children: [
                FilledButton(
                  onPressed: () => calls++,
                  child: const Text('Aceptar'),
                ),
                const FilledButton(onPressed: null, child: Text('Desactivado')),
              ],
            ),
          ),
        ),
      );
      final press = await tester.startGesture(
        tester.getCenter(find.text('Aceptar')),
      );
      await tester.pump(const Duration(milliseconds: 160));
      final scale = tester.widget<AnimatedScale>(
        find.ancestor(
          of: find.text('Aceptar'),
          matching: find.byType(AnimatedScale),
        ),
      );
      expect(scale.scale, .96);
      await press.up();
      await tester.pumpAndSettle();
      expect(calls, 1);
      await tester.tap(find.text('Desactivado'));
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(tester.takeException(), isNull);
    },
  );
}
