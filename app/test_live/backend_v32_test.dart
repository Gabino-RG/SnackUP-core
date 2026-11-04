import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:snackup/api/api_client.dart';
import 'package:snackup/api/rest_session.dart';
import 'package:snackup/operations/models.dart';
import 'package:snackup/operations/operations_repository.dart';
import 'package:snackup/operations/v32_repository.dart';
import 'package:snackup/catalog/catalog.dart';
import 'package:snackup/catalog/rest_catalog_repository.dart';
import 'package:snackup/features/admin/data/rest_admin_repository.dart';
import 'package:snackup/features/admin/domain/admin_models.dart';

// Native test adapter for the cookie/Origin behavior supplied by the browser.
// This is not shipped in the web build and never connects to a deployed server.
class LocalBrowserClient extends http.BaseClient {
  LocalBrowserClient(this.origin);
  final String origin;
  final inner = http.Client();
  String? cookie;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.url.origin != origin) {
      throw StateError('Unexpected test origin');
    }
    request.headers['Origin'] = origin;
    if (cookie != null) request.headers['Cookie'] = cookie!;
    final response = await inner.send(request);
    final next = response.headers['set-cookie'];
    if (next != null) cookie = next.split(';').first;
    return response;
  }

  @override
  void close() => inner.close();
}

