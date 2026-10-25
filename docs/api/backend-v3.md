# SnackUP V3: implementación en Python y FastAPI

Esta guía describe el backend implementado a partir de `SnackUP_API_V3_Consolidada.md` (versión documental 3.1, 22 de octubre de 2026) y del `schema.prisma` adjunto. La adaptación conserva **Python, FastAPI, SQLAlchemy, Alembic, PostgreSQL y Redis**. Socket.IO se incorpora mediante su servidor Python ASGI. Prisma se entrega como mapa relacional completo, con nombres en español, y no participa en las escrituras de la aplicación.

El contrato ejecutable es [contracts/v3.openapi.json](contracts/v3.openapi.json). Los esquemas de entrada rechazan campos no reconocidos; las respuestas y errores se documentan con sus formas reales. `/api/docs` y `/api/openapi.json` están disponibles en desarrollo. En producción se distribuye el archivo versionado del contrato.

## 1. Versiones, alcance y decisiones de adaptación

| Superficie | Ubicación | Uso |
|---|---|---|
| REST V3 | `/api/v1` | Integraciones nuevas de Alumno, Cocina y Administración; roles `ALUMNO`, `COCINA`, `ADMIN`. |
| REST de compatibilidad | `/api/legacy/v1` | Paneles actuales y extensión anterior del alumno; conserva nombres y reglas del contrato anterior. |
| Socket.IO V3 | `/socket.io` | Engine.IO 4, transporte WebSocket, autenticación mediante `auth.token`. |
| WebSocket anterior | `/api/legacy/v1/realtime` | Protocolo nativo que ya consumen los paneles; no es Socket.IO. |
| Imágenes | `/media/{filename}` | Archivos validados y recodificados, con nombres generados por el servidor. |
| Salud | `/health/live`, `/health/ready` | Vida del proceso y disponibilidad de sus dependencias. |

Los dos contratos REST comparten usuarios, sesiones, locales, inventario, pedidos y servicios transaccionales. Las versiones no mantienen copias separadas de los datos. Un pedido V3 puede ser atendido desde Cocina anterior, incluidos `Transferencia` y el código alfanumérico nuevo. El build del portal anterior se configura con `/api/legacy/v1/`.

**Cambio de integración:** los clientes que antes llamaban al contrato anterior en `/api/v1` deben pasar a `/api/legacy/v1` al desplegar esta versión. Publicar backend y configuración de los paneles en la misma ventana. Los clientes V3 utilizan `/api/v1` desde el principio.

| Tema del documento recibido | Resolución implementada |
|---|---|
| NestJS, guards y DTOs | Routers FastAPI, dependencias de autorización, modelos Pydantic y servicios Python compartidos. |
| Prisma como ORM | SQLAlchemy es el ORM existente. Alembic es la única autoridad de migraciones. `schema.prisma` refleja las tablas reales mediante `@map` y `@@map`. |
| Registro `201 {user,tokens}` y titularidad de correo pendiente | `202 {"status":"received"}` sin sesión. La cuenta solo puede acceder después de confirmar el correo con un token de un uso. Se conserva la protección de identidad ya implementada. |
| Fuente institucional | Padrón autorizado importado al PostgreSQL local. No hay llamadas a una universidad externa en cada login. La baja local del padrón sí bloquea acceso y revoca sesiones. |
| Nombre del alumno enviado al registrar | Se recibe el campo para compatibilidad de contrato, pero el nombre guardado proviene del padrón autorizado. Tampoco se aceptan carrera, grupo ni privilegios del cliente. |
| Alta/edición de Cocina sin payload definitivo | Se implementan los DTOs explícitos de esta guía, la creación atómica de negocio y cuenta, y las rutas administrativas propuestas por el documento. |
| Roles históricos en SQL | Se conservan `user`, `business`, `admin`, `pending` y sus restricciones. La frontera V3 y sus JWT traducen los tres roles autorizados; `pending` no es un rol público autorizado. Una cuenta inactiva con ese rol y correo aún no verificado puede recuperar el registro de alumno únicamente tras validar el padrón y confirmar la propiedad del correo. |
| IDs de Firebase | Identificadores públicos `TEXT`; se conservan valores antiguos. Los IDs nuevos son UUID representados como strings. Los clientes no deben exigir formato UUID a recursos existentes. |
| Códigos de entrega | Pedidos V3: seis caracteres aleatorios, índice único parcial y reintento de colisión. Códigos antiguos de ocho dígitos: se conservan sin truncar. La entrega siempre comprueba el código contra el pedido solicitado. |
| Importe, calificaciones y contadores | Importes en `NUMERIC`, cálculo con `Decimal`; agregados consultados en el servidor. No se aceptan `total`, `averageRating`, `totalOrders` ni `isRated` como datos del cliente. |
| `scheduledPickupTime` sin política operativa | Se admite `null`; un valor no nulo devuelve `422 SCHEDULING_NOT_CONFIGURED`. Los valores históricos se conservan. |
| Contrato V2 no recibido | Paginación, reseñas y DTOs de administración quedan definidos explícitamente aquí y en OpenAPI. Solo se habilita `user_other` entre los motivos estudiantiles mencionados por V3. No se inventa un catálogo V2 adicional. |
| Transferencia | Es un método registrado con estado `unverified`. No hay pasarela, comprobación bancaria ni confirmación de cobro. |
| Migración Firebase | Esta entrega actualiza el backend SQL existente. No importa ni elimina datos de una cuenta Firebase real y no transforma hashes de contraseña externos. |

