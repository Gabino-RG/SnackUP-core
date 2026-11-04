/// Aggregates delivered orders. Dates supplied by the Firestore adapter are UTC.
/// Money is a recorded order total, not confirmation from a payment processor.
class BusinessMetrics {
  BusinessMetrics.fromOrders(
    Iterable<Map<String, dynamic>> orders, {
    required DateTime now,
  }) {
    final today = campusDate(now);
    final firstDay = today.subtract(const Duration(days: 6));
    final tomorrow = today.add(const Duration(days: 1));
    for (final order in orders) {
      if (order['status'] != 'completed') continue;
      totalOrders++;
      final rawPrice = order['totalPrice'];
      final price = rawPrice is num && rawPrice.isFinite && rawPrice >= 0
          ? rawPrice.toDouble()
          : 0.0;
      totalRevenue += price;
      final method = order['paymentMethod'] is String
          ? order['paymentMethod'] as String
          : 'Sin registrar';
      paymentMethods.update(method, (count) => count + 1, ifAbsent: () => 1);
      final items = order['items'];
      if (items is List) {
        for (final item in items.whereType<Map>()) {
          final quantity = item['quantity'];
          final name = item['name'];
          if (name is! String ||
              name.trim().isEmpty ||
              quantity is! int ||
              quantity <= 0) {
            continue;
          }
          topItems.update(
            name,
            (count) => count + quantity,
            ifAbsent: () => quantity,
          );
        }
      }
      final date = order['completedAt'] ?? order['createdAt'];
      if (date is! DateTime) continue;
      final day = campusDate(date);
      if (!day.isBefore(firstDay) && day.isBefore(tomorrow)) {
        salesByDay[day.weekday] = salesByDay[day.weekday]! + price;
      }
    }
  }

  double totalRevenue = 0;
  int totalOrders = 0;
  final Map<String, int> paymentMethods = {};
  final Map<String, int> topItems = {};
  final Map<int, double> salesByDay = {
    1: 0,
    2: 0,
    3: 0,
    4: 0,
    5: 0,
    6: 0,
    7: 0,
  };

  static DateTime campusDate(DateTime instant) {
    final local = instant.toUtc().subtract(const Duration(hours: 6));
    return DateTime.utc(local.year, local.month, local.day);
  }
}
