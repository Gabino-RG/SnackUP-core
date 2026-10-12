// ignore: deprecated_member_use
import 'dart:html' as html;
import 'dart:async';
import 'dart:convert';

/// Notifications invalidate REST data; event payloads never authorize UI writes.
class OperationsRealtime {
  OperationsRealtime({required this.baseUri, required this.businessId,
    required this.token, required this.changed, required this.connected});
  final Uri baseUri;
  final String businessId;
  final Future<String> Function() token;
  final void Function() changed;
  final void Function(bool) connected;
  html.WebSocket? _socket;
  Timer? _retry, _refresh, _deadline;
  final _subscriptions = <StreamSubscription<dynamic>>[];
  bool _closed = false;
  int _failures = 0;
  final _seen = <String>{};
  void start() {
    if (_closed || _socket != null) return;
    try {
      final socket = html.WebSocket(baseUri.resolve('realtime').replace(scheme: baseUri.scheme == 'https' ? 'wss' : 'ws').toString());
      _socket = socket;
      _deadline = Timer(const Duration(seconds: 10), _disconnect);
      _subscriptions.add(socket.onOpen.listen((_) async {
        try {
          final access = await token();
          if (_closed || !identical(_socket,socket)) return;
          socket.send(jsonEncode({'action':'auth','token':access}));
          socket.send(jsonEncode({'action':'subscribe','topics':['business:$businessId:orders','business:$businessId']}));
        } catch (_) { _disconnect(); }
      }));
      _subscriptions.add(socket.onMessage.listen((event) {
        try {
          final data = jsonDecode(event.data as String);
          if (data is! Map) return;
          if (data['type'] == 'ping') { socket.send('{"action":"pong"}'); return; }
          if (data['type'] == 'subscribed') {
            final topics = data['topics'];
            if (topics is! List || !topics.contains('business:$businessId:orders')) return;
            _deadline?.cancel(); _failures = 0; connected(true); changed();
            _refresh?.cancel(); _refresh = Timer.periodic(const Duration(minutes: 1), (_) async {
              try { final access = await token(); if (!_closed && identical(_socket,socket)) socket.send(jsonEncode({'action':'auth','token':access})); }
              catch (_) { _disconnect(); }
            });
            return;
          }
          if (data['type'] == 'error' || data['type'] == 'unauthorized') { _disconnect(); return; }
          if (!['business:$businessId:orders','business:$businessId'].contains(data['topic'])) return;
          if (!['order.created','order.updated','business.updated'].contains(data['type'])) return;
          final id = data['id'];
          if (id is! String || !_seen.add(id)) return;
          if (_seen.length > 1000) _seen.remove(_seen.first);
          changed();
        } catch (_) { /* An invalid event cannot replace authoritative REST state. */ }
      }));
      _subscriptions.add(socket.onClose.listen((_) => _disconnect()));
      _subscriptions.add(socket.onError.listen((_) => _disconnect()));
    } catch (_) { _disconnect(); }
  }
  void _disconnect() {
    if (_closed) return;
    _clear(); connected(false);
    _failures++;
    _retry?.cancel();
    _retry = Timer(Duration(seconds: _failures >= 3 ? 60 : 10), start);
  }
  void _clear() {
    _deadline?.cancel(); _refresh?.cancel();
    for (final sub in _subscriptions) { sub.cancel(); }
    _subscriptions.clear(); final socket = _socket; _socket = null; socket?.close();
  }
  void close() { _closed = true; _retry?.cancel(); _clear(); }
}
