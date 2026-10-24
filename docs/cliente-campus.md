# Rama de clientes de SnackUP

Rama: `codex/cliente-campus`, basada en `origin/main`. El checkout original y sus cambios locales se conservaron por separado.

## Cambios

- Se retiraron las pantallas de acceso y operación del personal: administración del menú, edición de productos, pedidos de cocina y estadísticas.
- Las cuentas con rol `user` conservan el acceso. Las cuentas de personal no acceden al cliente.
- Inicio, Pedidos, Favoritos y Perfil; búsqueda y carrito disponibles en la cabecera.
- Azul marino #062B50, lima #D9F122, celeste #269DC1, fondo claro y tarjetas blancas redondeadas.
- Se mantienen Firebase Auth, registro, búsqueda, menú por cafetería, favoritos, notas, cantidades, carrito, modalidades de pago existentes, programación de recogida, reordenar y QR con seguimiento.
- Inicio usa los datos existentes de `products` y `businesses`. Las promociones siguen siendo productos con `isFeatured` e `isAvailable`.

## Reseñas

Desde Pedidos > Historial > estrella de un pedido completado:

1. Seleccionar el platillo comprado.
2. Elegir entre 1 y 5 estrellas.
3. Escribir una descripción opcional de hasta 300 caracteres.
4. Elegir si se muestra el nombre públicamente.
5. Enviar la valoración.

Cada reseña se guarda en `reviews/{orderId}_{productId}`. Reenviar actualiza la misma reseña; otros platillos del pedido tienen reseñas independientes. El servicio vuelve a leer el pedido en una transacción y comprueba propietario, estado completado y producto comprado. El detalle del platillo muestra el promedio y las cinco reseñas más recientes.

La opción anónima oculta el nombre en la interfaz pública; el registro conserva `userId` para asociarlo con su propietario.

## Integración

No se modificó ni desplegó Firebase. El archivo `firestore.rules` incorpora las reglas compartidas del proyecto y los permisos de valoraciones; ver `docs/valoraciones-firebase.md` para publicarlos. Antes de publicar, revisar que las reglas permitan las lecturas de productos/reseñas y autoricen escrituras de reseñas solo a su propietario para productos de sus pedidos completados. La comprobación del cliente no sustituye las reglas del servidor.

Los pagos conservan el comportamiento original del proyecto; no se añadieron cobros bancarios, monederos, descuentos ni información nutricional ficticios.

## Verificación

- Análisis de Flutter: sin errores ni advertencias; quedan avisos informativos de APIs antiguas.
- Pruebas incluidas: estrellas y descripción, actualización sin duplicados, diferentes platillos, rechazo de otro usuario, producto ajeno, pedido no entregado, límites de valores y anonimato; acceso exclusivo del cliente; categorías del menú en pantalla móvil.
- Las trece pruebas automáticas pasaron. El primer intento se interrumpió por espacio insuficiente; tras liberarse espacio, se completaron las pruebas y se corrigió un desbordamiento detectado en la pantalla móvil.

- Compilación web completada correctamente (`build/web`).

Para comprobar localmente: `flutter pub get`, `flutter analyze --no-fatal-infos`, `flutter test` y `flutter build web`.



## Entrega y valoración del restaurante

El seguimiento escucha el estado del pedido en tiempo real. Con `ready` se muestra el QR; con `completed` se retiran el QR y las instrucciones de recogida y aparece «¡Gracias por tu compra!» con el botón «Valorar restaurante». Con `cancelled` no se permite recoger ni valorar.

La valoración del local guarda de 1 a 5 estrellas y un comentario opcional de hasta 300 caracteres en `restaurant_reviews/{orderId}`. El restaurante se obtiene del pedido; solo se acepta un pedido completado de su propietario. Reenviar actualiza la misma reseña. La valoración de platillos se conserva por separado. Desde la estrella del historial se puede elegir valorar al restaurante o a un platillo.

Antes de publicar, las reglas de Firestore deben autorizar `restaurant_reviews` al propietario de un pedido completado, conservar la asociación con `businessId` y validar estrellas/comentario en el servidor. No se desplegaron cambios en Firebase.
