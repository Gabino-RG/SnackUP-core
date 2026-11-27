import 'package:flutter_test/flutter_test.dart';
import 'package:snackup/features/delivery_qr.dart';

void main() {
  const firstOrder = 'order-AutoId-001';
  const secondOrder = 'order-AutoId-002';

  test('accepts the QR generated for the current order', () {
    final payload = deliveryQrPayload(firstOrder);
    expect(payload, 'snackup:order:$firstOrder');
    expect(matchesDeliveryQr(payload, firstOrder), isTrue);
  });

  test('rejects a QR belonging to another order', () {
    expect(matchesDeliveryQr(deliveryQrPayload(secondOrder), firstOrder), isFalse);
  });

  test('rejects the former student control number QR', () {
    expect(matchesDeliveryQr('2023143096', firstOrder), isFalse);
  });

  test('rejects an unprefixed order ID as a scanned QR', () {
    expect(matchesDeliveryQr(firstOrder, firstOrder), isFalse);
  });

  test('rejects empty scanned values and empty order IDs', () {
    expect(matchesDeliveryQr('', firstOrder), isFalse);
    expect(matchesDeliveryQr('snackup:order:', ''), isFalse);
    expect(matchesDeliveryQr('', ''), isFalse);
    expect(matchesDeliveryQr('snackup:order:   ', '   '), isFalse);
    expect(() => deliveryQrPayload(''), throwsArgumentError);
    expect(() => deliveryQrPayload('   '), throwsArgumentError);
  });
}
