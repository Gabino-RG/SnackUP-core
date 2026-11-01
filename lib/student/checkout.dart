import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Contains purchase intent only: never tokens, pickup codes or a full order DTO.
class CheckoutIntent {
  final String businessId;
  final String key;
  final Map<String, dynamic> payload;
  final List<Map<String, dynamic>> cartSnapshot;
  final String createdAt;
  final String? orderId;

  const CheckoutIntent({
    required this.businessId,
    required this.key,
    required this.payload,
    required this.cartSnapshot,
    required this.createdAt,
    this.orderId,
  });

  bool get confirmed => orderId != null;

  Map<String, dynamic> toJson() => {
    'businessId': businessId,
    'key': key,
    'payload': payload,
    'cartSnapshot': cartSnapshot,
    'createdAt': createdAt,
    if (orderId != null) 'orderId': orderId,
  };

  factory CheckoutIntent.fromJson(Map<String, dynamic> json) => CheckoutIntent(
    businessId: json['businessId'] as String,
    key: json['key'] as String,
    payload: Map<String, dynamic>.from(json['payload'] as Map),
    cartSnapshot: (json['cartSnapshot'] as List)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList(),
    createdAt: json['createdAt'] as String,
    orderId: json['orderId'] as String?,
  );

  CheckoutIntent withOrder(String id) => CheckoutIntent(
    businessId: businessId,
    key: key,
    payload: payload,
    cartSnapshot: cartSnapshot,
    createdAt: createdAt,
    orderId: id,
  );
}

abstract class CheckoutStorage {
  Future<Map<String, dynamic>> read(String namespace);
  Future<void> put(
    String namespace,
    String businessId,
    Map<String, dynamic> value,
  );
  Future<void> remove(String namespace, String businessId);
}

class PreferencesCheckoutStorage implements CheckoutStorage {
  String _name(String namespace) =>
      'snackup.checkout.v1.${sha256.convert(utf8.encode(namespace))}.';

  String _entry(String namespace, String businessId) =>
      _name(namespace) + sha256.convert(utf8.encode(businessId)).toString();

  @override
  Future<Map<String, dynamic>> read(String namespace) async {
    final preferences = await SharedPreferences.getInstance();
    // Reload because another tab may have completed this purchase.
    await preferences.reload();
    final values = <String, dynamic>{};
    for (final key in preferences.getKeys().where(
      (key) => key.startsWith(_name(namespace)),
    )) {
      final raw = preferences.getString(key);
      if (raw == null) continue;
      final decoded = jsonDecode(raw);
      if (decoded is! Map || decoded['businessId'] is! String) {
        throw const FormatException(
          'No se pudo leer la compra pendiente. Revisa tus pedidos antes de comprar otra vez.',
        );
      }
      values[decoded['businessId'] as String] = Map<String, dynamic>.from(
        decoded,
      );
    }
    return values;
  }

  @override
  Future<void> put(
    String namespace,
    String businessId,
    Map<String, dynamic> value,
  ) async {
    final preferences = await SharedPreferences.getInstance();
    final saved = await preferences.setString(
      _entry(namespace, businessId),
      jsonEncode(value),
    );
    if (!saved) {
      throw StateError(
        'No se pudo conservar la compra de forma segura en este dispositivo.',
      );
    }
  }

  @override
  Future<void> remove(String namespace, String businessId) async {
    final preferences = await SharedPreferences.getInstance();
    if (!await preferences.remove(_entry(namespace, businessId))) {
      throw StateError('No se pudo actualizar la compra guardada.');
    }
  }
}

dynamic _canonical(dynamic value) {
  if (value is Map) {
    final keys = value.keys.map((key) => key.toString()).toList()..sort();
    return {for (final key in keys) key: _canonical(value[key])};
  }
  if (value is List) return value.map(_canonical).toList();
  return value;
}

String _stableJson(dynamic value) => jsonEncode(_canonical(value));

List<Map<String, dynamic>> checkoutSnapshot(List<Map<String, dynamic>> rows) {
  final snapshot = rows
      .map(
        (row) => <String, dynamic>{
          'id': row['id'],
          'productId': row['productId'],
          'quantity': row['quantity'],
          'notes': row['notes'] ?? '',
          'updatedAt': row['updatedAt'],
        },
      )
      .toList();
  snapshot.sort((a, b) => (a['id'] as String).compareTo(b['id'] as String));
  return snapshot;
}

