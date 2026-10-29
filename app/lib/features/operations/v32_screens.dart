import 'dart:async';
import 'package:flutter/material.dart';
import '../../api/api_client.dart';
import '../../operations/models.dart';
import '../../operations/panel_text.dart';
import '../admin/panel_motion.dart';
import '../../operations/v32_repository.dart';

class SpecialOrdersScreen extends StatefulWidget {
  const SpecialOrdersScreen({
    super.key,
    required this.repository,
    required this.businessId,
  });
  final V32Repository repository;
  final String businessId;
  @override
  State<SpecialOrdersScreen> createState() => _SpecialOrdersScreenState();
}

class _SpecialOrdersScreenState extends State<SpecialOrdersScreen> {
  List<Map<String, dynamic>> _orders = [];
  bool _history = false, _busy = false;
  int _page = 1, _pages = 0, _timeout = 30;
  DateTime _day = campusNow();
  String? _error, _notice;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final business = await widget.repository.business(widget.businessId);
      final result = await widget.repository.orders(
        widget.businessId,
        date: _history ? dayKey(_day) : null,
        page: _page,
      );
      if (mounted)
        setState(() {
          _orders = (result['data'] as List).map(object).toList();
          _pages = integer(object(result['pagination']), 'totalPages');
          _timeout = integer(business, 'pickupTimeoutMinutes', minimum: 5);
        });
    } catch (e) {
      if (mounted)
        setState(() {
          _error = v32Message(e);
          _orders = [];
        });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  DateTime? deadline(Map<String, dynamic> order) {
    final ready = DateTime.tryParse('${order['readyAt']}');
    if (ready == null) return null;
    final scheduled = DateTime.tryParse('${order['scheduledPickupTime']}');
    return (scheduled != null && scheduled.isAfter(ready) ? scheduled : ready)
        .add(Duration(minutes: _timeout));
  }

  Future<void> _act(Map<String, dynamic> order, bool release) async {
    if (_busy) return;
    final agreed = await confirmOperation(
      context,
      release
          ? 'Confirmar que el vale NO fue canjeado'
          : 'Cancelar pedido no recogido',
      release
          ? 'Confirma con el responsable que este vale no se utilizó. Se liberará su reserva; un vale consumido nunca se libera.'
          : 'El pedido listo se cancelará sin reponer existencias. Si tiene vale, la reserva se conserva hasta confirmar por separado que no se canjeó.',
    );
    if (!agreed || !mounted || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    String? error;
    try {
      if (release) {
        await widget.repository.releaseVoucher(order);
      } else {
        await widget.repository.notCollected(order, voucherNotRedeemed: false);
      }
    } catch (e) {
      error = v32Message(e);
    }
    if (!mounted) return;
    setState(() => _busy = false);
    await _load();
    if (mounted)
      setState(() {
        _error = error ?? _error;
        _notice = error == null && _error == null
            ? (release
                  ? 'Reserva del vale liberada.'
                  : 'Pedido cancelado porque no se recogió.')
            : null;
      });
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      Text(
        'Pedidos programados y vales',
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      const Text(
        'Las cancelaciones ordinarias se hacen desde Cocina. Aquí puedes gestionar pedidos listos no recogidos y liberar vales de pedidos cancelados.',
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Ver historial para liberar vales'),
        value: _history,
        onChanged: _busy
            ? null
            : (value) {
                setState(() {
                  _history = value;
                  _page = 1;
                  _notice = null;
                });
                _load();
              },
      ),
      if (_history)
        OutlinedButton(
          onPressed: _busy
              ? null
              : () async {
                  final chosen = await showDatePicker(
                    context: context,
                    initialDate: _day,
                    firstDate: DateTime(2020),
                    lastDate: campusNow(),
                  );
                  if (chosen != null && mounted) {
                    setState(() {
                      _day = chosen;
                      _page = 1;
                    });
                    _load();
                  }
                },
          child: Text('Día ${dayKey(_day)}'),
        ),
      TextButton(
        onPressed: _busy ? null : _load,
        child: const Text('Actualizar pedidos y plazos'),
      ),
      if (_busy) const LinearProgressIndicator(),
      if (_error != null)
        Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
      if (_notice != null) Text(_notice!),
      if (!_busy && _orders.isEmpty)
        const Text('No hay pedidos en esta página.'),
      for (final order in _orders)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Pedido #${order['orderNumber']} · ${order['customerName']}',
                ),
                Text(
                  '${KitchenStatus.values.firstWhere((s) => s.name == order['status']).label} · ${paymentLabel(order['paymentMethod'])}',
                ),
                if (order['scheduledPickupTime'] != null)
                  Text(
                    'Recogida programada: ${campusStamp(DateTime.tryParse('${order['scheduledPickupTime']}'))}',
                  ),
                if (order['status'] == 'ready') ...[
                  Text('Plazo de recogida: ${campusStamp(deadline(order))}'),
                  TextButton(
                    onPressed:
                        _busy ||
                            deadline(order) == null ||
                            DateTime.now().toUtc().isBefore(deadline(order)!)
                        ? null
                        : () => _act(order, false),
                    child: const Text('No recogido: cancelar'),
                  ),
                ],
                if (order['status'] == 'cancelled' &&
                    order['paymentMethod'] == 'ValeComida')
                  TextButton(
                    onPressed: _busy ? null : () => _act(order, true),
                    child: const Text(
                      'Confirmar que el vale no se canjeó y liberarlo',
                    ),
                  ),
              ],
            ),
          ),
        ),
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            tooltip: 'Página anterior',
            onPressed: _busy || _page <= 1
                ? null
                : () {
                    setState(() => _page--);
                    _load();
                  },
            icon: const Icon(Icons.chevron_left),
          ),
          Flexible(
            child: Text(
              'Página $_page de ${_pages == 0 ? 1 : _pages}',
              textAlign: TextAlign.center,
            ),
          ),
          IconButton(
            tooltip: 'Página siguiente',
            onPressed: _busy || _page >= _pages
                ? null
                : () {
                    setState(() => _page++);
                    _load();
                  },
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
    ],
  );
}

