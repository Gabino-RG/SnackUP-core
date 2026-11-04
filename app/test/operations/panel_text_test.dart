import 'package:flutter_test/flutter_test.dart';
import 'package:snackup/operations/models.dart';
import 'package:snackup/operations/panel_text.dart';
import 'operations_repository_test.dart' show orderData;

void main() {
  test(
    'payment labels preserve backend order values and Spanish legacy values',
    () {
      const labels = {
        'cash': 'Efectivo',
        'card': 'Tarjeta',
        'voucher': 'Vale de comida',
        'Efectivo': 'Efectivo',
        'Tarjeta': 'Tarjeta',
        'Transferencia': 'Transferencia',
        'ValeComida': 'Vale de comida',
        'Vale': 'Vale',
      };
      for (final entry in labels.entries) {
        final payload = {...orderData(), 'paymentMethod': entry.key};
        final order = KitchenOrder.fromJson(payload);
        expect(paymentLabel(order.payment), entry.value, reason: entry.key);
        expect(order.payment, entry.key);
        expect(payload['paymentMethod'], entry.key);
      }
    },
  );

  test('missing and unknown payment values do not invent a payment method', () {
    expect(paymentLabel(null), 'Sin especificar');
    expect(paymentLabel(''), 'Sin especificar');
    expect(paymentLabel('transfer'), 'transfer');
    expect(paymentLabel('new-provider-method'), 'new-provider-method');
  });
}
