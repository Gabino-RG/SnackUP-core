import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../theme/app_colors.dart';

class ProductReviews extends StatelessWidget {
  final String productId;
  const ProductReviews({super.key, required this.productId});
  @override
  Widget build(BuildContext context) => StreamBuilder<QuerySnapshot>(
    stream: FirebaseFirestore.instance
        .collection('reviews')
        .where('productId', isEqualTo: productId)
        .snapshots(),
    builder: (context, snapshot) {
      if (snapshot.hasError)
        return const Text('Las reseñas no están disponibles en este momento.');
      if (!snapshot.hasData) return const LinearProgressIndicator();
      final reviews = snapshot.data!.docs
          .map((doc) => doc.data() as Map<String, dynamic>)
          .toList();
      if (reviews.isEmpty)
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: Text('Aún no hay reseñas de este platillo.'),
        );
      final average =
          reviews.fold<double>(
            0,
            (sum, review) =>
                sum + ((review['rating'] as num?)?.toDouble() ?? 0),
          ) /
          reviews.length;
      reviews.sort(
        (a, b) => ((b['updatedAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0)
            .compareTo(
              (a['updatedAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0,
            ),
      );
      return Container(
        padding: const EdgeInsets.all(18),
        margin: const EdgeInsets.only(bottom: 24),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.star_rounded, color: Color(0xFFAEC500)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '${average.toStringAsFixed(1)} · ${reviews.length} reseñas',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            ...reviews
                .take(5)
                .map(
                  (review) => Padding(
                    padding: const EdgeInsets.only(top: 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${review['anonymous'] == true ? 'Estudiante anónimo' : review['userName'] ?? 'Estudiante'} · ${review['rating']}/5',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        if ((review['comment'] as String? ?? '').isNotEmpty)
                          Text(review['comment'] as String),
                      ],
                    ),
                  ),
                ),
          ],
        ),
      );
    },
  );
}
