import '../domain/admin_models.dart';

class AdminPage {
  const AdminPage({
    this.businesses = const [],
    this.reviews = const [],
    this.followups = const [],
    this.hasMore = false,
  });
  final List<AdminBusiness> businesses;
  final List<AdminReview> reviews;
  final List<AdminFollowup> followups;
  final bool hasMore;
}

abstract class AdminRepository {
  bool get isDemo;
  Future<AdminPage> loadNextPage({bool reset = false});
  Future<AdminFollowup> getFollowup(AdminReview review);
  Future<FollowupHistory> getHistory(String reviewId);
  Future<AdminFollowup> saveFollowup(AdminFollowup followup);
}


class AdminDataException implements Exception {
  const AdminDataException(this.message, {this.code = 'ADMIN_ERROR'});
  final String message, code;
}
