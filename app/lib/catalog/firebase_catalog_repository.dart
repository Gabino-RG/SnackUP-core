import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'catalog.dart';

/// Compatibility for the existing app only. SQL deployment uses REST instead.
class FirebaseCatalogRepository extends CatalogRepository {
  FirebaseCatalogRepository({FirebaseFirestore? db, FirebaseAuth? auth, FirebaseStorage? storage})
      : _db = db ?? FirebaseFirestore.instance, _auth = auth ?? FirebaseAuth.instance,
        _storage = storage ?? FirebaseStorage.instance;
  final FirebaseFirestore _db;
  final FirebaseAuth _auth;
  final FirebaseStorage _storage;
  @override
  bool get isLocal => false;
  @override
  bool get supportsOptionalStock => false;

  CatalogProduct _product(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    if (data == null) throw const CatalogException('El producto ya no existe.', code: 'NOT_FOUND');
    final timestamp = data['updatedAt'];
    final time = timestamp is Timestamp ? timestamp.toDate().toUtc() : DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    return CatalogProduct.fromJson({
      ...data, 'id': doc.id,
      'price': data['priceCents'] is int ? (data['priceCents'] as int) / 100 : data['price'],
      'version': time.microsecondsSinceEpoch, 'updatedAt': time.toIso8601String(),
    });
  }

  Future<void> _owner(String businessId) async {
    final user = _auth.currentUser;
    if (user == null) throw const CatalogException('Vuelve a iniciar sesión.');
    final doc = await _db.collection('businesses').doc(businessId).get(const GetOptions(source: Source.server));
    if (doc.data()?['ownerId'] != user.uid) {
      throw const CatalogException('Tu cuenta no administra este local.', code: 'FORBIDDEN');
    }
  }

  @override
  Future<CatalogPage> list(String businessId, {CatalogQuery query = const CatalogQuery()}) async {
    await _owner(businessId);
    final data = await _db.collection('products').where('businessId', isEqualTo: businessId)
        .get(const GetOptions(source: Source.server));
    return paginateCatalog(data.docs.map(_product).toList(), query);
  }

  @override
  Future<CatalogProduct> get(String businessId, String id) async {
    await _owner(businessId);
    final product = _product(await _db.collection('products').doc(id).get(const GetOptions(source: Source.server)));
    if (product.businessId != businessId) throw const CatalogException('El producto pertenece a otro local.');
    return product;
  }

  @override
  Future<CatalogProduct> save(String businessId, ProductDraft draft, {CatalogProduct? original}) async {
    draft.validate();
    if (draft.stock == null) throw const CatalogException('Indica las existencias para esta conexión.');
    if (original != null && original.businessId != businessId) throw const CatalogException('El producto pertenece a otro local.');
    await _owner(businessId);
    final ref = _db.collection('products').doc(original?.id);
    await _db.runTransaction((tx) async {
      final values = <String, dynamic>{
        ...draft.toJson(), 'priceCents': draft.priceCents,
        'name_searchable': draft.name.trim().toLowerCase(),
        'updatedAt': FieldValue.serverTimestamp(),
      };
      if (original == null) {
        tx.set(ref, {...values, 'businessId': businessId, 'createdAt': FieldValue.serverTimestamp()});
      } else {
        final current = _product(await tx.get(ref));
        if (current.businessId != businessId) throw const CatalogException('El producto pertenece a otro local.');
        if (current.version != original.version) throw const CatalogException('El producto cambió. Recarga antes de guardar.', code: 'VERSION_CONFLICT');
        if (draft.stock == original.draft.stock) {
          values.remove('stock');
          if (current.draft.stock == 0) values['isAvailable'] = false;
        } else if (current.draft.stock != original.draft.stock) {
          throw const CatalogException('Las existencias cambiaron. Recarga antes de ajustarlas.', code: 'VERSION_CONFLICT');
        }
        tx.update(ref, values);
      }
    });
    return get(businessId, ref.id);
  }

  @override
  Future<void> delete(CatalogProduct product) async {
    await _owner(product.businessId);
    final ref = _db.collection('products').doc(product.id);
    await _db.runTransaction((tx) async {
      final current = _product(await tx.get(ref));
      if (current.businessId != product.businessId || current.version != product.version) {
        throw const CatalogException('El producto cambió. Recarga antes de eliminarlo.', code: 'VERSION_CONFLICT');
      }
      tx.delete(ref);
    });
  }

  @override
  Future<String> uploadImage(String businessId, Uint8List bytes, String fileName) async {
    validateProductImage(bytes, fileName);
    await _owner(businessId);
    final extension = fileName.split('.').last.toLowerCase();
    final mime = extension == 'jpg' ? 'jpeg' : extension;
    final ref = _storage.ref('product_images/$businessId/${DateTime.now().microsecondsSinceEpoch}.$extension');
    final task = await ref.putData(bytes, SettableMetadata(contentType: 'image/$mime'));
    return task.ref.getDownloadURL();
  }
}
