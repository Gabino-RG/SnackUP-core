import 'dart:async';
import 'package:flutter/foundation.dart';
import 'v32_repository.dart';

/// Activity indicator, not a server-side unread counter. Stores no message text.
class ChatActivity extends ChangeNotifier {
  ChatActivity(this.repository, this.businessId);
  final V32Repository repository;
  final String businessId;
  Timer? _timer;
  bool _disposed = false, _busy = false, _active = false;
  int _failures = 0;
  String? _latest, _seen;
  bool get hasActivity => _latest != null && _latest != _seen;
  bool get unavailable => _failures > 0;

  void acknowledge() {
    _seen = _latest;
    if (!_disposed) notifyListeners();
  }

  void setActive(bool active) {
    _active = active;
    _timer?.cancel();
    if (active) refresh();
  }

  Future<void> refresh() async {
    if (_disposed || _busy || !_active) return;
    _timer?.cancel();
    _busy = true;
    try {
      // The API sorts descending by lastActivityAt. Only the latest activity
      // is needed for a dot; no messages or additional pages are downloaded.
      final result = await repository.chats(businessId, 1);
      if (_disposed || !_active) return;
      final rows = result['data'] as List;
      _latest = rows.isEmpty
          ? null
          : '${rows.first['id']}:${rows.first['lastActivityAt']}';
      _failures = 0;
    } catch (_) {
      if (!_disposed && _active) _failures++;
    } finally {
      _busy = false;
      if (!_disposed && _active) {
        notifyListeners();
        // Avoid hammering an unavailable backend. Resume refreshes immediately.
        final seconds = _failures == 0 ? 15 : (_failures == 1 ? 30 : 60);
        _timer = Timer(Duration(seconds: seconds), refresh);
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}
