import 'dart:js_interop';

@JS('history.replaceState')
external void _replaceState(JSAny? state, JSString title, JSString url);

void clearAuthFragment() {
  _replaceState(null, ''.toJS, Uri.base.replace(fragment: '').toString().toJS);
}
