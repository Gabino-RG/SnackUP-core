import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snackup/features/user/review_service.dart';

void main() {
  late FakeFirebaseFirestore db;
  late ReviewService service;
  setUp(() async {
    db = FakeFirebaseFirestore();
    service = ReviewService(db);
    await db.collection('orders').doc('order1').set({
      'userId': 'user1',
      'businessId': 'cafe1',
      'status': 'completed',
      'items': [
        {'productId': 'food1', 'name': 'Chilaquiles'},
        {'productId': 'food2', 'name': 'Café'},
      ],
    });
  });
  Future<void> save({
    String userId = 'user1',
    String productId = 'food1',
    int rating = 5,
    String comment = 'Muy rico',
    bool anonymous = false,
  }) => service.save(
    orderId: 'order1',
    productId: productId,
    userId: userId,
    rating: rating,
    comment: comment,
    anonymous: anonymous,
    userName: 'Sofía',
  );
  test('Saves stars and trimmed description for a purchased dish', () async {
    await save(comment: '  Muy rico  ');
    final review = (await db.collection('reviews').doc('order1_food1').get())
        .data()!;
    expect(review['rating'], 5);
    expect(review['comment'], 'Muy rico');
    expect(review['productName'], 'Chilaquiles');
  });
  test('Updates instead of duplicating and allows separate dishes', () async {
    await save();
    await save(rating: 3);
    await save(productId: 'food2');
    expect((await db.collection('reviews').get()).docs.length, 2);
    expect(
      (await db.collection('reviews').doc('order1_food1').get())
          .data()!['rating'],
      3,
    );
  });
  test('Rejects other users and dishes outside the order', () async {
    await expectLater(save(userId: 'another'), throwsStateError);
    await expectLater(save(productId: 'other'), throwsStateError);
    expect((await db.collection('reviews').get()).docs, isEmpty);
  });
  test('Rejects undelivered orders', () async {
    await db.collection('orders').doc('order1').update({'status': 'preparing'});
    await expectLater(save(), throwsStateError);
  });
  test('Validates rating bounds and description length', () async {
    await expectLater(save(rating: 0), throwsStateError);
    await expectLater(save(rating: 6), throwsStateError);
    await expectLater(
      save(comment: List.filled(301, 'a').join()),
      throwsStateError,
    );
  });
  test('Anonymous review omits the public name', () async {
    await save(anonymous: true);
    expect(
      (await db.collection('reviews').doc('order1_food1').get())
          .data()!['userName'],
      'Estudiante anónimo',
    );
  });
}
