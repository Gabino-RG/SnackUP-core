import '../api/api_client.dart';

Map<String, dynamic> object(dynamic value) {
  if (value is! Map)
    throw const ApiException(
      'El servidor devolvió datos incompletos.',
      code: 'INVALID_RESPONSE',
    );
  return Map<String, dynamic>.from(value);
}

Map<String, dynamic> resource(dynamic value) {
  final data = object(value);
  return data['data'] is Map ? object(data['data']) : data;
}

String requiredText(Map<String, dynamic> data, String key) {
  final value = data[key];
  if (value is! String || value.trim().isEmpty)
    throw ApiException('Falta el campo $key.', code: 'INVALID_RESPONSE');
  return value;
}

int integer(Map<String, dynamic> data, String key, {int minimum = 0}) {
  final value = data[key];
  if (value is! int || value < minimum)
    throw ApiException('El campo $key no es válido.', code: 'INVALID_RESPONSE');
  return value;
}

int cents(dynamic value) {
  if (value is! num || !value.isFinite || value < 0)
    throw const ApiException(
      'El importe no es válido.',
      code: 'INVALID_RESPONSE',
    );
  return (value * 100).round();
}

String money(int value) => '\$${(value / 100).toStringAsFixed(2)}';
DateTime campusNow() =>
    DateTime.now().toUtc().subtract(const Duration(hours: 6));
String dayKey(DateTime day) =>
    '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
String campusStamp(DateTime? date) {
  if (date == null) return 'Sin fecha';
  final d = date.toUtc().subtract(const Duration(hours: 6));
  return '${dayKey(d)} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

class BusinessRecord {
  BusinessRecord.fromJson(dynamic value) {
    final d = resource(value);
    id = requiredText(d, 'id');
    name = requiredText(d, 'name');
    category = d['category'] as String? ?? '';
    description = d['description'] as String? ?? '';
    timezone = d['timezone'] as String? ?? 'America/Mexico_City';
    version = integer(d, 'version', minimum: 1);
    if (d['isOpen'] is! bool)
      throw const ApiException(
        'Falta el estado del local.',
        code: 'INVALID_RESPONSE',
      );
    isOpen = d['isOpen'] as bool;
    isActive = d['isActive'] != false;
  }
  late final String id, name, category, description, timezone;
  late final int version;
  late final bool isOpen, isActive;
}

enum KitchenStatus { pending, accepted, preparing, ready, completed, cancelled }

extension KitchenStatusText on KitchenStatus {
  String get label => switch (this) {
    KitchenStatus.pending => 'Nuevo',
    KitchenStatus.accepted => 'Aceptado',
    KitchenStatus.preparing => 'En preparación',
    KitchenStatus.ready => 'Listo',
    KitchenStatus.completed => 'Entregado',
    KitchenStatus.cancelled => 'Cancelado',
  };
  bool get active =>
      this != KitchenStatus.completed && this != KitchenStatus.cancelled;
  bool get canCancel => [
    KitchenStatus.pending,
    KitchenStatus.accepted,
    KitchenStatus.preparing,
  ].contains(this);
  String? get action => switch (this) {
    KitchenStatus.pending => 'accept',
    KitchenStatus.accepted => 'start',
    KitchenStatus.preparing => 'ready',
    KitchenStatus.ready => 'complete',
    _ => null,
  };
  String? get button => switch (this) {
    KitchenStatus.pending => 'Aceptar pedido',
    KitchenStatus.accepted => 'Iniciar preparación',
    KitchenStatus.preparing => 'Marcar listo',
    KitchenStatus.ready => 'Verificar entrega',
    _ => null,
  };
}

const cancelReasons = {
  'product_unavailable': 'Producto agotado',
  'cannot_prepare': 'No se puede preparar',
  'store_issue': 'Problema en el local',
  'store_closing': 'Cierre del local',
  'other': 'Otro motivo',
};

class KitchenItem {
  KitchenItem.fromJson(dynamic value) {
    final d = object(value);
    name = requiredText(d, 'name');
    quantity = integer(d, 'quantity', minimum: 1);
    priceCents = cents(d['price']);
    notes = d['notes'] as String? ?? '';
  }
  late final String name, notes;
  late final int quantity, priceCents;
}

class KitchenOrder {
  KitchenOrder.fromJson(dynamic value) {
    final d = resource(value);
    id = requiredText(d, 'id');
    businessId = requiredText(d, 'businessId');
    number = integer(d, 'orderNumber', minimum: 1);
    version = integer(d, 'version', minimum: 1);
    final code = d['status'];
    if (!KitchenStatus.values.any((s) => s.name == code))
      throw const ApiException(
        'Estado de pedido desconocido.',
        code: 'INVALID_RESPONSE',
      );
    status = KitchenStatus.values.firstWhere((s) => s.name == code);
    customer = d['customerName'] as String? ?? 'Cliente';
    payment = d['paymentMethod'] as String? ?? '';
    totalCents = cents(d['total']);
    if (d['items'] is! List || (d['items'] as List).isEmpty)
      throw const ApiException(
        'El pedido no tiene productos.',
        code: 'INVALID_RESPONSE',
      );
    items = (d['items'] as List)
        .map(KitchenItem.fromJson)
        .toList(growable: false);
    createdAt = DateTime.tryParse(requiredText(d, 'createdAt'))?.toUtc();
    if (createdAt == null)
      throw const ApiException(
        'La fecha del pedido no es válida.',
        code: 'INVALID_RESPONSE',
      );
    scheduledAt = DateTime.tryParse(d['scheduledPickupTime'] as String? ?? '');
    cancelReason = d['cancelReason'] as String?;
    cancelNotes = d['cancelNotes'] as String?;
    // Never retain pickupCode or the student's fixed control number in the kitchen.
  }
  late final String id, businessId, customer, payment;
  late final String? cancelReason, cancelNotes;
  late final int number, version, totalCents;
  late final KitchenStatus status;
  late final List<KitchenItem> items;
  late final DateTime? createdAt, scheduledAt;
}

class OperationsPage<T> {
  const OperationsPage(
    this.items, {
    required this.page,
    required this.totalPages,
    required this.total,
  });
  final List<T> items;
  final int page, totalPages, total;
  bool get hasMore => page < totalPages;
}

class SalesSummary {
  SalesSummary.fromJson(dynamic value) {
    final d = object(value);
    completed = integer(d, 'completed');
    cancelled = integer(d, 'cancelled');
    totalCents = cents(d['totalSold']);
  }
  late final int completed, cancelled, totalCents;
}

class OrderHistory {
  const OrderHistory(this.orders, this.summary);
  final OperationsPage<KitchenOrder> orders;
  final SalesSummary summary;
}

class PortalUser {
  PortalUser.fromJson(dynamic value) {
    final d = resource(value);
    id = requiredText(d, 'id');
    email = requiredText(d, 'email');
    name = requiredText(d, 'displayName');
    role = requiredText(d, 'role');
    businessId = d['businessId'] as String?;
    isActive = d['isActive'] != false;
    version = integer(d, 'version', minimum: 1);
  }
  late final String id, email, name, role;
  late final String? businessId;
  late final bool isActive;
  late final int version;
}
