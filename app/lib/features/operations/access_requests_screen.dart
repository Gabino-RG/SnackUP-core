import 'package:flutter/material.dart';
import '../../api/api_client.dart';
import '../../operations/models.dart';
import '../../operations/operations_repository.dart';
import '../../operations/kitchen_controller.dart';
import 'record_editor.dart';

class AccessRequestsScreen extends StatefulWidget {
  const AccessRequestsScreen({super.key, required this.repository});
  final OperationsRepository repository;
  @override
  State<AccessRequestsScreen> createState() => _AccessRequestsScreenState();
}

class _AccessRequestsScreenState extends State<AccessRequestsScreen> {
  List<Map<String, dynamic>> _rows = [];
  int _page = 1, _pages = 0, _total = 0;
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
      final d = object(
        await widget.repository.api.json(
          'GET',
          'admin/access-requests',
          query: {'page': '$_page', 'limit': '30'},
        ),
      );
      final p = object(d['pagination']);
      if (d['data'] is! List || p['page'] != _page)
        throw const ApiException('La lista está incompleta.');
      final rows = (d['data'] as List).map((value) {
        final r = object(value);
        requiredText(r, 'id');
        requiredText(r, 'email');
        requiredText(r, 'displayName');
        integer(r, 'version', minimum: 1);
        return r;
      }).toList();
      final pages = integer(p, 'totalPages'), total = integer(p, 'total');
      if (mounted)
        setState(() {
          _rows = rows;
          _pages = pages;
          _total = total;
        });
    } catch (e) {
      if (mounted) setState(() => _error = operationsMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _review(Map<String, dynamic> r) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final options = <String, String>{'': 'Sin local'};
      for (var n = 1; n <= 100; n++) {
        final data = await widget.repository.businesses(number: n);
        for (final b in data.items) {
          if (b.isActive) options[b.id] = b.name;
        }
        if (n >= data.totalPages) break;
        if (n == 100)
          throw const ApiException('La lista de locales es demasiado grande.');
      }
      if (!mounted) return;
      final result = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => RecordEditor(
          title: 'Revisar solicitud',
          notice:
              '${r['displayName']} · ${r['email']}\n${r['requestContext'] ?? ''}\nMétodo: ${r['provider'] == 'google' ? 'Google' : 'Contraseña de SnackUP'}. ${r['emailVerified'] == true ? 'Correo verificado.' : 'Verifica la identidad de la persona antes de autorizar; el correo aún no está verificado.'}\nSolo tú asignas la función y el local. Rechazar mantiene el acceso bloqueado.',
          fields:
              const [
                RecordField(
                  'decision',
                  'Decisión',
                  options: {
                    'approve': 'Autorizar acceso',
                    'reject': 'Rechazar solicitud',
                  },
                ),
                RecordField(
                  'role',
                  'Función autorizada',
                  options: {
                    'business': 'Operar un local',
                    'admin': 'Administración institucional',
                  },
                ),
              ].followedBy([
                RecordField(
                  'businessId',
                  'Local asignado',
                  required: false,
                  options: options,
                ),
                const RecordField(
                  'identityConfirmed',
                  'Identidad de la persona',
                  options: {
                    'false': 'Pendiente de verificar',
                    'true': 'Sí, verifiqué su identidad',
                  },
                ),
                const RecordField(
                  'note',
                  'Nota de la revisión',
                  required: false,
                  multiline: true,
                  maxLength: 500,
                ),
              ]).toList(),
          initial: {
            'decision': 'approve',
            'role': r['requestedRole'] == 'admin' ? 'admin' : 'business',
            'businessId': '',
            'identityConfirmed': 'false',
            'note': '',
          },
          save: (d) async {
            if (d['decision'] == 'approve' && d['identityConfirmed'] != 'true')
              throw const ApiException(
                'Confirma que verificaste la identidad de la persona.',
              );
            if (d['decision'] == 'approve' &&
                d['role'] == 'business' &&
                d['businessId'] == '')
              throw const ApiException(
                'Crea y selecciona el local antes de autorizar.',
              );
            await widget.repository.api.json(
              'POST',
              'admin/access-requests/${Uri.encodeComponent(r['id'] as String)}/decision',
              body: {
                ...d,
                'identityConfirmed': d['identityConfirmed'] == 'true',
                'businessId': d['role'] == 'business' ? d['businessId'] : null,
                'expectedVersion': r['version'],
              },
            );
          },
        ),
      );
      if (result == true) {
        _page = 1;
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(operationsMessage(e))));
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        await _load();
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Solicitudes de acceso'),
      actions: [
        IconButton(
          tooltip: 'Actualizar solicitudes',
          onPressed: _busy ? null : _load,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Text(
              '$_total solicitudes pendientes. Autorizar permite entrar únicamente con la función y el local que asignes.',
            ),
          ),
          if (_busy) const LinearProgressIndicator(),
          Expanded(
            child: _error != null
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!),
                        TextButton(
                          onPressed: _load,
                          child: const Text('Reintentar'),
                        ),
                      ],
                    ),
                  )
                : _rows.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'No hay solicitudes pendientes.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    itemCount: _rows.length,
                    itemBuilder: (context, i) {
                      final r = _rows[i];
                      return Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 760),
                          child: Card(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(
                                    r['displayName'] as String,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleMedium,
                                  ),
                                  Text(r['email'] as String),
                                  Text(
                                    r['requestedRole'] == 'admin'
                                        ? 'Solicita administración'
                                        : 'Solicita operar un local',
                                  ),
                                  if ((r['requestContext'] as String? ?? '')
                                      .isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 8,
                                      ),
                                      child: Text(
                                        r['requestContext'] as String,
                                      ),
                                    ),
                                  FilledButton(
                                    onPressed: _busy ? null : () => _review(r),
                                    child: Text('Revisar ${r['displayName']}'),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
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
                        _page--;
                        _load();
                      },
                icon: const Icon(Icons.chevron_left),
              ),
              Text('Página $_page de ${_pages == 0 ? 1 : _pages}'),
              IconButton(
                tooltip: 'Página siguiente',
                onPressed: _busy || _page >= _pages
                    ? null
                    : () {
                        _page++;
                        _load();
                      },
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}
