import 'package:firebase_core/firebase_core.dart';

String reviewErrorMessage(Object error) {
  if (error is StateError) return error.message.toString();
  if (error is FirebaseException) {
    switch (error.code) {
      case 'permission-denied':
        return 'Firebase rechazó el guardado por permisos (permission-denied). '
            'Se deben revisar las reglas de Firestore para las valoraciones. Tu comentario se conserva.';
      case 'unauthenticated':
        return 'Tu sesión ya no es válida (unauthenticated). Inicia sesión de nuevo para enviar tu valoración.';
      case 'unavailable':
        return 'Firestore no está disponible en este momento (unavailable). '
            'Puede ser el servicio o la comunicación con Firebase. Tu comentario se conserva; intenta de nuevo.';
      case 'deadline-exceeded':
        return 'Firebase tardó demasiado en responder (deadline-exceeded). Tu comentario se conserva; intenta de nuevo.';
      case 'failed-precondition':
        return 'Firebase requiere revisar la configuración de la base de datos (failed-precondition). '
            'Tu comentario se conserva.';
      case 'aborted':
        return 'El pedido cambió mientras se guardaba la valoración (aborted). Intenta enviarla otra vez.';
      default:
        return 'Firebase no pudo guardar tu valoración (${error.code}). Tu comentario se conserva.';
    }
  }
  return 'No se pudo guardar tu valoración por un error inesperado. '
      'Tu comentario se conserva. Consulta el detalle en la consola de la aplicación.';
}
