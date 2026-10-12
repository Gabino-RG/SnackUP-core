import '../../../api/api_client.dart';
import '../domain/admin_models.dart';
import 'admin_repository.dart';

/// Provisional administrative endpoints, isolated until backend confirms them.
class AdminApiRoutes {
  const AdminApiRoutes({this.businesses = 'admin/businesses', this.reviews = 'admin/reviews',
    this.followups = 'admin/followups', this.casePath = 'admin/reviews/{reviewId}/followup'});
  final String businesses, reviews, followups, casePath;
  String forReview(String id) => casePath.replaceAll('{reviewId}', Uri.encodeComponent(id));
}

class RestAdminRepository implements AdminRepository {
  RestAdminRepository(this.api, {this.routes = const AdminApiRoutes()});
  final ApiClient api;
  final AdminApiRoutes routes;
  final _nextPages = <String, int>{};
  final _finished = <String>{};
  bool _loading = false;
  @override
  bool get isDemo => false;

  Future<T> _guard<T>(Future<T> Function() action) async {
    try { return await action(); }
    on ApiException catch (error) { throw AdminDataException(error.message, code: error.code); }
  }

  static Map<String, dynamic> _map(dynamic value) {
    if (value is! Map) throw const ApiException('La API devolvió datos incompletos.', code: 'INVALID_RESPONSE');
    return Map<String, dynamic>.from(value);
  }
  static String _id(Map<String, dynamic> data, String key) {
    final value = data[key];
    if (value is! String || value.isEmpty) throw const ApiException('Falta un identificador del registro.', code: 'INVALID_RESPONSE');
    return value;
  }
  static DateTime? _date(dynamic value) {
    if (value == null) return null;
    final result = value is String ? DateTime.tryParse(value)?.toUtc() : null;
    if (result == null) throw const ApiException('La fecha del registro no es válida.', code: 'INVALID_RESPONSE');
    return result;
  }
  static AdminBusiness _business(dynamic value) {
    final data = _map(value);
    return AdminBusiness(id: _id(data, 'id'), name: academicValue(data['name']),
      isOpen: data['isOpen'] is bool ? data['isOpen'] as bool : null);
  }
  static AdminReview _review(dynamic value) {
    final data = _map(value);
    return AdminReview(id: _id(data, 'id'), businessId: _id(data, 'businessId'),
      rating: validRating(data['rating']), serviceRating: validRating(data['serviceRating']),
      foodRating: validRating(data['foodRating']), career: academicValue(data['career']),
      group: academicValue(data['group']), comment: data['comment'] as String? ?? '',
      createdAt: _date(data['createdAt']));
  }
  static AdminFollowup _followup(dynamic value) {
    final data = _map(value);
    final version = data['version'];
    if (version is! int || version < 0) {
      throw const ApiException('Falta la versión del seguimiento.', code: 'INVALID_RESPONSE');
    }
    return AdminFollowup(reviewId: _id(data, 'reviewId'), businessId: _id(data, 'businessId'),
      status: statusFromCode(data['status']), assignee: data['assignee'] as String? ?? '',
      note: data['note'] as String? ?? '', updatedAt: _date(data['updatedAt']), version: version);
  }

  @override
  Future<AdminPage> loadNextPage({bool reset = false}) => _guard(() async {
    if (_loading) throw const AdminDataException('Espera a que termine la actualización.');
    _loading = true;
    try {
      final paths = [routes.businesses, routes.reviews, routes.followups];
      final pages = {for (final path in paths) path: reset ? 1 : (_nextPages[path] ?? 1)};
      final done = reset ? <String>{} : {..._finished};
      final responses = await Future.wait(paths.map((path) async => done.contains(path) ? null :
        api.json('GET', path, query: {'page': '${pages[path]}', 'limit': '200'})));
      final rows = <List<dynamic>>[];
      for (var i = 0; i < paths.length; i++) {
        if (responses[i] == null && done.contains(paths[i])) { rows.add([]); continue; }
        final data = _map(responses[i]);
        final pagination = _map(data['pagination']);
        final page = pagination['page'], totalPages = pagination['totalPages'];
        if (data['data'] is! List || page != pages[paths[i]] || totalPages is! int || totalPages < 0) {
          throw const ApiException('La paginación administrativa está incompleta.', code: 'INVALID_RESPONSE');
        }
        rows.add(data['data'] as List);
        if ((page as int) >= totalPages) done.add(paths[i]);
        pages[paths[i]] = page + 1;
      }
      final result = AdminPage(businesses: rows[0].map(_business).toList(),
        reviews: rows[1].map(_review).toList(), followups: rows[2].map(_followup).toList(),
        hasMore: done.length < paths.length);
      // Failed requests or malformed records cannot consume a pagination cursor.
      _nextPages..clear()..addAll(pages);
      _finished..clear()..addAll(done);
      return result;
    } finally { _loading = false; }
  });

  @override
  Future<AdminFollowup> getFollowup(AdminReview review) => _guard(() async {
    try {
      final data = _map(await api.json('GET', routes.forReview(review.id)));
      final result = _followup(data['data'] ?? data);
      if (result.reviewId != review.id || result.businessId != review.businessId) {
        throw const ApiException('El seguimiento pertenece a otro caso.', code: 'INVALID_RESPONSE');
      }
      return result;
    } on ApiException catch (error) {
      if (error.status == 404 && error.code == 'FOLLOWUP_NOT_FOUND') {
        return AdminFollowup(reviewId: review.id, businessId: review.businessId, version: 0);
      }
      rethrow;
    }
  });

  @override
  Future<FollowupHistory> getHistory(String reviewId) => _guard(() async {
    final data = _map(await api.json('GET', '${routes.forReview(reviewId)}/history',
      query: {'page': '1', 'limit': '50'}));
    final pagination = _map(data['pagination']);
    if (data['data'] is! List || pagination['totalPages'] is! int || pagination['page'] != 1) {
      throw const ApiException('El historial está incompleto.', code: 'INVALID_RESPONSE');
    }
    final events = (data['data'] as List).map(_followup).toList();
    if (events.any((event) => event.reviewId != reviewId)) {
      throw const ApiException('El historial pertenece a otro caso.', code: 'INVALID_RESPONSE');
    }
    return FollowupHistory(events.take(50).toList(), hasMore: (pagination['totalPages'] as int) > 1);
  });

  @override
  Future<AdminFollowup> saveFollowup(AdminFollowup followup) => _guard(() async {
    if (followup.version == null) throw const AdminDataException('Actualiza el caso antes de guardar.');
    if (followup.assignee.trim().isEmpty || followup.assignee.trim().length > 120 ||
        followup.note.trim().isEmpty || followup.note.trim().length > 2000) {
      throw const AdminDataException('Indica responsable y nota dentro de los límites del formulario.');
    }
    final data = _map(await api.json('PUT', routes.forReview(followup.reviewId), body: {
      'status': followup.status.code, 'assignee': followup.assignee.trim(),
      'note': followup.note.trim(), 'expectedVersion': followup.version,
    }));
    final result = _followup(data['data'] ?? data);
    if (result.reviewId != followup.reviewId || result.businessId != followup.businessId ||
        result.version! <= followup.version! || result.updatedAt == null) {
      throw const ApiException('El servidor no confirmó la versión guardada. Actualiza el caso.', code: 'INVALID_RESPONSE');
    }
    return result;
  });
}