class DetailedStatsScreen extends StatefulWidget {
  const DetailedStatsScreen({
    super.key,
    required this.repository,
    required this.businessId,
  });
  final V32Repository repository;
  final String businessId;
  @override
  State<DetailedStatsScreen> createState() => _DetailedStatsScreenState();
}

class _DetailedStatsScreenState extends State<DetailedStatsScreen> {
  Map<String, dynamic>? _data;
  int _days = 7;
  bool _busy = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final today = campusNow();
      final result = await widget.repository.stats(
        widget.businessId,
        dayKey(today.subtract(Duration(days: _days - 1))),
        dayKey(today),
      );
      if (mounted) setState(() => _data = result);
    } catch (e) {
      if (mounted)
        setState(() {
          _error = v32Message(e);
          _data = null;
        });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      Text(
        'Estadísticas del local',
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      const Text(
        'Ventas de pedidos entregados, según la fecha de entrega y la zona horaria del local. El medio de pago registrado no acredita un cobro ni una conciliación bancaria.',
      ),
      Wrap(
        spacing: 8,
        children: [
          for (final days in [7, 30])
            ChoiceChip(
              label: Text('Últimos $days días'),
              selected: _days == days,
              onSelected: _busy
                  ? null
                  : (_) {
                      setState(() => _days = days);
                      _load();
                    },
            ),
          TextButton(
            onPressed: _busy ? null : _load,
            child: const Text('Actualizar estadísticas'),
          ),
        ],
      ),
      if (_busy) const LinearProgressIndicator(),
      if (_error != null)
        Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
      if (_data != null) ...[
        Text(
          'Entregados: ${_data!['completed']} · Cancelados: ${_data!['cancelled']} · Ventas: ${money(cents(_data!['totalSold']))}',
        ),
        const SizedBox(height: 16),
        const Text(
          'Por medio de pago',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        for (final row in _data!['paymentMethods'] as List)
          ListTile(
            title: Text(paymentLabel(row['paymentMethod'])),
            subtitle: Text('Pedidos entregados: ${row['completed']}'),
            trailing: Text(money(cents(row['totalSold']))),
          ),
        const Text(
          'Productos más vendidos',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        for (final row in _data!['topProducts'] as List)
          ListTile(
            title: Text('${row['name']}'),
            subtitle: Text('Unidades: ${row['quantity']}'),
            trailing: Text(money(cents(row['totalSold']))),
          ),
        const Text(
          'Detalle diario',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        for (final row in _data!['daily'] as List)
          ListTile(
            title: Text('${row['date']}'),
            subtitle: Text(
              'Entregados: ${row['completed']} · Cancelados: ${row['cancelled']}',
            ),
            trailing: Text(money(cents(row['totalSold']))),
          ),
      ],
    ],
  );
}

Future<bool> confirmOperation(
  BuildContext context,
  String title,
  String message,
) async =>
    await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Volver'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    ) ??
    false;

class V32OperationsScreen extends StatefulWidget {
  const V32OperationsScreen({
    super.key,
    required this.repository,
    required this.businessId,
  });
  final V32Repository repository;
  final String businessId;
  @override
  State<V32OperationsScreen> createState() => _V32OperationsScreenState();
}

class _V32OperationsScreenState extends State<V32OperationsScreen> {
  int _section = 0;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Padding(
        padding: const EdgeInsets.all(12),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final entry in [
              'Chat',
              'Horarios',
              'Pedidos y vales',
              'Estadísticas',
            ].asMap().entries)
              ChoiceChip(
                label: Text(entry.value),
                selected: _section == entry.key,
                onSelected: (_) => setState(() => _section = entry.key),
              ),
          ],
        ),
      ),
      Expanded(
        child: PanelEntrance(
          key: ValueKey('operation-$_section'),
          child: switch (_section) {
            0 => KitchenChatScreen(
              repository: widget.repository,
              businessId: widget.businessId,
            ),
            1 => ClosingScreen(
              repository: widget.repository,
              businessId: widget.businessId,
            ),
            2 => SpecialOrdersScreen(
              repository: widget.repository,
              businessId: widget.businessId,
            ),
            _ => DetailedStatsScreen(
              repository: widget.repository,
              businessId: widget.businessId,
            ),
          },
        ),
      ),
    ],
  );
}

