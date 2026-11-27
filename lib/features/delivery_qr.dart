/// Identifies the order being collected. Authorization remains in Firestore
/// rules; this payload is an order reference, not a secret credential.
String deliveryQrPayload(String orderId) {
  if (orderId.trim().isEmpty) {
    throw ArgumentError.value(orderId, 'orderId', 'An order ID is required');
  }
  return 'snackup:order:$orderId';
}

bool matchesDeliveryQr(String payload, String orderId) {
  return orderId.trim().isNotEmpty && payload == deliveryQrPayload(orderId);
}
