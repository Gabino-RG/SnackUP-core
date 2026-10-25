import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:snackup/api/api_client.dart';
import 'package:snackup/api/student_store.dart';
import 'package:snackup/student_api/auth_screen.dart';

void main() {
  testWidgets('Student API login has no cafeteria staff access', (
    tester,
  ) async {
    final api = ApiClient(
      base: Uri.parse('https://campus.test/api/v1/'),
      web: true,
      transport: MockClient((_) async => http.Response('{}', 500)),
    );
    final store = StudentStore(api, realtimeEnabled: false);
    addTearDown(store.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: store,
        child: const MaterialApp(home: StudentAuthScreen()),
      ),
    );
    expect(find.text('Acceso para Negocios'), findsNothing);
    expect(find.text('Crear cuenta nueva'), findsOneWidget);
    expect(find.text('Iniciar sesión'), findsOneWidget);
  });
}