/// A deterministic UUID v8 makes simultaneous tabs share the same purchase key.
/// Recreating or editing a server cart row changes its id/updatedAt and the key.
String checkoutKey(
  String namespace,
  Map<String, dynamic> payload,
  List<Map<String, dynamic>> rows,
) {
  final bytes = sha256
      .convert(
        utf8.encode(
          _stableJson({
            'account': namespace,
            'payload': payload,
            'cart': checkoutSnapshot(rows),
          }),
        ),
      )
      .bytes
      .take(16)
      .toList();
  bytes[6] = (bytes[6] & 15) | 128;
  bytes[8] = (bytes[8] & 63) | 128;
  final hex = bytes
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

/// Purchased cart rows are removable only while their full saved state matches.
List<String> unchangedPurchasedRows(
  CheckoutIntent intent,
  List<Map<String, dynamic>> current,
) {
  final byId = {
    for (final row in checkoutSnapshot(current)) row['id'] as String: row,
  };
  return intent.cartSnapshot
      .where(
        (old) =>
            byId.containsKey(old['id']) &&
            _stableJson(old) == _stableJson(byId[old['id']]),
      )
      .map((row) => row['id'] as String)
      .toList();
}

class CheckoutPendingException implements Exception {
  const CheckoutPendingException();
  @override
  String toString() =>
      'Hay una compra pendiente de confirmar para este negocio. '
      'Resuelve ese intento con su misma clave antes de hacer otro.';
}

class CheckoutLedger {
  final CheckoutStorage storage;
  final String namespace;
  static final Set<String> _sending = {};

  CheckoutLedger({required this.storage, required this.namespace});

  Future<Map<String, CheckoutIntent>> intents() async {
    final stored = await storage.read(namespace);
    return stored.map(
      (id, value) => MapEntry(
        id,
        CheckoutIntent.fromJson(Map<String, dynamic>.from(value as Map)),
      ),
    );
  }

  Future<CheckoutIntent> prepare({
    required String businessId,
    required Map<String, dynamic> payload,
    required List<Map<String, dynamic>> rows,
  }) async {
    final values = await intents();
    final previous = values[businessId];
    if (previous != null) {
      if (_stableJson(previous.payload) != _stableJson(payload) ||
          _stableJson(previous.cartSnapshot) !=
              _stableJson(checkoutSnapshot(rows))) {
        throw const CheckoutPendingException();
      }
      return previous;
    }
    if (values.length >= 20) {
      throw StateError(
        'Resuelve las compras pendientes antes de iniciar otra.',
      );
    }
    final intent = CheckoutIntent(
      businessId: businessId,
      key: checkoutKey(namespace, payload, rows),
      payload: Map<String, dynamic>.from(
        jsonDecode(jsonEncode(payload)) as Map,
      ),
      cartSnapshot: checkoutSnapshot(rows),
      createdAt: DateTime.now().toUtc().toIso8601String(),
    );
    // Each business has a separate storage key, so tabs checking out different
    // businesses cannot overwrite each other's unresolved purchase.
    await storage.put(namespace, businessId, intent.toJson());
    return intent;
  }

  Future<CheckoutIntent> send(
    CheckoutIntent intent,
    Future<Map<String, dynamic>> Function(
      Map<String, dynamic> payload,
      String key,
    )
    sender,
  ) async {
    final lock = '$namespace:${intent.businessId}';
    if (!_sending.add(lock)) throw const CheckoutPendingException();
    try {
      final current = (await intents())[intent.businessId];
      if (current == null || current.key != intent.key) {
        throw const CheckoutPendingException();
      }
      if (current.confirmed) return current;
      final result = await sender(current.payload, current.key);
      final id = result['id'];
      if (id is! String || id.isEmpty) {
        throw const FormatException(
          'La respuesta del pedido no pudo confirmarse. Reintenta el mismo intento.',
        );
      }
      final confirmed = current.withOrder(id);
      await storage.put(namespace, current.businessId, confirmed.toJson());
      return confirmed;
    } finally {
      _sending.remove(lock);
    }
  }

  /// Only call after a definitive server rejection or confirmed cart cleanup.
  Future<void> forget(CheckoutIntent intent) async {
    final values = await intents();
    if (values[intent.businessId]?.key == intent.key) {
      await storage.remove(namespace, intent.businessId);
    }
  }
}