## 2. Identidad, sesiones y permisos

Las rutas abreviadas de esta guía son relativas al prefijo canónico `/api/v1`.

### Registro y verificación

```http
POST /api/v1/auth/register
Content-Type: application/json

{
  "email": "alumno@students.example.edu",
  "password": "<contraseña privada de 12 a 128 caracteres>",
  "displayName": "Nombre del formulario",
  "numeroDeControl": "MATRICULA-AUTORIZADA"
}
```

Los dominios de ejemplo no son configuración institucional real. Se requiere SMTP, dominio estudiantil permitido y coincidencia exacta entre correo y matrícula en un registro activo del padrón. Una respuesta `202` es un acuse genérico: no confirma públicamente que esa identidad exista. No entrega tokens. Repetir el registro no cambia la contraseña ni los privilegios de una cuenta ya establecida.

El enlace de correo lleva el token en el fragmento `#token=...`. La página retira el fragmento y solicita una confirmación explícita. `POST /auth/verify-email {"token":"..."}` consume el token y habilita el acceso correspondiente. No se confirma por un GET ni por abrir automáticamente un enlace. Los tokens se almacenan como hash; los datos temporales de registro nunca contienen contraseñas en claro.

| Operación | Resultado principal |
|---|---|
| `GET /auth/options` | Capacidades de autenticación anunciadas por el servidor. Google sigue deshabilitado. |
| `POST /auth/register` | `202`, registro estudiantil sujeto a padrón y verificación. |
| `POST /auth/verify-email` | `204`, confirmación de un uso. |
| `POST /auth/resend-verification` | `202`, acuse genérico y reenvío cuando corresponde. |
| `POST /auth/login` | `200 {user,tokens}`. |
| `POST /auth/refresh` | `200 {tokens}`, rotación de refresh. |
| `POST /auth/logout` | `204`, revoca la familia de sesión y retira sus dispositivos registrados. |
| `POST /auth/forgot-password` | `204` genérico si el servicio de correo está disponible. Un fallo de servicio devuelve `503`. |
| `POST /auth/reset-password` | `204`, cambia contraseña, consume token y revoca sesiones anteriores. |
| `GET /users/me` | Perfil propio con rol canónico y versión. |
| `PATCH /users/me` | Actualiza `avatarUrl` propio con `expectedVersion` obligatorio. |

### Web y aplicaciones nativas

El access token vence por defecto en 15 minutos. Cada refresh emitido vence por defecto 30 días después de su emisión; al rotarlo comienza un nuevo plazo. La base almacena su hash, familia, sesión sustituta, expiración y revocación. Reutilizar un refresh ya rotado revoca la familia; las peticiones concurrentes del cliente deben coordinar una sola renovación.

En navegador, enviar el `Origin` del mismo sitio y permitir cookies. El refresh viaja exclusivamente en cookie `HttpOnly; Secure; SameSite=Strict` en producción, con ruta `/api`; no aparece en JSON. Login, refresh y logout comprueban el origen. Refresh y logout admiten cuerpo ausente o `{}` y rechazan un `refreshToken` en JSON cuando se envía `Origin`. El access token se mantiene en memoria. La cookie no utiliza `Secure` cuando el origen local configurado es HTTP de desarrollo.

