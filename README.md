# SnackUP · cliente con Firebase

Rama `codex/cliente-firebase`. Contiene solamente la aplicación de alumnos y conserva Firebase Authentication y Cloud Firestore del proyecto `snackup-8fe96`.

## Funciones conservadas

- Diseño en azul marino, lima y celeste; inicio, menú, búsqueda, favoritos y perfil.
- Detalle de platillos, personalización, notas, carrito y creación de pedidos.
- Historial y seguimiento en tiempo real. El QR solo aparece cuando el pedido está listo; al entregarse se retira y aparece el agradecimiento.
- Valoraciones con estrellas y comentarios para comida y restaurante después de la entrega.
- Ocultación de productos agotados y mensajes que distinguen errores de permisos de problemas de comunicación con Firebase.
- Inicio de sesión y registro de clientes. No incluye pantallas de personal de cafetería.

## Ejecutar

Con Flutter y Dart 3.8 o posterior:

```powershell
git clone --branch codex/cliente-firebase https://github.com/Gabino-RG/SnackUP-core.git
cd SnackUP-core
flutter pub get
flutter run -d chrome
```

Si ya tienes otra rama y quieres conservar ambas versiones, clona esta rama en una carpeta distinta. Las cuentas de la demostración PostgreSQL no son cuentas de Firebase: usa tu cuenta existente del proyecto Firebase.

La configuración Firebase del proyecto se conserva. No se necesita FastAPI, PostgreSQL, SQL Server ni los iniciadores de las ramas SQL. No ejecutes `flutterfire configure` sobre otro proyecto para utilizar esta rama. Para Android necesitas tu archivo local `android/app/google-services.json`, que el repositorio excluye.

## Datos y permisos

Se mantienen las colecciones `users`, `businesses`, `products`, `orders`, `reviews` y `restaurant_reviews`, junto con el carrito y favoritos del usuario. La rama no migra datos ni cambia automáticamente el backend de Firebase. Iniciar y utilizar la app sí consulta y guarda datos con tu sesión según las funciones que uses.

Se verificó una lectura de productos del Firebase real con respuesta HTTP 200, sin modificar datos. No se desplegaron reglas, índices ni funciones. `firestore.rules` conserva la propuesta existente; su presencia en Git no significa que esté publicada. Para guardar valoraciones, las reglas publicadas deben permitir `reviews` y `restaurant_reviews`. Consulta `docs/valoraciones-firebase.md` si aparece `permission-denied`.

Las pruebas usan Firestore simulado, sin conectarse al proyecto real. Esta rama recupera la implementación Firebase del cliente previa a la integración REST y conserva sus funcionalidades; las ramas PostgreSQL y de la API permanecen separadas. No se modifica `main`.