class ClosingScreen extends StatefulWidget {
  const ClosingScreen({
    super.key,
    required this.repository,
    required this.businessId,
    this.readOnly = false,
  });
  final V32Repository repository;
  final String businessId;
  final bool readOnly;
  @override
  State<ClosingScreen> createState() => _ClosingScreenState();
}

class _ClosingScreenState extends State<ClosingScreen> {
  Map<String, dynamic>? _business;
  final _time = TextEditingController(), _timeout = TextEditingController();
  bool _enabled = false, _busy = false;
  String? _error, _notice;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _time.dispose();
    _timeout.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final b = await widget.repository.business(widget.businessId);
      if (!mounted) return;
      setState(() {
        _business = b;
        _enabled = b['autoCloseEnabled'] == true;
        _time.text = b['closeTimeLocal'] as String? ?? '';
        _timeout.text = '${b['pickupTimeoutMinutes']}';
      });
    } catch (e) {
      if (mounted)
        setState(() {
          _error = v32Message(e);
          _business = null;
        });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save(Future<void> Function(int) action) async {
    if (_busy || _business == null) return;
    final version = integer(_business!, 'version', minimum: 1);
    setState(() {
      _busy = true;
      _notice = null;
      _error = null;
    });
    String? error;
    try {
      await action(version);
    } catch (e) {
      error = v32Message(e);
    }
    if (!mounted) return;
    await _load();
    if (mounted)
      setState(() {
        _error = error ?? _error;
        _notice = error == null && _error == null
            ? 'Configuración guardada.'
            : null;
      });
  }

  Future<void> _postpone() async {
    final chosen = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(campusNow()),
    );
    if (chosen == null || !mounted) return;
    final today = campusNow();
    // This portal's campus is Mexico City (UTC-6). Disable this conversion for
    // any differently configured business instead of silently using device time.
    final until = DateTime.utc(
      today.year,
      today.month,
      today.day,
      chosen.hour + 6,
      chosen.minute,
    );
    if (!await confirmOperation(
      context,
      'Posponer cierre de hoy',
      'Cerrar a las ${chosen.hour.toString().padLeft(2, '0')}:${chosen.minute.toString().padLeft(2, '0')} (America/Mexico_City). Esto no reabre un local cerrado.',
    ))
      return;
    if (mounted)
      await _save(
        (version) =>
            widget.repository.postpone(widget.businessId, version, until),
      );
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      Text(
        widget.readOnly
            ? 'Horario del local · Consulta'
            : 'Horarios y recogida',
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      const SizedBox(height: 12),
      const Text(
        'El cierre detiene los pedidos nuevos y permite atender los recibidos. Los programados no se cancelan automáticamente. La apertura siempre es manual.',
      ),
      if (_busy) const LinearProgressIndicator(),
      if (_error != null)
        Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
      if (_notice != null) Text(_notice!),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: _busy ? null : _load,
          icon: const Icon(Icons.refresh),
          label: const Text('Actualizar horario'),
        ),
      ),
      if (_business != null) ...[
        Text('Zona horaria del local: ${_business!['timezone']}'),
        Text('Estado: ${_business!['isOpen'] == true ? 'Abierto' : 'Cerrado'}'),
        if (_business!['postponedCloseAt'] != null)
          Text('Cierre pospuesto: ${_business!['postponedCloseAt']}'),
        if (widget.readOnly)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Cierre automático'),
            subtitle: Text(_enabled ? 'Activado' : 'Desactivado'),
          )
        else
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Cierre automático'),
            value: _enabled,
            onChanged: widget.readOnly || _busy
                ? null
                : (value) => setState(() => _enabled = value),
          ),
        const SizedBox(height: 16),
        if (widget.readOnly)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Hora de cierre'),
            subtitle: Text(_time.text.isEmpty ? 'Sin configurar' : _time.text),
          )
        else
          TextField(
            controller: _time,
            enabled: !widget.readOnly && !_busy,
            decoration: const InputDecoration(
              labelText: 'Hora de cierre (HH:mm)',
              hintText: '18:30',
            ),
          ),
        if (!widget.readOnly) ...[
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _busy
                ? null
                : () {
                    final time = _time.text.trim();
                    if ((_enabled || time.isNotEmpty) &&
                        !RegExp(
                          r'^(?:[01][0-9]|2[0-3]):[0-5][0-9]$',
                        ).hasMatch(time)) {
                      setState(
                        () => _error = 'Escribe una hora entre 00:00 y 23:59.',
                      );
                      return;
                    }
                    _save(
                      (v) => widget.repository.closing(
                        widget.businessId,
                        v,
                        _enabled,
                        time.isEmpty ? null : time,
                      ),
                    );
                  },
            child: const Text('Guardar horario'),
          ),
          OutlinedButton(
            onPressed:
                _busy ||
                    _business!['autoCloseEnabled'] != true ||
                    _business!['timezone'] != 'America/Mexico_City'
                ? null
                : _postpone,
            child: const Text('Posponer cierre de hoy'),
          ),
        ],
        const Divider(height: 32),
        const Text(
          'Puedes cancelar un pedido listo que no se haya recogido cuando venza este plazo. Se cuenta desde que el pedido está listo o desde la hora de recogida programada, lo que ocurra después. La cancelación no repone existencias.',
        ),
        const SizedBox(height: 16),
        if (widget.readOnly)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Espera de recogida'),
            subtitle: Text('${_timeout.text} minutos'),
          )
        else
          TextField(
            controller: _timeout,
            enabled: !widget.readOnly && !_busy,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Espera de recogida (5–180 minutos)',
            ),
          ),
        if (!widget.readOnly)
          FilledButton(
            onPressed: _busy
                ? null
                : () {
                    final value = int.tryParse(_timeout.text);
                    if (value == null || value < 5 || value > 180) {
                      setState(
                        () => _error =
                            'La espera debe estar entre 5 y 180 minutos.',
                      );
                      return;
                    }
                    _save(
                      (v) => widget.repository.timeout(
                        widget.businessId,
                        v,
                        value,
                      ),
                    );
                  },
            child: const Text('Guardar espera'),
          ),
      ],
    ],
  );
}

