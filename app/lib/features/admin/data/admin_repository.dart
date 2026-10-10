import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
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
  Future<void> saveFollowup(AdminFollowup followup);
}

class FirebaseAdminRepository implements AdminRepository {
  FirebaseAdminRepository({FirebaseFirestore? firestore, FirebaseAuth? auth})
    : _db = firestore ?? FirebaseFirestore.instance,
      _auth = auth ?? FirebaseAuth.instance;
  final FirebaseFirestore _db;
  final FirebaseAuth _auth;
  final _cursors = <String, DocumentSnapshot<Map<String, dynamic>>>{};
  final _finished = <String>{};
  static const pageSize = 200;
  @override
  bool get isDemo => false;

  Future<QuerySnapshot<Map<String, dynamic>>?> _page(String name) async {
    if (_finished.contains(name)) return null;
    Query<Map<String, dynamic>> query = _db
        .collection(name)
        .orderBy(FieldPath.documentId)
        .limit(pageSize);
    if (_cursors[name] != null) {
      query = query.startAfterDocument(_cursors[name]!);
    }
    // Server reads avoid presenting cached records as a current campus-wide report.
    return query.get(const GetOptions(source: Source.server));
  }

  @override
  Future<AdminPage> loadNextPage({bool reset = false}) async {
    if (reset) {
      _cursors.clear();
      _finished.clear();
    }
    const names = ['businesses', 'reviews', 'admin_followups'];
    // Advance cursors only after all reads succeeded, so a retry cannot skip rows.
    final snapshots = await Future.wait(names.map(_page));
    final page = AdminPage(
      businesses:
          snapshots[0]?.docs.map((doc) {
            final data = doc.data();
            return AdminBusiness(
              id: doc.id,
              name: academicValue(data['name'] ?? data['businessName']),
              isOpen: data['isOpen'] is bool ? data['isOpen'] as bool : null,
            );
          }).toList() ??
          [],
      reviews:
          snapshots[1]?.docs
              .map((doc) => reviewFromMap(doc.id, doc.data()))
              .toList() ??
          [],
      followups:
          snapshots[2]?.docs
              .map((doc) => _followup(doc.id, doc.data()))
              .toList() ??
          [],
      hasMore: snapshots.asMap().entries.any(
        (e) => e.value != null && e.value!.docs.length == pageSize,
      ),
    );
    for (var i = 0; i < names.length; i++) {
      final snapshot = snapshots[i];
      if (snapshot == null) continue;
      if (snapshot.docs.isNotEmpty) _cursors[names[i]] = snapshot.docs.last;
      if (snapshot.docs.length < pageSize) _finished.add(names[i]);
    }
    return page;
  }

  static DateTime? _date(Object? value) =>
      value is Timestamp ? value.toDate() : null;
  static AdminReview reviewFromMap(String id, Map<String, dynamic> data) =>
      AdminReview(
        id: id,
        businessId: data['businessId'] is String
            ? data['businessId'] as String
            : '',
        rating: validRating(data['rating']),
        serviceRating: validRating(data['serviceRating']),
        foodRating: validRating(data['foodRating']),
        career: academicValue(data['career']),
        group: academicValue(data['group']),
        comment: data['comment'] is String ? data['comment'] as String : '',
        createdAt: _date(data['createdAt']),
      );
  static AdminFollowup _followup(String id, Map<String, dynamic> data) =>
      AdminFollowup(
        reviewId: id,
        businessId: data['businessId'] is String
            ? data['businessId'] as String
            : '',
        status: statusFromCode(data['status']),
        assignee: data['assignee'] is String ? data['assignee'] as String : '',
        note: data['note'] is String ? data['note'] as String : '',
        updatedAt: _date(data['updatedAt']),
      );
  @override
  Future<AdminFollowup> getFollowup(AdminReview review) async {
    final doc = await _db
        .collection('admin_followups')
        .doc(review.id)
        .get(const GetOptions(source: Source.server));
    return doc.exists
        ? _followup(doc.id, doc.data()!)
        : AdminFollowup(reviewId: review.id, businessId: review.businessId);
  }

  @override
  Future<FollowupHistory> getHistory(String reviewId) async {
    final rows = await _db
        .collection('admin_followups')
        .doc(reviewId)
        .collection('history')
        .orderBy('updatedAt', descending: true)
        .limit(51)
        .get(const GetOptions(source: Source.server));
    return FollowupHistory(
      rows.docs.take(50).map((doc) => _followup(reviewId, doc.data())).toList(),
      hasMore: rows.docs.length > 50,
    );
  }

  @override
  Future<void> saveFollowup(AdminFollowup followup) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('Sesión terminada. Vuelve a iniciar sesión.');
    }
    if (followup.assignee.trim().length > 120 ||
        followup.note.trim().length > 2000) {
      throw ArgumentError('El texto excede el límite permitido.');
    }
    if (followup.assignee.trim().isEmpty || followup.note.trim().isEmpty) {
      throw ArgumentError('Indica responsable y nota de seguimiento.');
    }
    final ref = _db.collection('admin_followups').doc(followup.reviewId);
    final event = ref.collection('history').doc();
    final values = <String, dynamic>{
      'eventId': event.id,
      'reviewId': followup.reviewId,
      'businessId': followup.businessId,
      'status': followup.status.code,
      'assignee': followup.assignee.trim(),
      'note': followup.note.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
      'updatedBy': user.uid,
    };
    final batch = _db.batch();
    batch.set(ref, values);
    batch.set(event, values);
    await batch.commit();
  }
}

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
  Future<void> saveFollowup(AdminFollowup followup) async {
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
    );
    _followups[followup.reviewId] = saved;
    _history.putIfAbsent(followup.reviewId, () => []).insert(0, saved);
  }
}
