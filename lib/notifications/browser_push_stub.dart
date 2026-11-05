Future<Map<String, dynamic>> browserPushStatus() async => {
  'supported': false,
  'permission': 'unavailable',
  'reason': 'UNSUPPORTED',
  'subscribed': false,
};

Future<Map<String, dynamic>> activateBrowserPush(String publicKey) async => {
  'error': 'UNSUPPORTED',
};

Future<Map<String, dynamic>> deactivateBrowserPush() async => {
  'unsubscribed': true,
};

void cancelBrowserPushActivation() {}
