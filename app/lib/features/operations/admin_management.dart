import 'dart:async';
import 'package:flutter/material.dart';
import '../../api/api_client.dart';
import '../../operations/models.dart';
import '../../operations/operations_repository.dart';
import '../../operations/kitchen_controller.dart';
import '../../operations/portal_configuration.dart';
import 'record_editor.dart';
import '../../operations/v32_repository.dart';
import 'v32_screens.dart';

class AdminManagement extends StatefulWidget {
  const AdminManagement({
    super.key,
    required this.repository,
    required this.currentUserId,
    this.canManageAccounts = false,
    this.createAccountOnOpen = false,
    this.v32,
  });
  final OperationsRepository repository;
  final V32Repository? v32;
  final String currentUserId;
  final bool canManageAccounts, createAccountOnOpen;
  @override
  State<AdminManagement> createState() => _AdminManagementState();
}

class _AdminManagementState extends State<AdminManagement> {
  OperationsPage<BusinessRecord>? _businesses;
  OperationsPage<PortalUser>? _users;
  int _section = 0, _page = 1, _revision = 0;
  bool _busy = true;
  String? _error;
  final _search = TextEditingController();
  Timer? _debounce;
  PortalConfiguration? _configuration;
  @override
  void initState() {
    super.initState();
    _section = widget.createAccountOnOpen && widget.canManageAccounts ? 1 : 0;
    _load().then((_) {
      if (mounted &&
          _error == null &&
          widget.createAccountOnOpen &&
          widget.canManageAccounts)
        _user();
    });
  }

