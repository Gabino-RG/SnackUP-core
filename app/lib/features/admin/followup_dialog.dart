import 'package:flutter/material.dart';
import 'admin_theme.dart';
import 'data/admin_repository.dart';
import 'domain/admin_models.dart';

class FollowupDialog extends StatefulWidget {
  const FollowupDialog({
    super.key,
    required this.review,
    required this.businessName,
    required this.repository,
  });
  final AdminReview review;
  final String businessName;
  final AdminRepository repository;
  @override
  State<FollowupDialog> createState() => _FollowupDialogState();
}

class _FollowupDialogState extends State<FollowupDialog> {
  final _form = GlobalKey<FormState>();
  final _assignee = TextEditingController(), _note = TextEditingController();
  FollowupStatus _status = FollowupStatus.pending;
  FollowupHistory _history = const FollowupHistory([]);
  bool _loading = true, _saving = false, _loaded = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _assignee.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final followup = await widget.repository.getFollowup(widget.review);
      final history = await widget.repository.getHistory(widget.review.id);
      if (!mounted) return;
      setState(() {
        _status = followup.status;
        _assignee.text = followup.assignee;
        _history = history;
        _loading = false;
        _loaded = true;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _error =
              'No se pudo leer el seguimiento. Comprueba tu acceso y vuelve a intentar.';
          _loading = false;
        });
      }
    }
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final update = AdminFollowup(
      reviewId: widget.review.id,
      businessId: widget.review.businessId,
      status: _status,
      assignee: _assignee.text.trim(),
      note: _note.text.trim(),
      updatedAt: DateTime.now().toUtc(),
    );
    try {
      await widget.repository.saveFollowup(update);
      if (mounted) Navigator.pop(context, update);
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error =
              'No se guardó el seguimiento. Revisa tu conexión y permisos e inténtalo de nuevo.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Dialog(
    insetPadding: const EdgeInsets.all(16),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 720, maxHeight: 850),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.businessName,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: AdminColors.navy,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: _saving ? null : () => Navigator.pop(context),
                    tooltip: 'Cerrar detalle',
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              Text(
                '${widget.review.career} · ${widget.review.group}',
                style: const TextStyle(fontSize: 12, color: AdminColors.muted),
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 14,
                runSpacing: 8,
                children: [
                  _rating('General', widget.review.rating),
                  _rating('Servicio', widget.review.serviceRating),
                  _rating('Alimentos', widget.review.foodRating),
                ],
              ),
              const SizedBox(height: 18),
              SelectableText(
                widget.review.comment.isEmpty
                    ? 'Sin comentario escrito.'
                    : widget.review.comment,
                style: const TextStyle(fontSize: 14, height: 1.6),
              ),
              const SizedBox(height: 18),
              const Divider(),
              const SizedBox(height: 14),
              const Text(
                'Seguimiento del caso',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AdminColors.navy,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                widget.repository.isDemo
                    ? 'Demostración: estos cambios solo viven en esta sesión.'
                    : 'Registra una acción acordada. Cada actualización conserva una entrada en el historial.',
                style: const TextStyle(fontSize: 11, color: AdminColors.muted),
              ),
              const SizedBox(height: 20),
              if (_loading)
                const Center(child: CircularProgressIndicator())
              else ...[
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Text(
                      _error!,
                      style: const TextStyle(
                        color: AdminColors.red,
                        fontSize: 12,
                      ),
                    ),
                  ),
                if (_error != null && !_loaded)
                  TextButton(
                    onPressed: _load,
                    child: const Text('Volver a cargar'),
                  ),
                DropdownButtonFormField<FollowupStatus>(
                  value: _status,
                  decoration: const InputDecoration(labelText: 'Estado'),
                  items: FollowupStatus.values
                      .map(
                        (status) => DropdownMenuItem(
                          value: status,
                          child: Text(status.label),
                        ),
                      )
                      .toList(),
                  onChanged: _saving
                      ? null
                      : (value) => setState(() => _status = value!),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _assignee,
                  enabled: !_saving,
                  maxLength: 120,
                  decoration: const InputDecoration(
                    labelText: 'Responsable del seguimiento',
                    hintText: 'Ej. Coordinación de servicios',
                  ),
                  validator: (value) => (value ?? '').trim().isEmpty
                      ? 'Indica a quién corresponde dar seguimiento.'
                      : null,
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _note,
                  enabled: !_saving,
                  maxLines: 3,
                  maxLength: 2000,
                  decoration: const InputDecoration(
                    labelText: 'Nueva nota o acuerdo',
                    hintText: 'Describe la revisión, acción y siguiente paso.',
                  ),
                  validator: (value) => (value ?? '').trim().isEmpty
                      ? 'Agrega la nota que quedará en el historial.'
                      : null,
                ),
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    onPressed: (_saving || !_loaded) ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check, size: 18),
                    label: Text(_saving ? 'Guardando…' : 'Guardar seguimiento'),
                  ),
                ),
                const SizedBox(height: 28),
                const Text(
                  'Historial de seguimiento',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AdminColors.navy,
                  ),
                ),
                const SizedBox(height: 12),
                if (_history.events.isEmpty)
                  const Text(
                    'Aún no hay acuerdos registrados.',
                    style: TextStyle(fontSize: 12, color: AdminColors.muted),
                  ),
                for (final event in _history.events)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 18),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(top: 4),
                          child: Icon(
                            Icons.circle,
                            size: 9,
                            color: AdminColors.cyan,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${event.status.label} · ${event.assignee}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12,
                                  color: AdminColors.navy,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                event.note,
                                style: const TextStyle(fontSize: 12),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                _date(event.updatedAt),
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: AdminColors.muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                if (_history.hasMore)
                  const Text(
                    'Se muestran los últimos 50 eventos. Existen eventos anteriores en el historial.',
                    style: TextStyle(fontSize: 11, color: AdminColors.red),
                  ),
              ],
            ],
          ),
        ),
      ),
    ),
  );
  Widget _rating(String title, int? value) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
    decoration: BoxDecoration(
      color: AdminColors.background,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      '$title: ${value == null ? 'Sin informar' : '$value ★'}',
      style: const TextStyle(fontSize: 12, color: AdminColors.navy),
    ),
  );
  String _date(DateTime? value) {
    if (value == null) return 'Fecha no disponible';
    final date = value.toUtc().subtract(const Duration(hours: 6));
    return '${date.day}/${date.month}/${date.year} · ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')} h (UTC−6)';
  }
}
