bool isValidEmail(String email) {
  final emailRegex = RegExp(
    r'^[\w\.-]+@[\w\.-]+\.\w+$',
  );

  return emailRegex.hasMatch(email);
}
