import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:snackup/theme/student_colors.dart';

const localRegistrationDemo = bool.fromEnvironment('SNACKUP_LOCAL_DEMO');

class LocalRegistrationHint extends StatelessWidget {
  const LocalRegistrationHint({super.key});
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 20),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: AppColors.paleBlue,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(Icons.science_outlined, size: 18, color: AppColors.tertiary),
            SizedBox(width: 8),
            Text('Prueba local', style: TextStyle(fontWeight: FontWeight.w700)),
          ],
        ),
        const SizedBox(height: 8),
        const Text(
          'Para crear tu cuenta de prueba usa estos datos y elige tu contraseña:',
        ),
        const SizedBox(height: 8),
        const SelectableText(
          'alumno.demo@students.example.edu\nMatrícula: DEMO-001',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
        ),
        const SizedBox(height: 8),
        const Text(
          'El correo de confirmación se verá en el buzón local. No se envía a Internet.',
          style: TextStyle(fontSize: 12),
        ),
        TextButton.icon(
          onPressed: () async {
            final messenger = ScaffoldMessenger.of(context);
            await Clipboard.setData(
              const ClipboardData(text: 'http://localhost:8025'),
            );
            messenger.showSnackBar(
              const SnackBar(
                content: Text(
                  'Dirección del buzón copiada: http://localhost:8025',
                ),
              ),
            );
          },
          icon: const Icon(Icons.copy, size: 16),
          label: const Text('Copiar dirección del buzón'),
        ),
      ],
    ),
  );
}
