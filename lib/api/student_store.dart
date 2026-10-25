import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'api_client.dart';
import 'student_repository.dart';

String purchaseKey() {
  final random = Random.secure();
  final bytes = List.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  final h = bytes.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
}

class StudentStore extends ChangeNotifier {
  final ApiClient api;
  final StudentRepository repo;
  final bool realtimeEnabled;
  SharedPreferences? _prefs;
  String? _uid;
  io.Socket? _socket;
  String? _socketToken;
  Timer? _eventDebounce;
  final Set<String> _seenEvents = {};
  Future<void>? _refreshing;
  bool _refreshQueued = false;
  bool _disposed = false;
  bool busy = false;
  bool connected = false;
  String? error;
  List<Json> businesses = [], products = [], orders = [], cart = [];
  Set<String> favorites = {};
  Map<String, String> favoriteNotes = {};
  Json? pendingPurchase;
  Future<Json>? _checkoutFuture;
  String get localPrefix =>
      'snackup.api.${Uri.encodeComponent(api.base.toString())}.${_uid ?? ''}';
  Json? get user => api.user;
  List<Json> get availableProducts =>
      products.where(apiProductAvailable).toList();
  int get cartCount =>
      cart.fold(0, (sum, row) => sum + (row['quantity'] as int));
  int get totalCents => cart.fold(
    0,
    (sum, row) =>
        sum +
        (((row['product'] as Map)['price'] as num).toDouble() * 100).round() *
            (row['quantity'] as int),
  );
  double get total => totalCents / 100;
  StudentStore(
    this.api, {
    SharedPreferences? preferences,
    this.realtimeEnabled = true,
  }) : repo = StudentRepository(api),
       _prefs = preferences {
    api.addListener(_sessionChanged);
  }
  factory StudentStore.live() =>
      StudentStore(ApiClient(base: ApiClient.configuredBase()));
  void changed() {
    if (!_disposed) notifyListeners();
  }

  String businessName(String id) =>
      businesses.where((b) => b['id'] == id).firstOrNull?['name'] as String? ??
      'Cafetería';
  Json? findProduct(String id) =>
      products.where((p) => p['id'] == id).firstOrNull;

  Future<void> boot() async {
    busy = true;
    changed();
    try {
      await api.restore();
      if (user != null) await activate();
    } catch (e) {
      error = e.toString();
    } finally {
      busy = false;
      changed();
    }
  }

  Future<void> login(String email, String password) async {
    await api.login(email, password);
    await activate();
  }

  Future<void> activate() async {
    final id = user!['id'] as String;
    _uid = id;
    _prefs ??= await SharedPreferences.getInstance();
    try {
      cart =
          (jsonDecode(_prefs!.getString('$localPrefix.cart') ?? '[]') as List)
              .map((x) => Map<String, dynamic>.from(x as Map))
              .toList();
      favorites =
          _prefs!.getStringList('$localPrefix.favorites')?.toSet() ?? {};
      favoriteNotes = Map<String, String>.from(
        jsonDecode(_prefs!.getString('$localPrefix.favoriteNotes') ?? '{}')
            as Map,
      );
      final raw = _prefs!.getString('$localPrefix.pending');
      pendingPurchase = raw == null
          ? null
          : Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } on FormatException {
      cart = [];
      pendingPurchase = null;
    }
    try {
      await refresh();
    } catch (e) {
      error = e.toString();
      rethrow;
    } finally {
      if (user != null && _uid == id) _connect();
      changed();
    }
  }

  Future<void> refresh() {
    if (_refreshing != null) {
      _refreshQueued = true;
      return _refreshing!;
    }
    return _refreshing = _refresh().whenComplete(() {
      _refreshing = null;
      if (_refreshQueued) {
        _refreshQueued = false;
        _invalidate();
      }
    });
  }

  Future<void> _refresh() async {
    final id = _uid;
    if (id == null || user == null) return;
    final shops = await repo.businesses();
    final catalog = <Json>[];
    for (final shop in shops) {
      catalog.addAll(await repo.products(shop['id'] as String));
    }
    final history = await repo.history();
    final active = await repo.activeOrders();
    if (_uid != id || user == null) return;
    final previous = {for (final order in orders) order['id']: order};
    final byId = <String, Json>{};
    for (final order in [...history, ...active]) {
      final id = order['id'] as String;
      final old = byId[id] ?? previous[id];
      byId[id] =
          old != null &&
              (old['version'] as num? ?? 0) > (order['version'] as num? ?? 0)
          ? old
          : {...?old, ...order};
    }
    businesses = shops;
    products = catalog;
    orders = byId.values.toList();
    orders.sort(
      (a, b) => (b['createdAt']?.toString() ?? '').compareTo(
        a['createdAt']?.toString() ?? '',
      ),
    );
    error = null;
    _subscribe();
    changed();
  }

