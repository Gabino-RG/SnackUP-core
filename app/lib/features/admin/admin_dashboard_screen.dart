import 'dart:math' as math;
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'admin_theme.dart';
import 'data/admin_repository.dart';
import 'domain/admin_models.dart';
import 'followup_dialog.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key, this.repository, this.onSignOut});
  final AdminRepository? repository;
  final VoidCallback? onSignOut;
  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  late final AdminRepository _repository;
  final _businesses = <String, AdminBusiness>{};
  final _reviews = <String, AdminReview>{};
  final _followups = <String, AdminFollowup>{};
  final _searchController = TextEditingController();
  bool _loading = true, _hasMore = false, _negativeOnly = false;
  String? _error, _businessId, _career, _group;
  int _section = 0, _visibleComments = 15;
  AdminPeriod _period = AdminPeriod.month;
  CampusTimeOfDay _timeOfDay = CampusTimeOfDay.all;
  FollowupStatus? _statusFilter;
  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? FirebaseAdminRepository();
    _load(reset: true);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load({bool reset = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await _repository.loadNextPage(reset: reset);
      if (!mounted) return;
      setState(() {
        if (reset) {
          _businesses.clear();
          _reviews.clear();
          _followups.clear();
        }
        for (final item in page.businesses) {
          _businesses[item.id] = item;
        }
        for (final item in page.reviews) {
          _reviews[item.id] = item;
        }
        for (final item in page.followups) {
          _followups[item.reviewId] = item;
        }
        _hasMore = page.hasMore;
        _loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'No se pudieron cargar los datos';
        });
      }
    }
  }

  List<AdminReview> get _filtered {
    final filter = AdminFilter(
      businessId: _businessId,
      career: _career,
      group: _group,
      period: _period,
      timeOfDay: _timeOfDay,
      negativeOnly: _negativeOnly,
      search: _searchController.text,
    );
    final result = _reviews.values
        .where((r) => filter.matches(r, DateTime.now().toUtc()))
        .toList();
    result.sort(
      (a, b) => (b.createdAt ?? DateTime(1970)).compareTo(
        a.createdAt ?? DateTime(1970),
      ),
    );
    return result;
  }

  String _businessName(String id) =>
      _businesses[id]?.name ?? 'Local sin registrar';
  String _mean(double? value) => value?.toStringAsFixed(1) ?? '—';
  void _resetFilters() => setState(() {
    _businessId = null;
    _career = null;
    _group = null;
    _period = AdminPeriod.month;
    _timeOfDay = CampusTimeOfDay.all;
    _negativeOnly = false;
    _searchController.clear();
    _visibleComments = 15;
    _statusFilter = null;
  });
  Future<void> _openReview(AdminReview review) async {
    final updated = await showDialog<AdminFollowup>(
      context: context,
      builder: (context) => Theme(
        data: adminTheme(),
        child: FollowupDialog(
          review: review,
          businessName: _businessName(review.businessId),
          repository: _repository,
        ),
      ),
    );
    if (updated != null && mounted) {
      setState(() => _followups[updated.reviewId] = updated);
    }
  }

  @override
  Widget build(BuildContext context) => Theme(
    data: adminTheme(),
    child: Builder(
      builder: (context) {
        final wide = MediaQuery.sizeOf(context).width >= 1100;
        return Scaffold(
          drawer: wide ? null : Drawer(child: _navigation()),
          appBar: wide
              ? null
              : AppBar(
                  title: const Text('SnackUP · Administración'),
                  backgroundColor: Colors.white,
                  actions: [
                    IconButton(
                      onPressed: _loading ? null : () => _load(reset: true),
                      tooltip: 'Actualizar datos',
                      icon: const Icon(Icons.refresh),
                    ),
                    if (widget.onSignOut != null)
                      IconButton(
                        onPressed: widget.onSignOut,
                        tooltip: 'Cerrar sesión',
                        icon: const Icon(Icons.logout),
                      ),
                  ],
                ),
          body: SafeArea(
            child: Row(
              children: [
                if (wide) SizedBox(width: 228, child: _navigation()),
                Expanded(
                  child: Column(
                    children: [
                      if (wide) _topbar(),
                      if (_loading) const LinearProgressIndicator(minHeight: 2),
                      Expanded(
                        child: SingleChildScrollView(
                          padding: EdgeInsets.all(wide ? 32 : 16),
                          child: Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 1320),
                              child: _content(wide),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );

  Widget _navigation() => Container(
    color: AdminColors.navy,
    child: SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 28, 18, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: AdminColors.lime,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.restaurant_rounded,
                    color: AdminColors.navy,
                  ),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'SnackUP',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 23,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const Padding(
              padding: EdgeInsets.only(top: 12, bottom: 38),
              child: Text(
                'OBSERVATORIO DEL CAMPUS',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.7,
                  color: Color(0xFFB8C8DE),
                ),
              ),
            ),
            for (var i = 0; i < 4; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Material(
                  color: _section == i
                      ? const Color(0xFF163D6E)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () {
                      setState(() => _section = i);
                      if (MediaQuery.sizeOf(context).width < 1100) {
                        Navigator.pop(context);
                      }
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 15,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            [
                              Icons.grid_view_rounded,
                              Icons.storefront_rounded,
                              Icons.forum_outlined,
                              Icons.fact_check_outlined,
                            ][i],
                            size: 19,
                            color: _section == i
                                ? AdminColors.lime
                                : const Color(0xFFB8C8DE),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              [
                                'Resumen general',
                                'Locales',
                                'Opiniones',
                                'Seguimiento',
                              ][i],
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: _section == i
                                    ? FontWeight.w700
                                    : FontWeight.w400,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF113762),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.school_outlined,
                    color: AdminColors.lime,
                    size: 22,
                  ),
                  SizedBox(height: 10),
                  Text(
                    'La voz del alumnado',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(height: 6),
                  Text(
                    'Información para acompañar a los locales y mejorar el servicio.',
                    style: TextStyle(
                      color: Color(0xFFB8C8DE),
                      fontSize: 11,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),
            const Text(
              'UTSJR · San Juan del Río',
              style: TextStyle(color: Color(0xFFB8C8DE), fontSize: 10),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _topbar() => Container(
    height: 68,
    padding: const EdgeInsets.symmetric(horizontal: 32),
    decoration: const BoxDecoration(
      color: Colors.white,
      border: Border(bottom: BorderSide(color: AdminColors.border)),
    ),
    child: Row(
      children: [
        const Text(
          'CAMPUS  /  ',
          style: TextStyle(
            fontSize: 10,
            color: AdminColors.muted,
            letterSpacing: 1,
          ),
        ),
        const Text(
          'Supervisión de cafeterías',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AdminColors.navy,
          ),
        ),
        const Spacer(),
        _badge(
          _repository.isDemo
              ? 'DEMO · DATOS SIMULADOS'
              : 'ACCESO ADMINISTRATIVO',
          AdminColors.cyan,
        ),
        const SizedBox(width: 16),
        IconButton(
          tooltip: 'Actualizar datos',
          onPressed: _loading ? null : () => _load(reset: true),
          icon: const Icon(Icons.refresh, size: 21),
        ),
        if (widget.onSignOut != null)
          IconButton(
            tooltip: 'Cerrar sesión',
            onPressed: widget.onSignOut,
            icon: const Icon(Icons.logout, size: 20),
          ),
      ],
    ),
  );

  Widget _content(bool wide) {
    final reviews = _filtered;
    final stats = ReviewStatistics(reviews);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          runSpacing: 10,
          spacing: 20,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  [
                    'Resumen general',
                    'Nuestros locales',
                    'Opiniones del alumnado',
                    'Seguimiento y acuerdos',
                  ][_section],
                  style: Theme.of(context).textTheme.headlineLarge,
                ),
                const SizedBox(height: 6),
                const Text(
                  'Escucha, identifica y acompaña la mejora del servicio.',
                  style: TextStyle(color: AdminColors.muted, fontSize: 13),
                ),
              ],
            ),
            if (!wide)
              _badge(
                _repository.isDemo ? 'DEMOSTRACIÓN' : 'DATOS REALES',
                AdminColors.cyan,
              ),
          ],
        ),
        const SizedBox(height: 22),
        if (_repository.isDemo)
          _notice(
            'Modo demostración: locales, opiniones y resultados son ficticios. Los seguimientos se conservan solo durante esta sesión.',
            Icons.science_outlined,
            AdminColors.cyan,
          ),
        if (_error != null)
          _notice(
            'No se pudieron actualizar los datos. Comprueba tu conexión y el permiso administrativo. ${_reviews.isNotEmpty ? 'Los datos visibles corresponden a la lectura anterior.' : ''}',
            Icons.error_outline,
            AdminColors.red,
            action: TextButton(
              onPressed: _loading ? null : () => _load(reset: true),
              child: const Text('Reintentar'),
            ),
          ),
        if (_hasMore)
          _notice(
            'Resultados parciales: quedan registros por cargar. Los indicadores y filtros se calculan solo sobre las opiniones cargadas; completa la carga antes de tomar decisiones.',
            Icons.info_outline,
            AdminColors.red,
            action: TextButton(
              onPressed: _loading ? null : () => _load(),
              child: const Text('Cargar 200 más'),
            ),
          ),
        _filters(),
        const SizedBox(height: 22),
        if (_section == 0) ...[
          _hero(stats),
          const SizedBox(height: 20),
          _kpis(stats),
          const SizedBox(height: 26),
          _sectionTitle(
            'Un campus, distintas experiencias',
            'Calificación y dimensiones de cada local',
          ),
          const SizedBox(height: 14),
          _storeCards(reviews),
          const SizedBox(height: 26),
          _charts(stats),
          const SizedBox(height: 26),
          _sectionTitle(
            'Opiniones recientes',
            'Comentarios según los filtros seleccionados',
          ),
          const SizedBox(height: 14),
          _comments(reviews.take(6).toList()),
        ],
        if (_section == 1) ...[
          _storeCards(reviews),
          const SizedBox(height: 24),
          _comparison(reviews),
          const SizedBox(height: 24),
          _charts(stats),
        ],
        if (_section == 2) ...[
          _kpis(stats),
          const SizedBox(height: 24),
          _comments(reviews.take(_visibleComments).toList()),
          if (reviews.length > _visibleComments)
            Center(
              child: TextButton(
                onPressed: () => setState(() => _visibleComments += 15),
                child: Text(
                  'Ver más opiniones (${reviews.length - _visibleComments} restantes)',
                ),
              ),
            ),
        ],
        if (_section == 3) ...[
          _notice(
            'Las alertas se basan en calificaciones de 1–2 estrellas. Revisa el contexto y la cantidad de opiniones antes de acordar acciones con un local.',
            Icons.fact_check_outlined,
            AdminColors.cyan,
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                label: const Text('Todos los casos'),
                selected: _statusFilter == null,
                onSelected: (_) => setState(() => _statusFilter = null),
              ),
              for (final status in FollowupStatus.values)
                ChoiceChip(
                  label: Text(status.label),
                  selected: _statusFilter == status,
                  onSelected: (_) => setState(() => _statusFilter = status),
                ),
            ],
          ),
          const SizedBox(height: 16),
          _comments(
            reviews
                .where((r) => r.isNegative || _followups.containsKey(r.id))
                .where(
                  (r) =>
                      _statusFilter == null ||
                      (_followups[r.id]?.status ?? FollowupStatus.pending) ==
                          _statusFilter,
                )
                .take(_visibleComments)
                .toList(),
          ),
          if (reviews
                  .where((r) => r.isNegative || _followups.containsKey(r.id))
                  .where(
                    (r) =>
                        _statusFilter == null ||
                        (_followups[r.id]?.status ?? FollowupStatus.pending) ==
                            _statusFilter,
                  )
                  .length >
              _visibleComments)
            Center(
              child: TextButton(
                onPressed: () => setState(() => _visibleComments += 15),
                child: const Text('Ver más casos'),
              ),
            ),
        ],
        const SizedBox(height: 22),
        Text(
          '${reviews.length} opiniones en la vista · ${_reviews.length} cargadas${_hasMore ? ' · Muestra incompleta' : ''}. Hora del campus: UTC−6. Los promedios excluyen valores no registrados.',
          style: const TextStyle(fontSize: 10, color: AdminColors.muted),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _filters() => LayoutBuilder(
    builder: (context, constraints) {
      if (constraints.maxWidth >= 700) {
        return _card(_filterFields());
      }
      final activeCount = [
        _businessId != null,
        _career != null,
        _group != null,
        _period != AdminPeriod.all,
        _timeOfDay != CampusTimeOfDay.all,
        _negativeOnly,
        _searchController.text.trim().isNotEmpty,
      ].where((active) => active).length;
      final periodLabel = switch (_period) {
        AdminPeriod.week => 'Últimos 7 días',
        AdminPeriod.month => 'Últimos 30 días',
        AdminPeriod.quarter => 'Últimos 90 días',
        AdminPeriod.all => 'Todo el historial',
      };
      return _card(
        ExpansionTile(
          key: const PageStorageKey('admin-mobile-filters'),
          initiallyExpanded: false,
          maintainState: true,
          shape: const Border(),
          collapsedShape: const Border(),
          leading: const Icon(Icons.tune, size: 20, color: AdminColors.navy),
          title: const Text(
            'Filtrar opiniones',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AdminColors.navy,
            ),
          ),
          subtitle: Text(
            '$periodLabel · $activeCount ${activeCount == 1 ? 'filtro activo' : 'filtros activos'}',
            style: const TextStyle(fontSize: 10, color: AdminColors.muted),
          ),
          children: [_filterFields()],
        ),
      );
    },
  );
  Widget _filterFields() => Padding(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _select<String>(
              'Local',
              _businessId,
              {for (final b in _businesses.values) b.id: b.name},
              (v) => setState(() => _businessId = v),
              all: 'Todos los locales',
            ),
            _select<String>(
              'Carrera',
              _career,
              {
                for (final c
                    in (_reviews.values.map((r) => r.career).toSet().toList()
                      ..sort()))
                  c: c,
              },
              (v) => setState(() {
                _career = v;
                _group = null;
              }),
              all: 'Todas las carreras',
            ),
            _select<String>(
              'Grupo',
              _group,
              {
                for (final g
                    in (_reviews.values
                        .where((r) => _career == null || r.career == _career)
                        .map((r) => r.group)
                        .toSet()
                        .toList()
                      ..sort()))
                  g: g,
              },
              (v) => setState(() => _group = v),
              all: 'Todos los grupos',
            ),
            _select<AdminPeriod>(
              'Periodo',
              _period,
              {
                AdminPeriod.week: 'Últimos 7 días',
                AdminPeriod.month: 'Últimos 30 días',
                AdminPeriod.quarter: 'Últimos 90 días',
                AdminPeriod.all: 'Todo el historial',
              },
              (v) => setState(() => _period = v ?? AdminPeriod.month),
            ),
            _select<CampusTimeOfDay>(
              'Hora de opinión',
              _timeOfDay,
              {
                CampusTimeOfDay.all: 'Todas las horas',
                CampusTimeOfDay.morning: 'Mañana · 06–12 h',
                CampusTimeOfDay.afternoon: 'Tarde · 12–18 h',
                CampusTimeOfDay.evening: 'Noche · 18–06 h',
              },
              (v) => setState(() => _timeOfDay = v ?? CampusTimeOfDay.all),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 280,
              child: TextField(
                controller: _searchController,
                onChanged: (_) => setState(() => _visibleComments = 15),
                decoration: const InputDecoration(
                  hintText: 'Buscar en los comentarios',
                  prefixIcon: Icon(Icons.search, size: 20),
                ),
              ),
            ),
            FilterChip(
              label: const Text('Solo 1–2 estrellas'),
              selected: _negativeOnly,
              onSelected: (v) => setState(() => _negativeOnly = v),
              avatar: Icon(
                Icons.flag_outlined,
                size: 16,
                color: _negativeOnly ? AdminColors.red : AdminColors.muted,
              ),
            ),
            TextButton.icon(
              onPressed: _resetFilters,
              icon: const Icon(Icons.restart_alt, size: 17),
              label: const Text('Limpiar filtros'),
            ),
          ],
        ),
      ],
    ),
  );
  Widget _select<T>(
    String label,
    T? value,
    Map<T, String> options,
    void Function(T?) onChanged, {
    String? all,
  }) => SizedBox(
    width: 198,
    child: DropdownButtonFormField<T>(
      value: value,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: [
        if (value != null && !options.containsKey(value))
          DropdownMenuItem<T>(
            value: value,
            child: Text(
              '$value · sin registros cargados',
              overflow: TextOverflow.ellipsis,
            ),
          ),
        if (all != null)
          DropdownMenuItem<T>(
            value: null,
            child: Text(all, overflow: TextOverflow.ellipsis),
          ),
        ...options.entries.map(
          (e) => DropdownMenuItem<T>(
            value: e.key,
            child: Text(e.value, overflow: TextOverflow.ellipsis),
          ),
        ),
      ],
      onChanged: onChanged,
    ),
  );
  Widget _hero(ReviewStatistics stats) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      color: AdminColors.navy,
      borderRadius: BorderRadius.circular(16),
    ),
    child: LayoutBuilder(
      builder: (context, constraints) => Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'MEJORAR EMPIEZA POR ESCUCHAR',
                  style: TextStyle(
                    color: AdminColors.lime,
                    letterSpacing: 1.4,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'La experiencia del campus,\nen un solo lugar.',
                  style: TextStyle(
                    fontSize: 25,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  '${stats.reviews.length} opiniones para entender qué funciona\ny dónde hace falta acompañamiento.',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFFB8C8DE),
                    height: 1.6,
                  ),
                ),
              ],
            ),
          ),
          if (constraints.maxWidth > 650) ...[
            const SizedBox(width: 24),
            Container(
              width: 152,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF17416E),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                children: [
                  const Icon(
                    Icons.star_rounded,
                    color: AdminColors.lime,
                    size: 28,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _mean(stats.rating),
                    style: const TextStyle(
                      fontSize: 34,
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const Text(
                    'de 5 estrellas',
                    style: TextStyle(fontSize: 11, color: Color(0xFFB8C8DE)),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    ),
  );
  Widget _kpis(ReviewStatistics stats) => LayoutBuilder(
    builder: (context, c) {
      final count = c.maxWidth >= 850
          ? 4
          : c.maxWidth >= 480
          ? 2
          : 1;
      return Wrap(
        spacing: 14,
        runSpacing: 14,
        children:
            [
                  _kpi(
                    'Calificación general',
                    _mean(stats.rating),
                    'Promedio de ${stats.validCount} valoraciones',
                    Icons.star_outline,
                    AdminColors.cyan,
                  ),
                  _kpi(
                    'Opiniones recibidas',
                    '${stats.reviews.length}',
                    'Según los filtros seleccionados',
                    Icons.chat_bubble_outline,
                    AdminColors.navy,
                  ),
                  _kpi(
                    'Opiniones negativas',
                    '${stats.negativeCount}',
                    stats.negativePercent == null
                        ? 'Sin calificaciones'
                        : '${stats.negativePercent!.toStringAsFixed(0)}% con 1–2 estrellas',
                    Icons.flag_outlined,
                    AdminColors.red,
                  ),
                  _kpi(
                    'Casos por atender',
                    '${stats.reviews.where((r) => (r.isNegative || _followups.containsKey(r.id)) && (_followups[r.id]?.status ?? FollowupStatus.pending) != FollowupStatus.resolved).length}',
                    'Negativas y seguimientos abiertos',
                    Icons.fact_check_outlined,
                    AdminColors.cyan,
                  ),
                ]
                .map(
                  (widget) => SizedBox(
                    width: (c.maxWidth - 14 * (count - 1)) / count,
                    child: widget,
                  ),
                )
                .toList(),
      );
    },
  );
  Widget _kpi(
    String title,
    String value,
    String caption,
    IconData icon,
    Color color,
  ) => _card(
    Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: AdminColors.muted,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Icon(icon, size: 20, color: color),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: const TextStyle(
              fontSize: 31,
              color: AdminColors.navy,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            caption,
            style: const TextStyle(fontSize: 10, color: AdminColors.muted),
          ),
        ],
      ),
    ),
  );
  Widget _storeCards(List<AdminReview> reviews) {
    final businesses = _businesses.values
        .where((b) => _businessId == null || b.id == _businessId)
        .toList();
    if (businesses.isEmpty) {
      return _empty(
        _loading ? 'Cargando locales…' : 'Todavía no hay locales registrados.',
      );
    }
    return LayoutBuilder(
      builder: (context, c) {
        final count = c.maxWidth >= 1000
            ? 4
            : c.maxWidth >= 540
            ? 2
            : 1;
        return Wrap(
          spacing: 14,
          runSpacing: 14,
          children: businesses.map((b) {
            final stats = ReviewStatistics(
              reviews.where((r) => r.businessId == b.id),
            );
            return SizedBox(
              width: (c.maxWidth - 14 * (count - 1)) / count,
              child: _card(
                Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: const Color(0xFFF0F6FA),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.storefront_rounded,
                              color: AdminColors.navy,
                              size: 21,
                            ),
                          ),
                          const Spacer(),
                          _badge(
                            stats.negativeCount > 0
                                ? 'Revisar opiniones'
                                : stats.validCount == 0
                                ? 'Sin datos'
                                : 'Sin alertas',
                            stats.negativeCount > 0
                                ? AdminColors.red
                                : AdminColors.cyan,
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        b.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: AdminColors.navy,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            _mean(stats.rating),
                            style: const TextStyle(
                              fontSize: 31,
                              fontWeight: FontWeight.w800,
                              color: AdminColors.navy,
                            ),
                          ),
                          const Padding(
                            padding: EdgeInsets.only(left: 6, bottom: 7),
                            child: Icon(
                              Icons.star_rounded,
                              color: Color(0xFF9EAB00),
                              size: 19,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${stats.validCount} opiniones',
                              textAlign: TextAlign.end,
                              style: const TextStyle(
                                fontSize: 10,
                                color: AdminColors.muted,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      _dimension('Servicio', stats.service, AdminColors.cyan),
                      const SizedBox(height: 10),
                      _dimension(
                        'Alimentos',
                        stats.food,
                        const Color(0xFF8C9900),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        '${stats.negativeCount} opiniones de 1–2 estrellas',
                        style: TextStyle(
                          fontSize: 10,
                          color: stats.negativeCount > 0
                              ? AdminColors.red
                              : AdminColors.muted,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton(
                          onPressed: () => setState(() {
                            _businessId = b.id;
                            _section = 2;
                            _visibleComments = 15;
                          }),
                          child: const Text(
                            'Ver opiniones →',
                            style: TextStyle(fontSize: 11),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _dimension(String label, double? value, Color color) => Column(
    children: [
      Row(
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 10, color: AdminColors.muted),
          ),
          const Spacer(),
          Text(
            _mean(value),
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AdminColors.navy,
            ),
          ),
        ],
      ),
      const SizedBox(height: 5),
      ClipRRect(
        borderRadius: BorderRadius.circular(3),
        child: LinearProgressIndicator(
          value: (value ?? 0) / 5,
          minHeight: 5,
          color: color,
          backgroundColor: AdminColors.border,
        ),
      ),
    ],
  );
  Widget _comparison(List<AdminReview> reviews) => _panel(
    'Comparación de locales',
    'Cada dimensión usa solo sus calificaciones disponibles.',
    Column(
      children: _businesses.values
          .where((b) => _businessId == null || b.id == _businessId)
          .map((b) {
            final stats = ReviewStatistics(
              reviews.where((r) => r.businessId == b.id),
            );
            return Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    b.name,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 10),
                  _dimension('General', stats.rating, AdminColors.navy),
                  const SizedBox(height: 8),
                  _dimension('Servicio', stats.service, AdminColors.cyan),
                  const SizedBox(height: 8),
                  _dimension('Alimentos', stats.food, const Color(0xFF8C9900)),
                ],
              ),
            );
          })
          .toList(),
    ),
  );
  Widget _charts(ReviewStatistics stats) => LayoutBuilder(
    builder: (context, c) {
      final wide = c.maxWidth >= 800;
      final width = wide ? (c.maxWidth - 18) / 2 : c.maxWidth;
      return Wrap(
        spacing: 18,
        runSpacing: 18,
        children: [
          SizedBox(
            width: width,
            child: _panel(
              'Evolución de la experiencia',
              'Promedio diario · días con opiniones · escala 1–5',
              _trend(stats),
            ),
          ),
          SizedBox(
            width: width,
            child: _panel(
              'Distribución de estrellas',
              'Cantidad de opiniones por calificación',
              Column(
                children: [
                  for (var star = 5; star >= 1; star--)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 30,
                            child: Text(
                              '$star ★',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(5),
                              child: LinearProgressIndicator(
                                value: stats.validCount == 0
                                    ? 0
                                    : stats.histogram[star]! / stats.validCount,
                                minHeight: 14,
                                backgroundColor: const Color(0xFFF0F3F6),
                                color: star <= 2
                                    ? const Color(0xFFEA8A76)
                                    : star == 3
                                    ? AdminColors.cyan
                                    : const Color(0xFFB1C000),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          SizedBox(
                            width: 24,
                            child: Text(
                              '${stats.histogram[star]}',
                              textAlign: TextAlign.end,
                              style: const TextStyle(
                                fontSize: 12,
                                color: AdminColors.muted,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
          SizedBox(
            width: width,
            child: _panel(
              'La opinión por carrera',
              'Promedio general y número de opiniones',
              stats.byCareer.isEmpty
                  ? _empty('Sin opiniones en este periodo.')
                  : Column(
                      children:
                          (stats.byCareer.entries.toList()..sort(
                                (a, b) => b.value.reviews.length.compareTo(
                                  a.value.reviews.length,
                                ),
                              ))
                              .map(
                                (e) => Padding(
                                  padding: const EdgeInsets.only(bottom: 16),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              e.key,
                                              style: const TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                          Text(
                                            '${_mean(e.value.rating)} ★ · ${e.value.reviews.length}',
                                            style: const TextStyle(
                                              fontSize: 11,
                                              color: AdminColors.muted,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 7),
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(4),
                                        child: LinearProgressIndicator(
                                          value: (e.value.rating ?? 0) / 5,
                                          minHeight: 8,
                                          backgroundColor: AdminColors.border,
                                          color: AdminColors.cyan,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              )
                              .toList(),
                    ),
            ),
          ),
          SizedBox(
            width: width,
            child: _panel(
              'Lectura de los resultados',
              'Indicadores para conversar, no para sancionar automáticamente',
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _explanation(
                    Icons.star_outline,
                    'Promedios con contexto',
                    'Cada opinión válida pesa lo mismo. Una calificación aislada no representa a todo el alumnado.',
                  ),
                  const SizedBox(height: 18),
                  _explanation(
                    Icons.people_outline,
                    'Carrera y grupo',
                    'Datos autodeclarados; no equivalen a un padrón verificado. Los campos ausentes aparecen como “Sin informar”.',
                  ),
                  const SizedBox(height: 18),
                  _explanation(
                    Icons.schedule,
                    'Horario de publicación',
                    'El filtro horario corresponde a cuándo se envió la opinión; no mide tiempo de espera ni entrega.',
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    },
  );
  Widget _trend(ReviewStatistics stats) {
    final points = stats.byDay.entries
        .where((e) => e.value.rating != null)
        .toList();
    if (points.isEmpty) {
      return SizedBox(
        height: 225,
        child: _empty('Sin calificaciones con fecha para graficar.'),
      );
    }
    if (points.length == 1) {
      return SizedBox(
        height: 225,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.insights, color: AdminColors.cyan, size: 32),
              const SizedBox(height: 10),
              Text(
                '${_mean(points.first.value.rating)} ★',
                style: const TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w700,
                  color: AdminColors.navy,
                ),
              ),
              Text('${_date(points.first.key)} · un día con opiniones'),
              const SizedBox(height: 6),
              const Text(
                'Se necesitan más días para mostrar una tendencia.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: AdminColors.muted),
              ),
            ],
          ),
        ),
      );
    }
    final first = points.first.key;
    final last = points.last.key.difference(first).inDays.toDouble();
    return SizedBox(
      height: 225,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(0, 10, 12, 0),
        child: LineChart(
          LineChartData(
            minX: 0,
            maxX: math.max(1, last),
            minY: 1,
            maxY: 5,
            gridData: FlGridData(
              show: true,
              drawVerticalLine: false,
              horizontalInterval: 1,
              getDrawingHorizontalLine: (_) =>
                  const FlLine(color: AdminColors.border, strokeWidth: 1),
            ),
            borderData: FlBorderData(show: false),
            titlesData: FlTitlesData(
              topTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
              rightTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 28,
                  interval: 1,
                  getTitlesWidget: (value, meta) => Text(
                    value.toInt().toString(),
                    style: const TextStyle(
                      fontSize: 10,
                      color: AdminColors.muted,
                    ),
                  ),
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 25,
                  interval: math.max(1, (last / 4).ceilToDouble()),
                  getTitlesWidget: (value, meta) => Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      _date(first.add(Duration(days: value.toInt()))),
                      style: const TextStyle(
                        fontSize: 9,
                        color: AdminColors.muted,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            lineBarsData: [
              LineChartBarData(
                spots: points
                    .map(
                      (e) => FlSpot(
                        e.key.difference(first).inDays.toDouble(),
                        e.value.rating!,
                      ),
                    )
                    .toList(),
                isCurved: false,
                color: AdminColors.cyan,
                barWidth: 3,
                dotData: FlDotData(show: points.length < 14),
                belowBarData: BarAreaData(
                  show: true,
                  color: AdminColors.cyan.withValues(alpha: .08),
                ),
              ),
            ],
            lineTouchData: LineTouchData(
              touchTooltipData: LineTouchTooltipData(
                getTooltipItems: (spots) => spots
                    .map(
                      (s) => LineTooltipItem(
                        '${_date(first.add(Duration(days: s.x.toInt())))}\n${s.y.toStringAsFixed(1)} ★',
                        const TextStyle(color: Colors.white, fontSize: 12),
                      ),
                    )
                    .toList(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _explanation(IconData icon, String title, String body) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, size: 22, color: AdminColors.cyan),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AdminColors.navy,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              body,
              style: const TextStyle(
                fontSize: 11,
                color: AdminColors.muted,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    ],
  );
  String _date(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}';
  Widget _comments(List<AdminReview> reviews) {
    if (reviews.isEmpty) {
      return _empty(
        _loading
            ? 'Cargando opiniones…'
            : 'No hay opiniones que coincidan con los filtros.',
      );
    }
    return _card(
      Column(
        children: [
          for (var i = 0; i < reviews.length; i++) ...[
            if (i > 0) const Divider(height: 1, color: AdminColors.border),
            InkWell(
              onTap: () => _openReview(reviews[i]),
              borderRadius: BorderRadius.circular(14),
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: _comment(reviews[i]),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _comment(AdminReview review) {
    final followup = _followups[review.id];
    final status = followup?.status ?? FollowupStatus.pending;
    return LayoutBuilder(
      builder: (context, c) {
        final wide = c.maxWidth >= 650;
        final meta = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 10,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  _businessName(review.businessId),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AdminColors.navy,
                  ),
                ),
                Text(
                  '${review.rating?.toString() ?? '—'} ★',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: review.isNegative
                        ? AdminColors.red
                        : const Color(0xFF788300),
                  ),
                ),
                if (review.isNegative || followup != null)
                  _badge(
                    status.label,
                    status == FollowupStatus.resolved
                        ? AdminColors.cyan
                        : AdminColors.red,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              review.comment.isEmpty
                  ? 'Sin comentario escrito.'
                  : review.comment,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF334155),
                height: 1.55,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 12,
              runSpacing: 5,
              children: [
                Text(
                  '${review.career} · ${review.group}',
                  style: const TextStyle(
                    fontSize: 10,
                    color: AdminColors.muted,
                  ),
                ),
                Text(
                  review.campusTime == null
                      ? 'Fecha sin registrar'
                      : '${_date(review.campusTime!)} · ${review.campusTime!.hour.toString().padLeft(2, '0')}:${review.campusTime!.minute.toString().padLeft(2, '0')} h',
                  style: const TextStyle(
                    fontSize: 10,
                    color: AdminColors.muted,
                  ),
                ),
                if (followup?.assignee.isNotEmpty ?? false)
                  Text(
                    'Responsable: ${followup!.assignee}',
                    style: const TextStyle(
                      fontSize: 10,
                      color: AdminColors.muted,
                    ),
                  ),
              ],
            ),
          ],
        );
        return wide
            ? Row(
                children: [
                  Expanded(child: meta),
                  const SizedBox(width: 20),
                  const Icon(
                    Icons.arrow_forward_rounded,
                    size: 19,
                    color: AdminColors.navy,
                  ),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  meta,
                  const SizedBox(height: 10),
                  const Text(
                    'Ver detalle y seguimiento →',
                    style: TextStyle(
                      color: AdminColors.cyan,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              );
      },
    );
  }

  Widget _sectionTitle(String title, String subtitle) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: AdminColors.navy,
        ),
      ),
      const SizedBox(height: 4),
      Text(
        subtitle,
        style: const TextStyle(fontSize: 11, color: AdminColors.muted),
      ),
    ],
  );
  Widget _panel(String title, String subtitle, Widget content) => _card(
    Padding(
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AdminColors.navy,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            subtitle,
            style: const TextStyle(fontSize: 10, color: AdminColors.muted),
          ),
          const SizedBox(height: 24),
          content,
        ],
      ),
    ),
  );
  Widget _card(Widget child) => Container(
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: AdminColors.border),
    ),
    clipBehavior: Clip.antiAlias,
    child: child,
  );
  Widget _badge(String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .08),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      text,
      style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: color),
    ),
  );
  Widget _empty(String text) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(28),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.inbox_outlined, color: AdminColors.muted, size: 30),
        const SizedBox(height: 10),
        Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(color: AdminColors.muted, fontSize: 12),
        ),
      ],
    ),
  );
  Widget _notice(String text, IconData icon, Color color, {Widget? action}) =>
      Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .06),
          border: Border.all(color: color.withValues(alpha: .16)),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    text,
                    style: TextStyle(fontSize: 11, color: color, height: 1.5),
                  ),
                  if (action != null) action,
                ],
              ),
            ),
          ],
        ),
      );
}
