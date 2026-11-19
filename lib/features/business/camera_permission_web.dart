import 'dart:js_interop';

@JS('navigator')
external _Navigator get _navigator;

extension type _Navigator(JSObject _) implements JSObject {
  external _Permissions? get permissions;
}

extension type _Permissions(JSObject _) implements JSObject {
  external JSPromise<_PermissionStatus> query(_PermissionDescriptor descriptor);
}

extension type _PermissionDescriptor._(JSObject _) implements JSObject {
  external factory _PermissionDescriptor({String name});
}

extension type _PermissionStatus(JSObject _) implements JSObject {
  external String get state;
  external void addEventListener(String type, JSFunction callback);
  external void removeEventListener(String type, JSFunction callback);
}

Future<void Function()> watchCameraPermission(void Function() onGranted) async {
  try {
    final permissions = _navigator.permissions;
    if (permissions == null) return () {};

    final status = await permissions.query(
      _PermissionDescriptor(name: 'camera'),
    ).toDart;
    void reportGrant() {
      if (status.state == 'granted') onGranted();
    }

    final onChange = ((JSAny? event) => reportGrant()).toJS;
    status.addEventListener('change', onChange);
    reportGrant();
    return () => status.removeEventListener('change', onChange);
  } catch (_) {
    // The scanner button still works when the Permissions API is unavailable.
    return () {};
  }
}
