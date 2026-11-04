import '../api/api_client.dart';
import 'models.dart';

/// Canonical DTOs are deliberately separate from the legacy portal contract.
class V32Repository {
  V32Repository(this.api);
  final ApiClient api;
  String id(String value) => Uri.encodeComponent(value);
  Future<Map<String, dynamic>> business(String businessId) async {
    final result = object(
      await api.json('GET', 'businesses/${id(businessId)}'),
    );
    if (result['id'] != businessId)
      throw const ApiException('El servidor devolvió otro local.');
    integer(result, 'version', minimum: 1);
    return result;
  }

  Future<void> closing(
    String businessId,
    int version,
    bool enabled,
    String? time,
  ) async {
    await api.json(
      'PATCH',
      'businesses/${id(businessId)}/closing-schedule',
      body: {
        'expectedVersion': version,
        'autoCloseEnabled': enabled,
        'closeTimeLocal': time,
      },
    );
  }

  Future<void> postpone(String businessId, int version, DateTime until) async {
    await api.json(
      'POST',
      'businesses/${id(businessId)}/postpone-closing',
      body: {
        'expectedVersion': version,
        'until': until.toUtc().toIso8601String(),
      },
    );
  }

  Future<void> timeout(String businessId, int version, int minutes) async {
    await api.json(
      'PATCH',
      'businesses/${id(businessId)}',
      body: {'expectedVersion': version, 'pickupTimeoutMinutes': minutes},
    );
  }

  Future<Map<String, dynamic>> chats(String businessId, int page) async =>
      object(
        await api.json(
          'GET',
          'businesses/${id(businessId)}/chats',
          query: {'page': '$page', 'limit': '20'},
        ),
      );
  Future<Map<String, dynamic>> openChat(
    String businessId,
    String orderId,
  ) async => object(
    await api.json(
      'POST',
      'businesses/${id(businessId)}/chats',
      body: {'orderId': orderId},
    ),
  );
  Future<List<Map<String, dynamic>>> messages(String chatId) async {
    final rows = <Map<String, dynamic>>[];
    // The server caps each conversation at 1,000 messages. Include all pages so
    // a conversation longer than the first page continues receiving replies.
    for (var page = 1; page <= 10; page++) {
      final result = object(
        await api.json(
          'GET',
          'chats/${id(chatId)}/messages',
          query: {'page': '$page', 'limit': '100'},
        ),
      );
      rows.addAll((result['data'] as List).map(object));
      if (page >= integer(object(result['pagination']), 'totalPages'))
        return rows;
    }
    throw const ApiException('La conversación excede el límite de mensajes.');
  }

  Future<void> send(String chatId, String text) async {
    await api.json(
      'POST',
      'chats/${id(chatId)}/messages',
      body: {'text': text.trim()},
    );
  }

  Future<void> closeChat(String chatId) async {
    await api.json('DELETE', 'chats/${id(chatId)}');
  }

  Future<Map<String, dynamic>> orders(
    String businessId, {
    String? date,
    int page = 1,
  }) async => object(
    await api.json(
      'GET',
      'businesses/${id(businessId)}/orders/${date == null ? 'active' : 'history'}',
      query: {'page': '$page', 'limit': '30', if (date != null) 'date': date},
    ),
  );
  Future<void> notCollected(
    Map<String, dynamic> order, {
    required bool voucherNotRedeemed,
  }) async {
    await api.json(
      'POST',
      'orders/${id(requiredText(order, 'id'))}/cancel',
      body: {
        'expectedVersion': integer(order, 'version', minimum: 1),
        'reason': 'not_picked_up',
        'voucherNotRedeemed': voucherNotRedeemed,
      },
    );
  }

  Future<void> releaseVoucher(Map<String, dynamic> order) async {
    await api.json(
      'POST',
      'orders/${id(requiredText(order, 'id'))}/meal-voucher/release',
      body: {
        'expectedVersion': integer(order, 'version', minimum: 1),
        'notRedeemed': true,
      },
    );
  }

  Future<Map<String, dynamic>> stats(
    String businessId,
    String from,
    String to,
  ) async => object(
    await api.json(
      'GET',
      'businesses/${id(businessId)}/stats',
      query: {'from': from, 'to': to},
    ),
  );
}

String v32Message(Object error) {
  if (error is! ApiException)
    return 'No se pudo completar la operación. Actualiza antes de repetir.';
  return switch (error.code) {
    'CHAT_NOT_FOUND' =>
      'La conversación terminó o venció. Su contenido ya no está disponible.',
    'CHAT_MESSAGE_LIMIT' =>
      'La conversación alcanzó 1,000 mensajes. Ciérrala antes de abrir otra.',
    'PICKUP_TIMEOUT_NOT_REACHED' =>
      'Todavía no vence el plazo de recogida. Actualiza el pedido más tarde.',
    'INVALID_POSTPONEMENT' =>
      'Elige una hora futura de hoy, posterior al cierre vigente.',
    'CLOSING_ALREADY_PROCESSED' =>
      'El cierre de hoy ya se ejecutó. La reapertura debe hacerse manualmente.',
    'CLOSING_NOT_CONFIGURED' => 'Activa y guarda primero el cierre automático.',
    'VERSION_CONFLICT' =>
      'El registro cambió. Se necesita actualizar antes de guardar otra vez.',
    'MEAL_VOUCHER_CONSUMED' =>
      'Un vale ya consumido no se puede liberar.',
    'MEAL_VOUCHER_NOT_FOUND' => 'Este pedido no tiene un vale registrado.',
    'ORDER_NOT_CANCELLED' => 'Solo puedes liberar el vale de un pedido cancelado.',
    _ => error.message,
  };
}
