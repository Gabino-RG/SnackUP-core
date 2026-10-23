import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:snackup/api/api_client.dart';
import 'package:snackup/operations/models.dart';
import 'package:snackup/operations/operations_repository.dart';
import 'package:snackup/operations/kitchen_controller.dart';
import 'dart:async';

Map<String, dynamic> orderData({
  String status = 'pending',
  int version = 1,
  String id = 'o1',
  String business = 'b1',
}) => {
  'id': id,
  'businessId': business,
  'orderNumber': 101,
  'version': version,
  'status': status,
  'customerName': 'Ana',
  'createdAt': '2026-10-12T03:00:00Z',
  'total': 85,
  'items': [
    {'name': 'Hamburguesa', 'price': 85, 'quantity': 1},
  ],
};
http.Response reply(dynamic d, [int status = 200]) => http.Response(
  jsonEncode(d),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
OperationsRepository repo(Future<http.Response> Function(http.Request) fn) =>
    OperationsRepository(
      ApiClient(
        baseUri: Uri.parse('https://test.example/api/v1/'),
        client: MockClient(fn),
      ),
    );
void main() {
  test(
    'actions send only intent, version and verification; server owns prices and timestamps',
    () async {
      final calls = <http.Request>[];
      final r = repo((request) async {
        calls.add(request);
        return reply(orderData(status: 'completed', version: 5));
      });
      final current = KitchenOrder.fromJson(
        orderData(status: 'ready', version: 4),
      );
      await r.act(current, 'complete', method: 'manual', code: ' 12345678 ');
      expect(calls.single.url.path, '/api/v1/orders/o1/complete');
      expect(jsonDecode(calls.single.body), {
        'expectedVersion': 4,
        'method': 'manual',
        'code': '12345678',
      });
    },
  );
  test(
    'ready cannot cancel, accepted cannot skip preparation and delivery requires a code',
    () async {
      var calls = 0;
      final r = repo((_) async {
        calls++;
        return reply({});
      });
      await expectLater(
        r.act(
          KitchenOrder.fromJson(orderData(status: 'ready')),
          'cancel',
          reason: 'other',
          notes: 'Cierre',
        ),
        throwsA(isA<ApiException>()),
      );
      await expectLater(
        r.act(KitchenOrder.fromJson(orderData(status: 'accepted')), 'ready'),
        throwsA(isA<ApiException>()),
      );
      await expectLater(
        r.act(
          KitchenOrder.fromJson(orderData(status: 'ready')),
          'complete',
          method: 'none',
        ),
        throwsA(isA<ApiException>()),
      );
      await expectLater(
        r.act(KitchenOrder.fromJson(orderData()), 'cancel', reason: 'other'),
        throwsA(isA<ApiException>()),
      );
      expect(calls, 0);
    },
  );
  test('active pagination never mixes businesses or terminal orders', () async {
    final r = repo((q) async {
      final page = int.parse(q.url.queryParameters['page']!);
      return reply({
        'data': [
          orderData(id: 'o$page', status: page == 1 ? 'pending' : 'completed'),
        ],
        'pagination': {'page': page, 'totalPages': 2, 'total': 2},
      });
    });
    expect((await r.active('b1')).map((o) => o.id), ['o1']);
    final foreign = repo(
      (_) async => reply({
        'data': [orderData(business: 'b2')],
      }),
    );
    await expectLater(foreign.active('b1'), throwsA(isA<ApiException>()));
  });
  test('conflict is surfaced without repeating mutation', () async {
    var calls = 0;
    final r = repo((_) async {
      calls++;
      return reply({
        'error': {'code': 'VERSION_CONFLICT'},
      }, 409);
    });
    await expectLater(
      r.act(KitchenOrder.fromJson(orderData()), 'accept'),
      throwsA(
        predicate((e) => e is ApiException && e.code == 'VERSION_CONFLICT'),
      ),
    );
    expect(calls, 1);
  });
  test(
    'history uses the server summary, not sums from the current page',
    () async {
      final r = repo((request) async {
        expect(request.url.queryParameters['date'], '2026-10-11');
        return reply({
          'data': [orderData(status: 'completed')],
          'summary': {'completed': 70, 'cancelled': 3, 'totalSold': 7650.5},
          'pagination': {'page': 2, 'totalPages': 3, 'total': 73},
        });
      });
      final h = await r.history('b1', '2026-10-11', number: 2);
      expect(h.summary.totalCents, 765050);
      expect(h.orders.hasMore, true);
      expect(h.summary.completed, 70);
    },
  );
  test(
    'controller blocks duplicate writes and keeps newer mutation over an older poll',
    () async {
      final poll = Completer<http.Response>();
      final mutation = Completer<http.Response>();
      var lists = 0, writes = 0;
      final r = repo((request) async {
        if (request.url.path.endsWith('/businesses/b1'))
          return reply({
            'id': 'b1',
            'name': 'Central',
            'isOpen': true,
            'version': 1,
          });
        if (request.method == 'POST') {
          writes++;
          return mutation.future;
        }
        lists++;
        if (lists == 2) return poll.future;
        return reply({
          'data': [orderData()],
        });
      });
      final controller = KitchenController(r, 'b1');
      await controller.refresh();
      final o = controller.orders.single;
      final loading = controller.refresh();
      await Future<void>.delayed(Duration.zero);
      final action = controller.act(o, 'accept');
      await controller.act(o, 'accept');
      mutation.complete(reply(orderData(status: 'accepted', version: 2)));
      await action;
      poll.complete(
        reply({
          'data': [orderData()],
        }),
      );
      await loading;
      expect(writes, 1);
      expect(controller.orders.single.version, 2);
      controller.dispose();
    },
  );
  test('only newly arriving pending orders alert after initial load', () async {
    var count = 1;
    final r = repo(
      (request) async => request.url.path.endsWith('/businesses/b1')
          ? reply({'id': 'b1', 'name': 'Central', 'isOpen': true, 'version': 1})
          : reply({
              'data': [for (var n = 1; n <= count; n++) orderData(id: 'o$n')],
            }),
    );
    final controller = KitchenController(r, 'b1');
    var alerts = 0;
    controller.onNewOrders = () => alerts++;
    await controller.refresh();
    expect(alerts, 0);
    count = 2;
    await controller.refresh();
    await controller.refresh();
    expect(alerts, 1);
    expect(controller.newCount, 1);
    controller.acknowledge();
    expect(controller.newCount, 0);
    controller.dispose();
  });
}
