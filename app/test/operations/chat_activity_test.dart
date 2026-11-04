import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:snackup/operations/chat_activity.dart';
import 'v32_features_test.dart' show FakeV32;

class ActivityRepo extends FakeV32 {
  int calls = 0;
  String stamp = 'one';
  bool fail = false, empty = false;
  Completer<Map<String, dynamic>>? pending;
  @override
  Future<Map<String, dynamic>> chats(String businessId, int page) async {
    calls++;
    if (pending != null) return pending!.future;
    if (fail) throw StateError('offline');
    return {
      'data': empty
          ? []
          : [
              {'id': 'chat', 'lastActivityAt': stamp},
            ],
    };
  }
}

void main() {
  testWidgets(
    'activity survives failures, acknowledges and clears deleted chats',
    (tester) async {
      final repo = ActivityRepo();
      final activity = ChatActivity(repo, 'b');
      activity.setActive(true);
      await tester.pump();
      expect(activity.hasActivity, isTrue);
      activity.acknowledge();
      expect(activity.hasActivity, isFalse);
      repo.fail = true;
      await tester.pump(const Duration(seconds: 15));
      expect(activity.unavailable, isTrue);
      final calls = repo.calls;
      await tester.pump(const Duration(seconds: 15));
      expect(repo.calls, calls); // Failed requests back off.
      repo.fail = false;
      repo.stamp = 'two';
      await tester.pump(const Duration(seconds: 15));
      expect(activity.unavailable, isFalse);
      expect(activity.hasActivity, isTrue);
      repo.empty = true;
      await activity.refresh();
      expect(activity.hasActivity, isFalse);
      activity.dispose();
    },
  );

  testWidgets('background pauses polling and resume fetches immediately', (
    tester,
  ) async {
    final repo = ActivityRepo();
    final activity = ChatActivity(repo, 'b');
    activity.setActive(true);
    await tester.pump();
    activity.setActive(false);
    await tester.pump(const Duration(minutes: 2));
    expect(repo.calls, 1);
    activity.setActive(true);
    await tester.pump();
    expect(repo.calls, 2);
    activity.dispose();
  });

  testWidgets(
    'logout discards pending response without notifying or restarting',
    (tester) async {
      final repo = ActivityRepo()..pending = Completer();
      final activity = ChatActivity(repo, 'b');
      var notifications = 0;
      activity.addListener(() => notifications++);
      activity.setActive(true);
      activity.refresh();
      expect(repo.calls, 1); // No overlapping calls.
      activity.dispose();
      repo.pending!.complete({
        'data': [
          {'id': 'private', 'lastActivityAt': 'now'},
        ],
      });
      await tester.pump(const Duration(minutes: 2));
      expect(notifications, 0);
      expect(repo.calls, 1);
    },
  );
}
