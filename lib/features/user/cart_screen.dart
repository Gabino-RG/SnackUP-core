import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:snackup/theme/app_colors.dart';
import 'package:snackup/theme/app_text.dart';

class CartScreen extends StatefulWidget {
  const CartScreen({super.key});

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  String _selectedPaymentMethod = 'Efectivo';
  TimeOfDay? _selectedTime;
  bool _isLoading = false;

  final List<String> _paymentMethods = ['Efectivo', 'Tarjeta', 'Vale'];

  Future<void> _pickTime() async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(DateTime.now().add(const Duration(minutes: 30))),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: AppColors.primary,
              onPrimary: Colors.white,
              surface: AppColors.background,
              onSurface: AppColors.textPrimary,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        _selectedTime = picked;
      });
    }
  }

  Future<bool> _showConfirmDialog(String title, String content) async {
    return await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          title,
          style: AppText.h3.copyWith(color: AppColors.textPrimary),
        ),
        content: Text(
          content,
          style: AppText.body.copyWith(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              'Cancelar',
              style: AppText.body.copyWith(color: AppColors.textSecondary),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
            child: Text(
              'Confirmar',
              style: AppText.body.copyWith(
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    ) ?? false;
  }

  Future<void> _placeOrder(List<QueryDocumentSnapshot> cartDocs, double totalPrice) async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return;

    if (cartDocs.isEmpty) {
      _showError('Tu carrito está vacío.');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final allBusinessIds = cartDocs.map((doc) => (doc.data() as Map<String, dynamic>)['businessId']).toSet();
      if (allBusinessIds.length > 1) {
        _showError('Tu carrito tiene productos de varias tiendas. Por favor, haz pedidos separados.');
        setState(() => _isLoading = false);
        return;
      }
      final String businessId = allBusinessIds.first;

      final userDoc = await FirebaseFirestore.instance.collection('users').doc(userId).get();
      if (!userDoc.exists || userDoc.data() == null) {
        _showError('Error: No se encontraron tus datos de usuario.');
        setState(() => _isLoading = false);
        return;
      }
      final userData = userDoc.data()!;
      
      final List<Map<String, dynamic>> orderItems = cartDocs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        return {
          'productId': data['productId'],
          'name': data['name'],
          'quantity': data['quantity'],
          'price': data['price'],
          'notes': data['notes'] ?? '',
        };
      }).toList();

      Timestamp? pickupTimestamp;
      if (_selectedTime != null) {
        final now = DateTime.now();
        final scheduledDateTime = DateTime(
          now.year, now.month, now.day,
          _selectedTime!.hour, _selectedTime!.minute,
        );
        pickupTimestamp = Timestamp.fromDate(scheduledDateTime);
      }
      
      final orderData = {
        'businessId': businessId,
        'userId': userId,
        'userDisplayName': userData['displayName'] ?? 'Usuario',
        'userNumeroDeControl': userData['numeroDeControl'] ?? '0000',
        'status': 'pending',
        'totalPrice': totalPrice,
        'paymentMethod': _selectedPaymentMethod,
        'createdAt': FieldValue.serverTimestamp(),
        'scheduledPickupTime': pickupTimestamp,
        'items': orderItems,
      };

      final batch = FirebaseFirestore.instance.batch();
      final orderRef = FirebaseFirestore.instance.collection('orders').doc();
      batch.set(orderRef, orderData);

      for (var doc in cartDocs) {
        batch.delete(doc.reference);
      }
      
      await batch.commit();

      _showSuccess('¡Pedido realizado con éxito!');

    } catch (e) {
      _showError('Error al crear el pedido: ${e.toString()}');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
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

  void _showSuccess(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.success,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final userId = FirebaseAuth.instance.currentUser?.uid;

    if (userId == null) {
      return _buildErrorState('Debes iniciar sesión para ver tu carrito');
    }

    final Stream<QuerySnapshot> cartStream = FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection('cart')
        .snapshots();

    return Scaffold(
      body: StreamBuilder<QuerySnapshot>(
        stream: cartStream,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _buildErrorState('Error al cargar el carrito');
          }
          
          if (snapshot.connectionState == ConnectionState.waiting) {
            return _buildLoadingState();
          }
          
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return _buildEmptyState();
          }

          final cartDocs = snapshot.data!.docs;
          double totalPrice = 0;
          for (var doc in cartDocs) {
            final item = doc.data()! as Map<String, dynamic>;
            totalPrice += (item['price'] ?? 0.0) * (item['quantity'] ?? 1);
          }

          return Column(
            children: [
              // HEADER INFORMATIVO
              _buildCartHeader(cartDocs.length),
              
              // LISTA DE ITEMS
              Expanded(
                child: _buildCartItems(cartDocs),
              ),
              
              // SECCIÓN DE CHECKOUT
              _buildCheckoutArea(totalPrice, cartDocs),
            ],
          );
        },
      ),
    );
  }

  Widget _buildCartHeader(int itemCount) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.1),
        border: Border(
          bottom: BorderSide(color: AppColors.borders, width: 1),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.primary,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.shopping_cart_rounded,
              color: Colors.white,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Mi Carrito',
                  style: AppText.h3.copyWith(
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$itemCount ${itemCount == 1 ? 'producto' : 'productos'} en tu pedido',
                  style: AppText.notes.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCartItems(List<QueryDocumentSnapshot> cartDocs) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: cartDocs.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        return _buildCartItem(cartDocs[index]);
      },
    );
  }

  Widget _buildCartItem(DocumentSnapshot doc) {
    final item = doc.data()! as Map<String, dynamic>;
    final notes = item['notes'] ?? '';
    final quantity = item['quantity'] ?? 1;
    final price = item['price'] ?? 0.0;
    final subtotal = price * quantity;

    return Material(
      color: AppColors.background,
      borderRadius: BorderRadius.circular(16),
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            // IMAGEN DEL PRODUCTO
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: AppColors.componentBase,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(
                  item['imageUrl'] ?? 'https://via.placeholder.com/100',
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      color: AppColors.componentBase,
                      child: Icon(
                        Icons.fastfood_rounded,
                        color: AppColors.textSecondary.withOpacity(0.4),
                        size: 24,
                      ),
                    );
                  },
                ),
              ),
            ),
            
            const SizedBox(width: 16),
            
            // INFORMACIÓN DEL PRODUCTO
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item['name'] ?? 'Producto',
                    style: AppText.body.copyWith(
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '${quantity}x',
                          style: AppText.notes.copyWith(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '\$${price.toStringAsFixed(2)} c/u',
                        style: AppText.notes.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  if (notes.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      notes,
                      style: AppText.notes.copyWith(
                        color: AppColors.textSecondary,
                        fontStyle: FontStyle.italic,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 8),
                  Text(
                    'Subtotal: \$${subtotal.toStringAsFixed(2)}',
                    style: AppText.notes.copyWith(
                      color: AppColors.success,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(width: 12),
            
            // BOTÓN DE ELIMINAR
            IconButton(
              icon: Icon(
                Icons.delete_outline_rounded,
                color: AppColors.error,
                size: 20,
              ),
              onPressed: () async {
                final confirmed = await _showConfirmDialog(
                  'Eliminar Producto', 
                  '¿Quieres eliminar "${item['name']}" del carrito?'
                );
                if (confirmed) {
                  doc.reference.delete();
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCheckoutArea(double totalPrice, List<QueryDocumentSnapshot> cartDocs) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.background,
        border: Border(
          top: BorderSide(color: AppColors.borders, width: 1),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // MÉTODO DE PAGO
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Método de Pago',
                style: AppText.body.copyWith(
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: AppColors.componentBase,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: DropdownButton<String>(
                  value: _selectedPaymentMethod,
                  isExpanded: true,
                  underline: const SizedBox(),
                  icon: Icon(Icons.arrow_drop_down_rounded, color: AppColors.textSecondary),
                  items: _paymentMethods.map((method) {
                    return DropdownMenuItem(
                      value: method,
                      child: Text(
                        method,
                        style: AppText.body.copyWith(color: AppColors.textPrimary),
                      ),
                    );
                  }).toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => _selectedPaymentMethod = value);
                    }
                  },
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 16),

          // HORA DE RECOGIDA
          Material(
            color: AppColors.componentBase,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              onTap: _pickTime,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(
                      Icons.schedule_rounded,
                      color: AppColors.primary,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _selectedTime == null ? 'Pedir Ahora (ASAP)' : 'Programado',
                            style: AppText.body.copyWith(
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _selectedTime != null 
                                ? 'Recoger a las: ${_selectedTime!.format(context)}'
                                : 'Recoger lo antes posible',
                            style: AppText.notes.copyWith(
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: _selectedTime == null ? AppColors.primary : AppColors.accent,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _selectedTime == null ? 'ASAP' : 'Programado',
                        style: AppText.notes.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 10,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          if (_selectedTime != null) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => setState(() => _selectedTime = null),
                child: Text(
                  'Quitar hora programada',
                  style: AppText.notes.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ),
          ],
          
          const SizedBox(height: 20),
          const Divider(height: 1, color: AppColors.borders),
          const SizedBox(height: 16),

          // TOTAL Y BOTÓN DE CONFIRMAR
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Total a Pagar:',
                style: AppText.h3.copyWith(
                  color: AppColors.textPrimary,
                  fontSize: 18,
                ),
              ),
              Text(
                '\$${totalPrice.toStringAsFixed(2)}',
                style: AppText.h1.copyWith(
                  color: AppColors.success,
                  fontSize: 24,
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 16),

          ElevatedButton(
            onPressed: _isLoading ? null : () => _placeOrder(cartDocs, totalPrice),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              elevation: 2,
              shadowColor: AppColors.primary.withOpacity(0.3),
            ),
            child: _isLoading
              ? SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.check_circle_rounded, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'Confirmar Pedido',
                      style: AppText.body.copyWith(
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.shopping_cart_rounded,
              size: 64,
              color: AppColors.error.withOpacity(0.7),
            ),
            const SizedBox(height: 16),
            Text(
              message,
              style: AppText.h3.copyWith(
                color: AppColors.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(color: AppColors.primary),
          const SizedBox(height: 16),
          Text(
            'Cargando tu carrito...',
            style: AppText.body.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: AppColors.componentBase,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.shopping_cart_outlined,
                size: 50,
                color: AppColors.textSecondary.withOpacity(0.5),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Tu carrito está vacío',
              style: AppText.h3.copyWith(
                color: AppColors.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              'Agrega algunos productos deliciosos para comenzar',
              style: AppText.body.copyWith(
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}