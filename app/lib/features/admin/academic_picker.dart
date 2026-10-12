import 'package:flutter/material.dart';

/// A searchable list stays usable when a university has hundreds of groups.
class AcademicPicker extends StatelessWidget {
  const AcademicPicker({
    super.key,
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
    required this.allLabel,
    this.enabled = true,
    this.disabledHint,
  });
  final String label, allLabel;
  final String? value, disabledHint;
  final Map<String, String> options;
  final ValueChanged<String?> onChanged;
  final bool enabled;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 198,
    child: Semantics(
      button: true,
      enabled: enabled,
      label: '$label: ${options[value] ?? allLabel}',
      child: InkWell(
        onTap: !enabled
            ? null
            : () async {
                final selected = await showDialog<_AcademicChoice>(
                  context: context,
                  builder: (_) => _AcademicDialog(
                    label: label,
                    options: options,
                    allLabel: allLabel,
                    selected: value,
                  ),
                );
                if (selected != null) onChanged(selected.value);
              },
        borderRadius: BorderRadius.circular(10),
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: label,
            enabled: enabled,
            suffixIcon: const Icon(Icons.expand_more),
          ),
          child: Text(
            enabled ? (options[value] ?? allLabel) : (disabledHint ?? allLabel),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    ),
  );
}

class _AcademicChoice {
  const _AcademicChoice(this.value);
  final String? value;
}

class _AcademicDialog extends StatefulWidget {
  const _AcademicDialog({
    required this.label,
    required this.options,
    required this.allLabel,
    this.selected,
  });
  final String label, allLabel;
  final String? selected;
  final Map<String, String> options;
  @override
  State<_AcademicDialog> createState() => _AcademicDialogState();
}

class _AcademicDialogState extends State<_AcademicDialog> {
  String query = '';
  @override
  Widget build(BuildContext context) {
    final rows = widget.options.entries
        .where((e) => e.value.toLowerCase().contains(query.toLowerCase()))
        .toList();
    return AlertDialog(
      title: Text('Seleccionar ${widget.label.toLowerCase()}'),
      content: SizedBox(
        width: 480,
        height: MediaQuery.sizeOf(context).height * .48,
        child: Column(
          children: [
            TextField(
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Buscar ${widget.label.toLowerCase()}',
                prefixIcon: const Icon(Icons.search),
              ),
              onChanged: (v) => setState(() => query = v),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                itemCount: rows.length + 1,
                itemBuilder: (context, i) {
                  final id = i == 0 ? null : rows[i - 1].key;
                  return ListTile(
                    title: Text(i == 0 ? widget.allLabel : rows[i - 1].value),
                    selected: widget.selected == id,
                    trailing: widget.selected == id
                        ? const Icon(Icons.check)
                        : null,
                    onTap: () => Navigator.pop(context, _AcademicChoice(id)),
                  );
                },
              ),
            ),
            if (rows.isEmpty) const Text('No hay coincidencias.'),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
      ],
    );
  }
}
