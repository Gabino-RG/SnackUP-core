import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:snackup/services/product_photo_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'convierte PNG a JPEG y conserva una foto pequeña sin agrandarla',
    () async {
      final source = img.Image(width: 120, height: 80);
      img.fill(source, color: img.ColorRgb8(220, 80, 20));
      final result = await ProductPhotoService.prepare(img.encodePng(source));
      expect(result.take(2), [0xff, 0xd8]);
      final decoded = img.decodeJpg(result)!;
      expect(decoded.width, 120);
      expect(decoded.height, 80);
      expect(
        result.lengthInBytes,
        lessThanOrEqualTo(ProductPhotoService.maxBytes),
      );
    },
  );

  test(
    'reduce una foto grande conservando proporción y límite de bytes',
    () async {
      final source = img.Image(width: 1600, height: 800);
      img.fill(source, color: img.ColorRgb8(30, 180, 80));
      final result = await ProductPhotoService.prepare(img.encodeJpg(source));
      final decoded = img.decodeJpg(result)!;
      expect(decoded.width, 640);
      expect(decoded.height, 320);
      expect(
        result.lengthInBytes,
        lessThanOrEqualTo(ProductPhotoService.maxBytes),
      );
    },
  );

  test(
    'comprime una foto con mucho detalle dentro del límite de Firestore',
    () async {
      final random = Random(17);
      final source = img.Image(width: 640, height: 640);
      for (final pixel in source) {
        pixel.setRgb(
          random.nextInt(256),
          random.nextInt(256),
          random.nextInt(256),
        );
      }
      final result = await ProductPhotoService.prepare(img.encodePng(source));
      expect(img.decodeJpg(result), isNotNull);
      expect(
        result.lengthInBytes,
        lessThanOrEqualTo(ProductPhotoService.maxBytes),
      );
    },
  );

  test('aplana transparencia sobre blanco', () async {
    final source = img.Image(width: 20, height: 20, numChannels: 4);
    final result = await ProductPhotoService.prepare(img.encodePng(source));
    final pixel = img.decodeJpg(result)!.getPixel(10, 10);
    expect(pixel.r, greaterThan(245));
    expect(pixel.g, greaterThan(245));
    expect(pixel.b, greaterThan(245));
  });

  test('elimina los metadatos EXIF de la foto publicada', () async {
    final source = img.Image(width: 40, height: 20);
    source.exif.imageIfd.make = 'Private Camera';
    final input = img.encodeJpg(source);
    expect(img.decodeJpg(input)!.exif.imageIfd.make, 'Private Camera');
    final result = await ProductPhotoService.prepare(input);
    expect(img.decodeJpg(result)!.exif.imageIfd.make, isNot('Private Camera'));
  });

  test(
    'rechaza contenido vacío, inválido y archivos de entrada excesivos',
    () async {
      expect(
        () => ProductPhotoService.prepare(Uint8List(0)),
        throwsFormatException,
      );
      await expectLater(
        ProductPhotoService.prepare(Uint8List.fromList([1, 2, 3, 4])),
        throwsFormatException,
      );
      expect(
        () => ProductPhotoService.prepare(
          Uint8List(ProductPhotoService.maxInputBytes + 1),
        ),
        throwsFormatException,
      );
    },
  );
}
