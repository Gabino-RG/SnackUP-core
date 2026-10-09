import 'package:flutter_test/flutter_test.dart';
import 'package:snackup/features/user/order_checkout.dart';

void main() {
  Map<String, dynamic> product({
    String business = 'cafeteria',
    int stock = 20,
  }) => {
    'businessId': business,
    'name': 'Taco',
    'price': 12.50,
    'priceCents': 1250,
    'stock': stock,
    'isAvailable': true,
  };
  Map<String, dynamic> cartLine({String id = 'taco', int quantity = 2}) => {
    'productId': id,
    'quantity': quantity,
    'price': 0.01,
    'name': 'Nombre manipulado',
    'businessId': 'otro-local',
    'notes': '  Sin salsa  ',
  };
  CheckoutQuote quote({
    Map<String, Map<String, dynamic>>? cart,
    Map<String, Map<String, dynamic>>? products,
    bool open = true,
  }) => buildCheckoutQuote(
    cart: cart ?? {'taco': cartLine()},
    products: products ?? {'taco': product()},
    business: {'isOpen': open},
  );

  test('ignora precio, nombre y negocio alterados del carrito', () {
    final result = quote();
    expect(result.businessId, 'cafeteria');
    expect(result.totalCents, 2500);
    expect(result.totalPrice, 25.0);
    expect(result.items.single['name'], 'Taco');
    expect(result.items.single['price'], 12.5);
    expect(result.items.single['unitPriceCents'], 1250);
    expect(result.items.single['notes'], 'Sin salsa');
  });

  test('suma exactamente centavos para cantidades y precios fraccionarios', () {
    final result = quote(
      cart: {
        'uno': cartLine(id: 'uno', quantity: 3),
        'dos': cartLine(id: 'dos', quantity: 2),
      },
      products: {
        'uno': {...product(), 'priceCents': 10, 'price': 0.10},
        'dos': {...product(), 'priceCents': 20, 'price': 0.20},
      },
    );
    expect(result.totalCents, 70);
    expect(result.totalPrice, 0.7);
  });

  test(
    'un cambio de catálogo o cantidad invalida la confirmación anterior',
    () {
      final original = quote();
      final repriced = quote(
        products: {
          'taco': {...product(), 'priceCents': 1350, 'price': 13.50},
        },
      );
      final resized = quote(cart: {'taco': cartLine(quantity: 3)});
      expect(repriced.signature, isNot(original.signature));
      expect(resized.signature, isNot(original.signature));
      expect(quote().signature, original.signature);
    },
  );

  test('bloquea local cerrado, mezcla de locales y producto eliminado', () {
    expect(() => quote(open: false), throwsA(isA<OrderFlowException>()));
    expect(() => quote(products: {}), throwsA(isA<OrderFlowException>()));
    expect(
      () => quote(
        cart: {
          'uno': cartLine(id: 'uno'),
          'dos': cartLine(id: 'dos'),
        },
        products: {
          'uno': product(),
          'dos': product(business: 'otro'),
        },
      ),
      throwsA(isA<OrderFlowException>()),
    );
  });

  test('rechaza stock insuficiente, agotado o producto deshabilitado', () {
    expect(
      () => quote(products: {'taco': product(stock: 1)}),
      throwsA(isA<OrderFlowException>()),
    );
    expect(
      () => quote(products: {'taco': product(stock: 0)}),
      throwsA(isA<OrderFlowException>()),
    );
    expect(
      () => quote(
        products: {
          'taco': {...product(), 'isAvailable': false},
        },
      ),
      throwsA(isA<OrderFlowException>()),
    );
  });

  test('acepta exactamente 8 productos distintos y rechaza 9 y duplicados', () {
    Map<String, Map<String, dynamic>> cart(int count) => {
      for (var i = 0; i < count; i++) '$i': cartLine(id: '$i'),
    };
    final products = {for (var i = 0; i < 9; i++) '$i': product()};
    expect(quote(cart: cart(8), products: products).items, hasLength(8));
    expect(
      () => quote(cart: cart(9), products: products),
      throwsA(isA<OrderFlowException>()),
    );
    expect(
      () => quote(cart: {'one': cartLine(), 'two': cartLine()}),
      throwsA(isA<OrderFlowException>()),
    );
    expect(() => quote(cart: {}), throwsA(isA<OrderFlowException>()));
  });

  test('solo cantidades enteras 1 a 99 y notas hasta 500 caracteres', () {
    for (final value in [0, -1, 100, 2.5, '2', null]) {
      expect(() => validQuantity(value), throwsA(isA<OrderFlowException>()));
    }
    expect(validQuantity(99), 99);
    expect(validNotes(' a '), 'a');
    expect(validNotes('a' * 500), hasLength(500));
    expect(() => validNotes('a' * 501), throwsA(isA<OrderFlowException>()));
  });

  test(
    'catálogo legado redondea centavos y rechaza precios no finitos o excesivos',
    () {
      expect(
        () => productPriceCents({'price': 12.345}),
        throwsA(isA<OrderFlowException>()),
      );
      expect(productPriceCents({'price': 10000}), 1000000);
      expect(productPriceCents({'price': 1.25, 'priceCents': 125}), 125);
      for (final price in [
        0,
        -1,
        double.nan,
        double.infinity,
        10000.01,
        '12',
      ]) {
        expect(
          () => productPriceCents({'price': price}),
          throwsA(isA<OrderFlowException>()),
        );
      }
      expect(
        () => productPriceCents({'priceCents': 10, 'price': 0.1000001}),
        throwsA(isA<OrderFlowException>()),
      );
    },
  );

  test('horario futuro como máximo 24 horas, sin aceptar horas ya pasadas', () {
    final now = DateTime(2026, 10, 5, 12);
    expect(validatePickupTime(null, now), isNull);
    expect(
      validatePickupTime(now.add(const Duration(hours: 1)), now),
      isNotNull,
    );
    for (final time in [
      now,
      now.subtract(const Duration(minutes: 1)),
      now.add(const Duration(hours: 25)),
    ]) {
      expect(
        () => validatePickupTime(time, now),
        throwsA(isA<OrderFlowException>()),
      );
    }
  });

  test(
    'QR pertenece al pedido y nunca utiliza la matrícula como credencial',
    () {
      const data = {'pickupCode': 'abc', 'userNumeroDeControl': '20260001'};
      expect(pickupQrData('order-1', data), 'snackup:order-1:abc');
      expect(
        pickupQrData('order-2', data),
        isNot(pickupQrData('order-1', data)),
      );
      expect(
        pickupQrData('legacy', {'userNumeroDeControl': '20260001'}),
        'snackup:legacy',
      );
    },
  );
}
