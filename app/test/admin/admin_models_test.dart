import 'package:flutter_test/flutter_test.dart';
import 'package:snackup/features/admin/domain/admin_models.dart';
import 'package:snackup/features/admin/data/admin_repository.dart';

void main() {
  test('global mean weights each individual opinion, not each business', () {
    final stats = ReviewStatistics([
      const AdminReview(id: 'a', businessId: 'one', rating: 1),
      for (var i = 0; i < 9; i++)
        AdminReview(id: '$i', businessId: 'two', rating: 5),
    ]);
    expect(stats.rating, 4.6);
    expect(stats.negativePercent, 10);
  });
  test(
    'legacy missing dimensions are excluded rather than treated as zero',
    () {
      final legacy = FirebaseAdminRepository.reviewFromMap('old', {
        'businessId': 'one',
        'rating': 4,
        'serviceRating': '5',
        'foodRating': 9,
      });
      expect(legacy.career, unknownAcademicValue);
      expect(legacy.group, unknownAcademicValue);
      final stats = ReviewStatistics([
        legacy,
        const AdminReview(
          id: 'new',
          businessId: 'one',
          rating: 2,
          serviceRating: 5,
          foodRating: 3,
        ),
      ]);
      expect(stats.rating, 3);
      expect(stats.service, 5);
      expect(stats.food, 3);
      expect(stats.histogram[4], 1);
    },
  );
  test('invalid and empty ratings do not produce fabricated percentages', () {
    for (final input in [
      0,
      6,
      -1,
      4.5,
      double.nan,
      double.infinity,
      '4',
      null,
    ]) {
      expect(validRating(input), isNull);
    }
    expect(validRating(4.0), 4);
    expect(ReviewStatistics([]).rating, isNull);
    expect(ReviewStatistics([]).negativePercent, isNull);
  });
  test(
    'all filters intersect including career, group, negative, text and campus hours',
    () {
      final now = DateTime.utc(2026, 10, 5, 1);
      final review = AdminReview(
        id: 'one',
        businessId: 'cafe',
        rating: 2,
        career: 'TI',
        group: 'DS02',
        comment: 'Comida fría',
        createdAt: DateTime.utc(2026, 10, 4, 15),
      );
      const filter = AdminFilter(
        businessId: 'cafe',
        career: 'TI',
        group: 'DS02',
        period: AdminPeriod.week,
        timeOfDay: CampusTimeOfDay.morning,
        negativeOnly: true,
        search: ' FRÍA ',
      );
      expect(filter.matches(review, now), true);
      expect(const AdminFilter(group: 'OTRO').matches(review, now), false);
      expect(
        const AdminFilter(
          timeOfDay: CampusTimeOfDay.afternoon,
        ).matches(review, now),
        false,
      );
    },
  );
  test('period uses campus midnight, excludes future and undated opinions', () {
    final now = DateTime.utc(2026, 10, 5, 1); // Oct 4, 19:00 at campus.
    const filter = AdminFilter(period: AdminPeriod.week);
    expect(
      filter.matches(
        AdminReview(
          id: 'start',
          businessId: 'a',
          createdAt: DateTime.utc(2026, 9, 28, 6),
        ),
        now,
      ),
      true,
    );
    expect(
      filter.matches(
        AdminReview(
          id: 'before',
          businessId: 'a',
          createdAt: DateTime.utc(2026, 9, 28, 5, 59),
        ),
        now,
      ),
      false,
    );
    expect(
      filter.matches(
        AdminReview(
          id: 'future',
          businessId: 'a',
          createdAt: now.add(const Duration(hours: 1)),
        ),
        now,
      ),
      false,
    );
    expect(
      filter.matches(const AdminReview(id: 'none', businessId: 'a'), now),
      false,
    );
    expect(
      const AdminFilter(
        period: AdminPeriod.all,
      ).matches(const AdminReview(id: 'none', businessId: 'a'), now),
      true,
    );
  });
  test('trend is chronological and maps UTC dates to campus day', () {
    final stats = ReviewStatistics([
      AdminReview(
        id: 'a',
        businessId: 'a',
        rating: 5,
        createdAt: DateTime.utc(2026, 10, 5, 3),
      ),
      AdminReview(
        id: 'b',
        businessId: 'a',
        rating: 1,
        createdAt: DateTime.utc(2026, 10, 3, 14),
      ),
    ]);
    expect(stats.byDay.keys.toList(), [
      DateTime.utc(2026, 10, 3),
      DateTime.utc(2026, 10, 4),
    ]);
  });
  test('demo followup saves immutable history entries independently', () async {
    final repo = DemoAdminRepository();
    final page = await repo.loadNextPage();
    expect(page.businesses.length, 4);
    expect(repo.isDemo, true);
    final review = page.reviews.first;
    await repo.saveFollowup(
      AdminFollowup(
        reviewId: review.id,
        businessId: review.businessId,
        status: FollowupStatus.inReview,
        assignee: 'Coordinación',
        note: 'Revisar tiempos',
      ),
    );
    await repo.saveFollowup(
      AdminFollowup(
        reviewId: review.id,
        businessId: review.businessId,
        status: FollowupStatus.resolved,
        assignee: 'Coordinación',
        note: 'Acuerdo registrado',
      ),
    );
    final history = await repo.getHistory(review.id);
    expect(history.events.length, 2);
    expect(history.events.first.status, FollowupStatus.resolved);
    expect(history.events.last.note, 'Revisar tiempos');
  });
}
