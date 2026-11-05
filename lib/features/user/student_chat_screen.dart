import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:snackup/student/student_api.dart';
import 'package:snackup/student/student_widgets.dart';
import 'package:snackup/theme/student_colors.dart';
import 'package:snackup/theme/student_text.dart';

class StudentChatScreen extends StatefulWidget {
  const StudentChatScreen({
    super.key,
    this.businessId,
    this.orderId,
    this.businessName,
  });

  final String? businessId;
  final String? orderId;
  final String? businessName;

  @override
  State<StudentChatScreen> createState() => _StudentChatScreenState();
}

class _StudentChatScreenState extends State<StudentChatScreen>
    with WidgetsBindingObserver {
  StudentApi? _api;
  String? _ownerId, _chatId, _businessId, _orderId;
  int? _generation;
  final _draft = TextEditingController();
  final _messageScroll = ScrollController();
  final Map<String, String> _businessNames = {};
  List<Map<String, dynamic>> _chats = [], _messages = [];
  int _listPage = 1, _listPages = 1, _messagePage = 0, _messagePages = 1;
  int _viewRevision = 0;
  bool _loading = false, _writing = false, _foreground = true;
  bool _closed = false, _followLatest = true, _restoringDraft = false;
  bool _cooldown = false, _sendUncertain = false;
  bool _apiInstanceValid = true;
  Object? _error;
  String? _notice;
  Timer? _poll, _cooldownTimer;

  bool get _sameSession =>
      _api != null &&
      _apiInstanceValid &&
      _ownerId != null &&
      _api!.user?['id'] == _ownerId &&
      _api!.sessionGeneration == _generation;

  bool _current(int revision) =>
      mounted && _sameSession && revision == _viewRevision;

  String _path(String id) => Uri.encodeComponent(id);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _draft.addListener(_rememberDraft);
    _poll = Timer.periodic(const Duration(seconds: 10), (_) {
      if (_foreground && mounted && ModalRoute.of(context)?.isCurrent == true) {
        unawaited(_load());
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final api = context.watch<StudentApi>();
    if (_api != null) {
      if (!identical(_api, api)) _apiInstanceValid = false;
      return;
    }
    _api = api;
    _ownerId = api.user?['id'] as String?;
    _generation = api.sessionGeneration;
    if (widget.businessId != null && widget.businessName != null) {
      _businessNames[widget.businessId!] = widget.businessName!;
    }
    if (widget.businessId != null) {
      unawaited(_open(widget.businessId!, widget.orderId));
    } else {
      unawaited(_load());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground && mounted && ModalRoute.of(context)?.isCurrent == true) {
      unawaited(_load());
    }
  }

  void _rememberDraft() {
    if (_restoringDraft || !_sameSession || _chatId == null) return;
    _api!.saveChatDraft(_chatId!, _draft.text);
    if (mounted) setState(() {});
  }

  void _restoreDraft() {
    final text = _chatId == null ? '' : _api!.chatDraft(_chatId!);
    _restoringDraft = true;
    _draft.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    _restoringDraft = false;
    _sendUncertain = _chatId != null && _api!.chatSendUncertain(_chatId!);
    if (_sendUncertain) {
      _notice =
          'Hay un envío sin confirmar. Revisa los mensajes antes de volver a enviar para evitar duplicados. Tu borrador se conservó.';
    }
  }

  List<Map<String, dynamic>> _rows(Map<String, dynamic> page) {
    final data = page['data'];
    if (data is! List || page['pagination'] is! Map) {
      throw const ApiException(
        0,
        'INVALID_RESPONSE',
        'No pudimos leer la conversación. Actualiza para intentarlo de nuevo.',
      );
    }
    return data.map((row) => Map<String, dynamic>.from(row as Map)).toList();
  }

  int _pages(Map<String, dynamic> page) {
    final total = (page['pagination'] as Map)['totalPages'];
    if (total is! num) {
      throw const ApiException(
        0,
        'INVALID_RESPONSE',
        'No pudimos leer las páginas de la conversación.',
      );
    }
    return total < 1 ? 1 : total.toInt();
  }

  Future<void> _loadBusinessName(String businessId, int revision) async {
    if (_businessNames.containsKey(businessId)) return;
    try {
      final business = await _api!.getObject(
        '/businesses/${_path(businessId)}',
      );
      final name = business['name'];
      if (!_current(revision) || _businessId != businessId) return;
      if (name is String && name.trim().isNotEmpty) {
        setState(() => _businessNames[businessId] = name);
      }
    } catch (_) {
      // The optional heading lookup must not hide or delay the conversation.
    }
  }

  Future<void> _open(String businessId, String? orderId) async {
    if (_loading || _writing || !_sameSession) return;
    final revision = ++_viewRevision;
    setState(() {
      _writing = true;
      _error = null;
      _notice = null;
    });
    try {
      final response = await _api!.request(
        'POST',
        '/businesses/${_path(businessId)}/chats',
        body: {if (orderId != null) 'orderId': orderId},
      );
      if (!_current(revision)) return;
      final chat = Map<String, dynamic>.from(response as Map);
      setState(() {
        _chatId = chat['id'] as String;
        _businessId = businessId;
        _orderId = orderId;
        _closed = false;
        _messagePage = 0;
        _followLatest = true;
        _sendUncertain = false;
        _messages = [];
        _restoreDraft();
      });
      unawaited(_loadBusinessName(businessId, revision));
    } catch (error) {
      if (_current(revision)) setState(() => _error = error);
    } finally {
      if (_current(revision)) {
        setState(() => _writing = false);
        if (_chatId != null) await _load();
      }
    }
  }

  Future<void> _load() async {
    if (_loading || _writing || _closed || !_sameSession) return;
    final revision = _viewRevision;
    final selected = _chatId;
    setState(() => _loading = true);
    try {
      if (selected == null) {
        if (_businessNames.isEmpty) {
          final businesses = await _api!.getAll('/businesses');
          if (!_current(revision)) return;
          for (final business in businesses) {
            _businessNames[business['id'] as String] =
                business['name'] as String;
          }
        }
        var page = await _api!.getObject(
          '/users/me/chats',
          query: {'page': '$_listPage', 'limit': '20'},
        );
        if (!_current(revision)) return;
        final pages = _pages(page);
        if (_listPage > pages) {
          page = await _api!.getObject(
            '/users/me/chats',
            query: {'page': '$pages', 'limit': '20'},
          );
          if (!_current(revision)) return;
        }
        final chats = _rows(page);
        setState(() {
          _chats = chats;
          _listPages = pages;
          if (_listPage > pages) _listPage = pages;
          _error = null;
        });
      } else {
        var requestedPage = _messagePage < 1 ? 1 : _messagePage;
        var page = await _api!.getObject(
          '/chats/${_path(selected)}/messages',
          query: {'page': '$requestedPage', 'limit': '100'},
        );
        if (!_current(revision)) return;
        final pages = _pages(page);
        if (_followLatest && requestedPage != pages) {
          requestedPage = pages;
          page = await _api!.getObject(
            '/chats/${_path(selected)}/messages',
            query: {'page': '$requestedPage', 'limit': '100'},
          );
          if (!_current(revision)) return;
        }
        final messages = _rows(page);
        final lastId = _messages.lastOrNull?['id'];
        setState(() {
          _messages = messages;
          _messagePage = requestedPage;
          _messagePages = _pages(page);
          _error = null;
        });
        if (_followLatest && messages.lastOrNull?['id'] != lastId) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_current(revision) && _messageScroll.hasClients) {
              _messageScroll.jumpTo(_messageScroll.position.maxScrollExtent);
            }
          });
        }
      }
    } catch (error) {
      if (_current(revision)) {
        if (error is ApiException &&
            error.code == 'CHAT_NOT_FOUND' &&
            selected != null) {
          _api!.clearChatDraft(selected);
          _api!.setChatSendUncertain(selected, false);
          setState(() {
            _messages = [];
            _closed = true;
            _draft.clear();
            _notice =
                'Esta conversación se cerró o venció. Sus mensajes ya no están disponibles.';
            _error = null;
          });
        } else {
          setState(() => _error = error);
        }
      }
    } finally {
      if (_current(revision)) setState(() => _loading = false);
    }
  }

  void _select(Map<String, dynamic>? chat) {
    if (_loading || _writing || !_sameSession) return;
    setState(() {
      _viewRevision++;
      _chatId = chat?['id'] as String?;
      _businessId = chat?['businessId'] as String?;
      _orderId = chat?['orderId'] as String?;
      _closed = false;
      _messages = [];
      _messagePage = 0;
      _followLatest = true;
      _error = null;
      _notice = null;
      _sendUncertain = false;
      _restoreDraft();
    });
    if (_businessId != null) {
      unawaited(_loadBusinessName(_businessId!, _viewRevision));
    }
    unawaited(_load());
  }

  Future<void> _send() async {
    final selected = _chatId;
    final text = _draft.text.trim();
    if (_writing ||
        _loading ||
        _cooldown ||
        _sendUncertain ||
        _closed ||
        !_sameSession ||
        selected == null ||
        text.isEmpty ||
        text.runes.length > 1000) {
      return;
    }
    final revision = _viewRevision;
    setState(() {
      _writing = true;
      _error = null;
      _notice = null;
    });
    try {
      await _api!.request(
        'POST',
        '/chats/${_path(selected)}/messages',
        body: {'text': text},
      );
      if (!_current(revision)) return;
      _api!.clearChatDraft(selected, matchingText: text);
      _api!.setChatSendUncertain(selected, false);
      _draft.clear();
      setState(() {
        _followLatest = true;
        _cooldown = true;
      });
      _cooldownTimer?.cancel();
      _cooldownTimer = Timer(const Duration(seconds: 1), () {
        if (mounted) setState(() => _cooldown = false);
      });
    } catch (error) {
      if (_current(revision)) {
        setState(() {
          _error = error;
          _sendUncertain =
              error is! ApiException ||
              error.status == 0 ||
              error.status >= 500;
          _api!.setChatSendUncertain(selected, _sendUncertain);
          _notice = friendlyError(error);
          if (_sendUncertain) {
            _notice =
                'No se pudo confirmar el envío. Revisa los mensajes antes de volver a enviar para evitar duplicados. Tu borrador se conservó.';
          }
        });
      }
    } finally {
      if (_current(revision)) {
        setState(() => _writing = false);
        await _load();
      }
    }
  }

  Future<void> _close() async {
    if (_chatId == null || _writing || _loading || !_sameSession) return;
    final selected = _chatId!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Cerrar y borrar conversación'),
        content: const Text(
          'Se eliminarán los mensajes para ti y para Cocina. Esta acción no se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Volver'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Cerrar y borrar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || !_sameSession) return;
    final revision = _viewRevision;
    setState(() {
      _writing = true;
      _error = null;
    });
    try {
      await _api!.request('DELETE', '/chats/${_path(selected)}');
      if (!_current(revision)) return;
      _api!.clearChatDraft(selected);
      _api!.setChatSendUncertain(selected, false);
      setState(() {
        _messages = [];
        _draft.clear();
        _closed = true;
        _notice = 'La conversación se cerró y sus mensajes se eliminaron.';
      });
    } catch (error) {
      if (_current(revision)) {
        setState(() {
          _error = error;
          _notice = 'No se pudo confirmar el cierre. ${friendlyError(error)}';
        });
      }
    } finally {
      if (_current(revision)) {
        setState(() => _writing = false);
        if (!_closed) await _load();
      }
    }
  }

  Widget _pagination({
    required int page,
    required int total,
    required String noun,
    required ValueChanged<int> change,
  }) => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      IconButton(
        tooltip: '$noun anteriores',
        onPressed: _loading || _writing || page <= 1
            ? null
            : () => change(page - 1),
        icon: const Icon(Icons.chevron_left),
      ),
      Text('Página $page de $total'),
      IconButton(
        tooltip: 'Más ${noun.toLowerCase()}',
        onPressed: _loading || _writing || page >= total
            ? null
            : () => change(page + 1),
        icon: const Icon(Icons.chevron_right),
      ),
    ],
  );

  Widget _list() => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      const Text('Conversaciones con Cocina', style: AppText.h3),
      const SizedBox(height: 8),
      const Text(
        'Para iniciar una conversación, abre uno de tus pedidos y elige “Chat con Cocina”. Las conversaciones vencen tras 24 horas sin actividad.',
        style: AppText.notes,
      ),
      if (_error != null)
        ErrorPanel(
          error: _error!,
          onRetry: () {
            if (widget.businessId != null && _chatId == null) {
              unawaited(_open(widget.businessId!, widget.orderId));
            } else {
              unawaited(_load());
            }
          },
        ),
      if (_loading || _writing) const LinearProgressIndicator(),
      if (_chats.isEmpty && !_loading && !_writing && _error == null)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 40),
          child: Text('No tienes conversaciones activas.'),
        ),
      for (final chat in _chats)
        Card(
          child: ListTile(
            leading: const Icon(Icons.chat_bubble_outline),
            title: Text(
              _businessNames[chat['businessId']] ?? 'Conversación con el local',
            ),
            subtitle: Text(
              'Último mensaje: ${dateText(chat['lastActivityAt'])}',
            ),
            trailing: const Icon(Icons.chevron_right),
            enabled: !_loading && !_writing,
            onTap: () => _select(chat),
          ),
        ),
      _pagination(
        page: _listPage,
        total: _listPages,
        noun: 'Conversaciones',
        change: (page) {
          setState(() => _listPage = page);
          unawaited(_load());
        },
      ),
    ],
  );

  Widget _messageList() => ListView.builder(
    controller: _messageScroll,
    padding: const EdgeInsets.symmetric(vertical: 12),
    itemCount: _messages.isEmpty ? 1 : _messages.length,
    itemBuilder: (context, index) {
      if (_messages.isEmpty) {
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            _loading ? 'Consultando mensajes…' : 'Aún no hay mensajes.',
          ),
        );
      }
      final message = _messages[index];
      final own = message['senderRole'] == 'ALUMNO';
      return Align(
        alignment: own ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 540),
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: own ? AppColors.paleBlue : AppColors.background,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.borders),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                own ? 'Tú' : 'Cocina',
                style: AppText.body.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              SelectableText(message['text'] as String),
              const SizedBox(height: 6),
              Text(dateText(message['createdAt']), style: AppText.notes),
            ],
          ),
        ),
      );
    },
  );

  Widget _conversation(bool compact) {
    final length = _draft.text.trim().runes.length;
    final canSend =
        !_loading &&
        !_writing &&
        !_closed &&
        !_cooldown &&
        !_sendUncertain &&
        length > 0 &&
        length <= 1000;
    return Column(
      mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          spacing: 8,
          children: [
            TextButton.icon(
              onPressed: _loading || _writing ? null : () => _select(null),
              icon: const Icon(Icons.forum_outlined),
              label: const Text('Conversaciones'),
            ),
            if (!_closed)
              TextButton(
                onPressed: _loading || _writing ? null : _close,
                child: const Text('Cerrar y borrar'),
              ),
          ],
        ),
        Text(
          _businessNames[_businessId] ?? 'Chat con Cocina',
          style: AppText.h3,
        ),
        const SizedBox(height: 6),
        const Text(
          'Una conversación por local: puede incluir otros pedidos tuyos. Se actualiza cada 10 segundos mientras esté abierta y vence tras 24 horas sin actividad.',
          style: AppText.notes,
        ),
        if (_loading || _writing) const LinearProgressIndicator(),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              friendlyError(_error!),
              style: const TextStyle(color: AppColors.error),
            ),
          ),
        if (_notice != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(_notice!),
          ),
        if (_closed) ...[
          const SizedBox(height: 12),
          if (_businessId != null)
            OutlinedButton(
              onPressed: _writing ? null : () => _open(_businessId!, _orderId),
              child: const Text('Comenzar otra conversación'),
            ),
        ] else ...[
          if (compact)
            SizedBox(height: 250, child: _messageList())
          else
            Expanded(child: _messageList()),
          _pagination(
            page: _messagePage < 1 ? 1 : _messagePage,
            total: _messagePages,
            noun: 'Mensajes',
            change: (page) {
              setState(() {
                _messagePage = page;
                _followLatest = page == _messagePages;
              });
              unawaited(_load());
            },
          ),
          TextField(
            controller: _draft,
            enabled: !_writing,
            maxLength: 1000,
            minLines: 1,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: 'Mensaje a Cocina',
              hintText: 'Escribe tu consulta sobre el pedido',
              errorText: length > 1000
                  ? 'El mensaje admite hasta 1000 caracteres.'
                  : null,
              border: const OutlineInputBorder(),
            ),
          ),
          if (_sendUncertain)
            TextButton(
              onPressed: _loading || _writing || _error != null
                  ? null
                  : () => setState(() {
                      _sendUncertain = false;
                      _notice = null;
                      _api!.setChatSendUncertain(_chatId!, false);
                    }),
              child: const Text('Ya revisé los mensajes; habilitar envío'),
            ),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: canSend ? _send : null,
              icon: const Icon(Icons.send_outlined),
              label: Text(_writing ? 'Espera…' : 'Enviar mensaje'),
            ),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    context.watch<StudentApi>();
    return PopScope(
      canPop: !_writing || !_sameSession,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && mounted && _writing && _sameSession) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Espera a que termine la operación antes de salir.',
              ),
            ),
          );
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Chat con Cocina'),
          actions: [
            IconButton(
              tooltip: 'Actualizar conversaciones',
              onPressed: _loading || _writing || _closed || !_sameSession
                  ? null
                  : _load,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: !_sameSession
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'Tu sesión cambió. Vuelve a abrir el chat desde tu cuenta.',
                  ),
                ),
              )
            : Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 820),
                  child: _chatId == null
                      ? _list()
                      : LayoutBuilder(
                          builder: (context, constraints) {
                            final compact =
                                constraints.maxHeight < 560 ||
                                MediaQuery.textScalerOf(context).scale(14) > 20;
                            final content = Padding(
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                              child: _conversation(compact),
                            );
                            return compact
                                ? SingleChildScrollView(child: content)
                                : content;
                          },
                        ),
                ),
              ),
      ),
    );
  }

  @override
  void dispose() {
    _viewRevision++;
    _poll?.cancel();
    _cooldownTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _draft.removeListener(_rememberDraft);
    _draft.dispose();
    _messageScroll.dispose();
    super.dispose();
  }
}