  @override
  void dispose() {
    _search.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final revision = ++_revision;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final configuration = await widget.repository.configuration();
      if (!mounted || revision != _revision) return;
      _configuration = configuration;
      if (_section == 0) {
        final data = await widget.repository.businesses(
          number: _page,
          search: _search.text,
        );
        if (mounted && revision == _revision)
          setState(() => _businesses = data);
      } else {
        final data = await widget.repository.users(
          number: _page,
          search: _search.text,
        );
        if (mounted && revision == _revision) setState(() => _users = data);
      }
    } catch (e) {
      if (mounted && revision == _revision)
        setState(() => _error = operationsMessage(e));
    } finally {
      if (mounted && revision == _revision) setState(() => _busy = false);
    }
  }

  Future<void> _business([BusinessRecord? b]) async {
    if (_configuration == null || _error != null) return;
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => RecordEditor(
        title: b == null ? 'Agregar local' : 'Editar local',
        notice:
            'Desactivar un local conserva sus productos e historial y detiene la recepción de pedidos.',
        fields: const [
          RecordField('name', 'Nombre del local', maxLength: 100),
          RecordField('category', 'Categoría', maxLength: 60),
          RecordField(
            'description',
            'Descripción',
            required: false,
            multiline: true,
            maxLength: 600,
          ),
          RecordField(
            'isActive',
            'Estado del local',
            options: {'true': 'Activo', 'false': 'Inactivo'},
          ),
        ],
        initial: {
          'name': b?.name ?? '',
          'category': b?.category ?? '',
          'description': b?.description ?? '',
          'isActive': '${b?.isActive ?? true}',
        },
        save: (d) async {
          await widget.repository.saveBusiness({
            ...d,
            'cafeteriaId': _configuration!.cafeteriaId,
            'isActive': d['isActive'] == 'true',
            if (b == null) 'timezone': 'America/Mexico_City',
          }, previous: b);
        },
      ),
    );
    if (result != null && mounted) _load();
  }

  Future<void> _user([PortalUser? user]) async {
    if (!widget.canManageAccounts || _configuration == null) return;
    setState(() => _busy = true);
    final options = <String, String>{'': 'Sin local'};
    try {
      for (var n = 1; n <= 100; n++) {
        final data = await widget.repository.businesses(number: n);
        for (final b in data.items) {
          if (b.isActive || b.id == user?.businessId) options[b.id] = b.name;
        }
        if (!data.hasMore) break;
        if (n == 100)
          throw const ApiException(
            'Hay demasiados locales para este selector. Contacta a soporte.',
          );
      }
      if (!mounted) return;
      if (user?.businessId != null)
        options.putIfAbsent(user!.businessId!, () => user.businessId!);
      final self = user?.id == widget.currentUserId;
      final result = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => RecordEditor(
          title: user == null ? 'Crear cuenta' : 'Editar cuenta',
          notice: self
              ? 'Tu rol y estado se conservan al editar tu propia cuenta.'
              : 'Crea un acceso para un local o para administración. Los administradores deben usar ${_configuration!.adminEmailDomains.map((d) => '@$d').join(', ')}. Cada local conserva su propia cuenta.',
          fields: [
            const RecordField('displayName', 'Nombre', maxLength: 100),
            const RecordField('email', 'Correo electrónico', maxLength: 160),
            if (user == null)
              const RecordField(
                'password',
                'Contraseña inicial',
                secret: true,
                maxLength: 128,
                minimum: 12,
              ),
            if (!self)
              const RecordField(
                'role',
                'Rol',
                options: {
                  'business': 'Local de cafetería',
                  'admin': 'Administración institucional',
                },
              ),
            RecordField(
              'businessId',
              'Local asignado',
              required: false,
              options: options,
            ),
            if (!self)
              const RecordField(
                'isActive',
                'Acceso',
                options: {'true': 'Activo', 'false': 'Suspendido'},
              ),
          ],
          initial: {
            'displayName': user?.name ?? '',
            'email': user?.email ?? '',
            'role': user?.role ?? 'business',
            'businessId': user?.businessId ?? '',
            'isActive': '${user?.isActive ?? true}',
          },
          save: (d) async {
            final role = self ? user!.role : d['role'];
            final email = (d['email'] as String).trim().toLowerCase();
            final unchangedMasterEmail =
                user?.isMaster == true && email == user?.email;
            if (role == 'admin' &&
                !unchangedMasterEmail &&
                !_configuration!.acceptsAdminEmail(email)) {
              throw ApiException(
                'Usa un correo institucional: ${_configuration!.adminEmailDomains.map((d) => '@$d').join(', ')}.',
              );
            }
            if (role == 'business' &&
                (d['businessId'] == null || d['businessId'] == ''))
              throw const ApiException(
                'Selecciona un local para la cuenta de negocio.',
              );
            await widget.repository.saveUser({
              ...d,
              'role': role,
              'email': email,
              'businessId': role == 'business' ? d['businessId'] : null,
              'isActive': self ? user!.isActive : d['isActive'] == 'true',
            }, previous: user);
          },
        ),
      );
      if (result != null && mounted) await _load();
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(operationsMessage(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final totalPages = _section == 0
        ? _businesses?.totalPages
        : _users?.totalPages;
    return Scaffold(
      appBar: AppBar(title: const Text('Gestión administrativa')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                if (widget.canManageAccounts)
                  SegmentedButton<int>(
                    segments: const [
                      ButtonSegment(
                        value: 0,
                        label: Text('Locales'),
                        icon: Icon(Icons.storefront),
                      ),
                      ButtonSegment(
                        value: 1,
                        label: Text('Cuentas'),
                        icon: Icon(Icons.manage_accounts),
                      ),
                    ],
                    selected: {_section},
                    onSelectionChanged: (v) {
                      _debounce?.cancel();
                      setState(() {
                        _section = v.first;
                        _page = 1;
                        _search.clear();
                      });
                      _load();
                    },
                  ),
                if (!widget.canManageAccounts)
                  const Text(
                    'La cuenta maestra administra los accesos de otras personas.',
                  ),
                if (_configuration != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      _configuration!.cafeteriaName,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _search,
                        decoration: InputDecoration(
                          labelText: _section == 0
                              ? 'Buscar local'
                              : 'Buscar nombre o correo',
                          prefixIcon: const Icon(Icons.search),
                        ),
                        onChanged: (_) {
                          _debounce?.cancel();
                          _debounce = Timer(
                            const Duration(milliseconds: 400),
                            () {
                              _page = 1;
                              _load();
                            },
                          );
                        },
                      ),
                    ),
                    IconButton(
                      tooltip: 'Actualizar',
                      onPressed: _busy ? null : _load,
                      icon: const Icon(Icons.refresh),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    onPressed: _busy || _configuration == null || _error != null
                        ? null
                        : () => _section == 0 ? _business() : _user(),
                    icon: const Icon(Icons.add),
                    label: Text(
                      _section == 0 ? 'Agregar local' : 'Crear cuenta',
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_busy) const LinearProgressIndicator(),
          Expanded(
            child: _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
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
                    ),
                  )
                : _busy
                ? const SizedBox()
                : _section == 0
                ? _businessList()
                : _userList(),
          ),
          SafeArea(
            top: false,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  tooltip: 'Página anterior',
                  onPressed: !_busy && _page > 1
                      ? () {
                          _page--;
                          _load();
                        }
                      : null,
                  icon: const Icon(Icons.chevron_left),
                ),
                Text('Página $_page de ${(totalPages ?? 1).clamp(1, 99999)}'),
                IconButton(
                  tooltip: 'Página siguiente',
                  onPressed: !_busy && _page < (totalPages ?? 0)
                      ? () {
                          _page++;
                          _load();
                        }
                      : null,
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _businessList() {
    final rows = _businesses?.items ?? [];
    if (rows.isEmpty)
      return const Center(child: Text('No hay locales para esta búsqueda.'));
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: rows.length,
      itemBuilder: (_, i) {
        final b = rows[i];
        return Card(
          child: ListTile(
            leading: const Icon(Icons.storefront),
            title: Text(b.name),
            subtitle: Text(
              '${b.category} · ${b.isActive ? (b.isOpen ? 'Abierto' : 'Cerrado') : 'Inactivo'}',
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.v32 != null)
                  IconButton(
                    tooltip: 'Consultar horario de ${b.name}',
                    icon: const Icon(Icons.schedule),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => Scaffold(
                          appBar: AppBar(title: Text(b.name)),
                          body: ClosingScreen(
                            repository: widget.v32!,
                            businessId: b.id,
                            readOnly: true,
                          ),
                        ),
                      ),
                    ),
                  ),
                IconButton(
                  tooltip: 'Editar ${b.name}',
                  onPressed: () => _business(b),
                  icon: const Icon(Icons.edit_outlined),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _userList() {
    final rows = _users?.items ?? [];
    if (rows.isEmpty)
      return const Center(child: Text('No hay cuentas para esta búsqueda.'));
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: rows.length,
      itemBuilder: (_, i) {
        final u = rows[i];
        return Card(
          child: ListTile(
            leading: const Icon(Icons.person_outline),
            title: Text(u.name),
            subtitle: Text(
              '${u.email}\n${u.isMaster ? 'Cuenta maestra' : ({'admin': 'Administración', 'business': 'Local de cafetería', 'user': 'Alumno'}[u.role] ?? u.role)} · ${u.isActive ? 'Activo' : 'Suspendido'}',
            ),
            isThreeLine: true,
            trailing: IconButton(
              tooltip: 'Editar ${u.name}',
              onPressed: () => _user(u),
              icon: const Icon(Icons.edit_outlined),
            ),
          ),
        );
      },
    );
  }
}
