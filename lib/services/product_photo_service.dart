import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Stores small catalogue photos within the project's Firestore quota.
/// Binary photo data stays outside product queries and cart/order snapshots.
class ProductPhotoService {
  static const maxBytes = 150 * 1024;
  static const maxInputBytes = 10 * 1024 * 1024;
  static const maxInputPixels = 16 * 1000 * 1000;
  static const maxDimension = 640;

  final FirebaseFirestore _firestore;

  ProductPhotoService({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  static Future<Uint8List> prepare(Uint8List input) {
    if (input.isEmpty) {
      throw const FormatException('Selecciona una imagen válida.');
    }
    if (input.lengthInBytes > maxInputBytes) {
      throw const FormatException(
        'La imagen es demasiado grande. Elige otra foto.',
      );
    }
    return compute(_prepareProductPhoto, input);
  }

  Future<void> saveProduct({
    required String businessId,
    String? productId,
    required Map<String, dynamic> data,
    Uint8List? photoBytes,
    bool removePhoto = false,
  }) async {
    if (photoBytes != null &&
        (photoBytes.isEmpty || photoBytes.lengthInBytes > maxBytes)) {
      throw const FormatException(
        'No se pudo preparar la foto. Elige otra imagen.',
      );
    }
    final product = productId == null
        ? _firestore.collection('products').doc()
        : _firestore.collection('products').doc(productId);
    final photo = _firestore.collection('productImages').doc(product.id);
    final batch = _firestore.batch();
    final productData = <String, dynamic>{
      ...data,
      'businessId': businessId,
      if (productId == null) 'hasPhoto': false,
      if (photoBytes != null || removePhoto) ...{
        'hasPhoto': photoBytes != null,
        'imageUrl': null,
      },
    };
    if (productId == null) {
      batch.set(product, productData);
    } else {
      batch.update(product, productData);
    }
    if (photoBytes != null) {
      batch.set(photo, {
        'businessId': businessId,
        'imageBytes': Blob(photoBytes),
        'contentType': 'image/jpeg',
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } else if (removePhoto && productId != null) {
      batch.delete(photo);
    }
    // Product and photo succeed or fail together, including permission errors.
    await batch.commit();
  }

  Future<void> deleteProduct({required String productId}) async {
    final batch = _firestore.batch();
    batch.delete(_firestore.collection('productImages').doc(productId));
    batch.delete(_firestore.collection('products').doc(productId));
    await batch.commit();
  }
}

Uint8List _prepareProductPhoto(Uint8List input) {
  try {
    final decoder = img.findDecoderForData(input);
    final info = decoder?.startDecode(input);
    if (decoder == null || info == null || info.width < 1 || info.height < 1) {
      throw const FormatException(
        'No se pudo leer la imagen. Prueba con una foto JPG o PNG.',
      );
    }
    if (info.width * info.height > ProductPhotoService.maxInputPixels) {
      throw const FormatException(
        'La resolución es demasiado grande. Elige una versión más pequeña.',
      );
    }
    // Read only the first frame of animated formats.
    final frame = decoder.decodeFrame(0);
    if (frame == null) {
      throw const FormatException(
        'No se pudo leer la imagen. Elige otra foto.',
      );
    }
    final oriented = img.bakeOrientation(frame);
    final largest = oriented.width > oriented.height
        ? oriented.width
        : oriented.height;
    final resized = largest <= ProductPhotoService.maxDimension
        ? oriented
        : img.copyResize(
            oriented,
            width: oriented.width >= oriented.height
                ? ProductPhotoService.maxDimension
                : null,
            height: oriented.height > oriented.width
                ? ProductPhotoService.maxDimension
                : null,
            interpolation: img.Interpolation.average,
          );
    // A fresh canvas omits EXIF/GPS metadata and renders transparency on white.
    final clean = img.Image(width: resized.width, height: resized.height);
    img.fill(clean, color: img.ColorRgb8(255, 255, 255));
    img.compositeImage(clean, resized);
    for (final quality in [85, 70, 55, 40, 25, 15, 8]) {
      final result = img.encodeJpg(clean, quality: quality);
      if (result.lengthInBytes <= ProductPhotoService.maxBytes) return result;
    }
    throw const FormatException(
      'No se pudo reducir la foto. Elige otra imagen.',
    );
  } on FormatException {
    rethrow;
  } catch (_) {
    throw const FormatException(
      'No se pudo procesar la imagen. Prueba con una foto JPG o PNG.',
    );
  }
}