En una app nativa, omitir `Origin`: login devuelve el refresh en JSON y las siguientes renovaciones/cierre envían `{"refreshToken":"..."}`. Guardarlo en almacenamiento seguro. Una petición de refresh/logout que dependa de la cookie y omita `Origin` se rechaza. Las rutas privadas siguen usando `Authorization: Bearer <accessToken>`.

Los JWT V3 incluyen `sub`, `role`, `sid`, `ver`, `exp`, `iss`, `aud` y `bid` para Cocina. Los permisos se verifican también contra el estado vigente de la cuenta, sesión, padrón y negocio; no basta con confiar en un rol antiguo del token. Las escrituras revalidan el acceso después de los bloqueos relevantes.

### Administración

```http
POST /api/v1/admin/businesses
Authorization: Bearer <accessTokenAdmin>
Content-Type: application/json

{
  "name": "Local de ejemplo",
  "category": "Cafetería",
  "description": "Descripción del local",
  "timezone": "America/Mexico_City",
  "account": {
    "email": "cocina@staff.example.edu",
    "displayName": "Responsable del local",
    "password": "<contraseña inicial privada>"
  }
}
```

La respuesta es `201 {business,user}`. Se crea un local activo, inicialmente cerrado, y una cuenta Cocina autorizada en la misma transacción. El administrador es responsable de comprobar la identidad y entregar la contraseña inicial por el procedimiento privado acordado. Este alta administrativa marca la cuenta como verificada; no simula un correo SMTP. La imagen se sube después de crear el negocio y se vincula mediante PATCH.

`GET /admin/businesses`, `GET /admin/businesses/{id}`, `PATCH /admin/businesses/{id}`, `GET /admin/users`, `PATCH /admin/users/{id}` y `POST /admin/users/{id}/reset-password` completan la gestión. La edición de cuentas no cambia arbitrariamente rol ni local y protege las cuentas administrativas/maestras. Cambiar una cuenta revoca sus sesiones. La recuperación de contraseña utiliza SMTP.

`DELETE /admin/businesses/{id}` es una baja lógica. Rechaza negocios con pedidos `pending`, `accepted`, `preparing` o `ready`. Cuando procede, cierra el local, desactiva Cocina y revoca sesiones/dispositivos, conservando pedidos y auditoría. Un índice parcial garantiza una sola cuenta Cocina activa y aprobada por negocio; no se impone una unicidad global que impida conservar operadores inactivos históricos.

La primera cuenta maestra se crea mediante `python -m snackup.cli create-master`, con contraseña solicitada sin eco. No existe bootstrap público ni contraseña predeterminada. Continúan disponibles las funciones previas de padrón, solicitudes, opiniones académicas y seguimiento administrativo. El contrato anterior conserva su política adicional de cuenta maestra.

## 3. Catálogo, inventario y pedidos

### Catálogo e imágenes

El alumno consulta `GET /businesses`, `GET /businesses/{id}`, `GET /businesses/{id}/products` y `GET /products/{id}`. Cocina queda limitada a su local. Los listados aceptan la paginación documentada; productos permiten filtros de disponibilidad, categoría, búsqueda `q` y proyección `fields` sobre una lista autorizada.

Cocina utiliza `PATCH /businesses/{id}`, `PATCH /businesses/{id}/status`, `POST /businesses/{id}/products`, `PATCH /products/{id}`, `PATCH /products/{id}/availability` y `DELETE /products/{id}`. La eliminación de productos es lógica. `isOpen` es el interruptor que permite recibir pedidos; cerrar el negocio no cancela pedidos ya aceptados.

Los productos añaden `subcategory`, `preparationMinutes`, `calories`, `deletedAt` y disponibilidad manual interna. `stock=null` significa inventario no controlado. `stock=0` hace que la disponibilidad efectiva sea falsa. Una reposición no anula una pausa manual: el servidor conserva `manual_available` por separado. Los productos migrados que ya estaban indisponibles permanecen pausados hasta revisión de Cocina, pues el esquema anterior no permite distinguir la causa original.

### Crear un pedido

```http
POST /api/v1/orders
Authorization: Bearer <accessTokenAlumno>
Idempotency-Key: 0c2d6354-3ee7-41ee-9c68-ec1fdf174150
Content-Type: application/json

{
  "businessId": "id-opaco-del-negocio",
  "items": [{"productId":"id-opaco-del-producto","quantity":2,"notes":"Sin cebolla"}],
  "paymentMethod": "Efectivo",
  "expectedTotal": 71.00
}
```

