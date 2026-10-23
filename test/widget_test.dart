import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snackup/features/auth/login_screen.dart';

void main() {
  testWidgets('Customer login has no cafeteria staff access', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));
    expect(find.text('Acceso para Negocios'), findsNothing);
    expect(find.text('Crear Cuenta Nueva'), findsOneWidget);
  });
}
