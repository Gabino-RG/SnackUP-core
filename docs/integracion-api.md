# Integración del cliente de alumnos con FastAPI

## Fuente y separación

Contrato inspeccionado: `origin/codex/backend-api-v3-fastapi`, commit `1c3459bfd58a083acf4a1638c5013db93873f057`. La rama del backend no se modificó ni se fusionó sobre el frontend. Se copiaron únicamente su contrato OpenAPI y guía como referencia a `docs/api/`.

El código activo está en `lib/api/` y `lib/student_api/`. `main.dart` conserva el tema visual y usa ese flujo REST. Se retiraron las dependencias e inicialización de Firebase, el plugin de Google Services de la app y los scripts Firebase de `web/index.html`. El código anterior y sus pruebas se archivaron como `.dart.txt` en `legacy/firebase/`; no se compilan. Los archivos originales `.firebaserc`, `firebase.json` y `firestore.rules` no se modificaron en esta integración y no deben desplegarse para ejecutar este cliente.

No se consultó, migró ni escribió la base real de Firebase. No se copiaron cuentas, contraseñas, menús ni pedidos de Firebase a SQL. El backend y el cliente necesitan cuentas y catálogo SQL autorizados; mantener el proyecto Firebase existente no los crea automáticamente.

## Operaciones y contrato

| Función | Rutas o almacenamiento |
| --- | --- |
| Registro y acceso | `POST /api/v1/auth/register`, `login`, `refresh`, `logout` |
| Recuperación | `forgot-password`, `reset-password`, `resend-verification`; la página del backend confirma el correo |
| Perfil | `GET /api/v1/users/me` |
| Cafeterías y menú | `GET /api/v1/businesses`, `/businesses/{id}/products`, `/products/{id}`; se procesan todas las páginas |
| Carrito, notas y favoritos | Preferencias locales, separadas por URL de API y cuenta. No hay rutas equivalentes en V3 |
| Compra | `POST /api/v1/orders`; UUID de idempotencia persistido antes de enviar, `expectedTotal`, IDs/cantidades/notas; no se envían precios por renglón, identidad ni estado |
| Activos y seguimiento | `GET /api/v1/users/me/orders/active`, `/orders/{id}` |
| Historial completo | `GET /api/legacy/v1/student/orders`; única lectura de compatibilidad, comparte SQL y acepta la sesión V3. Verificado con el backend fijado |
| Cancelación | `POST /api/v1/orders/{id}/cancel`, `expectedVersion`, motivo `user_other`; solo mientras el pedido esté pendiente |
| Restaurante | `POST /api/v1/orders/{id}/rating` |
| Platillo | `POST /api/v1/orders/{id}/reviews`; lecturas `/products/{id}/reviews` |
| Avisos | Socket.IO `/socket.io`, WebSocket Engine.IO 4, `auth.token` y temas autorizados de pedidos/catálogo |

La búsqueda y los destacados se componen de todas las páginas de los menús accesibles. Los productos no disponibles o con stock cero se ocultan. En esta API, **`stock:null` significa sin límite configurado**, por lo que sí se muestra y se puede pedir: no debe confundirse con cero.

## Sesión y privacidad

Solo `ALUMNO` abre este cliente. Una sesión de Cocina/Administración se revoca y se indica utilizar su portal. En web, access token en memoria y refresh únicamente en cookie HttpOnly; las operaciones de sesión se serializan con Web Locks entre pestañas. La renovación verifica que la identidad no haya cambiado antes de aplicar el nuevo token. En nativo se omite Origin y el refresh se guarda en almacenamiento seguro, no en preferencias.

Las URLs no llevan credenciales. Los enlaces de recuperación retiran el fragmento del navegador. El cliente no registra contraseñas, tokens ni códigos de retiro en logs. Los datos personales del pedido se consultan solo con su sesión autorizada. La implementación no acredita recepción de notificaciones push en segundo plano.

## Compras y estados

Una respuesta perdida conserva la misma clave y el mismo body incluso al recargar. El carrito se bloquea mientras la intención es incierta. Las validaciones definitivas permiten revisar el carrito; los errores de transporte/servidor o conflictos de idempotencia no crean automáticamente otra intención. La cesta se persiste vacía antes de retirar el registro del reintento, para evitar una compra duplicada tras una interrupción.

