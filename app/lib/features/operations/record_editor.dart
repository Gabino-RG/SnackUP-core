import 'package:flutter/material.dart';
import '../../api/api_client.dart';
import '../../operations/kitchen_controller.dart';

class RecordField {
  const RecordField(
    this.keyName,
    this.label, {
    this.required = true,
    this.multiline = false,
    this.secret = false,
    this.maxLength = 120,
    this.options,
    this.minimum = 0,
  });
  final String keyName, label;
  final bool required, multiline, secret;
  final int maxLength, minimum;
  final Map<String, String>? options;
}

class RecordEditor extends StatefulWidget {
  const RecordEditor({
    super.key,
    required this.title,
    required this.fields,
    required this.initial,
    required this.save,
    this.notice,
  });
  final String title;
  final List<RecordField> fields;
  final Map<String, dynamic> initial;
  final Future<void> Function(Map<String, dynamic>) save;
  final String? notice;
  @override
  State<RecordEditor> createState() => _RecordEditorState();
}

class _RecordEditorState extends State<RecordEditor> {
  final _form = GlobalKey<FormState>();
  late final Map<String, TextEditingController> _controllers;
  late final Map<String, dynamic> _values;
  bool _busy = false, _dirty = false, _conflict = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _values = {...widget.initial};
    _controllers = {
      for (final f in widget.fields)
        if (f.options == null)
          f.keyName: TextEditingController(
            text: widget.initial[f.keyName]?.toString() ?? '',
          ),
    };
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _leave() async {
    if (_busy) return;
    if (_dirty) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Descartar cambios'),
          content: const Text(
            'Hay cambios sin guardar. ¿Quieres salir del formulario?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Seguir editando'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Descartar'),
            ),
          ],
        ),
      );
      if (discard != true) return;
    }
    if (mounted) Navigator.pop(context, false);
  }

  Future<void> _save() async {
    if (_busy || _conflict || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.save({
        ..._values,
        for (final e in _controllers.entries) e.key: e.value.text,
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted)
        setState(() {
          _error = operationsMessage(e);
          _conflict =
              e is ApiException &&
              ['VERSION_CONFLICT', 'TIMEOUT', 'NETWORK'].contains(e.code);
        });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop) _leave();
    },
    child: AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 500,
        child: SingleChildScrollView(
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (widget.notice != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Text(widget.notice!),
                  ),
                for (final f in widget.fields)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: f.options != null
                        ? DropdownButtonFormField<String>(
                            value: f.options!.containsKey(_values[f.keyName])
                                ? _values[f.keyName] as String
                                : null,
                            isExpanded: true,
                            decoration: InputDecoration(labelText: f.label),
                            items: [
                              for (final e in f.options!.entries)
                                DropdownMenuItem(
                                  value: e.key,
                                  child: Text(
                                    e.value,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                            ],
                            onChanged: _busy
                                ? null
                                : (v) => setState(() {
                                    _values[f.keyName] = v;
                                    _dirty = true;
                                  }),
                            validator: (v) =>
                                f.required && (v == null || v.isEmpty)
                                ? 'Selecciona una opción.'
                                : null,
                          )
                        : TextFormField(
                            controller: _controllers[f.keyName],
                            enabled: !_busy,
                            obscureText: f.secret,
                            autocorrect: !f.secret,
                            enableSuggestions: !f.secret,
                            maxLength: f.maxLength,
                            minLines: f.multiline ? 3 : 1,
                            maxLines: f.multiline ? 5 : 1,
                            decoration: InputDecoration(labelText: f.label),
                            onChanged: (_) => _dirty = true,
                            validator: (v) {
                              final s = f.secret
                                  ? (v ?? '')
                                  : (v?.trim() ?? '');
                              if (f.required && s.isEmpty)
                                return 'Completa este campo.';
                              if (s.length < f.minimum)
                                return 'Utiliza al menos ${f.minimum} caracteres.';
                              if (f.keyName == 'email' &&
                                  !RegExp(
                                    r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
                                  ).hasMatch(s))
                                return 'Escribe un correo válido.';
                              return null;
                            },
                          ),
                  ),
                if (_error != null)
                  Text(_error!, style: const TextStyle(color: Colors.red)),
                if (_conflict)
                  const Text(
                    'Conservamos lo que escribiste. Cierra y actualiza la lista para comprobar el registro antes de volver a editarlo.',
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : _leave,
          child: const Text('Cerrar'),
        ),
        FilledButton(
          onPressed: _busy || _conflict ? null : _save,
          child: Text(_busy ? 'Guardando…' : 'Guardar'),
        ),
      ],
    ),
  );
}