`expectedTotal` se obtiene de los precios que mostró el cliente y sirve para detectar cambios. El servidor vuelve a leer los productos, comprueba pertenencia, disponibilidad y existencias, y calcula el total con `Decimal`. Si el importe cambió, devuelve `409 PRICE_CHANGED` con `details.currentTotal` y no reserva inventario. Se rechazan productos repetidos, cantidades no enteras o no positivas, campos monetarios/identidades impuestos por el cliente y productos de otro local.

La creación bloquea las filas necesarias, reserva existencias, asigna un consecutivo por negocio, guarda snapshots de productos/precios/cliente, crea la clave de idempotencia, registra la transición y escribe el outbox en una sola transacción. El cambio de `totalOrders` también incrementa `Business.version`/`updatedAt` y emite `business.updated`. `orderNumber` no se reinicia por día. Repetir la misma clave UUID con un payload equivalente devuelve el resultado original sin volver a incrementar contadores ni emitir avisos; reutilizarla con otro payload devuelve `409 IDEMPOTENCY_CONFLICT`. Ante timeout o respuesta incierta, el cliente conserva la clave: generar otra puede crear un segundo pedido legítimo.

`Efectivo` guarda `paymentStatus=pay_at_pickup`; `Transferencia` guarda `paymentStatus=unverified`. Completar la entrega no equivale a verificar una transferencia. No hay cálculo de impuestos/descuentos externos ni pasarela de cobro.

### Estados, cancelación y entrega

| Estado actual | Acción | Estado resultante | Quién puede realizarla |
|---|---|---|---|
| `pending` | `/orders/{id}/accept` | `accepted` | Cocina del negocio |
| `accepted` | `/orders/{id}/start` | `preparing` | Cocina del negocio |
| `preparing` | `/orders/{id}/ready` | `ready` | Cocina del negocio |
| `ready` | `/orders/{id}/complete` | `completed` | Cocina con código correcto |
| `pending` | `/orders/{id}/cancel` | `cancelled` | Alumno propietario o Cocina |
| `accepted`, `preparing` | `/orders/{id}/cancel` | `cancelled` | Cocina |

Las acciones son POST. No hay un PATCH libre para asignar cualquier estado. `ready`, `completed` y `cancelled` no se cancelan por estas rutas. Las transiciones concurrentes se serializan; una reserva se devuelve como máximo una vez. Se utiliza la cantidad realmente reservada en cada ítem, aunque posteriormente cambie la política de stock del producto. La cancelación bloquea negocio antes de productos, igual que catálogo y creación, para evitar la inversión entre reposición e inventario; se prueba la intercalación con PostgreSQL real.

Las mutaciones aceptan `expectedVersion` opcional, salvo los contratos que lo exigen expresamente como el perfil propio. Se recomienda enviarlo. Si no coincide, `409 VERSION_CONFLICT` obliga a recargar; omitirlo no elimina las reglas transaccionales de estado e inventario.

Alumno cancela con `{"reason":"user_other","notes":"Motivo de la cancelación","expectedVersion":1}`. Cocina admite `product_unavailable`, `cannot_prepare`, `store_issue`, `store_closing`, `other`; `other` requiere notas. Ambos perfiles reciben `422 INVALID_CANCEL_REASON` si el motivo no pertenece a su catálogo.

La entrega recibe `{"method":"qr","code":"A7X9B2","expectedVersion":4}` o `method=manual`. Ambos métodos verifican el mismo secreto del pedido. El QR representa ese código y no contiene matrícula. El código solo aparece en la respuesta del alumno propietario; se omite en DTOs y eventos de Cocina. Un código incorrecto deja el pedido en `ready`, produce `422 VERIFICATION_FAILED` y registra auditoría sin guardar el código intentado. Hay límite de diez intentos por operador/pedido/minuto.

### Consultas, fechas y reconciliación

`GET /orders/{id}` respeta propiedad/pertenencia. `GET /users/me/orders/active` consulta los pedidos activos propios. Cocina usa `GET /businesses/{id}/orders/active`, `GET /businesses/{id}/orders/history?date=YYYY-MM-DD` y `GET /businesses/{id}/stats?from=YYYY-MM-DD&to=YYYY-MM-DD`.

Las fechas se guardan y transmiten en UTC; los rangos diarios se calculan con la zona del negocio. Historia incluye pedidos terminados/cancelados y `summary: {completed,cancelled,totalSold}`; las estadísticas cuentan ventas completadas. No se presentan pedidos pendientes como ventas.

