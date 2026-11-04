import 'package:snackup/features/admin/data/firebase_admin_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snackup/features/admin/domain/admin_models.dart';
import 'package:snackup/features/admin/data/admin_repository.dart';
import 'package:snackup/features/admin/data/demo_admin_repository.dart';

void main() {
  test('career averages keep one identity together after a name change', () {
    final groups = ReviewStatistics(const [
      AdminReview(
        id: 'old',
        businessId: 'b',
        careerId: 'c1',
        career: 'Anterior',
        rating: 0,
      ),
      AdminReview(
        id: 'new',
        businessId: 'b',
        careerId: 'c1',
        career: 'Actual',
        rating: 4,
      ),
    ]).byCareer;
    expect(groups.length, 1);
    expect(groups.values.single.rating, 2);
    expect(groups.values.single.validCount, 2);
  });
  test(
    'career averages never merge different identifiers with the same name',
    () {
      final groups = ReviewStatistics(const [
        AdminReview(
          id: 'one',
          businessId: 'b',
          careerId: 'c1',
          career: 'Software',
          rating: 1,
        ),
        AdminReview(
          id: 'two',
          businessId: 'b',
          careerId: 'c2',
          career: 'Software',
          rating: 5,
        ),
      ]).byCareer;
      expect(groups.length, 2);
      expect(groups.values.map((g) => g.rating), unorderedEquals([1.0, 5.0]));
    },
  );
  test('legacy career names remain separate from identified careers', () {
    final groups = ReviewStatistics(const [
      AdminReview(
        id: 'identified',
        businessId: 'b',
        careerId: 'c1',
        career: 'Software',
        rating: 5,
      ),
      AdminReview(
        id: 'legacy-one',
        businessId: 'b',
        career: 'Software',
        rating: 0,
      ),
      AdminReview(
        id: 'legacy-two',
        businessId: 'b',
        career: 'Software',
        rating: 4,
      ),
    ]).byCareer;
    expect(groups.length, 2);
    final legacy = groups.values.singleWhere(
      (g) => g.reviews.first.careerId == null,
    );
    expect(legacy.validCount, 2);
    expect(legacy.rating, 2);
  });
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
    for (final input in [6, -1, 4.5, double.nan, double.infinity, '4', null]) {
      expect(validRating(input), isNull);
    }
    expect(validRating(4.0), 4);
    expect(validRating(0), 0);
    expect(ReviewStatistics([]).rating, isNull);
    expect(ReviewStatistics([]).negativePercent, isNull);
  });
  test('V3.2 zero stars count in averages, alerts, histogram and filters', () {
    const zero = AdminReview(id: 'zero', businessId: 'one', rating: 0);
    final stats = ReviewStatistics([
      zero,
      const AdminReview(id: 'five', businessId: 'one', rating: 5),
      const AdminReview(id: 'missing', businessId: 'one'),
    ]);
    expect(stats.rating, 2.5);
    expect(stats.validCount, 2);
    expect(stats.negativeCount, 1);
    expect(stats.negativePercent, 50);
    expect(stats.histogram[0], 1);
    expect(stats.service, isNull);
    expect(
      const AdminFilter(
        period: AdminPeriod.all,
        negativeOnly: true,
      ).matches(zero, DateTime.now()),
      isTrue,
    );
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
