import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snackup/features/user/review_error.dart';

void main() {
  test(
    'Permission denial identifies rules and does not blame the internet',
    () {
      final message = reviewErrorMessage(
        FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied'),
      );
      expect(message, contains('permission-denied'));
      expect(message, contains('reglas de Firestore'));
      expect(message, isNot(contains('Revisa tu conexión')));
    },
  );
  test(
    'Session, service and validation failures have distinct explanations',
    () {
      expect(
        reviewErrorMessage(
          FirebaseException(plugin: 'cloud_firestore', code: 'unauthenticated'),
        ),
        contains('sesión'),
      );
      expect(
        reviewErrorMessage(
          FirebaseException(plugin: 'cloud_firestore', code: 'unavailable'),
        ),
        contains('unavailable'),
      );
      expect(
        reviewErrorMessage(
          StateError('Solo puedes valorar tus pedidos entregados.'),
        ),
        'Solo puedes valorar tus pedidos entregados.',
      );
      expect(
        reviewErrorMessage(Exception('unknown')),
        contains('error inesperado'),
      );
    },
  );
}
