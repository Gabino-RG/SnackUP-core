/// Presentation labels only; API values stay unchanged.
String paymentLabel(Object? value) => switch (value) {
  'ValeComida' => 'Vale de comida',
  null || '' => 'Sin especificar',
  _ => value.toString(),
};

String counted(int count, String singular, String plural) =>
    '$count ${count == 1 ? singular : plural}';
