/// Shared business-side validation. Firestore rules enforce the same state graph.
bool canTransitionBusinessOrder(String from, String to) => switch (from) {
  'pending' => to == 'preparing' || to == 'cancelled',
  'preparing' => to == 'ready' || to == 'cancelled',
  'ready' => to == 'completed',
  _ => false,
};

/// Accepting an order reserves its stock exactly once, in the same transaction.
Map<String, int> stockQuantitiesForOrder(Map<String, dynamic> order) {
  final items = order['items'];
  if (items is! List ||
      items.isEmpty ||
      items.length > 8 ||
      order['stockReserved'] == true) {
    throw StateError('El pedido no tiene productos válidos para reservar.');
  }
  final quantities = <String, int>{};
  for (final item in items) {
    if (item is! Map) {
      throw StateError('El pedido contiene un producto inválido.');
    }
    final id = item['productId'];
    final quantity = item['quantity'];
    if (id is! String ||
        id.isEmpty ||
        id.contains('/') ||
        quantity is! int ||
        quantity < 1 ||
        quantity > 99 ||
        quantities.containsKey(id)) {
      throw StateError(
        'El pedido contiene productos repetidos o cantidades inválidas.',
      );
    }
    quantities[id] = quantity;
  }
  return quantities;
}

String deliveryCodeForOrder(String orderId, Map<String, dynamic> order) {
  final code = order['pickupCode'];
  return code is String && code.trim().isNotEmpty ? code : orderId;
}

String deliveryQrForOrder(String orderId, Map<String, dynamic> order) {
  final code = order['pickupCode'];
  return code is String && code.trim().isNotEmpty
      ? 'snackup:$orderId:$code'
      : 'snackup:$orderId';
}

void validateBusinessOrderTransition({
  required String orderId,
  required Map<String, dynamic> order,
  required String newStatus,
  String? deliveryCode,
}) {
  final current = order['status'];
  if (current is! String || !canTransitionBusinessOrder(current, newStatus)) {
    throw StateError('El estado del pedido cambió. Revisa su estado actual.');
  }
  if (newStatus == 'completed' &&
      (deliveryCode == null ||
          (deliveryCode.trim() != deliveryCodeForOrder(orderId, order) &&
              deliveryCode.trim() != deliveryQrForOrder(orderId, order)))) {
    throw StateError('El código de entrega no corresponde a este pedido.');
  }
}
