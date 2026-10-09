import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'order_checkout.dart';

class CartProductRequest {
  final String productId;
  final int quantity;
  final String notes;
  const CartProductRequest(this.productId, this.quantity, this.notes);
}

class StudentOrderRepository {
  final FirebaseFirestore firestore;
  final FirebaseAuth auth;

  StudentOrderRepository({FirebaseFirestore? firestore, FirebaseAuth? auth})
    : firestore = firestore ?? FirebaseFirestore.instance,
      auth = auth ?? FirebaseAuth.instance;

  String get _userId {
    final uid = auth.currentUser?.uid;
    if (uid == null) {
      throw const OrderFlowException('Inicia sesión para continuar.');
    }
    return uid;
  }

  /// Reordering, favorites and the product page share current catalog validation.
  /// A repeated product adds quantity instead of silently replacing the cart line.
  Future<void> addProducts(List<CartProductRequest> requests) async {
    final uid = _userId;
    if (requests.isEmpty || requests.length > maxOrderLines) {
      throw const OrderFlowException('Elige entre 1 y 8 productos distintos.');
    }
    final uniqueIds = requests.map((r) => validProductId(r.productId)).toSet();
    if (uniqueIds.length != requests.length) {
      throw const OrderFlowException(
        'Hay productos repetidos en la selección.',
      );
    }
    final cartRef = firestore.collection('users').doc(uid).collection('cart');
    final current = await cartRef.get(const GetOptions(source: Source.server));
    final allCartIds = {...current.docs.map((d) => d.id), ...uniqueIds};
    if (allCartIds.length > maxOrderLines) {
      throw const OrderFlowException(
        'Puedes agregar hasta 8 productos distintos por pedido.',
      );
    }
    await firestore.runTransaction((transaction) async {
      final existing = <String, Map<String, dynamic>>{};
      for (final id in allCartIds) {
        final snapshot = await transaction.get(cartRef.doc(id));
        if (snapshot.exists) existing[id] = snapshot.data()!;
      }
      final products = <String, Map<String, dynamic>>{};
      for (final request in requests) {
        final snapshot = await transaction.get(
          firestore.collection('products').doc(request.productId),
        );
        if (!snapshot.exists) {
          throw const OrderFlowException('Un producto ya no está disponible.');
        }
        products[request.productId] = snapshot.data()!;
      }
      final businessIds = {
        ...existing.values.map((item) => item['businessId']),
        ...products.values.map((product) => product['businessId']),
      };
      if (businessIds.length != 1 ||
          businessIds.single is! String ||
          (businessIds.single as String).isEmpty) {
        throw const OrderFlowException(
          'Tu carrito ya tiene productos de otro local. Termina o vacía ese pedido primero.',
        );
      }
      final business = await transaction.get(
        firestore.collection('businesses').doc(businessIds.single as String),
      );
      if (business.data()?['isOpen'] != true) {
        throw const OrderFlowException(
          'El local está cerrado y no recibe pedidos.',
        );
      }
      for (final request in requests) {
        final product = products[request.productId]!;
        final previous = existing[request.productId];
        final quantity =
            validQuantity(request.quantity) +
            (previous == null ? 0 : validQuantity(previous['quantity']));
        validateProductForOrder(product, quantity);
        transaction.set(cartRef.doc(request.productId), {
          'productId': request.productId,
          'businessId': product['businessId'],
          'name': product['name'],
          'price': productPriceCents(product) / 100,
          'imageUrl': product['imageUrl'] is String ? product['imageUrl'] : '',
          'quantity': quantity,
          'notes': validNotes(request.notes),
          'addedAt': FieldValue.serverTimestamp(),
        });
      }
    });
  }

