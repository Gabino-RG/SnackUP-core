import 'dart:convert';

const maxOrderLines = 8;
const maxOrderQuantity = 99;

class OrderFlowException implements Exception {
  final String message;
  const OrderFlowException(this.message);
}

int productPriceCents(Map<String, dynamic> product) {
  final price = product['price'];
  if (price is! num || !price.isFinite || price <= 0 || price > 10000) {
    throw const OrderFlowException(
      'El local debe corregir el precio de este producto antes de venderlo.',
    );
  }
  final canonical = product['priceCents'];
  final cents = canonical ?? (price * 100 + 0.5).toInt();
  if (cents is! int || cents <= 0 || cents > 1000000 || price != cents / 100) {
    throw const OrderFlowException(
      'El local debe actualizar el precio de este producto.',
    );
  }
  return cents;
}

int validQuantity(Object? value) {
  if (value is! int || value < 1 || value > maxOrderQuantity) {
    throw const OrderFlowException('La cantidad debe ser de 1 a 99 unidades.');
  }
  return value;
}

String validProductId(Object? value) {
  if (value is! String || value.isEmpty || value.contains('/')) {
    throw const OrderFlowException('Hay un producto inválido en el carrito.');
  }
  return value;
}

String validNotes(Object? value) {
  final notes = value is String ? value.trim() : '';
  if (notes.runes.length > 500) {
    throw const OrderFlowException(
      'Las instrucciones deben tener hasta 500 caracteres.',
    );
  }
  return notes;
}

void validateProductForOrder(Map<String, dynamic> product, int quantity) {
  validQuantity(quantity);
  final stock = product['stock'];
  if (product['isAvailable'] != true || stock is! int || stock < quantity) {
    final name = product['name'] is String ? product['name'] : 'Este producto';
    throw OrderFlowException(
      '$name no tiene disponibilidad para $quantity unidades.',
    );
  }
  productPriceCents(product);
}

DateTime? validatePickupTime(DateTime? requested, DateTime now) {
  if (requested != null &&
      (!requested.isAfter(now) ||
          requested.isAfter(now.add(const Duration(hours: 24))))) {
    throw const OrderFlowException(
      'Elige una hora futura, dentro de las próximas 24 horas.',
    );
  }
  return requested;
}

class CheckoutQuote {
  final String businessId;
  final List<String> cartIds;
  final List<Map<String, dynamic>> items;
  final int totalCents;
  const CheckoutQuote({
    required this.businessId,
    required this.cartIds,
    required this.items,
    required this.totalCents,
  });
  double get totalPrice => totalCents / 100;
  String get signature => jsonEncode([businessId, cartIds, items, totalCents]);
}

/// Prices and business identity always come from the current product catalog.
/// Cart values supply only product IDs, requested quantities and instructions.
CheckoutQuote buildCheckoutQuote({
  required Map<String, Map<String, dynamic>> cart,
  required Map<String, Map<String, dynamic>> products,
  required Map<String, dynamic> business,
}) {
  if (cart.isEmpty || cart.length > maxOrderLines) {
    throw const OrderFlowException(
      'El pedido debe tener de 1 a 8 productos distintos.',
    );
  }
  if (business['isOpen'] != true) {
    throw const OrderFlowException(
      'El local está cerrado y no recibe pedidos.',
    );
  }
  final ids = cart.keys.toList()..sort();
  final productIds = <String>{};
  final items = <Map<String, dynamic>>[];
  String? businessId;
  var totalCents = 0;
  for (final cartId in ids) {
    final line = cart[cartId]!;
    final productId = validProductId(line['productId']);
    if (!productIds.add(productId)) {
      throw const OrderFlowException(
        'El carrito contiene el mismo producto más de una vez.',
      );
    }
    final product = products[productId];
    if (product == null) {
      throw const OrderFlowException(
        'Un producto ya no existe. Retíralo del carrito.',
      );
    }
    final quantity = validQuantity(line['quantity']);
    validateProductForOrder(product, quantity);
    final local = product['businessId'];
    if (local is! String ||
        local.isEmpty ||
        (businessId != null && businessId != local)) {
      throw const OrderFlowException('Haz un pedido separado para cada local.');
    }
    businessId = local;
    final name = product['name'];
    if (name is! String || name.trim().isEmpty || name.runes.length > 160) {
      throw const OrderFlowException('Un producto no tiene un nombre válido.');
    }
    final cents = productPriceCents(product);
    totalCents += cents * quantity;
    items.add({
      'productId': productId,
      'name': name,
      'quantity': quantity,
      'price': cents / 100,
      'unitPriceCents': cents,
      'notes': validNotes(line['notes']),
    });
  }
  return CheckoutQuote(
    businessId: businessId!,
    cartIds: ids,
    items: items,
    totalCents: totalCents,
  );
}

String pickupQrData(String orderId, Map<String, dynamic> order) {
  final code = order['pickupCode'];
  return code is String && code.isNotEmpty
      ? 'snackup:$orderId:$code'
      : 'snackup:$orderId';
}