  Future<Json> refreshOrder(String id) async {
    final owner = _uid;
    final row = await repo.order(id);
    if (_uid != owner || user == null)
      throw const ApiException('SESSION_CHANGED', 'La sesión cambió.');
    final index = orders.indexWhere((o) => o['id'] == id);
    if (index < 0) {
      orders.insert(0, row);
    } else {
      final current = orders[index];
      if ((current['version'] as num? ?? 0) > (row['version'] as num? ?? 0))
        return current;
      orders[index] = {
        ...current,
        ...row,
        if (current['isRated'] == true) 'isRated': true,
      };
    }
    changed();
    return orders.firstWhere((order) => order['id'] == id);
  }

  Future<void> persistCart() async {
    if (_prefs == null || _uid == null) return;
    if (!await _prefs!.setString('$localPrefix.cart', jsonEncode(cart))) {
      throw const ApiException(
        'LOCAL_STORAGE',
        'No se pudo guardar el carrito en este dispositivo.',
      );
    }
    changed();
  }

  void _editable() {
    if (pendingPurchase != null)
      throw const ApiException(
        'PURCHASE_PENDING',
        'Hay un pedido pendiente de respuesta. Reinténtalo antes de modificar el carrito.',
      );
  }

  Future<void> add(Json product, int quantity, String notes) async {
    _editable();
    final current = await repo.product(product['id'] as String);
    if (!apiProductAvailable(current))
      throw const ApiException(
        'PRODUCT_UNAVAILABLE',
        'Este producto ya no está disponible.',
      );
    if (cart.isNotEmpty &&
        (cart.first['product'] as Map)['businessId'] != current['businessId']) {
      throw const ApiException(
        'ONE_BUSINESS',
        'Termina o vacía el carrito antes de elegir otra cafetería.',
      );
    }
    final index = cart.indexWhere(
      (row) => (row['product'] as Map)['id'] == current['id'],
    );
    final count = quantity + (index < 0 ? 0 : cart[index]['quantity'] as int);
    if (count < 1 ||
        count > 99 ||
        (current['stock'] is num && count > (current['stock'] as num))) {
      throw const ApiException(
        'INSUFFICIENT_STOCK',
        'La cantidad supera las existencias disponibles.',
      );
    }
    final line = {'product': current, 'quantity': count, 'notes': notes};
    if (index < 0) {
      cart.add(line);
    } else {
      cart[index] = line;
    }
    await persistCart();
  }

  Future<void> quantity(int index, int value) async {
    _editable();
    if (value <= 0) {
      cart.removeAt(index);
    } else {
      final product = await repo.product(
        (cart[index]['product'] as Map)['id'] as String,
      );
      if (!apiProductAvailable(product) ||
          value > 99 ||
          (product['stock'] is num && value > (product['stock'] as num))) {
        throw const ApiException(
          'INSUFFICIENT_STOCK',
          'La cantidad ya no está disponible.',
        );
      }
      cart[index] = {...cart[index], 'product': product, 'quantity': value};
    }
    await persistCart();
  }

  Future<void> editNotes(int index, String notes) async {
    _editable();
    if (notes.length > 500)
      throw const ApiException(
        'INVALID_NOTES',
        'Escribe hasta 500 caracteres.',
      );
    cart[index] = {...cart[index], 'notes': notes};
    await persistCart();
  }

  Future<void> updateCartPrices() async {
    _editable();
    final updated = <Json>[];
    for (final row in cart) {
      final product = await repo.product(
        (row['product'] as Map)['id'] as String,
      );
      if (!apiProductAvailable(product) ||
          (product['stock'] is num &&
              (row['quantity'] as int) > (product['stock'] as num))) {
        throw const ApiException(
          'PRODUCT_UNAVAILABLE',
          'Un producto ya no tiene la cantidad solicitada. Retíralo o reduce la cantidad.',
        );
      }
      updated.add({...row, 'product': product});
    }
    cart = updated;
    await persistCart();
  }

  Future<void> clearCart() async {
    _editable();
    cart.clear();
    await persistCart();
  }

  Future<void> favorite(String id, {String notes = ''}) async {
    if (!favorites.add(id)) {
      favorites.remove(id);
      favoriteNotes.remove(id);
    } else {
      favoriteNotes[id] = notes;
    }
    await _prefs!.setString(
      '$localPrefix.favoriteNotes',
      jsonEncode(favoriteNotes),
    );
    await _prefs!.setStringList('$localPrefix.favorites', favorites.toList());
    changed();
  }

  Future<void> reorder(Json order) async {
    _editable();
    final candidates = <Json>[];
    for (final line in (order['items'] as List).cast<Map>()) {
      final product = await repo.product(line['productId'] as String);
      final count = line['quantity'] as int;
      if (!apiProductAvailable(product) ||
          (product['stock'] is num && count > (product['stock'] as num))) {
        throw const ApiException(
          'PRODUCT_UNAVAILABLE',
          'Un producto de ese pedido ya no tiene existencias. Tu carrito se conserva.',
        );
      }
      candidates.add({
        'product': product,
        'quantity': count,
        'notes': line['notes'] ?? '',
      });
    }
    // The UI asks before replacing an existing basket. No partial changes on error.
    cart = candidates;
    await persistCart();
  }

