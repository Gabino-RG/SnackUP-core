import 'package:http/http.dart' as http;

const bool webSession = false;

http.Client createClient() => http.Client();

Future<T> withAuthLock<T>(String name, Future<T> Function() action) => action();

String? validateOrigin(Uri uri) => null;
