import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Loads a product photo independently of the catalog documents.
class ProductPhoto extends StatefulWidget {
  final String productId;
  final bool hasPhoto;
  final String? legacyUrl;
  final BoxFit fit;
  final double? width;
  final double? height;

  /// Allows isolated rendering tests without connecting to Firebase.
  final Stream<Uint8List?>? photoStream;

  const ProductPhoto({
    super.key,
    required this.productId,
    this.hasPhoto = false,
    this.legacyUrl,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.photoStream,
  });

  @override
  State<ProductPhoto> createState() => _ProductPhotoState();
}

class _ProductPhotoState extends State<ProductPhoto> {
  static const _maxPhotoBytes = 150 * 1024;
  Stream<Uint8List?>? _photos;

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  @override
  void didUpdateWidget(covariant ProductPhoto oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.productId != widget.productId ||
        oldWidget.hasPhoto != widget.hasPhoto ||
        oldWidget.photoStream != widget.photoStream) {
      _subscribe();
    }
  }

  void _subscribe() {
    _photos = null;
    if (!widget.hasPhoto || widget.productId.isEmpty) return;
    _photos =
        widget.photoStream ??
        FirebaseFirestore.instance
            .collection('productImages')
            .doc(widget.productId)
            .snapshots()
            .map((snapshot) {
              final data = snapshot.data();
              final bytes = data?['imageBytes'];
              if (data?['contentType'] != 'image/jpeg' || bytes is! Blob) {
                return null;
              }
              return bytes.bytes;
            });
  }

  Widget _placeholder({bool loading = false}) {
    return Semantics(
      label: loading ? 'Cargando foto del producto' : 'Producto sin foto',
      child: ColoredBox(
        color: AppColors.componentBase,
        child: Center(
          child: loading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(
                  Icons.fastfood_rounded,
                  color: AppColors.textSecondary.withValues(alpha: 0.4),
                  size: 30,
                ),
        ),
      ),
    );
  }

  Widget _image(Uint8List bytes) {
    if (bytes.isEmpty || bytes.length > _maxPhotoBytes) return _placeholder();
    return Image.memory(
      bytes,
      fit: widget.fit,
      width: widget.width,
      height: widget.height,
      semanticLabel: 'Foto del producto',
      errorBuilder: (_, __, ___) => _placeholder(),
    );
  }

  Widget _legacyImage() {
    final url = widget.legacyUrl?.trim() ?? '';
    final uri = Uri.tryParse(url);
    if (url.isEmpty ||
        uri == null ||
        !['https', 'http'].contains(uri.scheme) ||
        uri.host.isEmpty) {
      return _placeholder();
    }
    return Image.network(
      url,
      fit: widget.fit,
      width: widget.width,
      height: widget.height,
      semanticLabel: 'Foto del producto',
      webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
      errorBuilder: (_, __, ___) => _placeholder(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final photos = _photos;
    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: photos == null
          ? _legacyImage()
          : StreamBuilder<Uint8List?>(
              key: ValueKey(widget.productId),
              stream: photos,
              builder: (context, snapshot) {
                if (snapshot.hasError) return _placeholder();
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return _placeholder(loading: true);
                }
                final bytes = snapshot.data;
                return bytes == null ? _placeholder() : _image(bytes);
              },
            ),
    );
  }
}
