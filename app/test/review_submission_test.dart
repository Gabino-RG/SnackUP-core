import 'package:flutter_test/flutter_test.dart';
import 'package:snackup/features/user/review_submission.dart';

void main() {
  ReviewSubmission review({
    int rating = 4,
    int service = 5,
    int food = 3,
    String career = '',
    String group = '',
    String comment = '',
  }) => ReviewSubmission(
    rating: rating,
    serviceRating: service,
    foodRating: food,
    career: career,
    group: group,
    comment: comment,
  );

  group('Opinión del alumno', () {
    test('normaliza variantes sin eliminar acentos ni el comentario', () {
      final submission = review(
        career: '  Ingeniería   en\nProcesos  ',
        group: ' ds02sv-25 ',
        comment: '  Buena comida.\nServicio lento.  ',
      );
      expect(submission.career, 'Ingeniería en Procesos');
      expect(submission.group, 'DS02SV-25');
      expect(submission.comment, 'Buena comida.\nServicio lento.');
    });

    test('acepta una opinión sin perfil académico para cuentas anteriores', () {
      final submission = review(career: '  ', group: '\t');
      expect(submission.career, isEmpty);
      expect(submission.group, isEmpty);
    });

    test('no envía calificaciones parciales ni fuera de la escala', () {
      for (final invalid in [-1, 0, 6]) {
        expect(
          () => review(rating: invalid),
          throwsA(isA<ReviewSubmissionException>()),
        );
        expect(
          () => review(service: invalid),
          throwsA(isA<ReviewSubmissionException>()),
        );
        expect(
          () => review(food: invalid),
          throwsA(isA<ReviewSubmissionException>()),
        );
      }
      expect(review(rating: 1, service: 5, food: 1).rating, 1);
    });

    test('rechaza textos demasiado largos en vez de truncar la opinión', () {
      expect(review(comment: 'a' * 1500).comment.length, 1500);
      expect(
        () => review(comment: 'a' * 1501),
        throwsA(isA<ReviewSubmissionException>()),
      );
      expect(
        () => review(career: 'a' * 121),
        throwsA(isA<ReviewSubmissionException>()),
      );
      expect(
        () => review(group: 'a' * 41),
        throwsA(isA<ReviewSubmissionException>()),
      );
    });

    test('no incluye nombre, correo ni matrícula en una reseña nueva', () {
      final document = review().toDocument(
        orderId: 'pedido',
        businessId: 'local',
        userId: 'uid',
        createdAt: 123,
      );
      expect(document.keys, isNot(contains('userName')));
      expect(document.keys, isNot(contains('email')));
      expect(document.keys, isNot(contains('numeroDeControl')));
      expect(document['orderId'], 'pedido');
    });
  });

  group('Pedido elegible para reseña', () {
    const completed = {
      'userId': 'alumno',
      'businessId': 'cafeteria',
      'status': 'completed',
    };

    void validate(Map<String, dynamic>? order) => validateReviewOrder(
      order: order,
      userId: 'alumno',
      businessId: 'cafeteria',
    );

    test('permite el pedido completado del alumno y local correctos', () {
      expect(() => validate(completed), returnsNormally);
    });

    test(
      'rechaza un pedido inexistente o perteneciente a otra cuenta o local',
      () {
        for (final order in [
          null,
          {...completed, 'userId': 'otro'},
          {...completed, 'businessId': 'otro'},
        ]) {
          expect(
            () => validate(order),
            throwsA(isA<ReviewSubmissionException>()),
          );
        }
      },
    );

    test('no permite calificar pedidos pendientes, en curso o cancelados', () {
      for (final status in ['pending', 'preparing', 'ready', 'cancelled', '']) {
        expect(
          () => validate({...completed, 'status': status}),
          throwsA(isA<ReviewSubmissionException>()),
        );
      }
    });
  });
}
