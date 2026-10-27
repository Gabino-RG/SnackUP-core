import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:snackup/api/api_client.dart';
import 'package:snackup/api/rest_session.dart';
import 'package:snackup/operations/v32_repository.dart';
import 'package:snackup/features/operations/v32_screens.dart';

class FakeV32 extends V32Repository {
  FakeV32()
    : super(
        ApiClient(
          baseUri: Uri.parse('https://test.example/api/v1/'),
          client: MockClient((_) async => http.Response('{}', 500)),
        ),
      );
  int saves = 0;
  bool closed = false;
  @override
  Future<Map<String, dynamic>> business(String id) async => {
    'id': id,
    'version': 1,
    'autoCloseEnabled': false,
    'closeTimeLocal': null,
    'pickupTimeoutMinutes': 30,
    'timezone': 'America/Mexico_City',
    'isOpen': true,
  };
  @override
  Future<void> closing(
    String businessId,
    int version,
    bool enabled,
    String? time,
  ) async {
    saves++;
  }

  @override
  Future<Map<String, dynamic>> openChat(
    String businessId,
    String orderId,
  ) async => {'id': 'chat'};
  @override
  Future<List<Map<String, dynamic>>> messages(String chatId) async {
    if (closed)
      throw const ApiException('closed', code: 'CHAT_NOT_FOUND', status: 404);
    return [
      {
        'id': 'm',
        'senderRole': 'ALUMNO',
        'text': 'Mensaje privado de prueba',
        'createdAt': '2026-10-26T12:00:00Z',
      },
    ];
  }

  @override
  Future<Map<String, dynamic>> chats(String businessId, int page) async => {
    'data': [],
    'pagination': {'totalPages': 0},
  };
}

class DelayedChat extends FakeV32 {
  final pending = Completer<List<Map<String, dynamic>>>();
  int reads = 0;
  @override
  Future<List<Map<String, dynamic>>> messages(String chatId) {
    reads++;
    return reads == 1 ? super.messages(chatId) : pending.future;
  }
}

void main() {
  testWidgets('late poll cannot restore conversation content after changing view', (tester) async {
    final repo = DelayedChat();
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: KitchenChatScreen(repository: repo, businessId: 'b', orderId: 'order'))));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'borrador');
    await tester.tap(find.text('Conversaciones'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 10));
    await tester.tap(find.text('Confirmar'));
    await tester.pumpAndSettle();
    repo.pending.complete([{'id': 'late', 'text': 'Mensaje tardío', 'senderRole': 'ALUMNO', 'createdAt': '2026-10-26T12:00:00Z'}]);
    await tester.pumpAndSettle();
    expect(find.text('Mensaje tardío'), findsNothing);
    expect(find.text('Enviar mensaje'), findsNothing);
    expect(find.text('No hay conversaciones activas.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  test(
    'canonical session is limited to the configured same-origin V3 namespace',
    () async {
      var writes = 0;
      final session = RestSession(
        baseUri: Uri.parse('https://test.example/api/legacy/v1/'),
        client: MockClient((request) async {
          dynamic result;
          if (request.url.path.endsWith('auth/login')) {
            result = {
              'tokens': {
                'accessToken': 'test-token',
                'accessTokenExpiresAt': DateTime.now()
                    .toUtc()
                    .add(const Duration(hours: 1))
                    .toIso8601String(),
              },
            };
          } else if (request.url.path.endsWith('users/me')) {
            result = {
              'id': 'k',
              'displayName': 'Cocina',
              'role': 'business',
              'businessId': 'b',
            };
          } else {
            expect(request.url.path, '/api/v1/businesses/b/closing-schedule');
            expect(request.headers['Authorization'], 'Bearer test-token');
            expect(jsonDecode(request.body)['expectedVersion'], 7);
            writes++;
            result = {};
          }
          return http.Response(jsonEncode(result), 200);
        }),
      );
      addTearDown(session.dispose);
      await session.signIn('k@example.edu', 'test-password');
      final client = SessionHttpClient(session, canonical: true);
      final repo = V32Repository(
        ApiClient(
          baseUri: canonicalApiBase(session.api.baseUri),
          client: client,
        ),
      );
      await repo.closing('b', 7, true, '18:30');
      for (final url in [
        'https://evil.example/api/v1/orders',
        'https://test.example/api/legacy/v1/orders',
        'https://test.example/media',
      ]) {
        await expectLater(
          client.send(http.Request('GET', Uri.parse(url))),
          throwsA(isA<ApiException>()),
        );
      }
      expect(writes, 1);
      session.invalidate('revoked');
      await expectLater(
        repo.closing('b', 7, false, '18:30'),
        throwsA(isA<ApiException>()),
      );
      expect(writes, 1);
    },
  );
  test(
    'chat loads beyond page one, including the most recent messages',
    () async {
      final repo = V32Repository(
        ApiClient(
          baseUri: Uri.parse('https://test.example/api/v1/'),
          client: MockClient((r) async {
            final page = int.parse(r.url.queryParameters['page']!);
            return http.Response(
              jsonEncode({
                'data': [
                  {'id': '$page', 'text': page == 2 ? 'último' : 'primero'},
                ],
                'pagination': {'totalPages': 2},
              }),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }),
        ),
      );
      expect((await repo.messages('c')).map((m) => m['id']), ['1', '2']);
    },
  );
  testWidgets('administration can inspect schedule but has no write actions', (
    tester,
  ) async {
    final repo = FakeV32();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ClosingScreen(
            repository: repo,
            businessId: 'b',
            readOnly: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Horario del local · Consulta'), findsOneWidget);
    expect(find.text('Guardar horario'), findsNothing);
    expect(find.text('Guardar espera'), findsNothing);
    expect(find.text('Posponer cierre de hoy'), findsNothing);
    expect(repo.saves, 0);
  });
  testWidgets('invalid schedule never reaches the backend on a narrow screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo = FakeV32();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ClosingScreen(repository: repo, businessId: 'b'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '25:90');
    await tester.ensureVisible(find.text('Guardar horario'));
    await tester.tap(find.text('Guardar horario'));
    await tester.pumpAndSettle();
    expect(repo.saves, 0);
    expect(find.text('Escribe una hora entre 00:00 y 23:59.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'expired chat erases visible messages and draft and cannot be resent',
    (tester) async {
      final repo = FakeV32();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: KitchenChatScreen(
              repository: repo,
              businessId: 'b',
              orderId: 'order',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Mensaje privado de prueba'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Borrador privado');
      repo.closed = true;
      await tester.tap(find.text('Actualizar chat'));
      await tester.pumpAndSettle();
      expect(find.text('Mensaje privado de prueba'), findsNothing);
      expect(find.text('Borrador privado'), findsNothing);
      expect(find.text('Enviar mensaje'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
