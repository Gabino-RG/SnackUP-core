import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:snackup/features/user/show_qr_screen.dart';
import 'package:snackup/features/user/rate_order_screen.dart';
import 'package:snackup/features/user/review_service.dart';

void main() {
  testWidgets(
    'Delivery removes pickup QR and shows thanks without closing route',
    (tester) async {
      tester.view.physicalSize = const Size(390, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final db = FakeFirebaseFirestore();
      final order = db.collection('orders').doc('delivery');
      await order.set({
        'status': 'ready',
        'userId': 'student',
        'businessId': 'cafe',
        'totalPrice': 55,
        'items': [],
      });
      await tester.pumpWidget(
        MaterialApp(
          home: ShowQrScreen(
            orderId: 'delivery',
            qrData: 'delivery',
            firestore: db,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(QrImageView), findsOneWidget);
      expect(find.text('Tu pedido está listo'), findsOneWidget);
      await order.update({'status': 'completed'});
      await tester.pumpAndSettle();
      expect(find.byType(QrImageView), findsNothing);
      expect(find.text('Tu pedido está listo'), findsNothing);
      expect(find.text('¡Gracias por tu compra!'), findsOneWidget);
      expect(find.text('Valorar restaurante'), findsOneWidget);
      expect(find.byType(ShowQrScreen), findsOneWidget);
      await order.update({'status': 'cancelled'});
      await tester.pumpAndSettle();
      expect(find.byType(QrImageView), findsNothing);
      expect(find.text('Valorar restaurante'), findsNothing);
      expect(find.textContaining('Pedido cancelado.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Delivered order can rate restaurant with stars and comment without choosing a dish',
    (tester) async {
      final db = FakeFirebaseFirestore();
      await db.collection('orders').doc('order').set({
        'status': 'completed',
        'userId': 'student',
        'businessId': 'cafe',
        'items': [],
      });
      await tester.pumpWidget(
        MaterialApp(
          home: RateOrderScreen(
            orderId: 'order',
            businessId: 'cafe',
            businessName: 'Cafetería Central',
            restaurant: true,
            firestore: db,
            userId: 'student',
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Valorar restaurante'), findsOneWidget);
      expect(find.text('Selecciona tu platillo'), findsNothing);
      await tester.tap(find.byTooltip('4 de 5 estrellas'));
      await tester.enterText(
        find.byType(TextField),
        'Excelente atención en el local',
      );
      final send = find.text('Enviar calificación');
      tester.testTextInput.hide();
      await tester.scrollUntilVisible(
        send,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(send);
      await tester.pumpAndSettle();
      final review =
          (await db.collection('restaurant_reviews').doc('order').get())
              .data()!;
      expect(review['businessId'], 'cafe');
      expect(review['rating'], 4);
      expect(review['comment'], 'Excelente atención en el local');
    },
  );

  test(
    'Restaurant rating is updated per order and rejects undelivered or foreign orders',
    () async {
      final db = FakeFirebaseFirestore();
      final order = db.collection('orders').doc('order');
      await order.set({
        'status': 'completed',
        'userId': 'student',
        'businessId': 'cafe',
      });
      final service = ReviewService(db);
      Future<void> save({String userId = 'student', int rating = 5}) =>
          service.save(
            orderId: 'order',
            userId: userId,
            rating: rating,
            comment: 'Muy buen servicio',
            anonymous: false,
            userName: 'Alumno',
          );
      await save();
      await save(rating: 4);
      expect((await db.collection('restaurant_reviews').get()).docs.length, 1);
      expect(
        (await db.collection('restaurant_reviews').doc('order').get())
            .data()!['rating'],
        4,
      );
      expect((await db.collection('reviews').get()).docs, isEmpty);
      await expectLater(save(userId: 'another'), throwsStateError);
      await order.update({'status': 'ready'});
      await expectLater(save(), throwsStateError);
      await order.update({'status': 'cancelled'});
      await expectLater(save(), throwsStateError);
    },
  );
}
