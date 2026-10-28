# Cliente con la base Firebase existente

Esta rama se llama `codex/cliente-firebase` y recupera la implementación Firebase del cliente en `74277fd`, anterior a la integración REST. La aplicación utiliza Firebase Authentication y Cloud Firestore del proyecto real `snackup-8fe96`; no usa emuladores, datos de demostración ni un servidor PostgreSQL.

Se conservan el diseño del campus, acceso de usuarios, catálogo, búsqueda, favoritos, personalización y notas del carrito, pedidos, historial, seguimiento, ocultación de agotados, retiro del QR al entregar, agradecimiento y valoraciones de comida y restaurante con estrellas y comentarios. No se incorporan pantallas de cocina o administración.

La configuración de Firebase y las colecciones existentes no se migraron ni se modificaron. Se comprobó una petición de solo lectura a `products` en el proyecto real con respuesta HTTP 200 y un documento recibido; no se guardó su contenido en este informe. No se inició sesión con cuentas reales ni se crearon pedidos o reseñas de prueba en Firebase. Los permisos de escritura de valoraciones dependen de las reglas ya publicadas, según `valoraciones-firebase.md`.

Pasaron 13 pruebas automáticas que verifican el cliente y las transiciones de entrega. Esas pruebas usan Firestore simulado para evitar escribir en tu base real; la aplicación utiliza `FirebaseFirestore.instance` y `FirebaseAuth.instance`, sin configuración de emuladores.

Para utilizar esta rama: `flutter pub get` y `flutter run -d chrome`. Usa las cuentas existentes de Firebase. No necesitas los iniciadores ni los accesos de las ramas SQL. Las ramas PostgreSQL, API y `main` permanecen separadas.
