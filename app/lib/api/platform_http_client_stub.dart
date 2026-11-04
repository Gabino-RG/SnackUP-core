import 'package:http/http.dart' as http;

// VM implementation is used by tests. Production portal authentication is web-only.
http.Client createPortalHttpClient() => http.Client();
