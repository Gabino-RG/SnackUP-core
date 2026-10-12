import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:flutter/material.dart';
import '../../catalog/catalog.dart';
import '../../operations/models.dart';
import '../../operations/kitchen_controller.dart';
import '../../operations/operations_repository.dart';
import '../../operations/realtime.dart';
import '../catalog/catalog_screen.dart';
import '../admin/admin_theme.dart';
import 'order_dialogs.dart';
import 'history_screen.dart';
import 'record_editor.dart';

class BusinessPortal extends StatefulWidget {
  const BusinessPortal({
    super.key,
    required this.businessId,
    required this.catalog,
    required this.repository,
    required this.token,
    required this.onSignOut,
    this.enableRealtime = true,
  });
  final String businessId;
  final CatalogRepository catalog;
  final OperationsRepository repository;
  final Future<String> Function() token;
  final VoidCallback onSignOut;
  final bool enableRealtime;
  @override
  State<BusinessPortal> createState() => _BusinessPortalState();
}

class _BusinessPortalState extends State<BusinessPortal>
    with WidgetsBindingObserver {
  late final KitchenController _kitchen;
  OperationsRealtime? _realtime;
  Timer? _poll, _eventDebounce;
  AudioPlayer? _audio;
  int _section = 0, _mobileColumn = 0;
  bool _sound = false, _live = false, _visible = true;
  String _search = '';
  final _searchField = TextEditingController();
  static const _labels = [
    'Cocina',
    'Productos',
    'Historial',
    'Resumen',
    'Mi local',
  ];
  static const _icons = [
    Icons.restaurant_menu,
    Icons.inventory_2_outlined,
    Icons.receipt_long_outlined,
    Icons.bar_chart,
    Icons.storefront,
  ];
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _kitchen = KitchenController(widget.repository, widget.businessId)
      ..onNewOrders = _notify;
    _kitchen.refresh();
    _startUpdates();
  }

  void _startUpdates() {
    if (!_visible) return;
    _poll?.cancel();
    _poll = Timer.periodic(
      Duration(seconds: _live ? 60 : 10),
      (_) => _kitchen.refresh(),
    );
    if (widget.enableRealtime && _realtime == null) {
      _realtime = OperationsRealtime(
        baseUri: widget.repository.api.baseUri,
        businessId: widget.businessId,
        token: widget.token,
        changed: () {
          _eventDebounce?.cancel();
          _eventDebounce = Timer(
            const Duration(milliseconds: 350),
            _kitchen.refresh,
          );
        },
        connected: (value) {
          if (mounted && _visible) {
            setState(() => _live = value);
            _poll?.cancel();
            _poll = Timer.periodic(
              Duration(seconds: value ? 60 : 10),
              (_) => _kitchen.refresh(),
            );
          }
        },
      );
      _realtime!.start();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _visible = state == AppLifecycleState.resumed;
    if (_visible) {
      _kitchen.refresh();
      _startUpdates();
    } else {
      _poll?.cancel();
      _eventDebounce?.cancel();
      _realtime?.close();
      _realtime = null;
      _live = false;
    }
  }

  Future<void> _notify() async {
    if (_sound) {
      try {
        _audio ??= AudioPlayer();
        await _audio!.play(AssetSource('sounds/notification_bell.mp3'));
      } catch (_) {
        if (mounted) setState(() => _sound = false);
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _poll?.cancel();
    _eventDebounce?.cancel();
    _realtime?.close();
    _audio?.dispose();
    _kitchen.dispose();
    _searchField.dispose();
    super.dispose();
  }

  void _message(Object e) {
    if (mounted)
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(operationsMessage(e))));
  }

  Future<void> _action(KitchenOrder order) async {
    if (order.status == KitchenStatus.ready) {
      await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => OrderActionDialog(
          order: order,
          controller: _kitchen,
          cancel: false,
        ),
      );
    } else {
      try {
        await _kitchen.act(order, order.status.action!);
      } catch (e) {
        _message(e);
      }
    }
  }

  Future<void> _open(bool value) async {
    final agreed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          value ? 'Abrir recepción de pedidos' : 'Cerrar recepción de pedidos',
        ),
        content: Text(
          value
              ? 'Los clientes podrán enviar pedidos a tu local.'
              : 'Se pausarán los pedidos nuevos. Los pedidos que ya recibiste siguen pendientes de atención.',
        ),
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
    );
    if (agreed == true) {
      try {
        await _kitchen.setOpen(value);
      } catch (e) {
        _message(e);
      }
    }
  }

  void _navigate(int index) {
    setState(() => _section = index);
    if (index == 0) _kitchen.acknowledge();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _kitchen,
    builder: (context, _) {
      final wide = MediaQuery.sizeOf(context).width >= 980;
      final b = _kitchen.business;
      return Scaffold(
        appBar: AppBar(
          title: Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            Text(b?.name ?? 'SnackUP · Local',maxLines:1,overflow:TextOverflow.ellipsis),
            Text(b?.cafeteriaName ?? 'Cafetería universitaria',maxLines:1,overflow:TextOverflow.ellipsis,
              style:const TextStyle(fontSize:11,color:AdminColors.muted)),
          ]),
          backgroundColor: Colors.white,
          actions: [
            IconButton(
              tooltip: _sound
                  ? 'Silenciar pedidos'
                  : 'Activar sonido de pedidos',
              onPressed: () {
                setState(() => _sound = !_sound);
                if (_sound) _notify();
              },
              icon: Icon(_sound ? Icons.volume_up : Icons.volume_off_outlined),
            ),
            IconButton(
              tooltip: 'Actualizar tablero',
              onPressed: _kitchen.loading ? null : _kitchen.refresh,
              icon: const Icon(Icons.refresh),
            ),
            IconButton(
              tooltip: 'Cerrar sesión',
              onPressed: widget.onSignOut,
              icon: const Icon(Icons.logout),
            ),
          ],
        ),
        bottomNavigationBar: wide
            ? null
            : NavigationBar(
                selectedIndex: _section,
                onDestinationSelected: _navigate,
                destinations: [
                  for (var i = 0; i < _labels.length; i++)
                    NavigationDestination(icon: _navIcon(i), label: _labels[i]),
                ],
              ),
        body: SafeArea(
          child: Column(
            children: [
              Container(
                color: AdminColors.navy,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 7,
                ),
                child: Row(
                  children: [
                    const Icon(Icons.circle, size: 9, color: AdminColors.teal),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        b == null
                            ? 'Conectando con tu local…'
                            : b.isOpen
                            ? 'Recibiendo pedidos'
                            : 'Recepción de pedidos cerrada',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (b != null)
                      Switch(
                        value: b.isOpen,
                        onChanged:
                            _kitchen.stale ||
                                _kitchen.updatingBusiness ||
                                !b.isActive
                            ? null
                            : _open,
                        activeColor: AdminColors.teal,
                      ),
                  ],
                ),
              ),
              if (_kitchen.loading) const LinearProgressIndicator(minHeight: 2),
              if (_kitchen.error != null)
                MaterialBanner(
                  content: Text(
                    '${_kitchen.error} Los datos visibles pueden estar desactualizados.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: _kitchen.loading ? null : _kitchen.refresh,
                      child: const Text('Reintentar'),
                    ),
                  ],
                ),
              if (_kitchen.newCount > 0)
                MaterialBanner(
                  leading: const Icon(
                    Icons.notifications_active,
                    color: AdminColors.cyan,
                  ),
                  content: Text('${_kitchen.newCount} pedido(s) nuevo(s)'),
                  actions: [
                    TextButton(
                      onPressed: () => _navigate(0),
                      child: const Text('Revisar pedidos'),
                    ),
                  ],
                ),
              Expanded(
                child: Row(
                  children: [
                    if (wide)
                      NavigationRail(
                        selectedIndex: _section,
                        labelType: NavigationRailLabelType.all,
                        onDestinationSelected: _navigate,
                        destinations: [
                          for (var i = 0; i < _labels.length; i++)
                            NavigationRailDestination(
                              icon: _navIcon(i),
                              label: Text(_labels[i]),
                            ),
                        ],
                      ),
                    Expanded(
                      child: switch (_section) {
                        0 => _board(),
                        1 => CatalogScreen(
                          businessId: widget.businessId,
                          repository: widget.catalog,
                        ),
                        2 => HistoryScreen(
                          repository: widget.repository,
                          businessId: widget.businessId,
                        ),
                        3 => HistoryScreen(
                          key: const ValueKey('sales'),
                          repository: widget.repository,
                          businessId: widget.businessId,
                          summaryOnly: true,
                        ),
                        _ => _settings(),
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
  Widget _navIcon(int i) =>
      i == 0 &&
          _kitchen.orders
              .where((o) => o.status == KitchenStatus.pending)
              .isNotEmpty
      ? Badge(
          label: Text(
            '${_kitchen.orders.where((o) => o.status == KitchenStatus.pending).length}',
          ),
          child: Icon(_icons[i]),
        )
      : Icon(_icons[i]);
  Widget _board() {
    final rows = _kitchen.orders
        .where(
          (o) => '${o.number} ${o.customer}'.toLowerCase().contains(
            _search.toLowerCase(),
          ),
        )
        .toList();
    final groups = [
      rows.where((o) => o.status == KitchenStatus.pending).toList(),
      rows
          .where(
            (o) => [
              KitchenStatus.accepted,
              KitchenStatus.preparing,
            ].contains(o.status),
          )
          .toList(),
      rows.where((o) => o.status == KitchenStatus.ready).toList(),
    ];
    return LayoutBuilder(
      builder: (context, c) {
        final wide = c.maxWidth >= 1050;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Wrap(
                spacing: 20,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Text(
                    'Cocina',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: AdminColors.navy,
                    ),
                  ),
                  SizedBox(
                    width: wide ? 300 : c.maxWidth - 32,
                    child: TextField(
                      controller: _searchField,
                      onChanged: (v) => setState(() => _search = v),
                      decoration: const InputDecoration(
                        labelText: 'Buscar pedido o cliente',
                        prefixIcon: Icon(Icons.search),
                      ),
                    ),
                  ),
                  Text(
                    _kitchen.lastSync == null
                        ? 'Cargando pedidos…'
                        : '${_live ? 'En vivo' : 'Actualización cada 10 s'} · ${campusStamp(_kitchen.lastSync)}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AdminColors.muted,
                    ),
                  ),
                ],
              ),
            ),
            if (!wide)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: SegmentedButton<int>(
                  showSelectedIcon: false,
                  style: ButtonStyle(
                    padding: WidgetStateProperty.all(
                      const EdgeInsets.symmetric(horizontal: 8),
                    ),
                  ),
                  segments: [
                    for (var i = 0; i < 3; i++)
                      ButtonSegment(
                        value: i,
                        label: Text(
                          '${['Nuevos', 'Preparando', 'Listos'][i]} (${groups[i].length})',
                          style: const TextStyle(fontSize: 11),
                        ),
                      ),
                  ],
                  selected: {_mobileColumn},
                  onSelectionChanged: (v) =>
                      setState(() => _mobileColumn = v.first),
                ),
              ),
            if (const bool.fromEnvironment('REVIEW_MODE'))
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.science_outlined),
                    label: const Text('Recibir pedido de prueba'),
                    onPressed: _kitchen.stale
                        ? null
                        : () async {
                            try {
                              final ticket = await widget.repository.api.json(
                                'POST',
                                'review/orders',
                                body: {'businessId': widget.businessId},
                              );
                              await _kitchen.refresh();
                              if (mounted)
                                await showDialog<void>(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    title: Text(
                                      'Pedido de prueba #${ticket['orderNumber']}',
                                    ),
                                    content: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Text(
                                          'Simula el comprobante del cliente. Guarda el código para verificar la entrega.',
                                        ),
                                        QrImageView(
                                          data: ticket['pickupCode'] as String,
                                          size: 180,
                                        ),
                                        SelectableText(
                                          'Código: ${ticket['pickupCode']}',
                                          style: const TextStyle(
                                            fontSize: 24,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(ctx),
                                        child: const Text('Ir a cocina'),
                                      ),
                                    ],
                                  ),
                                );
                            } catch (e) {
                              _message(e);
                            }
                          },
                  ),
                ),
              ),
            Expanded(
              child: wide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var i = 0; i < 3; i++)
                          Expanded(child: _column(i, groups[i])),
                      ],
                    )
                  : _column(_mobileColumn, groups[_mobileColumn]),
            ),
          ],
        );
      },
    );
  }

  Widget _column(int index, List<KitchenOrder> orders) => Container(
    margin: const EdgeInsets.fromLTRB(8, 0, 8, 12),
    decoration: BoxDecoration(
      color: const Color(0xFFEEF2F6),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Icon(
                [
                  Icons.inbox_outlined,
                  Icons.soup_kitchen_outlined,
                  Icons.shopping_bag_outlined,
                ][index],
                color: AdminColors.navy,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${['Nuevos', 'Preparando', 'Listos para entregar'][index]} · ${orders.length}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: orders.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      _kitchen.lastSync == null
                          ? 'Esperando conexión…'
                          : 'Sin pedidos en esta etapa.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  itemCount: orders.length,
                  itemBuilder: (_, i) => _card(orders[i]),
                ),
        ),
      ],
    ),
  );
  Widget _card(KitchenOrder o) {
    final disabled = _kitchen.stale || _kitchen.busy.contains(o.id);
    final minutes = DateTime.now()
        .toUtc()
        .difference(o.createdAt!)
        .inMinutes
        .clamp(0, 99999);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Pedido #${o.number}',
                    style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Text(
                  '${minutes} min',
                  style: TextStyle(
                    color: minutes >= 20 ? AdminColors.red : AdminColors.muted,
                  ),
                ),
              ],
            ),
            Text(
              o.customer,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(
                o.status.label,
                style: const TextStyle(color: AdminColors.cyan),
              ),
            ),
            if (o.scheduledAt != null)
              Text('Recogida: ${campusStamp(o.scheduledAt)}'),
            const Divider(),
            for (final item in o.items)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${item.quantity} × ${item.name}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    if (item.notes.isNotEmpty)
                      Text(
                        'Nota: ${item.notes}',
                        style: const TextStyle(color: AdminColors.red),
                      ),
                  ],
                ),
              ),
            Text(
              '${money(o.totalCents)} · ${o.payment}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 14),
            FilledButton(
              onPressed: disabled ? null : () => _action(o),
              child: Text(
                _kitchen.busy.contains(o.id) ? 'Guardando…' : o.status.button!,
              ),
            ),
            if (o.status.canCancel)
              TextButton(
                onPressed: disabled
                    ? null
                    : () => showDialog<bool>(
                        context: context,
                        barrierDismissible: false,
                        builder: (_) => OrderActionDialog(
                          order: o,
                          controller: _kitchen,
                          cancel: true,
                        ),
                      ),
                child: const Text(
                  'Cancelar pedido',
                  style: TextStyle(color: AdminColors.red),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _settings() {
    final b = _kitchen.business;
    if (b == null)
      return const Center(
        child: Text('Actualiza la conexión para ver tu local.'),
      );
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('Mi local', style: Theme.of(context).textTheme.headlineLarge),
        const SizedBox(height: 24),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(b.name, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                Text(b.category),
                Text(b.description),
                const SizedBox(height: 16),
                Text('Zona horaria: ${b.timezone}'),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _kitchen.stale
                      ? null
                      : () async {
                          final saved = await showDialog<bool>(
                            context: context,
                            barrierDismissible: false,
                            builder: (_) => RecordEditor(
                              title: 'Editar mi local',
                              fields: const [
                                RecordField('name', 'Nombre', maxLength: 100),
                                RecordField(
                                  'category',
                                  'Categoría',
                                  maxLength: 60,
                                ),
                                RecordField(
                                  'description',
                                  'Descripción',
                                  maxLength: 600,
                                  required: false,
                                  multiline: true,
                                ),
                              ],
                              initial: {
                                'name': b.name,
                                'category': b.category,
                                'description': b.description,
                              },
                              save: (d) async {
                                await widget.repository.editBusiness(
                                  b,
                                  name: d['name'] as String,
                                  category: d['category'] as String,
                                  description: d['description'] as String,
                                );
                              },
                            ),
                          );
                          if (saved != null) await _kitchen.refresh();
                        },
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Editar información'),
                ),
              ],
            ),
          ),
        ),
        SwitchListTile(
          title: const Text('Recibir pedidos'),
          subtitle: const Text(
            'Controla la misma recepción que el interruptor superior.',
          ),
          value: b.isOpen,
          onChanged: _kitchen.stale || _kitchen.updatingBusiness || !b.isActive
              ? null
              : _open,
        ),
      ],
    );
  }
}
