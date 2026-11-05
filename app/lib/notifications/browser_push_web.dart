import 'dart:convert';
import 'dart:js_interop';

@JS('snackupPush')
external JSObject? get _bridge;

@JS('snackupPush.status')
external JSPromise<JSString> _status();

@JS('snackupPush.activate')
external JSPromise<JSString> _activate(JSString publicKey);

@JS('snackupPush.deactivate')
external JSPromise<JSString> _deactivate();

@JS('snackupPush.cancelActivation')
external void _cancelActivation();

Future<Map<String, dynamic>> _decode(JSPromise<JSString> operation) async {
  final value = jsonDecode((await operation.toDart).toDart);
  return Map<String, dynamic>.from(value as Map);
}

Future<Map<String, dynamic>> browserPushStatus() => _bridge == null
    ? Future.value({
        'supported': false,
        'permission': 'unavailable',
        'reason': 'BRIDGE_UNAVAILABLE',
        'subscribed': false,
      })
    : _decode(_status());

Future<Map<String, dynamic>> activateBrowserPush(String publicKey) =>
    _bridge == null
    ? Future.value({'error': 'BRIDGE_UNAVAILABLE'})
    : _decode(_activate(publicKey.toJS));

Future<Map<String, dynamic>> deactivateBrowserPush() => _bridge == null
    ? Future.value({'error': 'BRIDGE_UNAVAILABLE'})
    : _decode(_deactivate());

void cancelBrowserPushActivation() {
  if (_bridge != null) _cancelActivation();
}
