import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:snackup/widgets/product_photo.dart';

Widget frame(ProductPhoto photo) => MaterialApp(
  home: Scaffold(body: SizedBox(width: 80, height: 80, child: photo)),
);

Uint8List jpeg() =>
    Uint8List.fromList(image.encodeJpg(image.Image(width: 2, height: 2)));

void main() {
  testWidgets('un producto sin foto no accede a Firebase', (tester) async {
    await tester.pumpWidget(frame(const ProductPhoto(productId: 'product')));
    expect(find.byIcon(Icons.fastfood_rounded), findsOneWidget);
    expect(find.byType(Image), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('muestra los bytes de la foto del producto', (tester) async {
    final bytes = jpeg();
    await tester.pumpWidget(
      frame(
        ProductPhoto(
          productId: 'product',
          hasPhoto: true,
          photoStream: Stream.value(bytes),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final rendered = tester.widget<Image>(find.byType(Image));
    expect(rendered.image, isA<MemoryImage>());
    expect((rendered.image as MemoryImage).bytes, bytes);
    expect(tester.takeException(), isNull);
  });

  testWidgets('la eliminación de la foto retira la imagen anterior', (
    tester,
  ) async {
    final stream = StreamController<Uint8List?>();
    await tester.pumpWidget(
      frame(
        ProductPhoto(
          productId: 'product',
          hasPhoto: true,
          photoStream: stream.stream,
        ),
      ),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    stream.add(jpeg());
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsOneWidget);
    stream.add(null);
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsNothing);
    expect(find.byIcon(Icons.fastfood_rounded), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(stream.close);
  });

  testWidgets('un fallo de lectura muestra el estado sin foto', (tester) async {
    await tester.pumpWidget(
      frame(
        ProductPhoto(
          productId: 'product',
          hasPhoto: true,
          photoStream: Stream<Uint8List?>.error(StateError('sin permisos')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.fastfood_rounded), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('rechaza datos vacíos o mayores del límite', (tester) async {
    for (final bytes in [Uint8List(0), Uint8List(150 * 1024 + 1)]) {
      await tester.pumpWidget(
        frame(
          ProductPhoto(
            productId: 'product-${bytes.length}',
            hasPhoto: true,
            photoStream: Stream.value(bytes),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(Image), findsNothing);
      expect(find.byIcon(Icons.fastfood_rounded), findsOneWidget);
    }
  });

  testWidgets('cambiar de producto no conserva su foto anterior', (
    tester,
  ) async {
    final second = StreamController<Uint8List?>();
    await tester.pumpWidget(
      frame(
        ProductPhoto(
          productId: 'first',
          hasPhoto: true,
          photoStream: Stream.value(jpeg()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsOneWidget);
    await tester.pumpWidget(
      frame(
        ProductPhoto(
          productId: 'second',
          hasPhoto: true,
          photoStream: second.stream,
        ),
      ),
    );
    expect(find.byType(Image), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(second.close);
  });

  testWidgets('una ruta local antigua usa el estado sin foto', (tester) async {
    await tester.pumpWidget(
      frame(
        const ProductPhoto(
          productId: 'product',
          legacyUrl: 'file:///foto-del-otro-telefono.jpg',
        ),
      ),
    );
    expect(find.byIcon(Icons.fastfood_rounded), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('bytes que no son una imagen no rompen la pantalla', (
    tester,
  ) async {
    await tester.pumpWidget(
      frame(
        ProductPhoto(
          productId: 'corrupt',
          hasPhoto: true,
          photoStream: Stream.value(Uint8List.fromList([1, 2, 3, 4])),
        ),
      ),
    );
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.fastfood_rounded), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