  Future<Json> checkout(String method) => _checkoutFuture ??= _checkout(
    method,
  ).whenComplete(() => _checkoutFuture = null);
  Future<Json> _checkout(String method) async {
    if (!['Efectivo', 'Transferencia'].contains(method))
      throw const ApiException(
        'INVALID_PAYMENT',
        'Método no admitido por la API.',
      );
    if (pendingPurchase == null) {
      if (cart.isEmpty)
        throw const ApiException(
          'EMPTY_CART',
          'Agrega un platillo a tu carrito.',
        );
      final body = {
        'businessId': (cart.first['product'] as Map)['businessId'],
        'items': cart
            .map(
              (row) => {
                'productId': (row['product'] as Map)['id'],
                'quantity': row['quantity'],
                'notes': row['notes'] ?? '',
              },
            )
            .toList(),
        'paymentMethod': method,
        'expectedTotal': total,
      };
      pendingPurchase = {'key': purchaseKey(), 'body': body};
      if (!await _prefs!.setString(
        '$localPrefix.pending',
        jsonEncode(pendingPurchase),
      )) {
        pendingPurchase = null;
        throw const ApiException(
          'LOCAL_STORAGE',
          'No se pudo preparar un reintento seguro. No se envió el pedido.',
        );
      }
    }
    final pending = pendingPurchase!;
    Json result;
    try {
      result = await repo.createOrder(
        Map<String, dynamic>.from(pending['body'] as Map),
        pending['key'] as String,
      );
    } on ApiException catch (e) {
      // Definitive validation rejections did not create a purchase; transport/5xx
      // failures and idempotency conflicts keep the original intention and key.
      if ((e.status == 409 && e.code != 'IDEMPOTENCY_CONFLICT') ||
          e.status == 422) {
        await _prefs!.remove('$localPrefix.pending');
        pendingPurchase = null;
        changed();
      }
      rethrow;
    }
    // Remove the basket before the retry journal. A crash never permits the
    // original cart to be submitted with a fresh idempotency key.
    cart.clear();
    await persistCart();
    await _prefs!.remove('$localPrefix.pending');
    pendingPurchase = null;
    final index = orders.indexWhere((o) => o['id'] == result['id']);
    if (index >= 0) {
      orders[index] = result;
    } else {
      orders.insert(0, result);
    }
    changed();
    try {
      return await refreshOrder(result['id'] as String);
    } on ApiException {
      return result;
    }
  }

  Future<void> logout() => api.logout();
  void _sessionChanged() {
    if (user == null && _uid != null) {
      _uid = null;
      businesses = [];
      products = [];
      orders = [];
      cart = [];
      favorites = {};
      favoriteNotes = {};
      pendingPurchase = null;
      _socket?.dispose();
      _socket = null;
      _socketToken = null;
      connected = false;
      changed();
    } else if (user != null &&
        _uid != null &&
        api.accessToken != _socketToken) {
      _connect();
    }
  }

  void _connect() {
    if (!realtimeEnabled ||
        user == null ||
        _uid == null ||
        api.accessToken == null)
      return;
    _socket?.dispose();
    _socketToken = api.accessToken;
    _socket = io.io(
      api.base.origin,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .setPath('/socket.io')
          .disableAutoConnect()
          .enableForceNew()
          .setAuth({'token': api.accessToken})
          .build(),
    );
    _socket!.onConnect((_) {
      connected = true;
      _subscribe();
      _invalidate();
      changed();
    });
    _socket!.onDisconnect((_) {
      connected = false;
      changed();
    });
    _socket!.onConnectError((_) {
      connected = false;
      changed();
    });
    for (final type in [
      'order.created',
      'order.updated',
      'product.updated',
      'business.updated',
    ]) {
      _socket!.on(type, (event) {
        if (event is! Map ||
            event['id'] is! String ||
            !_seenEvents.add(event['id'] as String))
          return;
        if (_seenEvents.length > 500) _seenEvents.remove(_seenEvents.first);
        _invalidate();
      });
    }
    _socket!.connect();
  }

  void _subscribe() {
    if (_socket?.connected != true || _uid == null) return;
    final topics = [
      'user:$_uid:orders',
      ...businesses.expand(
        (b) => ['business:${b['id']}', 'business:${b['id']}:products'],
      ),
    ];
    for (var index = 0; index < topics.length; index += 64) {
      _socket!.emitWithAck(
        'subscribe',
        {'topics': topics.skip(index).take(64).toList()},
        ack: (reply) {
          if (reply is! Map || reply['ok'] != true) {
            connected = false;
            changed();
          }
        },
      );
    }
  }

  void _invalidate() {
    _eventDebounce?.cancel();
    _eventDebounce = Timer(const Duration(milliseconds: 200), () async {
      try {
        await refresh();
      } catch (e) {
        error = e.toString();
        changed();
      }
    });
  }

  @override
  void dispose() {
    _disposed = true;
    api.removeListener(_sessionChanged);
    _socket?.dispose();
    _eventDebounce?.cancel();
    api.dispose();
    super.dispose();
  }
}