void main() {
  final origin = Platform.environment['SNACKUP_LIVE_ORIGIN'];
  final password = Platform.environment['SNACKUP_LIVE_PASSWORD'];
  if (origin == null ||
      password == null ||
      Uri.parse(origin).host != '127.0.0.1') {
    throw StateError(
      'Run scripts/integration/live_backend.py to create a disposable local backend.',
    );
  }
  final base = Uri.parse('$origin/api/legacy/v1/');
  final sessions = <RestSession>[];
  Future<RestSession> login(String user, String domain) async {
    final s = RestSession(baseUri: base, client: LocalBrowserClient(origin));
    sessions.add(s);
    await s.signIn('$user@$domain.example.edu', password);
    expect(s.phase, PortalSessionPhase.authenticated, reason: s.message);
    return s;
  }

  ApiClient api(RestSession s) =>
      ApiClient(baseUri: base, client: SessionHttpClient(s));
  tearDown(() {
    for (final session in sessions) {
      session.dispose();
    }
    sessions.clear();
  });
  test(
    'real V3.2 purchase -> Kitchen -> zero review -> Administration followup',
    () async {
      final kitchen = await login('operator', 'staff');
      final admin = await login('master', 'staff');
      final student = await login('student', 'students');
      expect(kitchen.account!.isBusiness, isTrue);
      expect(admin.account!.canManageAccounts, isTrue);
      expect(student.account!.isAdmin, isFalse);
      final operations = OperationsRepository(api(kitchen));
      final administration = RestAdminRepository(api(admin));
      final catalog = RestCatalogRepository(
        baseUri: base,
        client: SessionHttpClient(kitchen),
        accessToken: kitchen.accessToken,
      );
      expect(
        (await catalog.list('business-1')).items.single.draft.priceCents,
        3550,
      );
      final created = await catalog.save(
        'business-1',
        const ProductDraft(
          name: 'Agua de prueba',
          description: '',
          category: 'Bebidas',
          priceCents: 1200,
        ),
      );
      final edited = await catalog.save(
        'business-1',
        const ProductDraft(
          name: 'Agua editada',
          description: '',
          category: 'Bebidas',
          priceCents: 1500,
        ),
        original: created,
      );
      expect(
        (await catalog.get('business-1', edited.id)).draft.priceCents,
        1500,
      );
      await catalog.delete(edited);
      expect((await catalog.list('business-1')).total, 1);
      final featured = <CatalogProduct>[];
      for (var i = 0; i < 3; i++) {
        featured.add(
          await catalog.save(
            'business-1',
            ProductDraft(
              name: 'Destacado $i',
              description: '',
              category: 'Bebidas',
              priceCents: 1000,
              isFeatured: true,
            ),
          ),
        );
      }
      await expectLater(
        catalog.save(
          'business-1',
          const ProductDraft(
            name: 'Cuarto destacado',
            description: '',
            category: 'Bebidas',
            priceCents: 1000,
            isFeatured: true,
          ),
        ),
        throwsA(
          isA<CatalogException>()
              .having((e) => e.code, 'code', 'FEATURED_LIMIT_REACHED')
              .having((e) => e.message, 'message', contains('tres productos')),
        ),
      );
      for (final product in featured) {
        await catalog.delete(product);
      }
      await administration.loadReferences();
      final token = await student.accessToken();
      final v3 = ApiClient(
        baseUri: Uri.parse('$origin/api/v1/'),
        client: student.rawClient,
      );
      final auth = {'Authorization': 'Bearer $token'};
      Future<dynamic> buy(String key) => v3.json(
        'POST',
        'orders',
        headers: {...auth, 'Idempotency-Key': key},
        body: {
          'businessId': 'business-1',
          'items': [
            {'productId': 'product-1', 'quantity': 1},
          ],
          'paymentMethod': 'Efectivo',
          'expectedTotal': 35.5,
        },
      );
      final purchase = await buy('b3142faa-87d9-41ae-b5c6-204c7576b829');
      expect(
        (await buy('b3142faa-87d9-41ae-b5c6-204c7576b829'))['id'],
        purchase['id'],
      );
      final active = await operations.active('business-1');
      expect(active.length, 1);
      var order = active.single;
      expect(order.totalCents, 3550);
      expect(order.id, purchase['id']);
      final kitchenResponse = await api(
        kitchen,
      ).json('GET', 'orders/${order.id}');
      expect(kitchenResponse.containsKey('pickupCode'), isFalse);
      await expectLater(
        operations.business('business-2'),
        throwsA(isA<ApiException>()),
      );
      final stale = order;
      order = await operations.act(order, 'accept');
      await expectLater(
        operations.act(stale, 'accept'),
        throwsA(
          isA<ApiException>().having((e) => e.code, 'code', 'VERSION_CONFLICT'),
        ),
      );
      order = await operations.act(order, 'start');
      order = await operations.act(order, 'ready');
      await expectLater(
        operations.act(order, 'complete', method: 'manual', code: 'wrong'),
        throwsA(
          isA<ApiException>().having(
            (e) => e.code,
            'code',
            'VERIFICATION_FAILED',
          ),
        ),
      );
      order = await operations.act(
        order,
        'complete',
        method: 'manual',
        code: purchase['pickupCode'],
      );
      expect(order.status, KitchenStatus.completed);
      expect(await operations.active('business-1'), isEmpty);
      final history = await operations.history(
        'business-1',
        dayKey(campusNow()),
      );
      expect(history.orders.items.single.id, order.id);
      await v3.json(
        'POST',
        'orders/${order.id}/rating',
        headers: auth,
        body: {'stars': 0, 'comment': 'Opinión sintética para integración'},
      );
      final page = await administration.loadNextPage(reset: true);
      final review = page.reviews.single;
      expect(review.rating, 0);
      expect(review.isNegative, isTrue);
      expect(review.career, 'Desarrollo de Software');
      expect(ReviewStatistics(page.reviews).rating, 0);
      final initial = await administration.getFollowup(review);
      final saved = await administration.saveFollowup(
        AdminFollowup(
          reviewId: review.id,
          businessId: review.businessId,
          version: initial.version,
          status: FollowupStatus.inReview,
          assignee: 'Responsable de prueba',
          note: 'Seguimiento de prueba',
        ),
      );
      expect(saved.status, FollowupStatus.inReview);
      expect((await administration.getHistory(review.id)).events, isNotEmpty);
      await expectLater(
        api(kitchen).json('GET', 'admin/reviews'),
        throwsA(isA<ApiException>()),
      );
      final cancelledPurchase = await buy(
        'b3142faa-87d9-41ae-b5c6-204c7576b830',
      );
      final cancelled = await operations.act(
        await operations.order(cancelledPurchase['id'], 'business-1'),
        'cancel',
        reason: 'product_unavailable',
      );
      expect(cancelled.status, KitchenStatus.cancelled);
      final business = await operations.business('business-1');
      expect((await operations.setOpen(business, false)).isOpen, isFalse);
      expect(await kitchen.refresh(), isTrue);
      await kitchen.signOut();
      expect(kitchen.phase, PortalSessionPhase.signedOut);
      expect(kitchen.logoutPending, isFalse);
    },
  );
  test(
    'V3.2 staff features use canonical API with legacy sessions and enforce permissions',
    () async {
      final kitchen = await login('operator', 'staff');
      final admin = await login('master', 'staff');
      final student = await login('student', 'students');
      ApiClient canonical(RestSession session) => ApiClient(
        baseUri: canonicalApiBase(base),
        client: SessionHttpClient(session, canonical: true),
      );
      final repo = V32Repository(canonical(kitchen));
      final otherKitchen = await login('operator2', 'staff');
      final otherRepo = V32Repository(canonical(otherKitchen));
      final expired = object(
        ((await otherRepo.orders('business-2'))['data'] as List).single,
      );
      await expectLater(
        repo.notCollected(expired, voucherNotRedeemed: false),
        throwsA(isA<ApiException>()),
      );
      await otherRepo.notCollected(expired, voucherNotRedeemed: false);
      expect(
        (await canonical(
          otherKitchen,
        ).json('GET', 'orders/expired-order'))['status'],
        'cancelled',
      );
      expect(
        (await canonical(
          otherKitchen,
        ).json('GET', 'products/product-2'))['stock'],
        5,
      );
      final adminRepo = V32Repository(canonical(admin));
      final studentApi = canonical(student);
      var b = await repo.business('business-1');
      await repo.closing('business-1', b['version'], true, '23:50');
      b = await repo.business('business-1');
      expect(b['autoCloseEnabled'], true);
      expect(
        (await adminRepo.business('business-1'))['closeTimeLocal'],
        '23:50',
      );
      await expectLater(
        adminRepo.closing('business-1', b['version'], false, '23:50'),
        throwsA(isA<ApiException>().having((e) => e.status, 'status', 403)),
      );
      final today = campusNow();
      final later = DateTime.utc(today.year, today.month, today.day, 29, 55);
      // Scheduling a closing later in today's campus day is deterministic except
      // during the last five minutes; the rejection is still checked by the API.
      if (later.isAfter(DateTime.now().toUtc())) {
        await repo.postpone('business-1', b['version'], later);
        b = await repo.business('business-1');
        expect(DateTime.parse(b['postponedCloseAt']).toUtc(), later);
      }
      await repo.timeout('business-1', b['version'], 5);
      b = await repo.business('business-1');
      expect(b['pickupTimeoutMinutes'], 5);
      await repo.closing('business-1', b['version'], false, '23:50');
      final old = OperationsRepository(api(kitchen));
      await old.setOpen(await old.business('business-1'), true);
      final purchase = await studentApi.json(
        'POST',
        'orders',
        headers: {'Idempotency-Key': 'b3142faa-87d9-41ae-b5c6-204c7576b831'},
        body: {
          'businessId': 'business-1',
          'items': [
            {'productId': 'product-1', 'quantity': 1},
          ],
          'paymentMethod': 'ValeComida',
          'expectedTotal': 35.5,
        },
      );
      final chat = await repo.openChat('business-1', purchase['id']);
      expect((await repo.chats('business-1', 1))['data'], isNotEmpty);
      await repo.send(chat['id'], 'Tu pedido está en preparación.');
      await studentApi.json(
        'POST',
        'chats/${chat['id']}/messages',
        body: {'text': 'Gracias, voy en camino.'},
      );
      expect((await repo.messages(chat['id'])).map((m) => m['senderRole']), [
        'COCINA',
        'ALUMNO',
      ]);
      await expectLater(
        adminRepo.messages(chat['id']),
        throwsA(isA<ApiException>()),
      );
      await expectLater(
        adminRepo.chats('business-1', 1),
        throwsA(isA<ApiException>()),
      );
      await repo.closeChat(chat['id']);
      await expectLater(
        repo.messages(chat['id']),
        throwsA(
          isA<ApiException>().having((e) => e.code, 'code', 'CHAT_NOT_FOUND'),
        ),
      );
      var order = await old.order(purchase['id'], 'business-1');
      order = await old.act(order, 'cancel', reason: 'product_unavailable');
      await repo.releaseVoucher(
        object(await canonical(kitchen).json('GET', 'orders/${order.id}')),
      );
      final secondVoucher = await studentApi.json(
        'POST',
        'orders',
        headers: {'Idempotency-Key': 'b3142faa-87d9-41ae-b5c6-204c7576b833'},
        body: {
          'businessId': 'business-1',
          'items': [
            {'productId': 'product-1', 'quantity': 1},
          ],
          'paymentMethod': 'ValeComida',
          'expectedTotal': 35.5,
        },
      );
      order = await old.order(secondVoucher['id'], 'business-1');
      order = await old.act(order, 'accept');
      order = await old.act(order, 'start');
      order = await old.act(order, 'ready');
      final active = (await repo.orders('business-1'))['data'] as List;
      final current = object(active.singleWhere((o) => o['id'] == order.id));
      await expectLater(
        repo.notCollected(current, voucherNotRedeemed: false),
        throwsA(
          isA<ApiException>().having(
            (e) => e.code,
            'code',
            'PICKUP_TIMEOUT_NOT_REACHED',
          ),
        ),
      );
      // Cash orders must never pass the meal-voucher release operation.
      final cash = await studentApi.json(
        'POST',
        'orders',
        headers: {'Idempotency-Key': 'b3142faa-87d9-41ae-b5c6-204c7576b832'},
        body: {
          'businessId': 'business-1',
          'items': [
            {'productId': 'product-1', 'quantity': 1},
          ],
          'paymentMethod': 'Efectivo',
          'expectedTotal': 35.5,
        },
      );
      await expectLater(
        repo.releaseVoucher(object(cash)),
        throwsA(isA<ApiException>()),
      );
      await old.act(
        await old.order(cash['id'], 'business-1'),
        'cancel',
        reason: 'product_unavailable',
      );
      final stats = await repo.stats(
        'business-1',
        dayKey(campusNow()),
        dayKey(campusNow()),
      );
      expect(stats['daily'], isNotEmpty);
      expect(stats['paymentMethods'], isA<List>());
      expect(stats['topProducts'], isA<List>());
      // Leave the existing browser fixture's expected closed business state.
      await old.setOpen(await old.business('business-1'), false);
    },
  );
}
