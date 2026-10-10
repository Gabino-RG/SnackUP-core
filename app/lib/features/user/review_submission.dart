/// A review belongs to a completed order and does not publish a student name.
/// Academic labels are self-declared, optional segmentation data.
class ReviewSubmission {
  static const maxCareerLength = 120;
  static const maxGroupLength = 40;
  static const maxCommentLength = 1500;

  final int rating;
  final int serviceRating;
  final int foodRating;
  final String career;
  final String group;
  final String comment;

  factory ReviewSubmission({
    required int rating,
    required int serviceRating,
    required int foodRating,
    required String career,
    required String group,
    required String comment,
  }) {
    if ([
      rating,
      serviceRating,
      foodRating,
    ].any((value) => value < 1 || value > 5)) {
      throw const ReviewSubmissionException(
        'Selecciona de 1 a 5 estrellas en las tres calificaciones.',
      );
    }
    final normalizedCareer = normalizeAcademicLabel(career);
    final normalizedGroup = normalizeAcademicLabel(group).toUpperCase();
    final normalizedComment = comment.trim();
    final errors = [
      validateTextLength(normalizedCareer, maxCareerLength, 'La carrera'),
      validateTextLength(normalizedGroup, maxGroupLength, 'El grupo'),
      validateTextLength(normalizedComment, maxCommentLength, 'El comentario'),
    ].whereType<String>();
    if (errors.isNotEmpty) {
      throw ReviewSubmissionException(errors.first);
    }
    return ReviewSubmission._(
      rating,
      serviceRating,
      foodRating,
      normalizedCareer,
      normalizedGroup,
      normalizedComment,
    );
  }

  const ReviewSubmission._(
    this.rating,
    this.serviceRating,
    this.foodRating,
    this.career,
    this.group,
    this.comment,
  );

  Map<String, dynamic> toDocument({
    required String orderId,
    required String businessId,
    required String userId,
    required Object createdAt,
  }) => {
    'orderId': orderId,
    'businessId': businessId,
    'userId': userId,
    'rating': rating,
    'serviceRating': serviceRating,
    'foodRating': foodRating,
    'career': career,
    'group': group,
    'comment': comment,
    'createdAt': createdAt,
    'schemaVersion': 2,
  };
}

String normalizeAcademicLabel(String value) =>
    value.trim().replaceAll(RegExp(r'\s+'), ' ');

String? validateTextLength(String value, int maximum, String label) =>
    value.runes.length > maximum
    ? '$label debe tener como máximo $maximum caracteres.'
    : null;

/// Server rules enforce the same relationship; this check gives a useful message
/// before attempting a write and also runs when a transaction is retried.
void validateReviewOrder({
  required Map<String, dynamic>? order,
  required String userId,
  required String businessId,
}) {
  if (order == null || order['userId'] != userId) {
    throw const ReviewSubmissionException(
      'No se encontró un pedido tuyo para esta reseña.',
    );
  }
  if (order['businessId'] != businessId) {
    throw const ReviewSubmissionException(
      'El pedido no corresponde a este local.',
    );
  }
  if (order['status'] != 'completed') {
    throw const ReviewSubmissionException(
      'Podrás calificar el pedido cuando esté completado.',
    );
  }
}

class ReviewSubmissionException implements Exception {
  final String message;

  const ReviewSubmissionException(this.message);
}
