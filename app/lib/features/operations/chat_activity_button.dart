import 'package:flutter/material.dart';
import '../../operations/chat_activity.dart';
import '../../operations/v32_repository.dart';
import 'v32_screens.dart';

class ChatActivityButton extends StatefulWidget {
  const ChatActivityButton({
    super.key,
    required this.repository,
    required this.businessId,
  });
  final V32Repository repository;
  final String businessId;
  @override
  State<ChatActivityButton> createState() => _ChatActivityButtonState();
}

class _ChatActivityButtonState extends State<ChatActivityButton>
    with WidgetsBindingObserver {
  late final ChatActivity activity;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    activity = ChatActivity(widget.repository, widget.businessId);
    activity.setActive(
      WidgetsBinding.instance.lifecycleState == null ||
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) =>
      activity.setActive(state == AppLifecycleState.resumed);

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    activity.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: activity,
    builder: (context, _) => IconButton(
      tooltip: activity.unavailable
          ? 'Avisos de chat sin conexión. Abrir y reintentar'
          : activity.hasActivity
          ? 'Actividad en chats: revisar conversaciones'
          : 'Abrir conversaciones',
      icon: Badge(
        isLabelVisible: activity.hasActivity || activity.unavailable,
        backgroundColor: activity.unavailable ? Colors.orange : null,
        child: const Icon(Icons.chat_outlined),
      ),
      onPressed: () async {
        activity.acknowledge();
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => Scaffold(
              appBar: AppBar(title: const Text('Conversaciones del local')),
              body: KitchenChatScreen(
                repository: widget.repository,
                businessId: widget.businessId,
              ),
            ),
          ),
        );
        if (mounted) activity.refresh();
      },
    ),
  );
}
