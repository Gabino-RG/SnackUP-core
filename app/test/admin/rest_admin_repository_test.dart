import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:snackup/api/api_client.dart';
import 'package:snackup/features/admin/data/admin_repository.dart';
import 'package:snackup/features/admin/data/rest_admin_repository.dart';
import 'package:snackup/features/admin/domain/admin_models.dart';

http.Response reply(Object data, [int status = 200]) => http.Response(jsonEncode(data), status, headers: {'content-type': 'application/json; charset=utf-8'});
Map<String, dynamic> page(List<Object> rows, {int number = 1, int pages = 1}) =>
  {'data': rows, 'pagination': {'page': number, 'totalPages': pages}};
Map<String, dynamic> followup({int version = 1}) => {
  'reviewId': 'review-1', 'businessId': 'local-1', 'version': version,
  'status': 'in_review', 'assignee': 'Coordinación', 'note': 'Revisar atención.',
  'updatedAt': '2026-10-12T10:30:00Z',
};
RestAdminRepository makeRepo(Future<http.Response> Function(http.Request) handler) =>
  RestAdminRepository(ApiClient(baseUri: Uri.parse('https://snackup.example/api/v1/'), client: MockClient(handler)));

void main() {
  test('failed page does not advance any administrative cursor', () async {
    var fail = true;
    final requested = <String, List<String>>{};
    final repo = makeRepo((r) async {
      requested.putIfAbsent(r.url.path, () => []).add(r.url.queryParameters['page']!);
      expect(r.url.queryParameters['limit'], '200');
      if (r.url.path.endsWith('/reviews') && fail) return reply({'error': {'code': 'UNAVAILABLE'}}, 503);
      return reply(page([], number: int.parse(r.url.queryParameters['page']!), pages: 2));
    });
    await expectLater(repo.loadNextPage(reset: true), throwsA(isA<AdminDataException>()));
    fail = false;
    expect((await repo.loadNextPage()).hasMore, true);
    expect((await repo.loadNextPage()).hasMore, false);
    for (final pages in requested.values) { expect(pages, ['1', '1', '2']); }
    await repo.loadNextPage();
    expect(requested.values.every((pages) => pages.length == 3), true);
  });

  test('REST followup creation sends version and uses the server result', () async {
    final repo = makeRepo((r) async {
      expect(r.url.path, '/api/v1/admin/reviews/review-1/followup');
      if (r.method == 'GET') return reply({'error': {'code': 'FOLLOWUP_NOT_FOUND'}}, 404);
      expect(r.method, 'PUT');
      final body = jsonDecode(r.body) as Map;
      expect(body, {'status': 'in_review', 'assignee': 'Coordinación', 'note': 'Revisar atención.', 'expectedVersion': 0});
      return reply(followup());
    });
    const review = AdminReview(id: 'review-1', businessId: 'local-1');
    expect((await repo.getFollowup(review)).version, 0);
    final saved = await repo.saveFollowup(const AdminFollowup(reviewId: 'review-1', businessId: 'local-1',
      status: FollowupStatus.inReview, assignee: ' Coordinación ', note: 'Revisar atención.', version: 0));
    expect(saved.version, 1);
    expect(saved.updatedAt, DateTime.utc(2026, 10, 12, 10, 30));
  });

  test('followup conflict is explicit and does not repeat the save', () async {
    var writes = 0;
    final repo = makeRepo((r) async {
      writes++;
      return reply({'error': {'code': 'VERSION_CONFLICT'}}, 409);
    });
    await expectLater(repo.saveFollowup(const AdminFollowup(reviewId: 'review-1', businessId: 'local-1',
      assignee: 'Coordinación', note: 'Nueva nota', version: 2)),
      throwsA(isA<AdminDataException>().having((e) => e.code, 'code', 'VERSION_CONFLICT')));
    expect(writes, 1);
  });

  test('history flags earlier events and rejects records from another case', () async {
    var wrongCase = false;
    final repo = makeRepo((r) async {
      expect(r.url.queryParameters, {'page': '1', 'limit': '50'});
      return reply(page([{...followup(), if (wrongCase) 'reviewId': 'other'}], pages: 2));
    });
    expect((await repo.getHistory('review-1')).hasMore, true);
    wrongCase = true;
    await expectLater(repo.getHistory('review-1'), throwsA(isA<AdminDataException>()));
  });

  test('denied administrative data never becomes a demo or an empty success', () async {
    final repo = makeRepo((r) async => reply({'error': {'code': 'FORBIDDEN'}}, 403));
    expect(repo.isDemo, false);
    await expectLater(repo.loadNextPage(reset: true), throwsA(isA<AdminDataException>()));
    await expectLater(repo.getFollowup(const AdminReview(id: 'review-1', businessId: 'local-1')),
      throwsA(isA<AdminDataException>()));
  });
}