Se reconocen `pending`, `accepted`, `preparing`, `ready`, `completed`, `cancelled`. El QR representa el `pickupCode` del pedido, nunca la matrícula. Solo aparece con estado `ready` confirmado. Al entregar desaparece y se muestra el agradecimiento y la valoración. Un error de actualización no conserva un QR que no se pudo verificar. Las versiones impiden que listados antiguos sobrescriban un pedido más reciente.

Socket.IO invalida datos y vuelve a consultar REST. Al reconectar o volver al primer plano se reconcilian los datos. No se añade polling periódico. Si los avisos no están disponibles, se indica y se ofrece actualización manual. El backend requiere Redis/configuración de eventos para distribuir correctamente avisos entre procesos en producción.

## Diferencias que impone la API existente

- Admite Efectivo y Transferencia. Transferencia queda pendiente de verificación; no se muestra como cobro realizado. Tarjeta y Vale no se ofrecen porque el backend V3 los rechaza.
- No admite programar la hora de recogida: un valor no nulo devuelve `SCHEDULING_NOT_CONFIGURED`.
- Una valoración de restaurante por pedido y una reseña por pedido/platillo. No hay edición ni borrado. La app conserva las estrellas y el comentario; ya no ofrece una falsa promesa de modificar reseñas existentes.
- No se envía un campo de publicación anónima que la API no acepta. Las reseñas públicas de producto no exponen identidad en su DTO; internamente se asocian al autor. No se presentan como anonimato absoluto.
- Carrito y favoritos se guardan en el dispositivo. No se ofrece sincronización entre dispositivos sin un contrato de backend para ello.
- Registro y recuperación dependen del padrón autorizado y SMTP. Un acuse de registro no es una cuenta aprobada ni una confirmación de correo entregado.

## Validación y alcance

Se ejecutó `tools/smoke_backend_api.py` contra una copia del backend con sus dependencias bloqueadas, identidades ficticias y SQLite temporal: 24 comprobaciones correctas, incluida la lectura legacy con un JWT V3, reserva única ante reintento, flujo de Cocina hasta entrega y ambas valoraciones. El reporte omite credenciales y cuerpos privados.

Las pruebas Flutter cubren renovación única concurrente, separación de cuentas, refresh nativo seguro, idempotencia tras recarga, precios cambiados, catálogo paginado, inventario, entrega, calificaciones y ausencia de acceso del personal. Los resultados finales de navegador/build se reportan en la entrega.

Esto no constituye despliegue ni prueba con alumnos reales, SMTP real, carga simultánea, PostgreSQL de producción o un dispositivo nativo. No se ha recibido una URL de API desplegada. La configuración por defecto sirve para desarrollo local o despliegue bajo el mismo origen; no debe describirse como conexión ya verificada al servidor de la universidad.

## Contenedor del cliente

`Dockerfile` genera únicamente el frontend estático, con el builder Flutter fijado que utiliza la rama de alumnos existente y un runtime Caddy sin privilegios en el puerto 8080. Expone `/healthz`, compatible con el servicio `usuarios` de `backend/deploy/compose.apps.yaml`.

En un despliegue de las tres aplicaciones, `SNACKUP_USERS_CONTEXT` debe apuntar al checkout de **esta rama**, sin modificar la rama del backend. El proxy público del backend se conserva: API, medios y Socket.IO se dirigen a FastAPI; `/` al cliente y `/paneles/` a Cocina. No apuntar el cliente a una URL distinta para intentar saltar el origen permitido.

No se construyó ni desplegó una imagen Docker en esta tarea. El build web local y las pruebas con el backend temporal son comprobaciones separadas de un despliegue Docker.

### Resultados de esta integración

- Suite Flutter del cliente: **16 pruebas aprobadas** con transporte HTTP de prueba y widgets.
- Backend FastAPI fijado: **24 comprobaciones aprobadas** con dependencias bloqueadas y SQLite temporal, sin Redis, SMTP ni push externos.
- Análisis Flutter: sin errores ni advertencias; quedan avisos informativos de APIs antiguas y estilo.
- Las pruebas `--platform chrome` no finalizaron con este SDK/entorno local y se detuvieron. No se declaran aprobadas ni equivalentes a pruebas de extremo a extremo con un navegador y servidor real.
- `tools/check_api_web.py` comprueba el build estático, su arranque Flutter y la ausencia del bootstrap de Firebase. El reporte está en `docs/evidence/api-client/web-build.json`.
