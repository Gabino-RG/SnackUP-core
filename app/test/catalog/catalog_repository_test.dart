import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:snackup/catalog/catalog.dart';
import 'package:snackup/catalog/local_catalog_repository.dart';
import 'package:snackup/catalog/rest_catalog_repository.dart';

ProductDraft draft({int price = 4500, int? stock, String name = 'Torta nueva', String? image}) =>
    ProductDraft(name: name, description: 'Preparada al momento', category: 'Alimentos',
      priceCents: price, stock: stock, imageUrl: image);

class FailingStore extends MemoryCatalogStore {
  @override
  Future<void> write(String value) async => throw StateError('quota');
}

void main() {
  test('MXN accepts decimals and comma without silently rounding extra digits', () {
    expect(parsePriceCents('35'), 3500);
    expect(parsePriceCents('35.05'), 3505);
    expect(parsePriceCents(' 35,5 '), 3550);
    expect(parsePriceCents('0.01'), 1);
    for (final invalid in ['', '0', '-10', '1.234', '1e2', 'NaN', '10001', '1,000.00']) {
      expect(parsePriceCents(invalid), isNull, reason: invalid);
    }
  });

  test('create, reload, edit price, remove image and delete persist by business', () async {
    final store = MemoryCatalogStore();
    final repo = LocalCatalogRepository(store);
    final created = await repo.save('local_1', draft(image: 'https://example.test/torta.jpg'));
    final reloaded = LocalCatalogRepository(store);
    expect((await reloaded.get('local_1', created.id)).draft.priceCents, 4500);
    final edited = await reloaded.save('local_1', draft(price: 4990), original: created);
    expect(edited.version, 2);
    expect(edited.draft.imageUrl, isNull);
    expect((await repo.get('local_1', created.id)).draft.priceCents, 4990);
    expect((await repo.list('local_2')).total, 3);
    await expectLater(repo.get('local_2', created.id), throwsA(isA<CatalogException>()));
    await reloaded.delete(edited);
    expect((await LocalCatalogRepository(store).list('local_1')).total, 3);
  });

  test('stale editors and different businesses cannot overwrite a product', () async {
    final repo = LocalCatalogRepository(MemoryCatalogStore());
    final product = await repo.save('local_1', draft());
    await repo.save('local_1', draft(price: 5000), original: product);
    await expectLater(repo.save('local_1', draft(price: 6000), original: product),
      throwsA(isA<CatalogException>().having((e) => e.code, 'code', 'VERSION_CONFLICT')));
    await expectLater(repo.save('local_2', draft(), original: product),
      throwsA(isA<CatalogException>().having((e) => e.code, 'code', 'FORBIDDEN')));
    expect((await repo.get('local_1', product.id)).draft.priceCents, 5000);
  });

  test('null inventory is supported; zero disables product and negatives fail', () async {
    final repo = LocalCatalogRepository(MemoryCatalogStore());
    expect((await repo.save('local_1', draft())).draft.stock, isNull);
    expect((await repo.save('local_1', draft(stock: 0))).draft.isAvailable, false);
    await expectLater(repo.save('local_1', draft(stock: -1)), throwsA(isA<CatalogException>()));
  });

  test('search spans catalog before pagination and filters stay within business', () async {
    final repo = LocalCatalogRepository(MemoryCatalogStore());
    for (var i = 0; i < 25; i++) {
      await repo.save('local_1', draft(name: 'Especial $i', stock: i == 24 ? 0 : null));
    }
    final second = await repo.list('local_1', query: const CatalogQuery(page: 2, search: 'Especial'));
    expect(second.items.length, 5); expect(second.total, 25); expect(second.totalPages, 2);
    expect((await repo.list('local_1', query: const CatalogQuery(search: 'Especial 24', available: false))).items.single.draft.stock, 0);
    expect((await repo.list('local_2', query: const CatalogQuery(search: 'Especial'))).total, 0);
  });

  test('storage failure does not claim success or replace stored data', () async {
    final store = FailingStore();
    final repo = LocalCatalogRepository(store);
    await expectLater(repo.save('local_1', draft()), throwsA(isA<CatalogException>()));
    expect(store.value, isNull);
  });

  test('image validation rejects disguised files and accepts PNG signature', () {
    expect(() => validateProductImage(Uint8List.fromList([1, 2, 3]), 'photo.png'), throwsA(isA<CatalogException>()));
    validateProductImage(Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10]), 'photo.png');
  });

  test('REST sends pagination and bearer token, keeps scoped server results', () async {
    final product = await LocalCatalogRepository(MemoryCatalogStore()).save('local_1', draft());
    final client = MockClient((request) async {
      expect(request.url.path, '/api/v1/businesses/local_1/products');
      expect(request.url.queryParameters, {'page':'2', 'limit':'20', 'q':'Torta', 'isAvailable':'true'});
      expect(request.headers['Authorization'], 'Bearer access');
      return http.Response(jsonEncode({'data':[product.toJson()], 'pagination':{'page':2, 'total':21, 'totalPages':2}}), 200);
    });
    final repo = RestCatalogRepository(baseUri: Uri.parse('https://snackup.example/api/v1'), client: client, accessToken: () async => 'access');
    final page = await repo.list('local_1', query: const CatalogQuery(page:2, search:'Torta', available:true));
    expect(page.total, 21); expect(page.items.single.id, product.id);
  });

  test('REST price edit excludes unchanged stock, sends version and preserves route', () async {
    final original = await LocalCatalogRepository(MemoryCatalogStore()).save('local_1', draft(stock: 10));
    final repo = RestCatalogRepository(baseUri: Uri.parse('https://snackup.example/api/v1/'),
      accessToken: () async => 'access', client: MockClient((request) async {
        expect(request.method, 'PATCH');
        expect(request.url.path, '/api/v1/products/${original.id}');
        final body = jsonDecode(request.body) as Map;
        expect(body['price'], 49.5); expect(body['expectedVersion'], 1);
        expect(body.containsKey('stock'), false);
        expect(body.containsKey('businessId'), false);
        return http.Response(jsonEncode({...original.toJson(), 'price':49.5, 'version':2}), 200);
      }));
    expect((await repo.save('local_1', draft(price:4950, stock:10), original: original)).draft.priceCents, 4950);
  });

  test('REST refreshes expired session once and never turns denial into examples', () async {
    var requests = 0, refreshes = 0;
    final repo = RestCatalogRepository(baseUri: Uri.parse('https://snackup.example/api/v1/'),
      accessToken: () async => 'access', refreshSession: () async { refreshes++; return true; },
      client: MockClient((request) async {
        requests++;
        return http.Response(jsonEncode({'error':{'code':'TOKEN_EXPIRED'}}), 401);
      }));
    await expectLater(repo.list('local_1'), throwsA(isA<CatalogException>()));
    expect(requests, 2); expect(refreshes, 1);
  });

  test('REST surfaces concurrency conflict without retrying write', () async {
    var requests = 0;
    final original = await LocalCatalogRepository(MemoryCatalogStore()).save('local_1', draft());
    final repo = RestCatalogRepository(baseUri: Uri.parse('https://snackup.example/api/v1/'),
      accessToken: () async => 'access', client: MockClient((request) async {
        requests++; return http.Response(jsonEncode({'error':{'code':'VERSION_CONFLICT'}}), 409);
      }));
    await expectLater(repo.save('local_1', draft(price:5000), original: original),
      throwsA(isA<CatalogException>().having((e) => e.code, 'code', 'VERSION_CONFLICT')));
    expect(requests, 1);
  });
}