Con `updatedSince` en los listados activos, se devuelven también transiciones terminales desde esa fecha: el cliente puede retirar tarjetas completadas/canceladas. Sin `updatedSince` se devuelven solo activos. El cliente procesa todas las páginas, deduplica por ID/versión y no avanza su marca temporal hasta terminar la reconciliación. Al reconectar también puede hacer una recarga completa de activos. No se incorpora polling HTTP periódico automático al protocolo V3.

Los listados devuelven `{"data":[],"pagination":{"page":1,"limit":20,"total":0,"totalPages":0}}`; consultar el límite de cada ruta en OpenAPI. Los errores usan `{"error":{"code":"...","message":"...","details":...}}`, con `details` opcional. Las validaciones no devuelven contraseñas ni valores sensibles del body.

## 4. Calificaciones y reseñas

El documento recibido remitía los payloads exactos a un V2 no adjunto. Esta implementación define una extensión explícita:

```http
POST /api/v1/orders/{id}/rating

{"rating":4,"comment":"Opinión del servicio","foodRating":5,"serviceRating":4}
```

`rating` es obligatorio; `comment` y los dos puntajes específicos son opcionales. Los puntajes son enteros de 1 a 5. Solo el alumno propietario puede calificar un pedido completado, una vez. La calificación de negocio reutiliza la tabla anterior `reviews`: mantiene las referencias y snapshots académicos y sigue siendo visible en el panel de opiniones y seguimiento. No se crea una tabla paralela que pierda esas relaciones. `isRated` del pedido se deriva de esta calificación.

```http
POST /api/v1/orders/{id}/reviews

{"reviews":[{"productId":"id-del-producto-comprado","rating":5,"comment":"Opinión del producto"}]}
```

Solo se permiten productos incluidos en ese pedido completado y una reseña por par pedido/producto. El lote es atómico: si un ítem no es válido, no se guarda ninguno. Los comentarios admiten hasta 2,000 caracteres. `GET /products/{id}/reviews` expone reseñas paginadas sin identidad, matrícula, correo ni ID del pedido del autor. Cocina solo puede consultar su negocio.

Los promedios y contadores se calculan a partir de filas confirmadas. Las reseñas de producto y la calificación de negocio son independientes: reseñar un producto no marca automáticamente `isRated`. La edición/eliminación de reseñas, moderación y vinculación de fotografías a una reseña requieren un contrato adicional; no se simulan mediante campos sin persistencia.

## 5. Archivos y propiedad

`POST /media` usa `multipart/form-data` con `file`, `purpose` y, cuando corresponde, `businessId`. Los propósitos admitidos son `product`, `business`, `avatar`, `review`. Cocina gestiona imágenes de su local y productos; Administración puede cargar la imagen de un negocio identificado; cada cuenta gestiona su avatar; el alumno puede cargar medios destinados a reseñas.

La API acepta JPEG, PNG y WebP de hasta 5 MiB, decodifica el contenido, comprueba que coincida con su MIME declarado, limita el tamaño descomprimido, normaliza orientación y recodifica a WebP con máximo 1600 × 1600. La respuesta es `{id,url,width,height}`. No se confía en el nombre original del archivo.

Para asociar una URL a producto/negocio/avatar, el servidor comprueba el registro del archivo, propósito, propietario o negocio y ausencia de baja. Una URL externa o una imagen de otra cuenta no sustituye esta autorización.

`DELETE /media/{id}` devuelve `204` si la persona está autorizada y la imagen ya no está asociada a un recurso. Mientras esté en uso devuelve `409 MEDIA_IN_USE`. La baja es lógica en SQL y el archivo se retira después del commit. Un upload cuya transacción falla elimina su archivo provisional. La limpieza tras caídas abruptas del proceso requiere mantenimiento operativo: disco y PostgreSQL no forman una única transacción distribuida.

Las imágenes servidas por `/media` son recursos públicos de presentación con nombres no predecibles. No deben utilizarse como almacén de documentación institucional, comprobantes privados ni credenciales. Una imagen con `purpose=review` se conserva como medio del alumno, pero no se añade silenciosamente al DTO de reseñas, cuyo contrato fotográfico no estaba definido.

## 6. Socket.IO y notificaciones

### Conexión y salas

Ejemplo de cliente JavaScript equivalente a la configuración de `socket_io_client` en Flutter:

