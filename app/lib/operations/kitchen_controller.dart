import 'dart:async';
import 'package:flutter/foundation.dart';
import '../api/api_client.dart';
import 'models.dart';
import 'operations_repository.dart';

class KitchenController extends ChangeNotifier {
  KitchenController(this.repository, this.businessId);
  final OperationsRepository repository;
  final String businessId;
  BusinessRecord? business;
  List<KitchenOrder> orders = [];
  String? error;
  DateTime? lastSync;
  bool loading = false, closed = false, stale = true, updatingBusiness = false;
  final busy = <String>{};
  final _seen = <String>{};
  bool _initialized = false;
  int newCount = 0, _revision = 0;
  VoidCallback? onNewOrders;
  Future<void> refresh() async {
    if (loading || closed) return;
    final revision = _revision;
    loading = true;
    notifyListeners();
    try {
      final result = await Future.wait<dynamic>([
        repository.business(businessId),
        repository.active(businessId),
      ]);
      if (closed || revision != _revision) return;
      final next = result[1] as List<KitchenOrder>;
      final fresh = _initialized
          ? next
                .where(
                  (o) =>
                      o.status == KitchenStatus.pending &&
                      !_seen.contains(o.id),
                )
                .length
          : 0;
      _seen.addAll(next.map((o) => o.id));
      _initialized = true;
      business = result[0] as BusinessRecord;
      orders = next;
      stale = false;
      error = null;
      lastSync = DateTime.now();
      if (fresh > 0) {
        newCount += fresh;
        onNewOrders?.call();
      }
    } catch (e) {
      if (!closed) {
        stale = true;
        error = operationsMessage(e);
      }
    } finally {
      if (!closed) {
        loading = false;
        notifyListeners();
      }
    }
  }

  void acknowledge() {
    if (!closed && newCount != 0) {
      newCount = 0;
      notifyListeners();
    }
  }

  Future<void> setOpen(bool value) async {
    if (business == null || updatingBusiness || stale) return;
    _revision++;
    updatingBusiness = true;
    notifyListeners();
    try {
      await repository.setOpen(business!, value);
    } finally {
      if (!closed) {
        updatingBusiness = false;
        await refresh();
      }
    }
  }

  Future<void> act(
    KitchenOrder order,
    String action, {
    String? method,
    String? code,
    String? reason,
    String? notes,
  }) async {
    if (closed || busy.contains(order.id)) return;
    if (stale)
      throw const ApiException(
        'Actualiza el tablero antes de modificar un pedido.',
      );
    _revision++;
    busy.add(order.id);
    notifyListeners();
    try {
      final updated = await repository.act(
        order,
        action,
        method: method,
        code: code,
        reason: reason,
        notes: notes,
      );
      if (!closed) {
        orders = [
          for (final o in orders)
            if (o.id != updated.id) o,
          if (updated.status.active) updated,
        ]..sort((a, b) => a.createdAt!.compareTo(b.createdAt!));
      }
    } on ApiException catch (e) {
      if ([
        'VERSION_CONFLICT',
        'INVALID_STATUS_TRANSITION',
        'TIMEOUT',
        'NETWORK',
      ].contains(e.code))
        await refresh();
      rethrow;
    } finally {
      if (!closed) {
        busy.remove(order.id);
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    closed = true;
    super.dispose();
  }
}

String operationsMessage(Object e) {
  if (e is ApiException)
    return switch (e.code) {
      'VERIFICATION_FAILED' =>
        'El código no coincide. Pide al cliente su código de este pedido.',
      'VERSION_CONFLICT' =>
        'Otro dispositivo actualizó este registro. Revisa la información actual antes de repetir.',
      'INVALID_STATUS_TRANSITION' =>
        'El pedido ya cambió de estado. Revisa el tablero actualizado.',
      'LAST_ADMIN' => 'Debe quedar al menos una cuenta administrativa activa.',
      'EMAIL_EXISTS' => 'Ya existe una cuenta con ese correo.',
      'BUSINESS_HAS_ACTIVE_ORDERS' =>
        'Termina los pedidos activos antes de desactivar el local.',
      _ => e.message,
    };
  return 'No se pudo completar la operación. Actualiza para comprobar el resultado antes de repetir.';
}
