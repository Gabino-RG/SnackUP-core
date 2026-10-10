import 'dart:convert';
import 'dart:typed_data';
import 'catalog.dart';

/// Storage is injected: no credentials or production data belong in this store.
abstract class CatalogStore {
  Future<String?> read();
  Future<void> write(String value);
}

class MemoryCatalogStore implements CatalogStore {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String value) async { this.value = value; }
}

class LocalCatalogRepository extends CatalogRepository {
  LocalCatalogRepository(this.store);
  final CatalogStore store;
  Future<void> _tail = Future<void>.value();
  @override
  bool get isLocal => true;

  Future<List<CatalogProduct>> _read() async {
    final raw = await store.read();
    if (raw != null) {
      try {
        return (jsonDecode(raw) as List)
            .map((e) => CatalogProduct.fromJson(Map<String, dynamic>.from(e as Map))).toList();
      } catch (_) {
        throw const CatalogException('No se pudo leer el catálogo local. Conservamos tus datos; no se reiniciaron.');
      }
    }
    return [
      for (var local = 1; local <= 4; local++)
        for (var item = 0; item < 3; item++)
          CatalogProduct(
            id: 'ejemplo-$local-$item', businessId: 'local_$local', version: 1,
            updatedAt: DateTime.utc(2026, 10, 10),
            draft: ProductDraft(
              name: ['Torta', 'Agua', 'Café'][item],
              description: ['Torta preparada al momento', 'Agua natural de 600 ml', 'Café americano'][item],
              category: ['Alimentos', 'Bebidas', 'Bebidas'][item],
              priceCents: [3500, 1500, 2000][item],
            ),
          ),
    ];
  }

  Future<T> _serialize<T>(Future<T> Function() action) {
    final next = _tail.then((_) => action());
    _tail = next.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return next;
  }

  @override
  Future<CatalogPage> list(String businessId, {CatalogQuery query = const CatalogQuery()}) async =>
      paginateCatalog((await _read()).where((p) => p.businessId == businessId).toList(), query);

  @override
  Future<CatalogProduct> get(String businessId, String id) async {
    final matches = (await _read()).where((p) => p.id == id && p.businessId == businessId);
    if (matches.isEmpty) throw const CatalogException('El producto ya no existe.', code: 'NOT_FOUND');
    return matches.first;
  }

  void _check(CatalogProduct current, CatalogProduct original) {
    if (current.businessId != original.businessId) {
      throw const CatalogException('El producto pertenece a otro local.', code: 'FORBIDDEN');
    }
    if (current.version != original.version) {
      throw const CatalogException('El producto cambió. Recarga antes de guardar.', code: 'VERSION_CONFLICT');
    }
  }

  @override
  Future<CatalogProduct> save(String businessId, ProductDraft draft, {CatalogProduct? original}) =>
      _serialize(() async {
        draft.validate();
        if (original != null && original.businessId != businessId) {
          throw const CatalogException('El producto pertenece a otro local.', code: 'FORBIDDEN');
        }
        final rows = await _read();
        var index = -1;
        if (original != null) {
          index = rows.indexWhere((p) => p.id == original.id && p.businessId == businessId);
          if (index < 0) throw const CatalogException('El producto ya no existe.', code: 'NOT_FOUND');
          _check(rows[index], original);
        }
        final product = CatalogProduct.fromJson({
          ...draft.toJson(),
          'id': original?.id ?? 'local-${DateTime.now().microsecondsSinceEpoch}',
          'businessId': businessId, 'version': (original?.version ?? 0) + 1,
          'updatedAt': DateTime.now().toUtc().toIso8601String(),
        });
        if (index < 0) { rows.add(product); } else { rows[index] = product; }
        // Report success only after storage accepted the write.
        try {
          await store.write(jsonEncode(rows.map((p) => p.toJson()).toList()));
        } catch (_) {
          throw const CatalogException('No se pudo guardar en este dispositivo. Revisa el espacio disponible.');
        }
        return product;
      });

  @override
  Future<void> delete(CatalogProduct product) => _serialize(() async {
    final rows = await _read();
    final index = rows.indexWhere((p) => p.id == product.id && p.businessId == product.businessId);
    if (index < 0) throw const CatalogException('El producto ya no existe.', code: 'NOT_FOUND');
    _check(rows[index], product);
    rows.removeAt(index);
    await store.write(jsonEncode(rows.map((p) => p.toJson()).toList()));
  });

  @override
  Future<String> uploadImage(String businessId, Uint8List bytes, String fileName) async {
    validateProductImage(bytes, fileName);
    final ext = fileName.split('.').last.toLowerCase();
    final type = ext == 'jpg' ? 'jpeg' : ext;
    return 'data:image/$type;base64,${base64Encode(bytes)}';
  }
}
