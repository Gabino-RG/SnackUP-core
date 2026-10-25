import 'package:characters/characters.dart';
import 'api_client.dart';

bool apiProductAvailable(Json product) =>
    product['isAvailable'] == true &&
    (product['stock'] == null ||
        (product['stock'] is num && (product['stock'] as num) > 0));
String resourceId(String value) => Uri.encodeComponent(value);

class StudentRepository {
  final ApiClient api;
  StudentRepository(this.api);
  Future<List<Json>> pages(
    String path, {
    bool legacy = false,
    Map<String, String>? query,
  }) async {
    final result = <Json>[];
    int page = 1;
    while (true) {
      final response = await api.request(
        'GET',
        path,
        legacy: legacy,
        query: {...?query, 'page': '$page', 'limit': '100'},
      );
      final rows = response['data'];
      final pagination = response['pagination'];
      if (rows is! List ||
          pagination is! Map ||
          pagination['totalPages'] is! num) {
        throw const ApiException(
          'INVALID_RESPONSE',
          'La lista de la API tiene un formato inesperado.',
        );
      }
      result.addAll(rows.map((row) => Map<String, dynamic>.from(row as Map)));
      if (page >= (pagination['totalPages'] as num).toInt()) break;
      if (++page > 10000)
        throw const ApiException(
          'INVALID_PAGINATION',
          'La API devolvió demasiadas páginas.',
        );
    }
    return result;
  }

  Future<List<Json>> businesses() => pages('businesses');
  Future<List<Json>> products(String businessId) => pages(
    'businesses/${resourceId(businessId)}/products',
    query: {'isAvailable': 'true'},
  );
  Future<Json> product(String id) =>
      api.request('GET', 'products/${resourceId(id)}');
  Future<Json> order(String id) =>
      api.request('GET', 'orders/${resourceId(id)}');
  // V3 does not have the student's full history. Its documented legacy endpoint
  // uses the same SQL records, sessions and authorization, not a second database.
  Future<List<Json>> history() => pages('student/orders', legacy: true);
  Future<List<Json>> activeOrders() => pages('users/me/orders/active');
  Future<List<Json>> reviews(String id) =>
      pages('products/${resourceId(id)}/reviews');
  Future<Json> createOrder(Json body, String key) => api.request(
    'POST',
    'orders',
    body: body,
    headers: {'Idempotency-Key': key},
  );
  Future<Json> cancel(Json order) => api.request(
    'POST',
    'orders/${resourceId(order['id'] as String)}/cancel',
    body: {'expectedVersion': order['version'], 'reason': 'user_other'},
  );
  Future<void> rate(
    String orderId,
    int rating,
    String comment, {
    String? productId,
  }) async {
    if (rating < 1 || rating > 5 || comment.characters.length > 300) {
      throw const ApiException(
        'INVALID_REVIEW',
        'Selecciona de 1 a 5 estrellas y escribe hasta 300 caracteres.',
      );
    }
    await api.request(
      'POST',
      'orders/${resourceId(orderId)}/${productId == null ? 'rating' : 'reviews'}',
      body: productId == null
          ? {'rating': rating, 'comment': comment.trim()}
          : {
              'reviews': [
                {
                  'productId': productId,
                  'rating': rating,
                  'comment': comment.trim(),
                },
              ],
            },
    );
  }
}
