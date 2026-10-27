import '../api/api_client.dart';
import 'models.dart';
import 'portal_configuration.dart';

/// Kitchen and administration DTOs served under /api/legacy/v1/.
class OperationsRepository {
  OperationsRepository(this.api);
  final ApiClient api;
  Future<PortalConfiguration> configuration() async =>
      PortalConfiguration.fromJson(await api.json('GET', 'institution'));
  String segment(String id) => Uri.encodeComponent(id);
  OperationsPage<T> page<T>(dynamic value, T Function(dynamic) parse) {
    final d = object(value), p = object(object(value)['pagination']);
    if (d['data'] is! List)
      throw const ApiException(
        'La lista está incompleta.',
        code: 'INVALID_RESPONSE',
      );
    return OperationsPage(
      (d['data'] as List).map(parse).toList(),
      page: integer(p, 'page', minimum: 1),
      totalPages: integer(p, 'totalPages'),
      total: integer(p, 'total'),
    );
  }

  KitchenOrder scopedOrder(dynamic value, String businessId) {
    final o = KitchenOrder.fromJson(value);
    if (o.businessId != businessId)
      throw const ApiException(
        'El pedido pertenece a otro local.',
        code: 'INVALID_RESPONSE',
      );
    return o;
  }

  Future<BusinessRecord> business(String id) async {
    final b = BusinessRecord.fromJson(
      await api.json('GET', 'businesses/${segment(id)}'),
    );
    if (b.id != id)
      throw const ApiException(
        'El servidor devolvió otro local.',
        code: 'INVALID_RESPONSE',
      );
    return b;
  }

  Future<BusinessRecord> setOpen(BusinessRecord b, bool open) async =>
      BusinessRecord.fromJson(
        await api.json(
          'PATCH',
          'businesses/${segment(b.id)}/status',
          body: {'isOpen': open, 'expectedVersion': b.version},
        ),
      );
  Future<BusinessRecord> editBusiness(
    BusinessRecord b, {
    required String name,
    required String description,
    required String category,
  }) async => BusinessRecord.fromJson(
    await api.json(
      'PATCH',
      'businesses/${segment(b.id)}',
      body: {
        'name': name.trim(),
        'description': description.trim(),
        'category': category.trim(),
        'expectedVersion': b.version,
      },
    ),
  );

  Future<List<KitchenOrder>> active(String businessId) async {
    final result = <String, KitchenOrder>{};
    for (var n = 1; n <= 50; n++) {
      final response = await api.json(
        'GET',
        'businesses/${segment(businessId)}/orders/active',
        query: {'page': '$n', 'limit': '200'},
      );
      final d = response is List ? {'data': response} : object(response);
      if (d['data'] is! List)
        throw const ApiException(
          'La lista de pedidos está incompleta.',
          code: 'INVALID_RESPONSE',
        );
      for (final row in d['data'] as List) {
        final order = scopedOrder(row, businessId);
        if (!order.status.active) continue;
        final previous = result[order.id];
        if (previous == null || order.version > previous.version)
          result[order.id] = order;
      }
      if (d['pagination'] == null) break;
      final p = object(d['pagination']);
      if (integer(p, 'page', minimum: 1) != n)
        throw const ApiException(
          'La paginación de pedidos no coincide.',
          code: 'INVALID_RESPONSE',
        );
      if (n >= integer(p, 'totalPages')) break;
      if (n == 50)
        throw const ApiException(
          'Hay demasiados pedidos para cargar el tablero. Contacta a soporte.',
          code: 'CAPACITY',
        );
    }
    return result.values.toList()
      ..sort((a, b) => a.createdAt!.compareTo(b.createdAt!));
  }

