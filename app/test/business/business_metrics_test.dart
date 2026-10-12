import 'package:flutter_test/flutter_test.dart';
import 'package:snackup/features/business/business_metrics.dart';

void main() {
  final now = DateTime.utc(2026, 10, 5, 2); // October 4 in Querétaro.

  test('totals include only delivered orders and tolerate legacy fields', () {
    final metrics = BusinessMetrics.fromOrders([
      {
        'status': 'completed',
        'totalPrice': 50,
        'items': [
          {'name': 'Taco', 'quantity': 2},
        ],
        'paymentMethod': 'Efectivo',
      },
      {
        'status': 'completed',
        'totalPrice': 25.5,
        'items': [
          {'name': 'Taco', 'quantity': 1},
          {'name': 'Bad', 'quantity': -1},
        ],
      },
      {'status': 'cancelled', 'totalPrice': 999},
      {'status': 'ready', 'totalPrice': 999},
    ], now: now);
    expect(metrics.totalRevenue, 75.5);
    expect(metrics.totalOrders, 2);
    expect(metrics.topItems, {'Taco': 3});
    expect(metrics.paymentMethods, {'Efectivo': 1, 'Sin registrar': 1});
  });

  test(
    'seven calendar days includes boundary, uses completedAt and excludes future',
    () {
      final metrics = BusinessMetrics.fromOrders([
        {
          'status': 'completed',
          'totalPrice': 10,
          'createdAt': DateTime.utc(2026, 9, 28, 6),
        },
        {
          'status': 'completed',
          'totalPrice': 20,
          'createdAt': DateTime.utc(2026, 9, 28, 5, 59),
        },
        {
          'status': 'completed',
          'totalPrice': 30,
          'createdAt': DateTime.utc(2026, 9, 1),
          'completedAt': DateTime.utc(2026, 10, 4, 20),
        },
        {
          'status': 'completed',
          'totalPrice': 40,
          'createdAt': DateTime.utc(2026, 10, 5, 6),
        },
      ], now: now);
      expect(metrics.salesByDay[DateTime.monday], 10);
      expect(metrics.salesByDay[DateTime.sunday], 30);
      expect(metrics.salesByDay.values.reduce((a, b) => a + b), 40);
      expect(BusinessMetrics.campusDate(now), DateTime.utc(2026, 10, 4));
    },
  );

  test('non-finite and negative values cannot break chart axes', () {
    final metrics = BusinessMetrics.fromOrders([
      {'status': 'completed', 'totalPrice': double.nan},
      {'status': 'completed', 'totalPrice': double.infinity},
      {'status': 'completed', 'totalPrice': -30},
    ], now: now);
    expect(metrics.totalRevenue, 0);
    expect(metrics.salesByDay.values.every((value) => value == 0), isTrue);
  });
}
