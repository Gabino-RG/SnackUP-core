import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../notifications/push_notifications_card.dart';
import 'student_api.dart';
import 'student_widgets.dart';

class StudentPushNotificationsCard extends StatelessWidget {
  const StudentPushNotificationsCard({super.key});

  @override
  Widget build(BuildContext context) {
    final api = context.watch<StudentApi>();
    if (!api.signedIn) return const SizedBox.shrink();
    return PushNotificationsCard(
      sessionKey: '${api.user?['id']}|${api.sessionGeneration}',
      request: (method, path, {body}) =>
          api.request(method, '/$path', body: body),
      errorMessage: friendlyError,
      registrationIsMissing: (error) =>
          error is ApiException && error.status == 404,
    );
  }
}
