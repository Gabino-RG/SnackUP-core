import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../domain/admin_models.dart';
import 'admin_repository.dart';

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
  Future<AdminFollowup> saveFollowup(AdminFollowup followup) async {
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
    final saved = await ref.get(const GetOptions(source: Source.server));
    return _followup(saved.id, saved.data()!);
  }
}

