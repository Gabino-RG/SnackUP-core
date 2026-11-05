import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:snackup/student/student_api.dart';
import 'package:snackup/student/student_widgets.dart';
import 'package:snackup/theme/student_colors.dart';
import 'package:snackup/theme/student_text.dart';

class RateOrderScreen extends StatefulWidget {
  final String orderId;
  const RateOrderScreen({super.key, required this.orderId});

  @override
  State<RateOrderScreen> createState() => _RateOrderScreenState();
}

class _RateOrderScreenState extends State<RateOrderScreen> {
  final _comment = TextEditingController();
  StudentApi? _api;
  String? _ownerId;
  int _revision = -1;
  Future<Map<String, dynamic>>? _future;
  int? _stars;
  int? _foodRating;
  int? _serviceRating;
  bool _saving = false;
  Object? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final api = context.watch<StudentApi>();
    _ownerId ??= api.user?['id'] as String?;
    if (!identical(_api, api) || _revision != api.revision) {
      _api = api;
      _revision = api.revision;
      _future = _load();
    }
  }

  Future<Map<String, dynamic>> _load() async {
    final account = _ownerId;
    if (account != _api!.user?['id']) {
      throw const ApiException(
        401,
        'SESSION_CHANGED',
        'Tu sesión cambió. Vuelve a abrir tu pedido.',
      );
    }
    final order = await _api!.getObject('/orders/${widget.orderId}');
    if (account == null ||
        account != _api!.user?['id'] ||
        order['userId'] != account) {
      throw const ApiException(
        403,
        'NOT_OWN_ORDER',
        'Este pedido no pertenece a tu cuenta.',
      );
    }
    return order;
  }

  void _reload() => setState(() {
    _future = _load();
  });

  Future<void> _submit() async {
    if (_saving || _stars == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final order = await _load();
      if (order['status'] != 'completed') {
        throw const ApiException(
          409,
          'ORDER_NOT_COMPLETED',
          'Solo puedes calificar un pedido que ya fue entregado.',
        );
      }
      if (order['isRated'] == true) {
        _reload();
        return;
      }
      if (_ownerId != _api!.user?['id']) {
        throw const ApiException(
          401,
          'SESSION_CHANGED',
          'Tu sesión cambió. Vuelve a abrir tu pedido.',
        );
      }
      await _api!.request(
        'POST',
        '/orders/${widget.orderId}/rating',
        body: {
          'rating': _stars!,
          'comment': _comment.text.trim(),
          if (_foodRating != null) 'foodRating': _foodRating,
          if (_serviceRating != null) 'serviceRating': _serviceRating,
        },
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Gracias por tu calificación.')),
      );
      Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        setState(() => _error = error);
        // A lost POST response must be reconciled with isRated before enabling
        // another submission. The server permits one business rating per order.
        _reload();
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _form(Map<String, dynamic> order) {
    if (_ownerId != _api!.user?['id'] || order['userId'] != _ownerId) {
      return const Center(child: Text('Este pedido no pertenece a tu cuenta.'));
    }
    if (order['status'] != 'completed') {
      return _message(
        'Podrás calificar cuando tu pedido haya sido entregado.',
        Icons.schedule,
      );
    }
    if (order['isRated'] == true) {
      return _message(
        'Este pedido ya tiene una calificación. Gracias por compartir tu experiencia.',
        Icons.star,
      );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      const Icon(
                        Icons.star_outline,
                        size: 44,
                        color: AppColors.primary,
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        '¿Cómo fue tu experiencia?',
                        style: AppText.h3,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Pedido #${order['orderNumber']}',
                        style: AppText.body,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              const Text('Calificación de 0 a 5 estrellas', style: AppText.h3),
              const SizedBox(height: 8),
              const Text(
                'Cero también es una calificación válida. Selecciona el valor que represente tu experiencia.',
                style: AppText.notes,
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 10,
                children: List.generate(
                  6,
                  (value) => _ratingChoice(
                    chipKey: ValueKey('rating-$value'),
                    aspect: 'Calificación general',
                    score: value,
                    selected: _stars == value,
                    onSelected: () => setState(() => _stars = value),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Aspectos del servicio (opcionales)',
                style: AppText.h3,
              ),
              const SizedBox(height: 8),
              const Text(
                'Califica solo los aspectos que pudiste valorar. Dejar uno sin seleccionar no equivale a darle cero estrellas.',
                style: AppText.notes,
              ),
              const SizedBox(height: 16),
              _optionalRating(
                label: 'Alimentos',
                value: _foodRating,
                onChanged: (value) => setState(() => _foodRating = value),
              ),
              const SizedBox(height: 16),
              _optionalRating(
                label: 'Servicio',
                value: _serviceRating,
                onChanged: (value) => setState(() => _serviceRating = value),
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _comment,
                enabled: !_saving,
                maxLength: 1000,
                maxLines: 5,
                decoration: const InputDecoration(
                  labelText: 'Comentario opcional',
                  hintText: 'Cuéntanos cómo estuvo tu pedido',
                  border: OutlineInputBorder(),
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    friendlyError(_error!),
                    style: const TextStyle(color: AppColors.error),
                  ),
                ),
              const SizedBox(height: 16),
              FilledButton(
                key: const ValueKey('submit-rating'),
                onPressed: _saving || _stars == null ? null : _submit,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Text(_saving ? 'Enviando…' : 'Enviar calificación'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _optionalRating({
    required String label,
    required int? value,
    required ValueChanged<int?> onChanged,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: AppText.body),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (var score = 0; score <= 5; score++)
            _ratingChoice(
              aspect: label,
              score: score,
              selected: value == score,
              onSelected: () => onChanged(score),
            ),
          _ratingChoice(
            aspect: label,
            selected: value == null,
            onSelected: () => onChanged(null),
          ),
        ],
      ),
    ],
  );

  Widget _ratingChoice({
    Key? chipKey,
    required String aspect,
    int? score,
    required bool selected,
    required VoidCallback onSelected,
  }) {
    final value = score == null
        ? 'sin valorar'
        : '$score ${score == 1 ? 'estrella' : 'estrellas'}';
    return Semantics(
      label: '$aspect: $value${selected ? ', seleccionado' : ''}',
      button: true,
      selected: selected,
      enabled: !_saving,
      onTap: _saving ? null : onSelected,
      excludeSemantics: true,
      child: ChoiceChip(
        key: chipKey,
        selected: selected,
        onSelected: _saving ? null : (_) => onSelected(),
        avatar: score == null ? null : const Icon(Icons.star, size: 18),
        label: Text(score == null ? 'Sin valorar' : '$score'),
      ),
    );
  }

  Widget _message(String text, IconData icon) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 60, color: AppColors.primary),
          const SizedBox(height: 16),
          Text(text, style: AppText.h3, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Volver al pedido'),
          ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.componentBase,
    appBar: AppBar(
      title: const Text('Calificar pedido'),
      backgroundColor: AppColors.background,
    ),
    body: FutureBuilder<Map<String, dynamic>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return ErrorPanel(error: snapshot.error!, onRetry: _reload);
        }
        if (!snapshot.hasData ||
            snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        return Column(
          children: [
            if (_saving || snapshot.connectionState == ConnectionState.waiting)
              const LinearProgressIndicator(),
            Expanded(child: _form(snapshot.data!)),
          ],
        );
      },
    ),
  );

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }
}
