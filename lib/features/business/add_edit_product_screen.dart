import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:snackup/theme/app_colors.dart';
import 'package:snackup/theme/app_text.dart';

import '../../services/product_photo_service.dart';
import '../../widgets/product_photo.dart';

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

  final _photoService = ProductPhotoService();
  final _imagePicker = ImagePicker();
  String? _existingImageUrl;
  Uint8List? _selectedPhoto;
  bool _hasPhoto = false;
  bool _removePhoto = false;
  bool _isPickingPhoto = false;
  bool _isFeatured = false;
  bool _isAvailable = true;
  bool _isLoading = false;
  bool _isEditing = false;

  @override
  void initState() {
    super.initState();
    _isEditing = widget.productId != null;
    if (_isEditing) {
      _loadProductData();
    }
  }

  Future<void> _loadProductData() async {
    setState(() => _isLoading = true);
    try {
      final doc = await FirebaseFirestore.instance
          .collection('products')
          .doc(widget.productId)
          .get();

      if (!mounted) return;
      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        _nameController.text = data['name'] ?? '';
        _descriptionController.text = data['description'] ?? '';
        _priceController.text = (data['price'] ?? 0.0).toString();
        _stockController.text = (data['stock'] ?? 0).toString();
        _categoryController.text = data['category'] ?? '';
        setState(() {
          _isFeatured = data['isFeatured'] ?? false;
          _isAvailable = data['isAvailable'] ?? true;
          _existingImageUrl = data['imageUrl'] as String?;
          _hasPhoto = data['hasPhoto'] == true;
        });
      }
    } catch (e) {
      _showError('Error al cargar producto: ${e.toString()}');
    }
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _saveProduct() async {
    if (_isLoading || _isPickingPhoto || !_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _isLoading = true);

    try {
      final price = double.tryParse(_priceController.text) ?? 0.0;
      final stock = int.tryParse(_stockController.text) ?? 0;

      final productData = {
        'businessId': widget.businessId,
        'name': _nameController.text.trim(),
        'description': _descriptionController.text.trim(),
        'price': price,
        'stock': stock,
        'isAvailable': _isAvailable && stock > 0,
        'isFeatured': _isFeatured,
        'category': _categoryController.text.trim().toUpperCase(),
        'updatedAt': FieldValue.serverTimestamp(),
        'name_searchable': _nameController.text.trim().toLowerCase(),
      };

      await _photoService.saveProduct(
        businessId: widget.businessId,
        productId: widget.productId,
        data: productData,
        photoBytes: _selectedPhoto,
        removePhoto: _removePhoto,
      );

      if (mounted) Navigator.of(context).pop();
    } on FirebaseException catch (error) {
      _showError(
        error.code == 'permission-denied'
            ? 'No tienes permiso para guardar este producto.'
            : 'No se pudo guardar el producto. Revisa tu conexión.',
      );
    } catch (_) {
      _showError('No se pudo guardar el producto. Inténtalo de nuevo.');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
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
      body: _isLoading
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
                    _buildPhotoPicker(),

                    const SizedBox(height: 16),

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

  bool get _hasVisiblePhoto =>
      _selectedPhoto != null ||
      (!_removePhoto &&
          (_hasPhoto || (_existingImageUrl?.isNotEmpty ?? false)));

  Future<void> _pickPhoto() async {
    if (_isLoading || _isPickingPhoto) return;
    setState(() => _isPickingPhoto = true);
    try {
      final picked = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1280,
        maxHeight: 1280,
        imageQuality: 85,
      );
      if (picked == null || !mounted) return;
      if (await picked.length() > 10 * 1024 * 1024) {
        throw const FormatException('Elige una foto de hasta 10 MB.');
      }
      final photo = await ProductPhotoService.prepare(
        await picked.readAsBytes(),
      );
      if (!mounted) return;
      setState(() {
        _selectedPhoto = photo;
        _removePhoto = false;
      });
    } on PlatformException catch (error) {
      _showError(
        error.code == 'photo_access_denied' ||
                error.code == 'photo_access_restricted'
            ? 'No se pudo acceder a las fotos. Revisa el permiso de la galería en Ajustes.'
            : 'No se pudo abrir la galería. Inténtalo de nuevo.',
      );
    } on FormatException catch (error) {
      _showError(error.message);
    } catch (_) {
      _showError('No se pudo preparar la foto. Elige otra imagen.');
    } finally {
      if (mounted) setState(() => _isPickingPhoto = false);
    }
  }

  void _clearPhoto() {
    if (_isLoading || _isPickingPhoto) return;
    setState(() {
      _selectedPhoto = null;
      _hasPhoto = false;
      _removePhoto = true;
    });
  }

  Widget _buildPhotoPicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Foto del producto (opcional)',
          style: AppText.body.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: _selectedPhoto != null
              ? Image.memory(
                  _selectedPhoto!,
                  height: 180,
                  width: double.infinity,
                  fit: BoxFit.cover,
                )
              : _hasVisiblePhoto && widget.productId != null
              ? ProductPhoto(
                  productId: widget.productId!,
                  hasPhoto: _hasPhoto,
                  legacyUrl: _existingImageUrl,
                  height: 180,
                  width: double.infinity,
                  fit: BoxFit.cover,
                )
              : Container(
                  height: 150,
                  color: AppColors.componentBase,
                  child: const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.add_photo_alternate_outlined, size: 40),
                      SizedBox(height: 8),
                      Text('Agrega una foto de tu producto'),
                    ],
                  ),
                ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _isLoading || _isPickingPhoto ? null : _pickPhoto,
          icon: _isPickingPhoto
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.photo_library_outlined),
          label: Text(
            _isPickingPhoto
                ? 'Cargando foto...'
                : _hasVisiblePhoto
                ? 'Cambiar foto'
                : 'Elegir foto de la galería',
          ),
        ),
        if (_hasVisiblePhoto)
          TextButton.icon(
            onPressed: _isLoading || _isPickingPhoto ? null : _clearPhoto,
            icon: const Icon(Icons.delete_outline),
            label: const Text('Quitar foto'),
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
          hintText: 'Ej: Taco al Pastor',
          validator: (value) =>
              value == null || value.trim().isEmpty || value.trim().length > 120
              ? 'El nombre es obligatorio'
              : null,
        ),

        const SizedBox(height: 16),

        // CATEGORÍA
        _buildTextField(
          controller: _categoryController,
          label: 'Categoría',
          hintText: 'Ej: TACOS, BEBIDAS, POSTRES',
          validator: (value) =>
              value == null || value.trim().isEmpty || value.trim().length > 80
              ? 'La categoría es obligatoria'
              : null,
        ),

        const SizedBox(height: 16),

        // DESCRIPCIÓN
        _buildTextField(
          controller: _descriptionController,
          label: 'Descripción',
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
                  final price = double.tryParse(value);
                  if (price == null ||
                      !price.isFinite ||
                      price <= 0 ||
                      price > 1000000 ||
                      !RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(value.trim())) {
                    return 'Precio inválido';
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
                    return 'Stock inválido';
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
      onPressed: _isLoading || _isPickingPhoto ? null : _saveProduct,
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
      onPressed: _isLoading || _isPickingPhoto ? null : _deleteProduct,
    );
  }

  Future<void> _deleteProduct() async {
    if (_isLoading || _isPickingPhoto || widget.productId == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Eliminar producto'),
        content: Text(
          '¿Eliminar "${_nameController.text}" del menú? Los pedidos anteriores conservarán su información.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _isLoading = true);
    try {
      await _photoService.deleteProduct(productId: widget.productId!);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Producto eliminado.')));
      Navigator.of(context).pop();
    } on FirebaseException catch (error) {
      _showError(
        error.code == 'permission-denied'
            ? 'No tienes permiso para eliminar este producto.'
            : 'No se pudo eliminar el producto. Revisa tu conexión.',
      );
    } catch (_) {
      _showError('No se pudo eliminar el producto. Inténtalo de nuevo.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
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
