import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../user/menu_screen.dart';
import 'package:snackup/theme/app_colors.dart';
import 'package:snackup/theme/app_text.dart';

class UserHomeScreen extends StatelessWidget {
  const UserHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // HEADER DE BIENVENIDA
            _buildWelcomeHeader(),
            
            const SizedBox(height: 8),

            // CARRUSEL DE PROMOCIONES
            _buildPromotionsSection(),

            const SizedBox(height: 24),

            // LISTA DE NEGOCIOS ABIERTOS
            _buildBusinessesSection(),
          ],
        ),
      ),
    );
  }

  Widget _buildWelcomeHeader() {
    final user = FirebaseAuth.instance.currentUser;
    String displayName = user?.displayName ?? user?.email?.split('@').first ?? 'Estudiante';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.primary.withOpacity(0.1),
            AppColors.accent.withOpacity(0.05),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(30),
          bottomRight: Radius.circular(30),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppColors.primary, AppColors.accent],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.school_rounded, // <-- Corregido (era .school en tu código)
                  color: Colors.white,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '¡Hola, $displayName!',
                      style: AppText.h1.copyWith(
                        fontSize: 24,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '¿Qué vas a ordenar hoy?',
                      style: AppText.body.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // ESTADO RÁPIDO DEL CAMPUS
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.componentBase,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.local_cafe_rounded,
                  color: AppColors.primary,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Text(
                  'Cafeterías disponibles ahora',
                  style: AppText.notes.copyWith(
                    fontWeight: FontWeight.w500,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPromotionsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              Icon(
                Icons.local_offer_rounded,
                color: AppColors.accent,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                'Promociones Destacadas',
                style: AppText.h3.copyWith(
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _buildPromotionsCarousel(),
      ],
    );
  }

  Widget _buildPromotionsCarousel() {
    final Stream<QuerySnapshot> promotionsStream = FirebaseFirestore.instance
        .collection('products')
        .where('isFeatured', isEqualTo: true)
        .where('isAvailable', isEqualTo: true)
        .limit(5)
        .snapshots();

    return SizedBox(
      height: 180,
      child: StreamBuilder<QuerySnapshot>(
        stream: promotionsStream,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return _buildErrorState('Error al cargar promociones');
          }
          
          if (snapshot.connectionState == ConnectionState.waiting) {
            return _buildLoadingCarousel();
          }
          
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return _buildEmptyPromotions();
          }

          final docs = snapshot.data!.docs;
          
          return PageView.builder(
            itemCount: docs.length,
            // Añadimos viewportFraction para que se vea un poco de la siguiente tarjeta
            controller: PageController(viewportFraction: 0.9), 
            itemBuilder: (context, index) {
              final promo = docs[index].data() as Map<String, dynamic>;
              // Pasamos un padding diferente al último item
              bool isLastItem = index == docs.length - 1;

              return _buildPromotionCard(
                title: promo['name'] ?? 'Promoción',
                price: '\$${(promo['price'] ?? 0.0).toStringAsFixed(2)}',
                imageUrl: promo['imageUrl'] ?? '',
                description: promo['description'] ?? '',
                isLastItem: isLastItem,
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildPromotionCard({
    required String title,
    required String price,
    required String imageUrl,
    required String description,
    bool isLastItem = false,
  }) {
    return Container(
      // Ajustamos el margen para el PageView
      margin: EdgeInsets.only(left: 20, right: isLastItem ? 20 : 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          children: [
            // IMAGEN DE FONDO
            Container(
              width: double.infinity,
              height: double.infinity,
              child: Image.network(
                imageUrl.isNotEmpty ? imageUrl : 'https://via.placeholder.com/400x200',
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    color: AppColors.componentBase,
                    child: Icon(
                      Icons.local_offer_rounded,
                      size: 50,
                      color: AppColors.textSecondary.withOpacity(0.4),
                    ),
                  );
                },
              ),
            ),
            
            // --- ¡CORRECCIÓN AQUÍ! ---
            // Gradiente modificado para mejor legibilidad
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    Colors.black.withOpacity(0.8), // 80% oscuro abajo
                    Colors.black.withOpacity(0.2), // 20% oscuro arriba
                  ],
                  // El gradiente se aplica desde el 0% (abajo) hasta el 70% de la altura
                  stops: const [0.0, 0.7], 
                ),
              ),
            ),
            // --- FIN DE LA CORRECCIÓN ---
            
            // CONTENIDO
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.accent,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'PROMOCIÓN',
                      style: AppText.notes.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 10,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    title,
                    style: AppText.h3.copyWith(
                      color: Colors.white,
                      fontSize: 18,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (description.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: AppText.notes.copyWith(
                        color: Colors.white.withOpacity(0.8),
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          price,
                          style: AppText.body.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const Spacer(),
                      Icon(
                        Icons.arrow_forward_rounded,
                        color: Colors.white.withOpacity(0.8),
                        size: 20,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBusinessesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              Icon(
                Icons.storefront_rounded,
                color: AppColors.primary,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                'Tiendas Abiertas',
                style: AppText.h3.copyWith(
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _buildBusinessesList(),
      ],
    );
  }

  Widget _buildBusinessesList() {
    final Stream<QuerySnapshot> businessesStream = FirebaseFirestore.instance
        .collection('businesses')
        .where('isOpen', isEqualTo: true)
        .snapshots();

    return StreamBuilder<QuerySnapshot>(
      stream: businessesStream,
      builder: (BuildContext context, AsyncSnapshot<QuerySnapshot> snapshot) {
        if (snapshot.hasError) {
          return _buildErrorState('Error al cargar tiendas');
        }
        
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildLoadingBusinesses();
        }
        
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return _buildEmptyBusinesses();
        }

        final docs = snapshot.data!.docs;
        
        return ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          itemCount: docs.length,
          separatorBuilder: (context, index) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final document = docs[index];
            Map<String, dynamic> data = document.data()! as Map<String, dynamic>;
            return BusinessCard(
              businessId: document.id,
              name: data['name'] ?? 'Cafetería',
              imageUrl: data['imageUrl'] ?? '',
              category: data['category'] ?? 'Cafetería',
            );
          },
        );
      },
    );
  }

  // ESTADOS DE CARGA Y ERROR
  Widget _buildLoadingCarousel() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(color: AppColors.primary),
          const SizedBox(height: 8),
          Text(
            'Cargando promociones...',
            style: AppText.notes.copyWith(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingBusinesses() {
    return Center(
      child: Column(
        children: [
          CircularProgressIndicator(color: AppColors.primary),
          const SizedBox(height: 8),
          Text(
            'Cargando tiendas...',
            style: AppText.notes.copyWith(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(String message) {
    return Container(
      height: 120,
      margin: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: AppColors.componentBase,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline_rounded,
              color: AppColors.error,
              size: 32,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: AppText.notes.copyWith(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyPromotions() {
    return Container(
      height: 120,
      margin: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: AppColors.componentBase,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.local_offer_rounded,
              color: AppColors.textSecondary.withOpacity(0.4),
              size: 40,
            ),
            const SizedBox(height: 8),
            Text(
              'No hay promociones hoy',
              style: AppText.notes.copyWith(color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyBusinesses() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.componentBase,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Icon(
            Icons.storefront_rounded,
            size: 50,
            color: AppColors.textSecondary.withOpacity(0.4),
          ),
          const SizedBox(height: 12),
          Text(
            'Todas las tiendas están cerradas',
            style: AppText.body.copyWith(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Vuelve más tarde para ver las cafeterías disponibles',
            style: AppText.notes.copyWith(color: AppColors.textSecondary),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// Tarjeta de Negocio (BusinessCard)
class BusinessCard extends StatelessWidget {
  final String businessId;
  final String name;
  final String imageUrl;
  final String category;

  const BusinessCard({
    super.key,
    required this.businessId,
    required this.name,
    required this.imageUrl,
    required this.category,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.background, // Cambiado a fondo blanco para que resalte la sombra
      borderRadius: BorderRadius.circular(16),
      elevation: 2, // Elevación sutil
      shadowColor: Colors.black.withOpacity(0.1), // Sombra suave
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => MenuScreen(
                businessId: businessId, 
                businessName: name
              ),
            ),
          );
        },
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // IMAGEN DEL NEGOCIO
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: AppColors.componentBase,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(
                    imageUrl.isNotEmpty ? imageUrl : 'https://via.placeholder.com/300',
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return Container(
                        color: AppColors.componentBase,
                        child: Icon(
                          Icons.storefront_rounded,
                          size: 30,
                          color: AppColors.textSecondary.withOpacity(0.4),
                        ),
                      );
                    },
                  ),
                ),
              ),
              
              const SizedBox(width: 16),
              
              // INFORMACIÓN
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: AppText.body.copyWith( // Usamos 'body' pero más grueso
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        category.toUpperCase(),
                        style: AppText.notes.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600,
                          fontSize: 10,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(
                          Icons.circle_rounded,
                          color: AppColors.success,
                          size: 8,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Abierto ahora',
                          style: AppText.notes.copyWith(
                            color: AppColors.success,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              
              const SizedBox(width: 12),
              
              // INDICADOR DE NAVEGACIÓN
              Icon(
                Icons.chevron_right_rounded,
                color: AppColors.textSecondary.withOpacity(0.5),
                size: 24,
              ),
            ],
          ),
        ),
      ),
    );
  }
}