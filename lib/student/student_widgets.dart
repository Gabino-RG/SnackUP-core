import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:snackup/theme/student_colors.dart';
import 'student_api.dart';

String money(Object? value) {
  final amount = value is num ? value.toDouble() : double.tryParse('$value');
  return '\$${(amount ?? 0).toStringAsFixed(2)}';
}

String dateText(Object? value) {
  final date = DateTime.tryParse('$value')?.toLocal();
  if (date == null) return 'Sin fecha';
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(date.day)}/${two(date.month)}/${date.year} ${two(date.hour)}:${two(date.minute)}';
}

String statusLabel(Object? value) => switch (value) {
  'pending' => 'Pendiente de aceptar',
  'accepted' => 'Aceptado',
  'preparing' => 'En preparación',
  'ready' => 'Listo para recoger',
  'completed' => 'Entregado',
  'cancelled' => 'Cancelado',
  _ => 'Estado por actualizar',
};

String friendlyError(Object error) {
  if (error is ApiException) return error.message;
  return 'No pudimos completar la operación. Revisa tu conexión e inténtalo de nuevo.';
}

class StudentImage extends StatelessWidget {
  const StudentImage({
    super.key,
    required this.url,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
  });
  final Object? url;
  final double? width;
  final double? height;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final source = context.read<StudentApi>().mediaUrl(url);
    final placeholder = Container(
      width: width,
      height: height,
      color: AppColors.componentBase,
      alignment: Alignment.center,
      child: const Icon(
        Icons.restaurant_rounded,
        color: AppColors.primary,
        size: 36,
      ),
    );
    if (source.isEmpty) return placeholder;
    return Image.network(
      source,
      width: width,
      height: height,
      fit: fit,
      errorBuilder: (_, _, _) => placeholder,
    );
  }
}

class ErrorPanel extends StatelessWidget {
  const ErrorPanel({super.key, required this.error, required this.onRetry});
  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.wifi_off_rounded,
              size: 40,
              color: AppColors.textSecondary,
            ),
            const SizedBox(height: 12),
            Text(friendlyError(error), textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar'),
            ),
          ],
        ),
      ),
    ),
  );
}

class StudentAuthLayout extends StatelessWidget {
  const StudentAuthLayout({
    super.key,
    required this.title,
    required this.subtitle,
    required this.child,
  });
  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: AppColors.borders),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: .04),
                    blurRadius: 30,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(13),
                        ),
                        child: const Icon(
                          Icons.lunch_dining_rounded,
                          color: AppColors.accent,
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 10),
                      RichText(
                        text: const TextSpan(
                          style: TextStyle(
                            fontFamily: 'Lato',
                            color: AppColors.primary,
                            fontSize: 26,
                            fontWeight: FontWeight.w700,
                          ),
                          children: [
                            TextSpan(text: 'Snack'),
                            TextSpan(
                              text: 'UP',
                              style: TextStyle(color: AppColors.tertiary),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    subtitle,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 28),
                  child,
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