```javascript
const socket = io(origin, {
  path: '/socket.io',
  transports: ['websocket'],
  auth: {token: accessToken}
});
socket.on('connect', () => {
  socket.emit('subscribe', {topics: [`user:${userId}:orders`]}, ack => {
    if (ack.ok) reconcileMyOrders();
  });
});
socket.on('order.updated', event => reconcileOrder(event.data.id));
```

El gateway autentica el JWT antes de aceptar la sesión Socket.IO y permite diez segundos como máximo para completar la autenticación inicial. `subscribe` y `unsubscribe` reciben `{topics:[...]}` y responden mediante ACK `{ok:true,topics:[...]}` o un error. No colocar tokens en query strings. Los mensajes no reconocidos y el exceso de solicitudes se rechazan. La validación se repite periódicamente y antes de entregar eventos, de modo que logout, baja institucional, desactivación, reasignación o expiración retiren el acceso.

| Tema | Acceso |
|---|---|
| `user:{userId}:orders` | Solo el alumno propietario. |
| `business:{businessId}:orders` | Solo Cocina de ese negocio. |
| `business:{businessId}:products` | Catálogo de negocio activo; Cocina limitada a su local. |
| `business:{businessId}` | Estado de negocio activo; Cocina limitada a su local. |

Se aceptan los aliases `room_user_{id}` y `room_business_{id}` del documento, que se normalizan a los temas de pedidos respectivos. Administración no obtiene códigos de entrega ni acceso automático a las salas privadas de pedidos.

Los eventos `order.created`, `order.updated`, `product.updated` y `business.updated` usan `{id,type,topic,occurredAt,data}`. `id` identifica el evento; `data.id` identifica el recurso cuando corresponde, y `data.version` permite descartar información anterior. Son avisos mínimos: REST devuelve la representación completa. Código de retiro, matrícula, correo, tokens y credenciales no se incluyen en eventos o push de Cocina.

La escritura del outbox comparte transacción con el cambio de negocio. Los cambios de productos y las reservas/reposiciones realizados desde el portal legacy también emiten los eventos de catálogo que consume V3. Redis distribuye los eventos entre procesos. El outbox conserva reintentos de publicación y el worker espera la confirmación de su suscripción Redis al iniciar. La entrega puede repetirse: deduplicar por ID del evento y versión. Al renovar el access token, actualizar `auth.token` y reconectar; no cambiar privilegios de una conexión existente.

### Dispositivos y entrega push

```http
POST /api/v1/users/me/devices
Authorization: Bearer <accessToken>
Content-Type: application/json

{"platform":"android","provider":"fcm","token":"<token privado del dispositivo>"}
```

Plataformas: `android`, `ios`, `web`. Proveedores: `fcm`, `apns` (solo iOS), `webpush` (solo web). Para Web Push, `token` es el JSON serializado de `PushSubscription.toJSON()`, con endpoint y claves válidos. Solo se permiten endpoints HTTPS de hosts autorizados; no se aceptan redirecciones, IPs arbitrarias, credenciales en URL ni destinos internos.

El registro devuelve `201` si es nuevo o `200` si ya pertenece al mismo usuario, con metadatos y sin devolver el token. Un token no puede apropiarse desde otra cuenta. La unicidad utiliza un hash de tamaño fijo; Web Push canoniza el endpoint para que cambiar el orden de las claves JSON no evite la comprobación. `DELETE /users/me/devices/{id}` comprueba propiedad. Logout elimina los dispositivos asociados a esa familia de sesión.

Cada evento apto genera entregas persistentes por dispositivo. El worker usa leases, reintentos con espera, detección de dispositivos revocados y descarte de avisos cuyo estado de pedido ya fue superado. Estados de entrega: `pending`, `sending`, `retry`, `unconfigured`, `sent`, `dead`, `cancelled`. Un proveedor que acepta el mensaje permite marcar `sent`; eso no prueba que una persona lo haya recibido o leído. Un resultado de red incierto puede provocar duplicados, por lo que el cliente debe deduplicar `eventId`.

Hay adaptadores reales para FCM HTTP v1 con credenciales de servicio, APNs con clave `.p8` y JWT ES256, y Web Push con VAPID y cifrado. Se prueban sus contratos con transportes de ensayo. **No se han proporcionado credenciales reales ni se ha verificado la recepción en un dispositivo externo.**

