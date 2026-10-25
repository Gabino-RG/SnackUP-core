// Browser-only platform boundary. Tokens remain in memory or HttpOnly cookies.
import 'dart:html' as html;
import 'dart:js' show allowInterop;
import 'dart:js_util' as js;
import 'package:http/browser_client.dart';
import 'package:http/http.dart' as http;

http.Client createPlatformClient() => BrowserClient()..withCredentials = true;

Future<T> withSessionLock<T>(Future<T> Function() action) async {
  final locks = js.getProperty<Object?>(html.window.navigator, 'locks');
  if (locks == null)
    throw StateError(
      'La sesión web requiere HTTPS o localhost y un navegador con Web Locks.',
    );
  late T result;
  Object? failure;
  StackTrace? trace;
  final callback = allowInterop((dynamic lock) {
    return js.callConstructor<Object>(
      js.getProperty<Object>(html.window, 'Promise'),
      [
        allowInterop((dynamic resolve, dynamic reject) {
          Future<T>.sync(action).then(
            (value) {
              result = value;
              js.callMethod<Object?>(resolve, 'call', [null, null]);
            },
            onError: (Object error, StackTrace stack) {
              failure = error;
              trace = stack;
              js.callMethod<Object?>(resolve, 'call', [null, null]);
            },
          );
        }),
      ],
    );
  });
  await js.promiseToFuture<Object?>(
    js.callMethod(locks, 'request', ['snackup-api-session', callback]),
  );
  if (failure != null) Error.throwWithStackTrace(failure!, trace!);
  return result;
}

String? takeResetToken() {
  final fragment = Uri.base.fragment;
  final token = Uri.splitQueryString(fragment)['token'];
  if (token == null) return null;
  html.window.history.replaceState(
    null,
    '',
    Uri.base.replace(fragment: '').toString(),
  );
  return token;
}
