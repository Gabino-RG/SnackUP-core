import 'package:cloud_firestore/cloud_firestore.dart';

class ReviewService {
  final FirebaseFirestore firestore;
  ReviewService(this.firestore);

  Future<void> save({
    required String orderId,
    String? productId,
    required String userId,
    required int rating,
    required String comment,
    required bool anonymous,
    required String userName,
  }) async {
    if (rating < 1 || rating > 5 || comment.trim().length > 300) {
      throw StateError(
        'Selecciona de 1 a 5 estrellas y escribe hasta 300 caracteres.',
      );
    }
    final orderRef = firestore.collection('orders').doc(orderId);
    final reviewRef = firestore
        .collection(productId == null ? 'restaurant_reviews' : 'reviews')
        .doc(productId == null ? orderId : '${orderId}_$productId');
    await firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(orderRef);
      final order = snapshot.data();
      if (order == null ||
          order['userId'] != userId ||
          order['status'] != 'completed') {
        throw StateError('Solo puedes valorar tus pedidos entregados.');
      }
      final items = (order['items'] as List? ?? []).whereType<Map>();
      final matches = items.where((item) => item['productId'] == productId);
      if (productId != null && matches.isEmpty)
        throw StateError('El platillo no pertenece al pedido.');
      transaction.set(reviewRef, {
        'orderId': orderId,
        'type': productId == null ? 'restaurant' : 'product',
        if (productId != null) 'productId': productId,
        if (productId != null)
          'productName': matches.first['name'] ?? 'Platillo',
        'businessId': order['businessId'],
        'userId': userId,
        'userName': anonymous ? 'Estudiante anónimo' : userName,
        'anonymous': anonymous,
        'rating': rating,
        'comment': comment.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }
}
