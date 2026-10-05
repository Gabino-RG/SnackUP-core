import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:snackup/theme/app_colors.dart';
import 'package:snackup/theme/app_text.dart';

class AddEditProductScreen extends StatefulWidget {
  final String businessId;
  final String? productId;

  const AddEditProductScreen({
    super.key,
    required this.businessId,
    this.productId,
  });

  @override
  State<AddEditProductScreen> createState() => _AddEditProductScreenState();
}

class _AddEditProductScreenState extends State<AddEditProductScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _priceController = TextEditingController();
  final _stockController = TextEditingController();
  final _categoryController = TextEditingController();

  Uint8List? _imageBytes;
  String _imageExtension = 'jpg';
  String _imageContentType = 'image/jpeg';
  String? _existingImageUrl;
  bool _isFeatured = false;
  bool _isAvailable = true;
  bool _isLoading = false;
  bool _isEditing = false;
  bool _loadFailed = false;
  int? _loadedStock;
  double _uploadProgress = 0;

  @override
  void initState() {
    super.initState();
    _isEditing = widget.productId != null;
    if (_isEditing) {
      _loadProductData();
    }
  }

  Future<void> _loadProductData() async {
    setState(() {
      _isLoading = true;
      _loadFailed = false;
    });
    try {
      final doc = await FirebaseFirestore.instance
          .collection('products')
          .doc(widget.productId)
          .get();

      if (!mounted) return;
      if (doc.exists && doc.data()?['businessId'] == widget.businessId) {
        final data = doc.data()!;
        _nameController.text = data['name'] ?? '';
        _descriptionController.text = data['description'] ?? '';
        _priceController.text = data['priceCents'] is int
            ? ((data['priceCents'] as int) / 100).toStringAsFixed(2)
            : (data['price'] ?? 0.0).toString();
        _stockController.text = (data['stock'] ?? 0).toString();
        _loadedStock = (data['stock'] as num?)?.toInt() ?? 0;
        _categoryController.text = data['category'] ?? '';
        setState(() {
          _isFeatured = data['isFeatured'] ?? false;
          _isAvailable = data['isAvailable'] ?? true;
          _existingImageUrl = data['imageUrl'];
        });
      } else {
        _loadFailed = true;
        _showError('El producto no existe o no pertenece a este negocio.');
      }
    } catch (e) {
      _loadFailed = true;
      _showError('Error al cargar producto: ${e.toString()}');
    }
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _pickImage() async {
    if (_isLoading) return;
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? pickedFile = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 70,
        maxWidth: 800,
      );

      if (pickedFile != null) {
        final extension = pickedFile.name.split('.').last.toLowerCase();
        const contentTypes = {
          'jpg': 'image/jpeg',
          'jpeg': 'image/jpeg',
          'png': 'image/png',
          'webp': 'image/webp',
        };
        if (!contentTypes.containsKey(extension)) {
          _showError('Selecciona una imagen JPG, PNG o WebP.');
          return;
        }
        if (await pickedFile.length() > 5 * 1024 * 1024) {
          _showError('La imagen debe pesar como máximo 5 MB.');
          return;
        }
        final bytes = await pickedFile.readAsBytes();
        if (!mounted) return;
        setState(() {
          _imageBytes = bytes;
          _imageExtension = extension;
          _imageContentType = contentTypes[extension]!;
        });
      }
    } catch (_) {
      _showError('No se pudo abrir la imagen. Revisa los permisos de galería.');
    }
  }

  Future<String?> _uploadImage() async {
    if (_imageBytes == null) return null;
    StreamSubscription<TaskSnapshot>? progressSubscription;
    try {
      String fileName =
          '${DateTime.now().microsecondsSinceEpoch}.$_imageExtension';
      Reference storageRef = FirebaseStorage.instance
          .ref()
          .child('product_images')
          .child(widget.businessId)
          .child(fileName);

      UploadTask uploadTask = storageRef.putData(
        _imageBytes!,
        SettableMetadata(contentType: _imageContentType),
      );

      progressSubscription = uploadTask.snapshotEvents.listen((
        TaskSnapshot snapshot,
      ) {
        if (!mounted || snapshot.totalBytes == 0) return;
        setState(() {
          _uploadProgress = (snapshot.bytesTransferred / snapshot.totalBytes);
        });
      }, onError: (Object _) {});

      TaskSnapshot taskSnapshot = await uploadTask;
      String downloadUrl = await taskSnapshot.ref.getDownloadURL();

      return downloadUrl;
    } catch (e) {
      _showError('Error al subir imagen: $e');
      return null;
    } finally {
      await progressSubscription?.cancel();
      if (mounted) setState(() => _uploadProgress = 0);
    }
  }

  Future<void> _saveProduct() async {
    if (_isLoading || _loadFailed || !_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      await _verifyOwner();
      String? imageUrl;

      if (_imageBytes != null) {
        imageUrl = await _uploadImage();
        if (imageUrl == null) return;
      } else {
        imageUrl = _existingImageUrl;
      }

      final price = double.parse(
        _priceController.text.trim().replaceAll(',', '.'),
      );
      final priceCents = (price * 100).round();
      final stock = int.tryParse(_stockController.text) ?? 0;

      final productData = {
        'businessId': widget.businessId,
        'name': _nameController.text.trim(),
        'description': _descriptionController.text.trim(),
        'price': priceCents / 100,
        'priceCents': priceCents,
        'stock': stock,
        'isAvailable': _isAvailable,
        'isFeatured': _isFeatured,
        'category': _categoryController.text.trim().toUpperCase(),
        'imageUrl': imageUrl,
        'updatedAt': FieldValue.serverTimestamp(),
        'name_searchable': _nameController.text.trim().toLowerCase(),
      };

      final firestore = FirebaseFirestore.instance;
      final reference = firestore.collection('products').doc(widget.productId);
      await firestore.runTransaction((transaction) async {
        if (_isEditing) {
          final current = await transaction.get(reference);
          if (!current.exists ||
              current.data()?['businessId'] != widget.businessId) {
            throw StateError('El producto ya no está disponible para editar.');
          }
          final updates = Map<String, dynamic>.from(productData);
          if (stock == _loadedStock) {
            updates.remove('stock');
          } else if (current.data()?['stock'] != _loadedStock) {
            throw StateError(
              'El stock cambió mientras editabas. Abre el producto de nuevo antes de ajustarlo.',
            );
          }
          transaction.update(reference, updates);
        } else {
          transaction.set(reference, {
            ...productData,
            'createdAt': FieldValue.serverTimestamp(),
          });
        }
      });

      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      _showError('Error al guardar: ${e.toString()}');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _verifyOwner() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final business = await FirebaseFirestore.instance
        .collection('businesses')
        .doc(widget.businessId)
        .get();
    if (uid == null || business.data()?['ownerId'] != uid) {
      throw StateError('Tu cuenta no administra este negocio.');
    }
  }

  Future<void> _deleteProduct() async {
    if (_isLoading || _loadFailed) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar producto'),
        content: const Text(
          'Se quitará del menú. Los pedidos que ya lo incluyen conservarán su información.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _isLoading = true);
    try {
      await _verifyOwner();
      final firestore = FirebaseFirestore.instance;
      final reference = firestore.collection('products').doc(widget.productId);
      await firestore.runTransaction((transaction) async {
        final product = await transaction.get(reference);
        if (!product.exists ||
            product.data()?['businessId'] != widget.businessId) {
          throw StateError('El producto no pertenece a este negocio.');
        }
        transaction.delete(reference);
      });
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      _showError(
        'No se pudo eliminar el producto. Revisa tu conexión y permisos.',
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _isEditing ? 'Editar Producto' : 'Nuevo Producto',
          style: AppText.h3.copyWith(
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
        backgroundColor: AppColors.background,
        elevation: 0,
        foregroundColor: AppColors.textPrimary,
        actions: _isEditing ? [_buildDeleteButton()] : null,
      ),
      body: _loadFailed
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'No se pudo cargar el producto. Verifica tu conexión y permisos.',
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _loadProductData,
                      child: const Text('Reintentar'),
                    ),
                  ],
                ),
              ),
            )
          : _isLoading && _uploadProgress == 0
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20.0),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // HEADER INFORMATIVO
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.tertiary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: AppColors.tertiary.withOpacity(0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.info_outline_rounded,
                            color: AppColors.tertiary,
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _isEditing
                                  ? 'Actualiza la información de tu producto'
                                  : 'Agrega un nuevo producto a tu menú',
                              style: AppText.notes.copyWith(
                                color: AppColors.tertiary,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    // SELECTOR DE IMAGEN MEJORADO
                    _buildImagePicker(),

                    const SizedBox(height: 16),

                    // BARRA DE PROGRESO DE SUBIDA
                    if (_isLoading && _uploadProgress > 0) ...[
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Subiendo imagen... ${(_uploadProgress * 100).toStringAsFixed(0)}%',
                            style: AppText.notes.copyWith(
                              color: AppColors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 8),
                          LinearProgressIndicator(
                            value: _uploadProgress,
                            minHeight: 6,
                            borderRadius: BorderRadius.circular(3),
                            color: AppColors.primary,
                            backgroundColor: AppColors.componentBase,
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                    ],

                    // FORMULARIO MEJORADO
                    _buildFormFields(),

                    const SizedBox(height: 24),

                    // BOTÓN DE GUARDAR MEJORADO
                    _buildSaveButton(),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildImagePicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Imagen del Producto',
          style: AppText.body.copyWith(
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: _pickImage,
          child: Container(
            height: 180,
            width: double.infinity,
            decoration: BoxDecoration(
              color: AppColors.componentBase,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.borders, width: 2),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // CONTENIDO DE LA IMAGEN
                  _buildImageContent(),

                  // OVERLAY PARA SELECCIONAR
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.9),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          _imageBytes != null || _existingImageUrl != null
                              ? Icons.camera_alt_rounded
                              : Icons.add_photo_alternate_rounded,
                          color: AppColors.primary,
                          size: 30,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Toca para seleccionar una imagen',
          style: AppText.notes.copyWith(color: AppColors.textSecondary),
        ),
      ],
    );
  }

  Widget _buildImageContent() {
    if (_imageBytes != null) {
      return Image.memory(_imageBytes!, fit: BoxFit.cover);
    } else if (_existingImageUrl != null) {
      return Image.network(
        _existingImageUrl!,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => _buildPlaceholder(),
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return Center(
            child: CircularProgressIndicator(
              value: loadingProgress.expectedTotalBytes != null
                  ? loadingProgress.cumulativeBytesLoaded /
                        loadingProgress.expectedTotalBytes!
                  : null,
              color: AppColors.primary,
            ),
          );
        },
      );
    } else {
      return _buildPlaceholder();
    }
  }

  Widget _buildPlaceholder() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.fastfood_rounded,
          size: 60,
          color: AppColors.textSecondary.withOpacity(0.5),
        ),
        const SizedBox(height: 8),
        Text(
          'Agregar imagen',
          style: AppText.notes.copyWith(color: AppColors.textSecondary),
        ),
      ],
    );
  }

  Widget _buildFormFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // NOMBRE
        _buildTextField(
          controller: _nameController,
          label: 'Nombre del Producto',
          maxLength: 160,
          hintText: 'Ej: Taco al Pastor',
          validator: (value) => value == null || value.trim().isEmpty
              ? 'El nombre es obligatorio'
              : null,
        ),

        const SizedBox(height: 16),

        // CATEGORÍA
        _buildTextField(
          controller: _categoryController,
          label: 'Categoría',
          maxLength: 120,
          hintText: 'Ej: TACOS, BEBIDAS, POSTRES',
          validator: (value) => value == null || value.trim().isEmpty
              ? 'La categoría es obligatoria'
              : null,
        ),

        const SizedBox(height: 16),

        // DESCRIPCIÓN
        _buildTextField(
          controller: _descriptionController,
          label: 'Descripción',
          maxLength: 2000,
          hintText: 'Describe tu producto...',
          maxLines: 3,
        ),

        const SizedBox(height: 16),

        // PRECIO Y STOCK EN FILA
        Row(
          children: [
            Expanded(
              child: _buildTextField(
                controller: _priceController,
                label: 'Precio (\$)',
                hintText: '0.00',
                keyboardType: TextInputType.numberWithOptions(decimal: true),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'El precio es obligatorio';
                  }
                  final price = double.tryParse(
                    value.trim().replaceAll(',', '.'),
                  );
                  if (price == null ||
                      !price.isFinite ||
                      price <= 0 ||
                      price > 10000 ||
                      (price * 100).round() < 1) {
                    return 'Precio entre \$0.01 y \$10,000';
                  }
                  return null;
                },
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildTextField(
                controller: _stockController,
                label: 'Stock',
                hintText: '0',
                keyboardType: TextInputType.number,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'El stock es obligatorio';
                  }
                  final stock = int.tryParse(value);
                  if (stock == null || stock < 0 || stock > 1000000) {
                    return 'Stock entre 0 y 1,000,000';
                  }
                  return null;
                },
              ),
            ),
          ],
        ),

        const SizedBox(height: 24),

        // SWITCHES MEJORADOS
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.componentBase,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: [
              _buildSwitch(
                value: _isAvailable,
                onChanged: (value) => setState(() => _isAvailable = value),
                title: 'Disponible para pedir',
                subtitle: 'Los clientes pueden ordenar este producto',
              ),
              const SizedBox(height: 16),
              _buildSwitch(
                value: _isFeatured,
                onChanged: (value) => setState(() => _isFeatured = value),
                title: 'Promocionar en Inicio',
                subtitle: 'Destacar este producto en la página principal',
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    String? hintText,
    int maxLines = 1,
    int? maxLength,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppText.body.copyWith(
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          style: AppText.body,
          decoration: InputDecoration(
            hintText: hintText,
            hintStyle: AppText.notes.copyWith(
              color: AppColors.textSecondary.withOpacity(0.6),
            ),
            filled: true,
            fillColor: AppColors.componentBase,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 14,
            ),
          ),
          maxLines: maxLines,
          maxLength: maxLength,
          keyboardType: keyboardType,
          validator: validator,
        ),
      ],
    );
  }

  Widget _buildSwitch({
    required bool value,
    required Function(bool) onChanged,
    required String title,
    required String subtitle,
  }) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: AppText.body.copyWith(
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: AppText.notes.copyWith(color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
        Switch.adaptive(
          value: value,
          onChanged: onChanged,
          activeColor: AppColors.primary,
        ),
      ],
    );
  }

  Widget _buildSaveButton() {
    return ElevatedButton(
      onPressed: _isLoading || _loadFailed ? null : _saveProduct,
      style: ElevatedButton.styleFrom(
        backgroundColor: _isEditing ? AppColors.accent : AppColors.primary,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        elevation: 2,
        shadowColor: (_isEditing ? AppColors.accent : AppColors.primary)
            .withOpacity(0.3),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (_isLoading)
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          else
            Icon(_isEditing ? Icons.save_rounded : Icons.add_rounded, size: 20),
          const SizedBox(width: 8),
          Text(
            _isLoading
                ? 'Guardando...'
                : (_isEditing ? 'Guardar Cambios' : 'Agregar Producto'),
            style: AppText.body.copyWith(
              fontWeight: FontWeight.w600,
              color: Colors.white,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeleteButton() {
    return IconButton(
      icon: const Icon(Icons.delete_outline_rounded),
      tooltip: 'Eliminar producto',
      onPressed: _isLoading || _loadFailed ? null : _deleteProduct,
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _priceController.dispose();
    _stockController.dispose();
    _categoryController.dispose();
    super.dispose();
  }
}