  Future<KitchenOrder> order(String id, String businessId) async =>
      scopedOrder(await api.json('GET', 'orders/${segment(id)}'), businessId);
  Future<KitchenOrder> act(
    KitchenOrder order,
    String action, {
    String? method,
    String? code,
    String? reason,
    String? notes,
  }) async {
    if (action == 'cancel') {
      if (!order.status.canCancel ||
          !cancelReasons.containsKey(reason) ||
          (reason == 'other' && (notes?.trim().isEmpty ?? true))) {
        throw const ApiException(
          'Indica un motivo válido. Los pedidos listos ya no se pueden cancelar.',
          code: 'INVALID_CANCEL_REASON',
        );
      }
    } else if (action != order.status.action) {
      throw const ApiException(
        'Esta acción no corresponde al estado actual.',
        code: 'INVALID_STATUS_TRANSITION',
      );
    }
    if (action == 'complete' &&
        (!['qr', 'manual'].contains(method) ||
            (code?.trim().isEmpty ?? true))) {
      throw const ApiException(
        'Verifica el código del cliente antes de entregar.',
        code: 'VERIFICATION_REQUIRED',
      );
    }
    final result = scopedOrder(
      await api.json(
        'POST',
        'orders/${segment(order.id)}/$action',
        body: {
          'expectedVersion': order.version,
          if (action == 'complete') ...{'method': method, 'code': code!.trim()},
          if (action == 'cancel') ...{
            'reason': reason,
            if (notes?.trim().isNotEmpty ?? false) 'notes': notes!.trim(),
          },
        },
      ),
      order.businessId,
    );
    if (result.id != order.id || result.version <= order.version)
      throw const ApiException(
        'Actualiza el pedido para comprobar el resultado.',
        code: 'INVALID_RESPONSE',
      );
    return result;
  }

  Future<OrderHistory> history(
    String businessId,
    String date, {
    int number = 1,
  }) async {
    final d = object(
      await api.json(
        'GET',
        'businesses/${segment(businessId)}/orders/history',
        query: {'date': date, 'page': '$number', 'limit': '30'},
      ),
    );
    // v3 permits an unpaginated daily list; paginated servers use the same envelope as other collections.
    final rows = d['data'];
    if (rows is! List)
      throw const ApiException(
        'El historial está incompleto.',
        code: 'INVALID_RESPONSE',
      );
    final orders = d['pagination'] != null
        ? page(d, (r) => scopedOrder(r, businessId))
        : OperationsPage(
            rows.map((r) => scopedOrder(r, businessId)).toList(),
            page: 1,
            totalPages: 1,
            total: rows.length,
          );
    return OrderHistory(orders, SalesSummary.fromJson(d['summary']));
  }

  Future<SalesSummary> stats(String businessId, String from, String to) async =>
      SalesSummary.fromJson(
        resource(
          await api.json(
            'GET',
            'businesses/${segment(businessId)}/stats',
            query: {'from': from, 'to': to},
          ),
        ),
      );
  Future<OperationsPage<BusinessRecord>> businesses({
    int number = 1,
    String search = '',
  }) async => page(
    await api.json(
      'GET',
      'admin/businesses',
      query: {'page': '$number', 'limit': '20', 'q': search},
    ),
    BusinessRecord.fromJson,
  );
  Future<BusinessRecord> saveBusiness(
    Map<String, dynamic> input, {
    BusinessRecord? previous,
  }) async => BusinessRecord.fromJson(
    await api.json(
      previous == null ? 'POST' : 'PATCH',
      previous == null
          ? 'admin/businesses'
          : 'admin/businesses/${segment(previous.id)}',
      body: {
        ...input,
        if (previous != null) 'expectedVersion': previous.version,
      },
    ),
  );
  Future<OperationsPage<PortalUser>> users({
    int number = 1,
    String search = '',
  }) async => page(
    await api.json(
      'GET',
      'admin/users',
      query: {'page': '$number', 'limit': '20', 'q': search},
    ),
    PortalUser.fromJson,
  );
  Future<PortalUser> saveUser(
    Map<String, dynamic> input, {
    PortalUser? previous,
  }) async => PortalUser.fromJson(
    await api.json(
      previous == null ? 'POST' : 'PATCH',
      previous == null ? 'admin/users' : 'admin/users/${segment(previous.id)}',
      body: {
        ...input,
        if (previous != null) 'expectedVersion': previous.version,
      },
    ),
  );
}
