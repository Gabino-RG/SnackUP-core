import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../operations/models.dart';
import '../../operations/kitchen_controller.dart';
import '../../api/api_client.dart';

class OrderActionDialog extends StatefulWidget {
  const OrderActionDialog({
    super.key,
    required this.order,
    required this.controller,
    required this.cancel,
  });
  final KitchenOrder order;
  final KitchenController controller;
  final bool cancel;
  @override
  State<OrderActionDialog> createState() => _OrderActionDialogState();
}

class _OrderActionDialogState extends State<OrderActionDialog> {
  final _form = GlobalKey<FormState>();
  final _text = TextEditingController();
  String _reason = 'product_unavailable', _method = 'manual';
  String? _error;
  bool _saving = false, _mustReload = false;
  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || _mustReload || !_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.controller.act(
        widget.order,
        widget.cancel ? 'cancel' : 'complete',
        reason: _reason,
        notes: _text.text,
        method: _method,
        code: _text.text,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted)
        setState(() {
          _error = operationsMessage(e);
          // Keep the code/note, but never replay an action on a stale card.
          _mustReload =
              widget.controller.stale ||
              (e is ApiException &&
                  const [
                    'NETWORK',
                    'TIMEOUT',
                    'INVALID_RESPONSE',
                  ].contains(e.code)) ||
              !widget.controller.orders.any(
                (o) =>
                    o.id == widget.order.id &&
                    o.version == widget.order.version,
              );
          if (_mustReload) {
            _error =
                '$_error Vuelve al tablero y actualiza para comprobar el resultado antes de repetir.';
          }
        });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _scan() async {
    final code = await Navigator.of(
      context,
    ).push<String>(MaterialPageRoute(builder: (_) => const DeliveryScanner()));
    if (mounted && code != null)
      setState(() {
        _text.text = code;
        _method = 'qr';
      });
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: AlertDialog(
      title: Text(
        '${widget.cancel ? 'Cancelar' : 'Entregar'} pedido #${widget.order.number}',
      ),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '${widget.order.customer} · ${money(widget.order.totalCents)}',
                ),
                const SizedBox(height: 16),
                if (widget.cancel) ...[
                  const Text(
                    'El cliente verá la cancelación. Si hubo un cobro, acuerda la devolución correspondiente.',
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: _reason,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Motivo de cancelación',
                    ),
                    items: [
                      for (final e in cancelReasons.entries)
                        DropdownMenuItem(value: e.key, child: Text(e.value)),
                    ],
                    onChanged: _saving
                        ? null
                        : (v) => setState(() => _reason = v!),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _text,
                    maxLength: 500,
                    minLines: 2,
                    maxLines: 4,
                    enabled: !_saving,
                    decoration: const InputDecoration(
                      labelText: 'Detalle del motivo',
                    ),
                    validator: (v) =>
                        _reason == 'other' && (v?.trim().isEmpty ?? true)
                        ? 'Explica el motivo.'
                        : null,
                  ),
                ] else ...[
                  const Text(
                    'Pide el código de recogida del pedido al cliente o escanea su QR.',
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    key: const ValueKey('delivery-code'),
                    controller: _text,
                    enabled: !_saving,
                    maxLength: 128,
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: 'Código del cliente',
                    ),
                    onChanged: (_) {
                      _method = 'manual';
                    },
                    onFieldSubmitted: (_) => _save(),
                    validator: (v) => v == null || v.trim().isEmpty
                        ? 'Introduce el código para verificar la entrega.'
                        : null,
                  ),
                  OutlinedButton.icon(
                    onPressed: _saving ? null : _scan,
                    icon: const Icon(Icons.qr_code_scanner),
                    label: const Text('Escanear QR'),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _method == 'qr'
                        ? 'QR leído. Confirma la entrega.'
                        : 'Verificación manual',
                  ),
                ],
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      _error!,
                      style: TextStyle(color: Theme.of(context).colorScheme.error),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: Text(_mustReload ? 'Volver y comprobar el pedido' : 'Volver'),
        ),
        FilledButton(
          onPressed: _saving || _mustReload ? null : _save,
          child: Text(
            _saving
                ? 'Guardando…'
                : widget.cancel
                ? 'Confirmar cancelación'
                : 'Confirmar entrega',
          ),
        ),
      ],
    ),
  );
}

class DeliveryScanner extends StatefulWidget {
  const DeliveryScanner({super.key});
  @override
  State<DeliveryScanner> createState() => _DeliveryScannerState();
}

class _DeliveryScannerState extends State<DeliveryScanner> {
  final _controller = MobileScannerController(formats: [BarcodeFormat.qrCode]);
  bool _read = false;
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Escanear código de recogida')),
    body: Column(
      children: [
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text('Apunta la cámara al QR que muestra el cliente.'),
        ),
        Expanded(
          child: MobileScanner(
            controller: _controller,
            onDetect: (capture) {
              if (_read) return;
              final values = capture.barcodes
                  .map((b) => b.rawValue)
                  .whereType<String>()
                  .where((v) => v.trim().isNotEmpty && v.length <= 128);
              if (values.isEmpty) return;
              _read = true;
              Navigator.pop(context, values.first);
            },
            errorBuilder: (context, error) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'No se pudo abrir la cámara. Comprueba el permiso del navegador o utiliza el código manual.',
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Usar código manual'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
