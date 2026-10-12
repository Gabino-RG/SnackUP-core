# Verificación de la aplicación integrada

Revisión del 4 de octubre de 2026 (hora de México), rama `test/api-aaa-sonarqube`. La entrada comprobada es `app/lib/main.dart`, con los roles alumno, negocio y administración.

| Comprobación ejecutada | Resultado |
| --- | --- |
| Flutter 3.32.0 / Dart 3.8.0, pruebas unitarias y de widgets | **59 aprobadas**: 14 de administración, 8 de reseñas, 10 de checkout, 12 de auth, 7 de negocio, 4 de arranque y 4 existentes. |
| Análisis global de Dart | 0 errores y 0 advertencias; 124 avisos informativos de estilo/API heredados. |
| Compilación web de `main.dart` con CanvasKit local | Correcta. |
| Arranque de la app completa en Chromium 134 | Login renderizado en escritorio 1440×1100 y móvil 390×844, sin excepciones JavaScript. |
| Herramienta de accesos | 6 pruebas sin red aprobadas; confirma proyecto/UID/correo y conserva claims no relacionados. No se ejecutó `--apply`. |
| Guardas existentes de aislamiento QA | 15 pruebas aprobadas, sin acceder a endpoints. |
| JavaScript del contrato de reglas integrado y JSON de configuración | Sintaxis/estructura correctas; esto **no ejecuta ni compila las reglas de Firebase**. |
| Iniciador PC en Linux | HTTP, MIME JavaScript/WASM, carpeta con espacios, aislamiento de `web/`, puerto ocupado y puerto inválido comprobados. |
| Diff | Sin errores de espacios. |

## Qué acreditan las pruebas

Los casos cubren resolución de roles y revocación de acceso, recuperación del registro parcial, recuperación de contraseña, preservación de espacios de la contraseña y cierre de rutas protegidas. Checkout comprueba datos de carrito manipulados, catálogo actual, confirmación de precio, negocio abierto, mezcla de locales, existencias, límites de renglones/unidades y horario. Negocio verifica transiciones, reserva, QR por pedido y estadísticas por fecha de entrega. Administración verifica indicadores, filtros, interfaz móvil, errores sin sustitución por demo e historial de seguimiento.

La comprobación en navegador usa la **aplicación compilada real**, sin entrar a cuentas. Los cinco módulos públicos de Firebase JS SDK 10.11.1 se descargaron de `www.gstatic.com` y se sirvieron desde caché local del arnés porque este navegador no puede descargarlos directamente. El arnés bloquea toda llamada a backends de proyecto antes de salir a la red; no observó intentos de esas llamadas durante el arranque. No simula respuestas de Auth/Firestore ni concede un rol a la app. Por tanto, acredita el arranque y renderizado, **no un login real ni un pedido contra Firebase**.

Esta comprobación detectó y corrigió un acceso a `Firebase.apps` antes de cargar el SDK web. Se añadió además recuperación visible: si la carga de módulos queda suspendida, el navegador puede recargar la aplicación.

Capturas de la app integrada:

- [Inicio de sesión en escritorio](./admin/capturas/07_login_integrado_escritorio.png).
- [Inicio de sesión en móvil](./admin/capturas/08_login_integrado_movil.png).

## Pendientes que impiden afirmar “100 % funcional en producción”

- Comparar y activar reglas/índices/Storage en el proyecto aprobado; ejecutar `tests/api/app-security.test.mjs` en un entorno aislado autorizado. La suite fue preparada, **no ejecutada**.
- Designar y habilitar la cuenta administrativa y comprobar cuentas reales de los locales.
- Ejecutar el recorrido completo con cuentas autorizadas: alumno compra, negocio acepta/prepara/entrega, alumno califica y administrador consulta/guarda/reabre seguimiento.
- Verificar las imágenes en Storage, cámara del dispositivo, datos históricos y permisos efectivos del servidor.
- Probar el iniciador y navegador directamente en Windows. Este entorno es Linux; el runtime de Windows solo se revisó como archivo del paquete.
- Las pruebas no acreditan cobro electrónico, push con app cerrada, padrón escolar, carga de 2,500 personas ni cumplimiento legal. El alcance efectivo está en [INTEGRACION.md](./INTEGRACION.md).

No hubo despliegue, asignación de privilegios ni escrituras en Firebase real. Los cambios de esta entrega se guardan en la rama de trabajo, no en `main`.
