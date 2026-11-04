import 'dart:typed_data';
import 'package:flutter/widgets.dart';

class CatalogException implements Exception {
  const CatalogException(this.message, {this.code = 'CATALOG_ERROR'});
  final String message, code;
  @override
  String toString() => message;
}

/// Decimal input becomes integer cents without floating-point rounding.
int? parsePriceCents(String input) {
  final text = input.trim().replaceAll(',', '.');
  if (!RegExp(r'^\d{1,5}(\.\d{1,2})?$').hasMatch(text)) return null;
  final parts = text.split('.');
  final cents = int.parse(parts.first) * 100 +
      (parts.length == 2 ? int.parse(parts.last.padRight(2, '0')) : 0);
  return cents > 0 && cents <= 1000000 ? cents : null;
}

class ProductDraft {
  const ProductDraft({
    required this.name,
    required this.description,
    required this.category,
    required this.priceCents,
    this.stock,
    this.imageUrl,
    this.isAvailable = true,
    this.isFeatured = false,
  });
  final String name, description, category;
  final int priceCents;
  final int? stock;
  final String? imageUrl;
  final bool isAvailable, isFeatured;

  void validate() {
    if (name.trim().isEmpty || name.trim().length > 160) {
      throw const CatalogException('Escribe un nombre de 1 a 160 caracteres.');
    }
    if (category.trim().isEmpty || category.trim().length > 120) {
      throw const CatalogException('Escribe una categoría de 1 a 120 caracteres.');
    }
    if (description.length > 2000) {
      throw const CatalogException('La descripción admite hasta 2000 caracteres.');
    }
    if (priceCents <= 0 || priceCents > 1000000) {
      throw const CatalogException('El precio debe estar entre \$0.01 y \$10,000.00.');
    }
    if (stock != null && (stock! < 0 || stock! > 1000000)) {
      throw const CatalogException('Las existencias deben ser un entero de 0 a 1,000,000.');
    }
  }

  Map<String, dynamic> toJson() => {
    'name': name.trim(), 'description': description.trim(),
    'category': category.trim(), 'price': priceCents / 100,
    'stock': stock, 'imageUrl': imageUrl,
    'isAvailable': stock == 0 ? false : isAvailable,
    'isFeatured': isFeatured,
  };
}

class CatalogProduct {
  const CatalogProduct({
    required this.id, required this.businessId, required this.draft,
    required this.version, required this.updatedAt,
  });
  final String id, businessId;
  final ProductDraft draft;
  final int version;
  final DateTime updatedAt;

  factory CatalogProduct.fromJson(Map<String, dynamic> json) {
    final rawPrice = json['price'];
    if (rawPrice is! num || !rawPrice.isFinite) {
      throw const CatalogException('El servidor devolvió un precio inválido.');
    }
    final version = json['version'];
    final stock = json['stock'];
    if (json['id'] is! String || json['businessId'] is! String ||
        version is! int || (stock != null && stock is! int)) {
      throw const CatalogException('El servidor devolvió un producto incompleto.');
    }
    final draft = ProductDraft(
      name: json['name'] as String, description: json['description'] as String? ?? '',
      category: json['category'] as String, priceCents: (rawPrice * 100).round(),
      stock: stock as int?, imageUrl: json['imageUrl'] as String?,
      isAvailable: json['isAvailable'] as bool, isFeatured: json['isFeatured'] as bool? ?? false,
    );
    draft.validate();
    return CatalogProduct(
      id: json['id'] as String, businessId: json['businessId'] as String,
      draft: draft, version: version,
      updatedAt: DateTime.parse(json['updatedAt'] as String).toUtc(),
    );
  }

  Map<String, dynamic> toJson() => {
    ...draft.toJson(), 'id': id, 'businessId': businessId,
    'version': version, 'updatedAt': updatedAt.toUtc().toIso8601String(),
  };
}

void validateProductImage(Uint8List bytes, String name) {
  final ext = name.split('.').last.toLowerCase();
  if (!['jpg', 'jpeg', 'png', 'webp'].contains(ext) ||
      bytes.isEmpty || bytes.length > 5 * 1024 * 1024) {
    throw const CatalogException('Selecciona una imagen JPG, PNG o WebP de hasta 5 MB.');
  }
  final jpeg = bytes.length > 2 && bytes[0] == 255 && bytes[1] == 216 && bytes[2] == 255;
  final png = bytes.length >= 8 &&
      bytes.take(8).join(',') == '137,80,78,71,13,10,26,10';
  final webp = bytes.length >= 12 &&
      String.fromCharCodes(bytes.take(4)) == 'RIFF' &&
      String.fromCharCodes(bytes.skip(8).take(4)) == 'WEBP';
  if (!((['jpg', 'jpeg'].contains(ext) && jpeg) ||
      (ext == 'png' && png) || (ext == 'webp' && webp))) {
    throw const CatalogException('El archivo no corresponde al formato de imagen indicado.');
  }
}

class CatalogQuery {
  const CatalogQuery({this.page = 1, this.limit = 20, this.search = '', this.available});
  final int page, limit;
  final String search;
  final bool? available;
}

class CatalogPage {
  const CatalogPage({required this.items, required this.total, required this.page, required this.totalPages});
  final List<CatalogProduct> items;
  final int total, page, totalPages;
}

CatalogPage paginateCatalog(List<CatalogProduct> products, CatalogQuery query) {
  final search = query.search.trim().toLowerCase();
  final filtered = products.where((p) =>
      (query.available == null || p.draft.isAvailable == query.available) &&
      ('${p.draft.name} ${p.draft.description} ${p.draft.category}'.toLowerCase().contains(search))).toList()
    ..sort((a, b) => a.draft.name.toLowerCase().compareTo(b.draft.name.toLowerCase()));
  final limit = query.limit.clamp(1, 100).toInt();
  final pages = (filtered.length / limit).ceil();
  final page = query.page.clamp(1, pages == 0 ? 1 : pages).toInt();
  return CatalogPage(
    items: filtered.skip((page - 1) * limit).take(limit).toList(),
    total: filtered.length, page: page, totalPages: pages,
  );
}

abstract class CatalogRepository {
  bool get isLocal;
  bool get supportsOptionalStock => true;
  Future<CatalogPage> list(String businessId, {CatalogQuery query = const CatalogQuery()});
  Future<CatalogProduct> get(String businessId, String id);
  Future<CatalogProduct> save(String businessId, ProductDraft draft, {CatalogProduct? original});
  Future<void> delete(CatalogProduct product);
  Future<String> uploadImage(String businessId, Uint8List bytes, String fileName);
}

class CatalogScope extends InheritedWidget {
  const CatalogScope({super.key, required this.repository, required super.child});
  final CatalogRepository repository;
  static CatalogRepository of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<CatalogScope>();
    if (scope == null) throw StateError('Falta configurar CatalogScope.');
    return scope.repository;
  }
  @override
  bool updateShouldNotify(CatalogScope oldWidget) => oldWidget.repository != repository;
}
