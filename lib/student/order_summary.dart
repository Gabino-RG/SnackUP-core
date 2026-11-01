import 'package:flutter/material.dart';
import 'package:snackup/theme/student_colors.dart';
import 'package:snackup/theme/student_text.dart';
import 'student_widgets.dart';

String orderSummaryStatus(Object? status) => switch (status) {
  'pending' || 'accepted' => 'Recibido',
  'preparing' => 'Preparando',
  'ready' => '¡Listo!',
  'completed' => 'Entregado',
  'cancelled' => 'Cancelado',
  _ => 'Por actualizar',
};

class StudentOrderSummary extends StatelessWidget {
  const StudentOrderSummary({
    super.key,
    required this.order,
    required this.onTap,
  });
  final Map<String, dynamic> order;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final items = (order['items'] as List).cast<Map>();
    final count = items.fold<int>(
      0,
      (sum, item) => sum + (item['quantity'] as num).toInt(),
    );
    final summary = items
        .take(2)
        .map((item) => '${item['quantity']}x ${item['name']}')
        .join(', ');
    final stage = switch (order['status']) {
      'preparing' => 1,
      'ready' || 'completed' => 2,
      _ => 0,
    };
    return Semantics(
      button: true,
      label: 'Opciones del pedido #${order['orderNumber']}',
      child: Card(
        color: AppColors.background,
        surfaceTintColor: Colors.transparent,
        elevation: 1,
        shadowColor: Colors.black.withValues(alpha: .2),
        margin: const EdgeInsets.only(bottom: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: AppColors.borders),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(26, 26, 26, 46),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 9,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFDFE3EB),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        orderSummaryStatus(order['status']),
                        style: AppText.body.copyWith(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerRight,
                        child: Text(
                          money(order['total']),
                          textAlign: TextAlign.right,
                          style: AppText.h3.copyWith(
                            color: const Color(0xFF00A819),
                            fontSize: 22,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Text(
                  'Resumen del Pedido',
                  style: AppText.body.copyWith(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 10),
                Text(summary, style: AppText.body.copyWith(fontSize: 18)),
                if (items.length > 2)
                  Text(
                    '+ ${items.length - 2} productos más',
                    style: AppText.notes,
                  ),
                const SizedBox(height: 4),
                Text(
                  '$count ${count == 1 ? 'producto' : 'productos'} en total',
                  style: AppText.notes.copyWith(fontSize: 14),
                ),
                const SizedBox(height: 22),
                _OrderProgress(stage: stage),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OrderProgress extends StatelessWidget {
  const _OrderProgress({required this.stage});
  final int stage;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      return Stack(
        children: [
          Positioned(
            left: constraints.maxWidth / 6,
            right: constraints.maxWidth / 6,
            top: 48,
            child: Row(
              children: [
                for (var index = 0; index < 2; index++)
                  Expanded(
                    child: Container(
                      height: 4,
                      color: stage > index
                          ? AppColors.primary
                          : const Color(0xFFDDDDDD),
                    ),
                  ),
              ],
            ),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var index = 0; index < 3; index++)
                Expanded(
                  child: Column(
                    children: [
                      SizedBox(
                        height: 24,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            const ['Recibido', 'Preparando', '¡Listo!'][index],
                            style: AppText.body.copyWith(
                              fontSize: 17,
                              color: index <= stage
                                  ? AppColors.primary
                                  : const Color(0xFF606169),
                              fontWeight: index <= stage
                                  ? FontWeight.w600
                                  : FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        key: ValueKey('order-progress-$index'),
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: index <= stage
                              ? AppColors.primary
                              : Colors.white,
                        ),
                        child: Icon(
                          const [
                            Icons.receipt_long_outlined,
                            Icons.restaurant,
                            Icons.check_circle,
                          ][index],
                          size: 19,
                          color: index <= stage
                              ? Colors.white
                              : const Color(0xFF68696E),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      );
    },
  );
}
