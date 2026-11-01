const institutionalStudentDomain = 'utsjr.edu.mx';

String? studentEmailError(
  String? value, {
  String domain = institutionalStudentDomain,
}) {
  final email = value?.trim() ?? '';
  if (email.length > 254 || !RegExp(r'^\S+@[^\s@]+$').hasMatch(email)) {
    return 'Escribe tu correo institucional.';
  }
  if (email.split('@').length != 2 ||
      email.split('@').last.toLowerCase() != domain) {
    return 'Usa tu correo @$domain.';
  }
  return null;
}