class KitchenChatScreen extends StatefulWidget {
  const KitchenChatScreen({
    super.key,
    required this.repository,
    required this.businessId,
    this.orderId,
  });
  final V32Repository repository;
  final String businessId;
  final String? orderId;
  @override
  State<KitchenChatScreen> createState() => _KitchenChatScreenState();
}

class _KitchenChatScreenState extends State<KitchenChatScreen>
    with WidgetsBindingObserver {
  final _draft = TextEditingController();
  Timer? _poll;
  List<Map<String, dynamic>> _chats = [], _messages = [];
  String? _chat, _error;
  bool _loading = false, _writing = false, _visible = true;
  bool _loadFailed = false;
  int _page = 1, _pages = 0, _revision = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
    _poll = Timer.periodic(const Duration(seconds: 10), (_) {
      if (_visible) _load();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _visible = state == AppLifecycleState.resumed;
    if (_visible) _load();
  }

  @override
  void dispose() {
    _revision++;
    _poll?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _draft.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    if (widget.orderId != null) {
      setState(() => _writing = true);
      try {
        final chat = await widget.repository.openChat(
          widget.businessId,
          widget.orderId!,
        );
        if (mounted) _chat = requiredText(chat, 'id');
      } catch (e) {
        if (mounted) setState(() => _error = v32Message(e));
      } finally {
        if (mounted) setState(() => _writing = false);
      }
    }
    if (mounted) _load();
  }

  Future<void> _load() async {
    if (_loading || _writing || !mounted) return;
    final revision = ++_revision, selected = _chat;
    setState(() => _loading = true);
    try {
      if (selected == null) {
        final data = await widget.repository.chats(widget.businessId, _page);
        if (mounted && revision == _revision)
          setState(() {
            if (_loadFailed) _error = null;
            _loadFailed = false;
            _chats = (data['data'] as List).map(object).toList();
            _pages = integer(object(data['pagination']), 'totalPages');
          });
      } else {
        final messages = await widget.repository.messages(selected);
        if (mounted && revision == _revision)
          setState(() {
            if (_loadFailed) _error = null;
            _loadFailed = false;
            _messages = messages;
          });
      }
    } catch (e) {
      if (mounted && revision == _revision)
        setState(() {
          _loadFailed = true;
          _error = v32Message(e);
          if (e is ApiException && e.code == 'CHAT_NOT_FOUND') {
            _chat = null;
            _messages = [];
            _draft.clear();
          }
        });
    } finally {
      if (mounted && revision == _revision) setState(() => _loading = false);
    }
  }

  Future<void> _select(String? id) async {
    if (_writing || _loading) return;
    if (_draft.text.isNotEmpty &&
        !await confirmOperation(
          context,
          'Cambiar conversación',
          'Se descartará el mensaje sin enviar.',
        ))
      return;
    if (!mounted) return;
    setState(() {
      _revision++;
      _loading = false;
      _chat = id;
      _messages = [];
      _draft.clear();
      _error = null;
    });
    _load();
  }

  Future<void> _send() async {
    final selected = _chat, text = _draft.text.trim();
    if (_writing ||
        _loading ||
        selected == null ||
        text.isEmpty ||
        text.length > 1000)
      return;
    setState(() {
      _writing = true;
      _loadFailed = false;
      _error = null;
    });
    try {
      await widget.repository.send(selected, text);
      if (mounted) _draft.clear();
      await Future<void>.delayed(const Duration(seconds: 1));
    } catch (e) {
      if (mounted)
        setState(
          () => _error =
              '${v32Message(e)} Comprueba los mensajes antes de repetir el envío.',
        );
    } finally {
      if (mounted) {
        setState(() => _writing = false);
        _load();
      }
    }
  }

  Future<void> _close() async {
    if (_writing || _loading || _chat == null) return;
    final selected = _chat!;
    if (!await confirmOperation(
      context,
      'Cerrar y borrar conversación',
      'Se borrarán la conversación y sus mensajes del servidor para ambos participantes. No podrás recuperar este historial.',
    ))
      return;
    if (!mounted) return;
    setState(() {
      _revision++;
      _loading = false;
      _writing = true;
      _error = null;
    });
    try {
      await widget.repository.closeChat(selected);
      if (mounted)
        setState(() {
          _chat = null;
          _messages = [];
          _draft.clear();
        });
    } catch (e) {
      if (mounted) setState(() => _error = v32Message(e));
    } finally {
      if (mounted) {
        setState(() => _writing = false);
        _load();
      }
    }
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final compact =
          constraints.maxHeight < 600 ||
          MediaQuery.textScalerOf(context).scale(14) > 18;
      if (compact)
        return SingleChildScrollView(child: _content(context, compact: true));
      return _content(context, compact: false);
    },
  );

  Widget _messageArea({required bool compact, required Widget child}) =>
      compact ? SizedBox(height: 240, child: child) : Expanded(child: child);

  Widget _content(BuildContext context, {required bool compact}) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Chat con alumnos',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const Text(
              'Los mensajes se actualizan cada 10 segundos mientras esta pantalla está abierta. Las conversaciones vencen tras 24 horas de inactividad. Para iniciar una, usa “Chat del pedido” en Cocina.',
            ),
            if (_error != null)
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            Wrap(
              spacing: 8,
              children: [
                TextButton(
                  onPressed: _loading || _writing
                      ? null
                      : () {
                          setState(() => _error = null);
                          _load();
                        },
                  child: const Text('Actualizar chat'),
                ),
                if (_chat != null) ...[
                  TextButton(
                    onPressed: _loading || _writing
                        ? null
                        : () => _select(null),
                    child: const Text('Conversaciones'),
                  ),
                  TextButton(
                    onPressed: _loading || _writing ? null : _close,
                    child: const Text('Cerrar y borrar'),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
      if (_loading || _writing) const LinearProgressIndicator(),
      _messageArea(
        compact: compact,
        child: _chat == null
            ? ListView(
                children: [
                  if (_chats.isEmpty && !_loading)
                    const ListTile(
                      title: Text('No hay conversaciones activas.'),
                    ),
                  for (final chat in _chats)
                    ListTile(
                      leading: const Icon(Icons.chat_bubble_outline),
                      title: Text(
                        chat['orderId'] == null
                            ? 'Consulta de alumno'
                            : 'Pedido ${chat['orderId']}',
                      ),
                      subtitle: Text(
                        'Último mensaje: ${campusStamp(DateTime.tryParse('${chat['lastActivityAt']}'))}',
                      ),
                      onTap: _loading || _writing
                          ? null
                          : () => _select(requiredText(chat, 'id')),
                    ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        tooltip: 'Conversaciones anteriores',
                        onPressed: _loading || _page <= 1
                            ? null
                            : () {
                                setState(() => _page--);
                                _load();
                              },
                        icon: const Icon(Icons.chevron_left),
                      ),
                      Flexible(
                        child: Text(
                          'Página $_page de ${_pages == 0 ? 1 : _pages}',
                          textAlign: TextAlign.center,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Más conversaciones',
                        onPressed: _loading || _page >= _pages
                            ? null
                            : () {
                                setState(() => _page++);
                                _load();
                              },
                        icon: const Icon(Icons.chevron_right),
                      ),
                    ],
                  ),
                ],
              )
            : ListView(
                reverse: true,
                padding: const EdgeInsets.all(12),
                children: [
                  for (final message in _messages.reversed)
                    Align(
                      alignment: message['senderRole'] == 'COCINA'
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                message['senderRole'] == 'COCINA'
                                    ? 'Cocina'
                                    : 'Alumno',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text('${message['text']}'),
                              Text(
                                campusStamp(
                                  DateTime.tryParse('${message['createdAt']}'),
                                ),
                                style: const TextStyle(fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
      ),
      if (_chat != null)
        Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              TextField(
                controller: _draft,
                enabled: !_writing,
                maxLength: 1000,
                minLines: 1,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Mensaje al alumno',
                ),
              ),
              FilledButton(
                onPressed: _writing || _loading ? null : _send,
                child: const Text('Enviar mensaje'),
              ),
            ],
          ),
        ),
    ],
  );
}
