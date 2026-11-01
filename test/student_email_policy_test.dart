import 'package:flutter_test/flutter_test.dart';
import 'package:snackup/student/email_policy.dart';

void main() {
  test('institutional address accepts exact domain including uppercase', () {
    expect(studentEmailError('alumno.ti23@utsjr.edu.mx'), isNull);
    expect(studentEmailError(' Alumno@UTSJR.EDU.MX '), isNull);
  });

  test('personal, demo and lookalike domains are rejected', () {
    for (final address in [
      'alumno@gmail.com',
      'alumno@students.example.edu',
      'alumno@utsjr.edu.mx.ejemplo.com',
      'alumno@sub.utsjr.edu.mx',
      'alumno@falsoutsjr.edu.mx',
      'alumno@utsjr.edu.mx@ejemplo.com',
      '@utsjr.edu.mx',
      'alumno @utsjr.edu.mx',
      '',
    ]) {
      expect(studentEmailError(address), isNotNull, reason: address);
    }
  });
}
