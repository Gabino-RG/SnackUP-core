import '../domain/admin_models.dart';
import 'admin_repository.dart';

/// Local fixtures. Never selected automatically when Firebase fails.
class DemoAdminRepository implements AdminRepository {
  DemoAdminRepository({DateTime? now, this.empty = false})
    : now = now ?? DateTime.now().toUtc();
  final DateTime now;
  final bool empty;
  final _followups = <String, AdminFollowup>{};
  final _history = <String, List<AdminFollowup>>{};
  @override
  bool get isDemo => true;
  static const businesses = [
    AdminBusiness(id: 'demo-1', name: 'Cafetería Central', isOpen: true),
    AdminBusiness(id: 'demo-2', name: 'La Terraza', isOpen: true),
    AdminBusiness(id: 'demo-3', name: 'Rincón del Café', isOpen: true),
    AdminBusiness(id: 'demo-4', name: 'Snack & Go', isOpen: false),
  ];
  List<AdminReview> _reviews() {
    const careers = [
      'Tecnologías de la Información',
      'Administración',
      'Mecatrónica',
      'Química',
    ];
    const groups = ['DS02SV-26', 'AD01SV-26', 'ME03SM-26', 'QI02SM-26'];
    const comments = [
      'La atención fue amable y mi pedido estuvo listo a tiempo.',
      'La comida estuvo fría y tardaron más de lo indicado.',
      'Buen sabor. Me gustaría que hubiera más opciones vegetarianas.',
      'Excelente servicio durante el receso, volvería a pedir.',
      'Esperé demasiado y no me avisaron del retraso.',
      'Las porciones y la calidad me parecieron muy buenas.',
    ];
    final campusNow = now.toUtc().subtract(const Duration(hours: 6));
    return List.generate(96, (i) {
      final shop = i % 4;
      final rating = shop == 1
          ? [1, 2, 2, 3, 4, 2][(i ~/ 4) % 6]
          : shop == 2
          ? [5, 5, 4, 5, 4, 5][(i ~/ 4) % 6]
          : [4, 3, 5, 4, 2, 5][(i ~/ 4) % 6];
      final day = DateTime.utc(
        campusNow.year,
        campusNow.month,
        campusNow.day,
      ).subtract(Duration(days: 1 + i ~/ 4));
      final date = day.add(
        Duration(hours: 6 + [8, 11, 14, 17][i % 4], minutes: i % 50),
      );
      return AdminReview(
        id: 'demo-review-$i',
        businessId: 'demo-${shop + 1}',
        rating: rating,
        serviceRating: i % 11 == 0 ? null : (shop == 1 ? 2 : rating),
        foodRating: i % 9 == 0 ? null : (shop == 2 ? 5 : rating),
        career: i % 13 == 0
            ? unknownAcademicValue
            : careers[(i ~/ 4 + shop) % 4],
        group: i % 13 == 0 ? unknownAcademicValue : groups[(i ~/ 4 + shop) % 4],
        comment: rating <= 2
            ? comments[i % 2 == 0 ? 1 : 4]
            : comments[[0, 2, 3, 5][i % 4]],
        createdAt: date,
      );
    });
  }

  @override
  Future<AdminPage> loadNextPage({bool reset = false}) async => AdminPage(
    businesses: empty ? [] : businesses,
    reviews: empty ? [] : _reviews(),
    followups: _followups.values.toList(),
  );
  @override
  Future<AdminFollowup> getFollowup(AdminReview review) async =>
      _followups[review.id] ??
      AdminFollowup(reviewId: review.id, businessId: review.businessId);
  @override
  Future<FollowupHistory> getHistory(String reviewId) async =>
      FollowupHistory(List.unmodifiable(_history[reviewId] ?? []));
  @override
  Future<AdminFollowup> saveFollowup(AdminFollowup followup) async {
    if (followup.assignee.trim().isEmpty || followup.note.trim().isEmpty) {
      throw ArgumentError('Indica responsable y nota.');
    }
    final saved = AdminFollowup(
      reviewId: followup.reviewId,
      businessId: followup.businessId,
      status: followup.status,
      assignee: followup.assignee.trim(),
      note: followup.note.trim(),
      updatedAt: DateTime.now().toUtc(),
      version: (_followups[followup.reviewId]?.version ?? 0) + 1,
    );
    _followups[followup.reviewId] = saved;
    _history.putIfAbsent(followup.reviewId, () => []).insert(0, saved);
    return saved;
  }
}
