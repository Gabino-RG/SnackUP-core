import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'catalog.dart';

/// Provisional CRUD routes from the v3 interfaces. Confirm these with backend;
/// the v3 attachment refers to v2 for full product CRUD and pagination schemas.
class CatalogRoutes {
  const CatalogRoutes({
    this.collection = 'businesses/{businessId}/products',
    this.item = 'products/{id}',
    this.media = 'media',
    this.updateMethod = 'PATCH',
  });
  final String collection, item, media, updateMethod;
  String collectionFor(String id) => collection.replaceAll('{businessId}', Uri.encodeComponent(id));
  String itemFor(String id) => item.replaceAll('{id}', Uri.encodeComponent(id));
}

class RestCatalogRepository extends CatalogRepository {
  RestCatalogRepository({
    required Uri baseUri, required this.client, required this.accessToken,
    this.refreshSession, this.routes = const CatalogRoutes(),
  }) : baseUri = Uri.parse(baseUri.toString().replaceFirst(RegExp(r'/?$'), '/')) {
    if (!['http', 'https'].contains(baseUri.scheme) || baseUri.host.isEmpty ||
        baseUri.hasQuery || baseUri.hasFragment || baseUri.userInfo.isNotEmpty) {
      throw ArgumentError('La API requiere una URL base HTTP(S) sin credenciales ni parámetros.');
    }
  }
  final Uri baseUri;
  final http.Client client;
  final Future<String> Function() accessToken;
  final Future<bool> Function()? refreshSession;
  final CatalogRoutes routes;
  Future<bool>? _refreshing;
  @override
  bool get isLocal => false;

  Future<bool> _refresh() async {
    final refresh = refreshSession;
    if (refresh == null) return false;
    final running = _refreshing;
    if (running != null) return running;
    final future = refresh();
    _refreshing = future;
    try { return await future; } finally {
      if (identical(_refreshing, future)) _refreshing = null;
    }
  }

  Future<dynamic> _send(String method, String path, {
    Map<String, String>? query, Map<String, dynamic>? body,
    Uint8List? image, String? fileName,
  }) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      final token = await accessToken();
      if (token.isEmpty) throw const CatalogException('Vuelve a iniciar sesión.', code: 'UNAUTHENTICATED');
      final uri = baseUri.resolve(path).replace(queryParameters: query);
      final http.BaseRequest request;
      if (image != null) {
        final ext = fileName!.split('.').last.toLowerCase();
        request = http.MultipartRequest(method, uri)
          ..fields['purpose'] = 'product'
          ..files.add(http.MultipartFile.fromBytes('file', image, filename: fileName,
            contentType: MediaType('image', ext == 'jpg' ? 'jpeg' : ext)));
      } else {
        request = http.Request(method, uri)
          ..headers['Content-Type'] = 'application/json';
        if (body != null) (request as http.Request).body = jsonEncode(body);
      }
      request.headers.addAll({'Accept': 'application/json', 'Authorization': 'Bearer $token'});
      try {
        final response = await (() async {
          final streamed = await client.send(request);
          return http.Response.fromStream(streamed);
        })().timeout(const Duration(seconds: 20));
        dynamic data;
        if (response.body.isNotEmpty) {
          try { data = jsonDecode(utf8.decode(response.bodyBytes)); }
          catch (_) { throw const CatalogException('La API devolvió una respuesta inválida.'); }
        }
        if (response.statusCode >= 200 && response.statusCode < 300) return data;
        final error = data is Map ? data['error'] : null;
        final code = error is Map ? error['code']?.toString() ?? 'HTTP_ERROR' : 'HTTP_ERROR';
        if (response.statusCode == 401 && code == 'TOKEN_EXPIRED' &&
            attempt == 0 && await _refresh()) continue;
        final message = switch (response.statusCode) {
          401 => 'Tu sesión terminó. Vuelve a iniciar sesión.',
          403 => 'Tu cuenta no tiene permiso para modificar este catálogo.',
          404 => 'El producto ya no existe.',
          409 => 'El producto cambió en otro dispositivo. Recarga antes de guardar.',
          413 => 'La imagen supera el tamaño permitido.',
          422 => 'Revisa los datos del producto antes de guardar.',
          _ => 'No se pudo completar la operación. Inténtalo de nuevo.',
        };
        throw CatalogException(message, code: code);
      } on TimeoutException {
        // Never replay POST/PATCH/DELETE after an ambiguous timeout.
        throw const CatalogException('La API tardó demasiado. Actualiza el catálogo para comprobar si se guardó antes de repetir.', code: 'TIMEOUT');
      } on http.ClientException {
        throw const CatalogException('No se pudo conectar con el servidor local. Revisa tu conexión.', code: 'NETWORK');
      }
    }
    throw const CatalogException('Tu sesión terminó.', code: 'UNAUTHENTICATED');
  }

  CatalogProduct _product(dynamic data, String businessId) {
    if (data is Map && data['data'] is Map) data = data['data'];
    if (data is! Map) throw const CatalogException('Respuesta de producto incompleta.');
    final product = CatalogProduct.fromJson(Map<String, dynamic>.from(data));
    if (product.businessId != businessId) throw const CatalogException('La API devolvió un producto de otro local.');
    return product;
  }

  @override
  Future<CatalogPage> list(String businessId, {CatalogQuery query = const CatalogQuery()}) async {
    final data = await _send('GET', routes.collectionFor(businessId), query: {
      'page': query.page.toString(), 'limit': query.limit.clamp(1, 100).toString(),
      if (query.search.trim().isNotEmpty) 'q': query.search.trim(),
      if (query.available != null) 'isAvailable': query.available.toString(),
    });
    if (data is! Map || data['data'] is! List || data['pagination'] is! Map) {
      throw const CatalogException('La API debe devolver data y pagination para el catálogo.');
    }
    final pagination = data['pagination'] as Map;
    if (pagination['total'] is! int || pagination['page'] is! int || pagination['totalPages'] is! int) {
      throw const CatalogException('La paginación del servidor está incompleta.');
    }
    return CatalogPage(
      items: (data['data'] as List).map((p) => _product(p, businessId)).toList(),
      total: pagination['total'] as int, page: pagination['page'] as int,
      totalPages: pagination['totalPages'] as int,
    );
  }

  @override
  Future<CatalogProduct> get(String businessId, String id) async =>
      _product(await _send('GET', routes.itemFor(id)), businessId);

  @override
  Future<CatalogProduct> save(String businessId, ProductDraft draft, {CatalogProduct? original}) async {
    draft.validate();
    if (original != null && original.businessId != businessId) {
      throw const CatalogException('El producto pertenece a otro local.');
    }
    final body = draft.toJson();
    if (original != null) {
      body['expectedVersion'] = original.version;
      // Price-only edits must not overwrite inventory changed by orders.
      if (draft.stock == original.draft.stock) body.remove('stock');
    }
    return _product(await _send(
      original == null ? 'POST' : routes.updateMethod,
      original == null ? routes.collectionFor(businessId) : routes.itemFor(original.id),
      body: body,
    ), businessId);
  }

  @override
  Future<void> delete(CatalogProduct product) async {
    await _send('DELETE', routes.itemFor(product.id), body: {'expectedVersion': product.version});
  }

  @override
  Future<String> uploadImage(String businessId, Uint8List bytes, String fileName) async {
    validateProductImage(bytes, fileName);
    final data = await _send('POST', routes.media, image: bytes, fileName: fileName);
    if (data is! Map || data['url'] is! String) {
      throw const CatalogException('La API no devolvió la dirección de la imagen.');
    }
    return data['url'] as String;
  }
}
