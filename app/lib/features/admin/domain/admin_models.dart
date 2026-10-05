// Pure Dart domain: no Firebase or Flutter dependency.
const unknownAcademicValue = 'Sin informar';

int? validRating(Object? value) {
  if (value is! num || !value.isFinite || value != value.roundToDouble()) {
    return null;
  }
  final rating = value.toInt();
  return rating >= 1 && rating <= 5 ? rating : null;
}

String academicValue(Object? value) =>
    value is String && value.trim().isNotEmpty
    ? value.trim()
    : unknownAcademicValue;

class AdminBusiness {
  const AdminBusiness({required this.id, required this.name, this.isOpen});
  final String id;
  final String name;
  final bool? isOpen;
}

class AdminReview {
  const AdminReview({
    required this.id,
    required this.businessId,
    this.rating,
    this.serviceRating,
    this.foodRating,
    this.career = unknownAcademicValue,
    this.group = unknownAcademicValue,
    this.comment = '',
    this.createdAt,
  });
  final String id;
  final String businessId;
  final int? rating;
  final int? serviceRating;
  final int? foodRating;
  final String career;
  final String group;
  final String comment;
  final DateTime? createdAt;
  bool get isNegative => rating != null && rating! >= 1 && rating! <= 2;
  // The campus is in San Juan del Río: UTC−6 throughout the year.
  DateTime? get campusTime =>
      createdAt?.toUtc().subtract(const Duration(hours: 6));
}

enum FollowupStatus { pending, inReview, resolved }

extension FollowupStatusText on FollowupStatus {
  String get code => switch (this) {
    FollowupStatus.pending => 'pending',
    FollowupStatus.inReview => 'in_review',
    FollowupStatus.resolved => 'resolved',
  };
  String get label => switch (this) {
    FollowupStatus.pending => 'Pendiente',
    FollowupStatus.inReview => 'En revisión',
    FollowupStatus.resolved => 'Resuelto',
  };
}

FollowupStatus statusFromCode(Object? code) => switch (code) {
  'in_review' => FollowupStatus.inReview,
  'resolved' => FollowupStatus.resolved,
  _ => FollowupStatus.pending,
};

class AdminFollowup {
  const AdminFollowup({
    required this.reviewId,
    required this.businessId,
    this.status = FollowupStatus.pending,
    this.assignee = '',
    this.note = '',
    this.updatedAt,
  });
  final String reviewId;
  final String businessId;
  final FollowupStatus status;
  final String assignee;
  final String note;
  final DateTime? updatedAt;
}

class FollowupHistory {
  const FollowupHistory(this.events, {this.hasMore = false});
  final List<AdminFollowup> events;
  final bool hasMore;
}

enum AdminPeriod { all, week, month, quarter }

enum CampusTimeOfDay { all, morning, afternoon, evening }

class AdminFilter {
  const AdminFilter({
    this.businessId,
    this.career,
    this.group,
    this.period = AdminPeriod.month,
    this.timeOfDay = CampusTimeOfDay.all,
    this.negativeOnly = false,
    this.search = '',
  });
  final String? businessId;
  final String? career;
  final String? group;
  final AdminPeriod period;
  final CampusTimeOfDay timeOfDay;
  final bool negativeOnly;
  final String search;

  bool matches(AdminReview review, DateTime now) {
    if (businessId != null && review.businessId != businessId) return false;
    if (career != null && review.career != career) return false;
    if (group != null && review.group != group) return false;
    if (negativeOnly && !review.isNegative) return false;
    if (search.trim().isNotEmpty &&
        !review.comment.toLowerCase().contains(search.trim().toLowerCase())) {
      return false;
    }
    final time = review.campusTime;
    if (period != AdminPeriod.all) {
      if (time == null) return false;
      final campusNow = now.toUtc().subtract(const Duration(hours: 6));
      final days = switch (period) {
        AdminPeriod.week => 7,
        AdminPeriod.month => 30,
        AdminPeriod.quarter => 90,
        AdminPeriod.all => 0,
      };
      final start = DateTime.utc(
        campusNow.year,
        campusNow.month,
        campusNow.day,
      ).subtract(Duration(days: days - 1));
      if (time.isBefore(start) || time.isAfter(campusNow)) return false;
    }
    if (timeOfDay != CampusTimeOfDay.all) {
      if (time == null) return false;
      final matchesHour = switch (timeOfDay) {
        CampusTimeOfDay.morning => time.hour >= 6 && time.hour < 12,
        CampusTimeOfDay.afternoon => time.hour >= 12 && time.hour < 18,
        CampusTimeOfDay.evening => time.hour >= 18 || time.hour < 6,
        CampusTimeOfDay.all => true,
      };
      if (!matchesHour) return false;
    }
    return true;
  }
}

class ReviewStatistics {
  ReviewStatistics(Iterable<AdminReview> source)
    : reviews = List.unmodifiable(source);
  final List<AdminReview> reviews;
  double? average(int? Function(AdminReview) select) {
    final ratings = reviews
        .map(select)
        .whereType<int>()
        .where((r) => r >= 1 && r <= 5)
        .toList();
    return ratings.isEmpty
        ? null
        : ratings.reduce((a, b) => a + b) / ratings.length;
  }

  double? get rating => average((r) => r.rating);
  double? get service => average((r) => r.serviceRating);
  double? get food => average((r) => r.foodRating);
  int get validCount =>
      reviews.where((r) => validRating(r.rating) != null).length;
  int get negativeCount => reviews.where((r) => r.isNegative).length;
  double? get negativePercent =>
      validCount == 0 ? null : 100 * negativeCount / validCount;
  Map<int, int> get histogram => {
    for (var star = 1; star <= 5; star++)
      star: reviews.where((r) => r.rating == star).length,
  };
  Map<String, ReviewStatistics> get byCareer {
    final grouped = <String, List<AdminReview>>{};
    for (final review in reviews) {
      grouped.putIfAbsent(review.career, () => []).add(review);
    }
    return grouped.map((key, value) => MapEntry(key, ReviewStatistics(value)));
  }

  Map<DateTime, ReviewStatistics> get byDay {
    final grouped = <DateTime, List<AdminReview>>{};
    for (final review in reviews) {
      final date = review.campusTime;
      if (date == null) continue;
      grouped
          .putIfAbsent(DateTime.utc(date.year, date.month, date.day), () => [])
          .add(review);
    }
    final keys = grouped.keys.toList()..sort();
    return {for (final key in keys) key: ReviewStatistics(grouped[key]!)};
  }
}
