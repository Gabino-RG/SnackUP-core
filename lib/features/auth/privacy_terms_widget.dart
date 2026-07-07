import 'package:flutter/material.dart';

class PrivacyTermsWidget extends StatefulWidget {
  final Function(bool) onAccepted;

  const PrivacyTermsWidget({Key? key, required this.onAccepted}) : super(key: key);

  @override
  State<PrivacyTermsWidget> createState() => _PrivacyTermsWidgetState();
}

class _PrivacyTermsWidgetState extends State<PrivacyTermsWidget> {
  bool _isAccepted = false;

  // Textos completos
  final String _datosPersonalesText = 
      "En SnackUp protegemos tus datos personales y los utilizamos únicamente para el funcionamiento de la aplicación.\n\n"
      "Al registrarte, podremos solicitar datos como tu nombre, correo electrónico, matrícula o identificador escolar, rol de usuario y datos relacionados con tus pedidos. Esta información será utilizada únicamente para crear tu cuenta, permitir el inicio de sesión, gestionar pedidos de alimentos y mostrar el estado de tus solicitudes dentro de la cafetería universitaria.\n\n"
      "SnackUp no solicitará datos sensibles como información médica, datos biométricos, domicilio particular, religión, preferencias políticas u otra información que no sea necesaria para el uso del sistema.\n\n"
      "Tus datos serán tratados con medidas de seguridad adecuadas para evitar pérdida, alteración, acceso no autorizado o uso indebido. Además, podrás solicitar el acceso, corrección, cancelación u oposición al uso de tus datos personales mediante el correo:\nSoporte.snackup@gmail.com\n\n"
      "Al aceptar este documento, autorizas a SnackUp a utilizar tus datos personales únicamente para el registro, autenticación y gestión de pedidos dentro de la aplicación.";

  final String _politicaPrivacidadText = 
      "SnackUp es una aplicación web diseñada para facilitar la gestión de pedidos dentro de una cafetería universitaria. Para poder utilizar el sistema, necesitamos recopilar algunos datos personales básicos.\n\n"
      "Los datos que podremos solicitar incluyen nombre, correo electrónico, matrícula o identificador escolar, contraseña de acceso, rol de usuario y datos relacionados con los pedidos realizados.\n\n"
      "Esta información será utilizada únicamente para crear tu cuenta, validar tu acceso, gestionar tus pedidos, mostrar el estado de tus solicitudes y brindar soporte en caso necesario.\n\n"
      "SnackUp no venderá, rentará ni compartirá tus datos personales con terceros para fines ajenos al funcionamiento de la aplicación. En caso de utilizar servicios externos como bases de datos, autenticación, hosting o pasarelas de pago, tus datos serán tratados únicamente para permitir el funcionamiento técnico del sistema.\n\n"
      "Tus datos personales serán conservados solo durante el tiempo necesario para cumplir con las finalidades de la aplicación. Cuando ya no sean necesarios, podrán ser eliminados, bloqueados o cancelados conforme corresponda.\n\n"
      "Puedes solicitar información, corrección o eliminación de tus datos personales escribiendo al correo:\nSoporte.snackup@gmail.com\n\n"
      "Al aceptar esta Política de Privacidad, confirmas que has leído y comprendido cómo SnackUp recopila, utiliza y protege tus datos personales.";

  // Función para mostrar los diálogos
  void _mostrarDocumento(BuildContext context, String titulo, String contenido) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(titulo, style: const TextStyle(fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Text(contenido, style: const TextStyle(fontSize: 14.0)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text("Cerrar"),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. Resumen
        Container(
          padding: const EdgeInsets.all(12.0),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(8.0),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: const Text(
            "Para crear tu cuenta en SnackUp, necesitamos utilizar algunos datos personales básicos, como tu nombre, correo electrónico y datos relacionados con tus pedidos. Esta información será utilizada únicamente para registrar tu cuenta, permitir el inicio de sesión y gestionar tus pedidos dentro de la cafetería universitaria.\n\nAntes de continuar, revisa y acepta nuestro Documento de Protección de Datos Personales y nuestra Política de Privacidad.",
            style: TextStyle(fontSize: 13.0, color: Colors.black87),
            textAlign: TextAlign.justify,
          ),
        ),
        const SizedBox(height: 10),
        
        // 2. Botones para ver los documentos completos
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            Expanded(
              child: TextButton.icon(
                icon: const Icon(Icons.shield_outlined, size: 18),
                label: const Text(
                  "Protección de Datos", 
                  style: TextStyle(fontSize: 13, decoration: TextDecoration.underline),
                  textAlign: TextAlign.center,
                ),
                onPressed: () => _mostrarDocumento(
                  context, 
                  "Protección de Datos Personales", 
                  _datosPersonalesText
                ),
              ),
            ),
            Expanded(
              child: TextButton.icon(
                icon: const Icon(Icons.privacy_tip_outlined, size: 18),
                label: const Text(
                  "Política de Privacidad", 
                  style: TextStyle(fontSize: 13, decoration: TextDecoration.underline),
                  textAlign: TextAlign.center,
                ),
                onPressed: () => _mostrarDocumento(
                  context, 
                  "Política de Privacidad", 
                  _politicaPrivacidadText
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // 3. Casilla de verificación (Checkbox)
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 24,
              width: 24,
              child: Checkbox(
                value: _isAccepted,
                onChanged: (bool? newValue) {
                  setState(() {
                    _isAccepted = newValue ?? false;
                  });
                  widget.onAccepted(_isAccepted); // Envía el estado al formulario principal
                },
              ),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                "He leído y acepto el Documento de Protección de Datos Personales y la Política de Privacidad de SnackUp. Autorizo el uso de mis datos personales únicamente para el registro, autenticación y gestión de pedidos dentro de la aplicación.",
                style: TextStyle(fontSize: 13.0),
              ),
            ),
          ],
        ),
      ],
    );
  }
}