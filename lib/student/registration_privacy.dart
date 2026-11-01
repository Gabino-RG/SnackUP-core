import 'package:flutter/material.dart';
import 'package:snackup/theme/student_colors.dart';

const registrationDataNotice =
    'Para crear tu cuenta en SnackUp, necesitamos utilizar algunos datos '
    'personales básicos, como tu nombre, correo electrónico y datos '
    'relacionados con tus pedidos. Esta información será utilizada '
    'únicamente para registrar tu cuenta, permitir el inicio de sesión y '
    'gestionar tus pedidos dentro de la cafetería universitaria.\n\n'
    'Antes de continuar, revisa y acepta nuestro Documento de '
    'Protección de Datos Personales y nuestra Política de Privacidad.';

const registrationConsentLabel =
    'He leído y acepto el Documento de Protección de Datos Personales '
    'y la Política de Privacidad de SnackUp. Autorizo el uso de mis datos '
    'personales únicamente para el registro, autenticación y gestión de '
    'pedidos dentro de la aplicación.';

enum RegistrationDocument {
  protection(
    'Protección de Datos Personales',
    'En SnackUp protegemos tus datos personales y los '
        'utilizamos únicamente para el funcionamiento de la '
        'aplicación.\n\n'
        'Al registrarte, podremos solicitar datos como tu '
        'nombre, correo electrónico, matrícula o identificador '
        'escolar, rol de usuario y datos relacionados con tus '
        'pedidos. Esta información será utilizada únicamente '
        'para crear tu cuenta, permitir el inicio de sesión, '
        'gestionar pedidos de alimentos y mostrar el estado de '
        'tus solicitudes dentro de la cafetería universitaria.\n\n'
        'SnackUp no solicitará datos sensibles como información '
        'médica, datos biométricos, domicilio particular, religión, '
        'preferencias políticas u otra información que no sea '
        'necesaria para el uso del sistema.\n\n'
        'Tus datos serán tratados con medidas de seguridad '
        'adecuadas para evitar pérdida, alteración, acceso no '
        'autorizado o uso indebido. Además, podrás solicitar el '
        'acceso, corrección, cancelación u oposición al uso de '
        'tus datos personales mediante el correo:\n'
        'Soporte.snackup@gmail.com\n\n'
        'Al aceptar este documento, autorizas a SnackUp a '
        'utilizar tus datos personales únicamente para el '
        'registro, autenticación y gestión de pedidos dentro de la '
        'aplicación.',
  ),
  privacy(
    'Política de Privacidad',
    'SnackUp es una aplicación web diseñada para facilitar '
        'la gestión de pedidos dentro de una cafetería '
        'universitaria. Para poder utilizar el sistema, necesitamos '
        'recopilar algunos datos personales básicos.\n\n'
        'Los datos que podremos solicitar incluyen nombre, '
        'correo electrónico, matrícula o identificador escolar, '
        'contraseña de acceso, rol de usuario y datos '
        'relacionados con los pedidos realizados.\n\n'
        'Esta información será utilizada únicamente para crear '
        'tu cuenta, validar tu acceso, gestionar tus pedidos, '
        'mostrar el estado de tus solicitudes y brindar soporte '
        'en caso necesario.\n\n'
        'SnackUp no venderá, rentará ni compartirá tus datos '
        'personales con terceros para fines ajenos al '
        'funcionamiento de la aplicación. En caso de utilizar '
        'servicios externos como bases de datos, autenticación, '
        'hosting o pasarelas de pago, tus datos serán tratados '
        'únicamente para permitir el funcionamiento técnico del '
        'sistema.\n\n'
        'Tus datos personales serán conservados solo durante el '
        'tiempo necesario para cumplir con las finalidades de la '
        'aplicación. Cuando ya no sean necesarios, podrán ser '
        'eliminados, bloqueados o cancelados conforme '
        'corresponda.',
  );

  const RegistrationDocument(this.title, this.body);
  final String title;
  final String body;
}

Future<void> showRegistrationDocument(
  BuildContext context,
  RegistrationDocument document,
) => showDialog<void>(
  context: context,
  builder: (dialogContext) => AlertDialog(
    backgroundColor: Colors.white,
    surfaceTintColor: Colors.transparent,
    insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
    title: Text(document.title),
    content: SizedBox(
      width: 540,
      child: SingleChildScrollView(
        child: SelectableText(
          document.body,
          style: const TextStyle(
            fontSize: 15,
            height: 1.6,
            color: AppColors.textPrimary,
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(dialogContext),
        child: const Text('Cerrar'),
      ),
    ],
  ),
);
