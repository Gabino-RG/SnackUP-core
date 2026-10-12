import 'package:flutter_test/flutter_test.dart';
import 'package:snackup/features/business/business_order_workflow.dart';

void main() {
  test('only allowed state edges can change an order', () {
    const states = ['pending', 'preparing', 'ready', 'completed', 'cancelled'];
    const allowed = {
      'pending:preparing',
      'pending:cancelled',
      'preparing:ready',
      'preparing:cancelled',
      'ready:completed',
    };
    for (final from in states) {
      for (final to in states) {
        expect(
          canTransitionBusinessOrder(from, to),
          allowed.contains('$from:$to'),
          reason: '$from → $to',
        );
      }
    }
  });

  test(
    'QR ties code to this order and rejects student number or another order',
    () {
      final order = {
        'status': 'ready',
        'pickupCode': 'unique-code',
        'userNumeroDeControl': '12345',
      };
      expect(
        deliveryQrForOrder('order-a', order),
        'snackup:order-a:unique-code',
      );
      for (final input in ['12345', '', 'snackup:order-b:unique-code']) {
        expect(
          () => validateBusinessOrderTransition(
            orderId: 'order-a',
            order: order,
            newStatus: 'completed',
            deliveryCode: input,
          ),
          throwsStateError,
        );
      }
      for (final input in ['unique-code', 'snackup:order-a:unique-code']) {
        expect(
          () => validateBusinessOrderTransition(
            orderId: 'order-a',
            order: order,
            newStatus: 'completed',
            deliveryCode: input,
          ),
          returnsNormally,
        );
      }
    },
  );

  test('legacy order uses its own ID and cannot complete twice', () {
    expect(deliveryQrForOrder('legacy', {'status': 'ready'}), 'snackup:legacy');
    expect(
      () => validateBusinessOrderTransition(
        orderId: 'legacy',
        order: {'status': 'ready'},
        newStatus: 'completed',
        deliveryCode: 'snackup:legacy',
      ),
      returnsNormally,
    );
    expect(
      () => validateBusinessOrderTransition(
        orderId: 'legacy',
        order: {'status': 'completed'},
        newStatus: 'completed',
        deliveryCode: 'legacy',
      ),
      throwsStateError,
    );
  });

  test(
    'stock reservation rejects invalid or repeated lines and double reservation',
    () {
      Map<String, dynamic> line(String id, dynamic qty) => {
        'productId': id,
        'quantity': qty,
      };
      expect(
        stockQuantitiesForOrder({
          'items': [line('a', 2), line('b', 1)],
        }),
        {'a': 2, 'b': 1},
      );
      for (final items in [
        [],
        [line('a', -1)],
        [line('a', 100)],
        [line('a', 1.5)],
        [line('a', 1), line('a', 2)],
        [line('bad/id', 1)],
        List.generate(9, (i) => line('$i', 1)),
      ]) {
        expect(
          () => stockQuantitiesForOrder({'items': items}),
          throwsStateError,
        );
      }
      expect(
        () => stockQuantitiesForOrder({
          'stockReserved': true,
          'items': [line('a', 1)],
        }),
        throwsStateError,
      );
    },
  );
}
