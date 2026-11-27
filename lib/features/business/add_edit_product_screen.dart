import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
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

  final _imageUrlController = TextEditingController();
  String? _existingImageUrl;
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
          _imageUrlController.text = _existingImageUrl ?? '';
        });
      }
    } catch (e) {
      _showError('Error al cargar producto: ${e.toString()}');
    }
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _saveProduct() async {
    if (_isLoading || !_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _isLoading = true);

    try {
      final imageUrl = _imageUrlController.text.trim();
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
        'imageUrl': imageUrl.isEmpty ? null : imageUrl,
        'updatedAt': FieldValue.serverTimestamp(),
        'name_searchable': _nameController.text.trim().toLowerCase(),
      };

      if (_isEditing) {
        await FirebaseFirestore.instance
            .collection('products')
            .doc(widget.productId)
            .update(productData);
      } else {
        await FirebaseFirestore.instance
            .collection('products')
            .add(productData);
      }

      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      _showError('Error al guardar: ${e.toString()}');
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
                    _buildImageUrlField(),

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

  String? _validateImageUrl(String? value) {
    final url = value?.trim() ?? '';
    if (url.isEmpty || url == _existingImageUrl) return null;
    final uri = Uri.tryParse(url);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        RegExp(r'\s').hasMatch(url)) {
      return 'Pega una URL HTTPS válida de la imagen.';
    }
    return null;
  }

  Widget _buildImageUrlField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          controller: _imageUrlController,
          keyboardType: TextInputType.url,
          autocorrect: false,
          maxLength: 2048,
          decoration: const InputDecoration(
            labelText: 'URL de la foto (opcional)',
            hintText: 'https://ejemplo.com/foto.jpg',
            helperText: 'Usa un enlace directo que abra sin iniciar sesión.',
            prefixIcon: Icon(Icons.link),
          ),
          validator: _validateImageUrl,
        ),
        const SizedBox(height: 8),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: _imageUrlController,
          builder: (context, value, _) {
            final url = value.text.trim();
            if (url.isEmpty || _validateImageUrl(url) != null) {
              return const SizedBox.shrink();
            }
            return ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.network(
                url,
                height: 180,
                fit: BoxFit.cover,
                webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
                errorBuilder: (_, __, ___) => const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text(
                    'No se pudo mostrar la foto. Verifica el enlace.',
                  ),
                ),
              ),
            );
          },
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
      onPressed: _isLoading ? null : _saveProduct,
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
      onPressed: _isLoading ? null : _deleteProduct,
    );
  }

  Future<void> _deleteProduct() async {
    if (_isLoading || widget.productId == null) return;
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
      await FirebaseFirestore.instance
          .collection('products')
          .doc(widget.productId)
          .delete();
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
    _imageUrlController.dispose();
    super.dispose();
  }
}
