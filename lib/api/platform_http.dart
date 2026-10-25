import 'package:http/http.dart' as http;

http.Client createPlatformClient() => http.Client();
Future<T> withSessionLock<T>(Future<T> Function() action) => action();
String? takeResetToken() => null;
