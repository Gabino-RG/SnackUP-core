import 'dart:async';
import 'dart:js_interop';

import 'package:http/browser_client.dart';
import 'package:http/http.dart' as http;

const bool webSession = true;

http.Client createClient() => BrowserClient()..withCredentials = true;

@JS('navigator.locks')
external _LockManager? get _locks;

extension type _LockManager(JSObject _) implements JSObject {
  external JSPromise<JSAny?> request(String name, JSFunction callback);
}

/// Cookie rotation must finish before another tab uses the refresh cookie.
/// Never exchange or persist access/refresh tokens between tabs.
Future<T> withAuthLock<T>(String name, Future<T> Function() action) async {
  final locks = _locks;
  if (locks == null) {
    throw StateError('Usa HTTPS o localhost en un navegador con Web Locks.');
  }
  final result = Completer<T>();
  JSPromise<JSAny?> run(JSAny? _) {
    return Future<JSAny?>(() async {
      try {
        result.complete(await action());
      } catch (error, stack) {
        result.completeError(error, stack);
      }
      return null;
    }).toJS;
  }

  // Await the result immediately too, so a rejected action is never unhandled
  // while the browser is resolving the lock request's promise.
  final waiting = locks.request(name, run.toJS).toDart;
  return await Future.wait<dynamic>([
    result.future,
    waiting,
  ]).then((values) => values.first as T);
}

String? validateOrigin(Uri uri) {
  if (uri.origin != Uri.base.origin) {
    return 'Abre la aplicación desde el mismo origen que la API. '
        'Este backend no admite solicitudes web entre orígenes distintos.';
  }
  return null;
}