  Future<CheckoutQuote> prepareQuote(List<String> cartIds) async {
    final uid = _userId;
    if (cartIds.isEmpty || cartIds.length > maxOrderLines) {
      throw const OrderFlowException(
        'El pedido debe tener de 1 a 8 productos distintos.',
      );
    }
    final cart = <String, Map<String, dynamic>>{};
    final products = <String, Map<String, dynamic>>{};
    for (final id in cartIds) {
      final snapshot = await firestore
          .collection('users')
          .doc(uid)
          .collection('cart')
          .doc(id)
          .get(const GetOptions(source: Source.server));
      if (!snapshot.exists) {
        throw const OrderFlowException(
          'Tu carrito cambió. Revísalo antes de confirmar.',
        );
      }
      cart[id] = snapshot.data()!;
      final productId = validProductId(cart[id]!['productId']);
      final product = await firestore
          .collection('products')
          .doc(productId)
          .get(const GetOptions(source: Source.server));
      if (product.exists) products[productId] = product.data()!;
    }
    final businessId = products.values.firstOrNull?['businessId'];
    if (businessId is! String || businessId.isEmpty) {
      throw const OrderFlowException(
        'El local de este pedido ya no está disponible.',
      );
    }
    final business = await firestore
        .collection('businesses')
        .doc(businessId)
        .get(const GetOptions(source: Source.server));
    return buildCheckoutQuote(
      cart: cart,
      products: products,
      business: business.data() ?? {},
    );
  }

  Future<String> placeOrder({
    required CheckoutQuote confirmedQuote,
    required String paymentMethod,
    DateTime? pickupTime,
  }) async {
    final uid = _userId;
    if (!['Efectivo', 'Tarjeta', 'Vale'].contains(paymentMethod)) {
      throw const OrderFlowException('Selecciona una forma de pago válida.');
    }
    validatePickupTime(pickupTime, DateTime.now());
    final orderRef = firestore.collection('orders').doc();
    final pickupCode = List.generate(
      16,
      (_) => Random.secure().nextInt(256),
    ).map((value) => value.toRadixString(16).padLeft(2, '0')).join();
    await firestore.runTransaction((transaction) async {
      final cart = <String, Map<String, dynamic>>{};
      final products = <String, Map<String, dynamic>>{};
      final cartRef = firestore.collection('users').doc(uid).collection('cart');
      for (final id in confirmedQuote.cartIds) {
        final snapshot = await transaction.get(cartRef.doc(id));
        if (!snapshot.exists) {
          throw const OrderFlowException(
            'Este carrito ya cambió o ya se convirtió en pedido.',
          );
        }
        cart[id] = snapshot.data()!;
      }
      for (final item in cart.values) {
        final productId = validProductId(item['productId']);
        final snapshot = await transaction.get(
          firestore.collection('products').doc(productId),
        );
        if (snapshot.exists) products[productId] = snapshot.data()!;
      }
      final business = await transaction.get(
        firestore.collection('businesses').doc(confirmedQuote.businessId),
      );
      final user = await transaction.get(
        firestore.collection('users').doc(uid),
      );
      final currentQuote = buildCheckoutQuote(
        cart: cart,
        products: products,
        business: business.data() ?? {},
      );
      if (currentQuote.signature != confirmedQuote.signature) {
        throw const OrderFlowException(
          'Cambió el precio o contenido del carrito. Revisa el total y confirma de nuevo.',
        );
      }
      if (!user.exists) {
        throw const OrderFlowException(
          'No se pudo cargar tu perfil. Vuelve a iniciar sesión.',
        );
      }
      validatePickupTime(pickupTime, DateTime.now());
      transaction.set(orderRef, {
        'businessId': currentQuote.businessId,
        'userId': uid,
        'userDisplayName': user.data()?['displayName'] is String
            ? user.data()!['displayName']
            : 'Estudiante',
        'userNumeroDeControl': user.data()?['numeroDeControl'] is String
            ? user.data()!['numeroDeControl']
            : '',
        'status': 'pending',
        'totalPrice': currentQuote.totalPrice,
        'totalCents': currentQuote.totalCents,
        'paymentMethod': paymentMethod,
        'createdAt': FieldValue.serverTimestamp(),
        'scheduledPickupTime': pickupTime == null
            ? null
            : Timestamp.fromDate(pickupTime),
        'items': currentQuote.items,
        'pickupCode': pickupCode,
        'schemaVersion': 2,
      });
      for (final id in currentQuote.cartIds) {
        transaction.delete(cartRef.doc(id));
      }
    });
    return orderRef.id;
  }
}

String studentOrderError(Object error) {
  if (error is OrderFlowException) return error.message;
  if (error is FirebaseException && error.code == 'permission-denied') {
    return 'No tienes permiso para esta operación. Revisa tu sesión o avisa a administración.';
  }
  return 'No se pudo completar la operación. Revisa tu conexión e inténtalo de nuevo.';
}
