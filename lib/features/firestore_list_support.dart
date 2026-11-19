import 'package:cloud_firestore/cloud_firestore.dart';

String firestoreListError(Object? error) {
  if (error is! FirebaseException)
    return 'Intenta volver a abrir esta sección.';
  return switch (error.code) {
    'permission-denied' =>
      'Tu cuenta no tiene permiso para consultar estos datos.',
    'failed-precondition' =>
      'Firestore requiere revisar la configuración de esta consulta.',
    'unavailable' || 'deadline-exceeded' =>
      'Firestore no está disponible en este momento. Intenta de nuevo.',
    _ => 'Firestore devolvió el error: ${error.code}.',
  };
}

int compareMenuProducts(QueryDocumentSnapshot a, QueryDocumentSnapshot b) {
  final left = a.data() as Map<String, dynamic>;
  final right = b.data() as Map<String, dynamic>;
  final category = (left['category']?.toString() ?? '').compareTo(
    right['category']?.toString() ?? '',
  );
  if (category != 0) return category;
  return (left['name']?.toString() ?? '').compareTo(
    right['name']?.toString() ?? '',
  );
}
