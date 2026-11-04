import 'models.dart';

/// Presentation labels only; API values stay unchanged.
String paymentLabel(Object? value) => switch (value) {
  'cash' => 'Efectivo',
  'card' => 'Tarjeta',
  'voucher' || 'ValeComida' => 'Vale de comida',
  null || '' => 'Sin especificar',
  _ => value.toString(),
};

String cancelReasonLabel(String? value) => switch (value) {
  'user_other' => 'Otro motivo indicado por el alumno',
  'student_cancelled' => 'Cancelado por el alumno',
  'not_picked_up' => 'Pedido no recogido',
  null || '' => 'Sin especificar',
  _ => cancelReasons[value] ?? 'Motivo no disponible',
};

String counted(int count, String singular, String plural) =>
    '$count ${count == 1 ? singular : plural}';
