import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:snackup/theme/app_colors.dart';
import 'package:snackup/theme/app_text.dart';

import 'review_submission.dart';

class RateOrderScreen extends StatefulWidget {
  final String orderId;
  final String businessId;
  final String businessName;

  const RateOrderScreen({
    super.key,
    required this.orderId,
    required this.businessId,
    required this.businessName,
  });

  @override
  State<RateOrderScreen> createState() => _RateOrderScreenState();
}

class _RateOrderScreenState extends State<RateOrderScreen> {
  final _formKey = GlobalKey<FormState>();
  final _commentController = TextEditingController();
  final _careerController = TextEditingController();
  final _groupController = TextEditingController();
  int _rating = 0;
  int _serviceRating = 0;
  int _foodRating = 0;
  bool _isLoading = false;
  bool _careerEdited = false;
  bool _groupEdited = false;
  String? _profileNotice;

  @override
  void initState() {
    super.initState();
    _prefillAcademicProfile();
  }

  Future<void> _prefillAcademicProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      if (!mounted || FirebaseAuth.instance.currentUser?.uid != user.uid) {
        return;
      }
      final data = snapshot.data();
      final career = data?['career'];
      final group = data?['group'];
      // Older profiles need no migration. Never overwrite a field the student
      // already edited while the profile was loading.
      if (!_careerEdited && career is String) {
        _careerController.text = normalizeAcademicLabel(career);
      }
      if (!_groupEdited && group is String) {
        _groupController.text = normalizeAcademicLabel(group).toUpperCase();
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _profileNotice =
            'No pudimos cargar tu carrera y grupo. Puedes escribirlos aquí.';
      });
    }
  }

  void _showMessage(String message, {bool success = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: success ? AppColors.success : AppColors.error,
      ),
    );
  }

  Future<void> _submitReview() async {
    if (_isLoading || !_formKey.currentState!.validate()) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _showMessage('Inicia sesión para enviar tu reseña.');
      return;
    }

    late final ReviewSubmission submission;
    try {
      submission = ReviewSubmission(
        rating: _rating,
        serviceRating: _serviceRating,
        foodRating: _foodRating,
        career: _careerController.text,
        group: _groupController.text,
        comment: _commentController.text,
      );
    } on ReviewSubmissionException catch (error) {
      _showMessage(error.message);
      return;
    }

    setState(() => _isLoading = true);
    try {
      final firestore = FirebaseFirestore.instance;
      // Older versions used random review IDs. Check the student's own reviews
      // before the transaction; a failed lookup must never bypass this guard.
      final previousReviews = await firestore
          .collection('reviews')
          .where('userId', isEqualTo: user.uid)
          .where('orderId', isEqualTo: widget.orderId)
          .limit(1)
          .get(const GetOptions(source: Source.server));
      if (previousReviews.docs.isNotEmpty) {
        throw const ReviewSubmissionException(
          'Ya enviaste una reseña para este pedido.',
        );
      }
      final orderReference = firestore.collection('orders').doc(widget.orderId);
      final reviewReference = firestore
          .collection('reviews')
          .doc(widget.orderId);
      await firestore.runTransaction((transaction) async {
        final order = await transaction.get(orderReference);
        validateReviewOrder(
          order: order.data(),
          userId: user.uid,
          businessId: widget.businessId,
        );
        final existingReview = await transaction.get(reviewReference);
        if (existingReview.exists) {
          throw const ReviewSubmissionException(
            'Ya enviaste una reseña para este pedido.',
          );
        }
        transaction.set(
          reviewReference,
          submission.toDocument(
            orderId: widget.orderId,
            businessId: widget.businessId,
            userId: user.uid,
            createdAt: FieldValue.serverTimestamp(),
          ),
        );
      });

      if (!mounted) return;
      _showMessage(
        '¡Gracias! Tu opinión ayudará a mejorar el local.',
        success: true,
      );
      Navigator.of(context).pop(true);
    } on ReviewSubmissionException catch (error) {
      _showMessage(error.message);
    } on FirebaseException catch (error) {
      _showMessage(
        error.code == 'permission-denied'
            ? 'No se pudo autorizar la reseña. Revisa tu sesión y que el pedido esté completado.'
            : error.code == 'failed-precondition'
            ? 'No pudimos verificar la reseña. Inténtalo más tarde o avisa a administración.'
            : 'No pudimos enviar tu reseña. Revisa tu conexión e inténtalo de nuevo.',
      );
    } catch (_) {
      _showMessage('No pudimos enviar tu reseña. Inténtalo de nuevo.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Widget _ratingSelector(String label, int value, ValueChanged<int> onChanged) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppText.h3.copyWith(fontSize: 18)),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(5, (index) {
              final stars = index + 1;
              return Semantics(
                selected: value == stars,
                child: IconButton(
                  tooltip:
                      '$label: $stars ${stars == 1 ? 'estrella' : 'estrellas'}',
                  onPressed: _isLoading ? null : () => onChanged(stars),
                  icon: Icon(
                    index < value
                        ? Icons.star_rounded
                        : Icons.star_border_rounded,
                    color: AppColors.warning,
                    size: 36,
                  ),
                ),
              );
            }),
          ),
          Center(
            child: Text(
              value == 0 ? 'Sin calificar' : '$value de 5 estrellas',
              style: AppText.notes.copyWith(color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Calificar pedido'),
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        children: [
                          const Icon(
                            Icons.rate_review_outlined,
                            size: 40,
                            color: AppColors.primary,
                          ),
                          const SizedBox(height: 12),
                          Text('Tu opinión cuenta', style: AppText.h3),
                          const SizedBox(height: 8),
                          Text(
                            widget.businessName,
                            style: AppText.body,
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Califica de 1 (muy malo) a 5 (excelente).',
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 28),
                    _ratingSelector(
                      'Experiencia general',
                      _rating,
                      (value) => setState(() => _rating = value),
                    ),
                    _ratingSelector(
                      'Servicio y atención',
                      _serviceRating,
                      (value) => setState(() => _serviceRating = value),
                    ),
                    _ratingSelector(
                      'Calidad de los alimentos',
                      _foodRating,
                      (value) => setState(() => _foodRating = value),
                    ),
                    const Divider(),
                    const SizedBox(height: 16),
                    Text('Tu comunidad estudiantil', style: AppText.h3),
                    const SizedBox(height: 8),
                    const Text(
                      'Carrera y grupo son opcionales y declarados por ti. '
                      'Ayudan a comparar las opiniones por comunidad. '
                      'El panel administrativo muestra tus calificaciones, '
                      'comentario, carrera y grupo sin mostrar tu nombre. '
                      'La reseña queda vinculada a tu cuenta y pedido.',
                    ),
                    if (_profileNotice != null) ...[
                      const SizedBox(height: 8),
                      Text(_profileNotice!, style: AppText.notes),
                    ],
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _careerController,
                      enabled: !_isLoading,
                      maxLength: ReviewSubmission.maxCareerLength,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Carrera (opcional)',
                        helperText: 'Escribe el nombre de tu carrera.',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) => _careerEdited = true,
                      validator: (value) => validateTextLength(
                        normalizeAcademicLabel(value ?? ''),
                        ReviewSubmission.maxCareerLength,
                        'La carrera',
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _groupController,
                      enabled: !_isLoading,
                      maxLength: ReviewSubmission.maxGroupLength,
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(
                        labelText: 'Grupo (opcional)',
                        helperText: 'Usa la clave de tu grupo.',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) => _groupEdited = true,
                      validator: (value) => validateTextLength(
                        normalizeAcademicLabel(value ?? '').toUpperCase(),
                        ReviewSubmission.maxGroupLength,
                        'El grupo',
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _commentController,
                      enabled: !_isLoading,
                      maxLength: ReviewSubmission.maxCommentLength,
                      minLines: 3,
                      maxLines: 6,
                      decoration: const InputDecoration(
                        labelText: 'Comentario (opcional)',
                        hintText: '¿Qué salió bien y qué podría mejorar?',
                        helperText:
                            'Evita nombres, teléfonos u otros datos personales.',
                        helperMaxLines: 3,
                        border: OutlineInputBorder(),
                        alignLabelWithHint: true,
                      ),
                      validator: (value) => validateTextLength(
                        (value ?? '').trim(),
                        ReviewSubmission.maxCommentLength,
                        'El comentario',
                      ),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: _isLoading ? null : _submitReview,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(double.infinity, 56),
                      ),
                      child: _isLoading
                          ? const SizedBox.square(
                              dimension: 24,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : const Text('Enviar reseña'),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _commentController.dispose();
    _careerController.dispose();
    _groupController.dispose();
    super.dispose();
  }
}
