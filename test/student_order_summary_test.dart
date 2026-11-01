import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snackup/student/order_summary.dart';
import 'package:snackup/theme/student_colors.dart';

void main() {
  testWidgets(
    'pending and accepted share received step while preparation and ready advance it',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final state in {
        'pending': 0,
        'accepted': 0,
        'preparing': 1,
        'ready': 2,
      }.entries) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(16),
                child: StudentOrderSummary(
                  order: {
                    'id': 'order',
                    'orderNumber': 2,
                    'status': state.key,
                    'total': 25,
                    'items': [
                      {'name': 'Agua', 'quantity': 1},
                    ],
                  },
                  onTap: () {},
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('1 producto en total'), findsOneWidget);
        for (var step = 0; step < 3; step++) {
          final container = tester.widget<Container>(
            find.byKey(ValueKey('order-progress-$step')),
          );
          expect(
            (container.decoration as BoxDecoration).color,
            step <= state.value ? AppColors.primary : Colors.white,
          );
        }
        expect(tester.takeException(), isNull);
      }
    },
  );
}