Activar `SNACKUP_PUSH_ENABLED=true` y configurar el proveedor elegido. [compose.push.example.yaml](compose.push.example.yaml) muestra montajes de credenciales de solo lectura; `.env.example` enumera las variables. Con push deshabilitado o credenciales incompletas, no se finge un envío: las entregas quedan `unconfigured` con reintento espaciado. Un envío ya aceptado o en vuelo no puede retirarse retroactivamente al cerrar sesión.

## 7. Modelo SQL y mapa Prisma

El archivo [schema.prisma](schema.prisma) es una referencia **Prisma 7** generada de los modelos SQLAlchemy. Contiene 23 tablas, 259 columnas y 43 claves foráneas. No instala un cliente Prisma ni exige Node para ejecutar el backend. No ejecutar `prisma migrate`, `db push` o `db pull` como procedimiento de despliegue sobre esta base; las migraciones se aplican con Alembic.

| Área | Modelos Prisma | Tablas Python/PostgreSQL |
|---|---|---|
| Identidad | `Usuario`, `Carrera`, `GrupoAcademico`, `RegistroInstitucional` | `users`, `careers`, `academic_groups`, `academic_records` |
| Accesos previos | `SolicitudAcceso`, `DecisionAcceso` | `access_requests`, `access_decisions` |
| Credenciales | `TokenVerificacion`, `RefreshToken`, `Dispositivo` | `verification_tokens`, `refresh_sessions`, `devices` |
| Catálogo | `Negocio`, `Platillo` | `businesses`, `products` |
| Compra y auditoría | `Pedido`, `DetallePedido`, `EventoPedido`, `ClaveIdempotencia` | `orders`, `order_items`, `order_transitions`, `idempotency_records` |
| Opiniones | `Resena`, `CalificacionNegocio`, `SeguimientoOpinion`, `EventoSeguimiento` | `product_reviews`, `reviews`, `followups`, `followup_events` |
| Medios y operación | `Medio`, `EventoAuditoriaCuenta`, `EventoSalida`, `EntregaPush` | `media_files`, `account_audit_events`, `outbox_events`, `push_deliveries` |

El mapa conserva los campos existentes de permisos, padrón y seguimiento que no aparecían completos en el esquema adjunto. No reemplaza `reviews` ni rompe sus referencias. Agrega reseñas de producto, dispositivos, auditoría administrativa y cola de entregas push. Las relaciones de reemplazo de refresh tokens y asociación a dispositivos incluyen su comportamiento de borrado.

Los valores por defecto que calcula Python se documentan como tales; no se inventan defaults SQL ni `@updatedAt` que cambiarían el comportamiento real. Los estados almacenados como VARCHAR permanecen strings en Prisma, con sus restricciones SQL anotadas. Las restricciones `CHECK` y los índices parciales se describen en el mapa y se implementan en Alembic. En particular, no se sustituye la unicidad parcial de Cocina activa por `negocioId @unique`, ni la de códigos nuevos por una unicidad global que rechace códigos históricos repetidos.

Para regenerar y verificar los contratos desde `backend/`:

```bash
python tools/export_prisma_reference.py
python tools/export_prisma_reference.py --check
python tools/export_v3_openapi.py
python tools/export_v3_openapi.py --check
python -m alembic check
```

Las pruebas comprueban cobertura de tablas, columnas, relaciones y estabilidad de la regeneración. El archivo Prisma se valida además con CLI Prisma 7 en un entorno de herramientas separado del runtime Python.

## 8. Migración y actualización de una instalación existente

La revisión `0002_v3` parte de `0001_initial`. Es una migración de datos existentes, no solo una creación de tablas para instalaciones vacías. Los tests construyen una base V1 poblada, aplican la migración y comparan **todas las columnas históricas de todas las tablas**, además de probar restricciones y los campos nuevos, en PostgreSQL y SQLite.

Se conservan contraseñas, IDs, roles históricos, sesiones, códigos de retiro, pedidos, detalles, reservas, snapshots académicos, opiniones, seguimientos, decisiones de acceso, idempotencia y outbox. Los cambios de tamaño amplían cadenas sin reescribir su contenido. Los tópicos del outbox pasan a TEXT para aceptar IDs antiguos largos.

Los backfills se limitan a datos demostrables: matrícula desde el padrón local; `subtotal=total`; `verified_at=completed_at` cuando existía método de verificación; `updated_at=created_at` para registros que antes carecían de ese campo; medios anteriores con propósito `product`; disponibilidad manual inicial igual a la disponibilidad anterior. No se inventan fechas históricas de verificación institucional, último login, borrado, autor de una imagen ni snapshots académicos de un pedido antiguo.

