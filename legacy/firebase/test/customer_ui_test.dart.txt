import 'dart:io';
import 'dart:ui' as ui;
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snackup/features/home/user_home_screen.dart';
import 'package:snackup/theme/app_colors.dart';

void main() {
  testWidgets('Mobile menu filters real categories without overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final font = FontLoader('Lato')
      ..addFont(rootBundle.load('assets/fonts/Lato/Lato-Regular.ttf'));
    await font.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
    final db = FakeFirebaseFirestore();
    await db.collection('products').doc('food').set({
      'name': 'Chilaquiles verdes con pollo',
      'description': 'Salsa verde y pollo deshebrado',
      'price': 55,
      'isAvailable': true,
      'stock': 8,
      'isFeatured': true,
      'category': 'Desayunos',
    });
    await db.collection('products').doc('coffee').set({
      'name': 'Café americano',
      'price': 20,
      'isAvailable': true,
      'stock': 8,
      'category': 'Bebidas',
    });
    await db.collection('businesses').doc('cafe').set({
      'name': 'Cafetería Central',
      'isOpen': true,
    });
    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          useMaterial3: true,
          fontFamily: 'Lato',
          scaffoldBackgroundColor: AppColors.background,
          colorScheme: ColorScheme.fromSeed(seedColor: AppColors.primary),
        ),
        home: RepaintBoundary(
          key: key,
          child: UserHomeScreen(firestore: db),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Menú del campus'), findsOneWidget);
    await db.collection('products').doc('food').update({'stock': 0});
    await tester.pumpAndSettle();
    expect(find.text('Chilaquiles verdes con pollo'), findsNothing);
    await db.collection('products').doc('food').update({'stock': 8});
    await tester.pumpAndSettle();
    expect(find.text('Chilaquiles verdes con pollo'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
    await tester.runAsync(() async {
      final image =
          await (key.currentContext!.findRenderObject()
                  as RenderRepaintBoundary)
              .toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('build/customer-menu-preview.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
    await tester.ensureVisible(find.widgetWithText(ChoiceChip, 'Bebidas'));
    await tester.tap(find.widgetWithText(ChoiceChip, 'Bebidas'));
    await tester.pumpAndSettle();
    expect(find.text('Café americano'), findsOneWidget);
    // The featured promotion remains visible; the filtered menu only shows coffee.
    expect(find.text('Chilaquiles verdes con pollo'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