Procedimiento para una instalación real:

1. Preparar la versión de backend y el build de paneles con base legacy; revisar los contratos de la aplicación del alumno que vaya a utilizar V3.
2. Ensayar la migración con una copia de la base y medios, incluida la restauración del respaldo. Registrar commit, revisión Alembic y versiones/digests del despliegue.
3. Abrir una ventana de mantenimiento y detener las escrituras y workers que puedan cambiar pedidos, inventario o sesiones. No migrar mientras una versión anterior siga atendiendo escrituras.
4. Ejecutar `sh deploy/backup.sh /ruta/privada/de/respaldos`, conservar los checksums y copiar el respaldo fuera del servidor.
5. Con el código nuevo, ejecutar `python -m alembic upgrade head` y `python -m alembic check`; en Compose, usar el servicio explícito `migrate` antes de levantar la API nueva.
6. Arrancar API, workers y paneles con sus nuevas bases. Verificar readiness, login, consulta/operación de un pedido controlado, stock, código de entrega, imágenes, opiniones y reconexión de Socket.IO.
7. Finalizar mantenimiento cuando la comprobación funcional y de integridad haya terminado. Conservar el respaldo según la política acordada.

**Reversión:** no hay downgrade automático destructivo de `0002_v3`. Eliminar tablas nuevas o reducir TEXT a VARCHAR perdería datos o haría inválidos IDs posteriores. El downgrade se detiene con un mensaje explícito. Para volver al estado anterior, detener escrituras, restaurar el respaldo comprobado en una base vacía y un volumen de medios correspondiente, desplegar el commit anterior y reconfigurar el tráfico. Cualquier operación realizada después del respaldo necesita reconciliación antes del retorno; no se promete conservarla mediante una restauración simple.

No se ha ejecutado este procedimiento contra una instalación de producción ni contra un proyecto Firebase real. El padrón, dominios y datos universitarios siguen pendientes de provisión autorizada.

## 9. Pruebas, infraestructura y límites de la entrega

Las suites V3 cubren registro y recuperación, sesiones web/nativas, replay de refresh, propiedad y roles, altas administrativas atómicas, catálogo, totales, idempotencia concurrente, sobreventa, carrera cancelación/aceptación, reserva/restitución, código de entrega, bajas, reseñas, privacidad, medios, migración poblada, dispositivos, reintentos push y protocolo Socket.IO real. Las pruebas con PostgreSQL son necesarias para demostrar bloqueo de filas; SQLite solo complementa la cobertura de desarrollo.

La suite usa PostgreSQL y Redis aislados cuando se configuran `SNACKUP_TEST_DATABASE_URL` y `SNACKUP_TEST_REDIS_URL`. Cada prueba SQL crea un esquema propio. Redis se usa de forma explícita en las pruebas de broker, límites distribuidos y gateways; no se presenta toda prueba funcional como una prueba de infraestructura distribuida.

```bash
python -m ruff check snackup tests tools deploy load
python -m pytest -q --junitxml=reports/pytest-postgres.xml
python tools/export_prisma_reference.py --check
python tools/export_v3_openapi.py --check
```

El workflow [backend.yml](../.github/workflows/backend.yml) ejecuta PostgreSQL 17 y Redis 7.4, valida migraciones y contratos, construye contenedores sin root y arranca Compose en un entorno de CI. Verificar siempre el resultado del commit concreto. El informe [VALIDACION_V3.md](VALIDACION_V3.md) registra qué se ejecutó para esta entrega y sus límites.

El escenario [load/students.js](load/students.js) utiliza REST V3, `expectedTotal`, UUID de idempotencia, cookie de renovación web y cancelación estudiantil. Es optativo y solo admite un entorno aislado confirmado. No se ejecutó una prueba de 1,000 usuarios y no se certifica esa capacidad. El escenario HTTP tampoco mide por sí solo Socket.IO, push, operadores concurrentes ni contención de inventario en el servidor final. Consultar [load/README.md](load/README.md).

Queda por completar para operación real: servidor/dominio/TLS, SMTP y entrega real de correo, padrón autorizado, credenciales y pruebas reales de push si se habilita, migración de las pantallas estudiantiles a los repositorios REST/Socket.IO, ensayos de restauración y carga sostenida. La programación de recogida, manejo de pedidos listos no recogidos, política de retención y datos del contrato V2 faltante requieren definición funcional. Los campos o estados correspondientes no se habilitan mediante supuestos silenciosos.
