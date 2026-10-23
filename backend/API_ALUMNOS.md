# API del alumnado e identidad institucional

Esta guía describe el backend que está implementado, con base `/api/v1`.
El contrato ejecutable es [extensions.openapi.json](contracts/extensions.openapi.json):
11 operaciones adicionales y la ampliación compatible de `GET users/me`.
Las 43 operaciones de Administración y Cocina conservan su
[contrato de paneles](contracts/panels.openapi.json).

La aplicación estudiantil existente todavía requiere integrar estas rutas REST.
Crear el backend no conecta automáticamente las pantallas que utilizan Firebase.
No se ha recibido un padrón, una API institucional, acceso al servidor ni un servicio
SMTP por el hecho de incorporar este código. Tampoco se acredita capacidad para
1,000 estudiantes concurrentes sin medir el despliegue final.

## Identidad: correo, padrón y carrera

La relación implementada es:

**Correo normalizado y confirmado → registro institucional autorizado → carrera y grupo.**

El servidor normaliza el correo con `strip().lower()` y busca una coincidencia
exacta en `academic_records`. No extrae matrícula, carrera ni privilegios mediante
suposiciones sobre el nombre del correo. El dominio permitido es una comprobación
adicional; un dominio correcto por sí solo no prueba que una persona sea estudiante.

El padrón contiene `kind=student` o `kind=staff`. El tipo institucional y el rol de
SnackUP son independientes: `student` permite solicitar una cuenta `role=user`;
`staff` no concede `admin`, `business` ni `isMaster`. Los accesos del personal se
autorizan mediante el flujo de la cuenta maestra después de verificar el correo.

Para estudiantes, cada acceso autenticado requiere un registro `student` activo.
Para el personal, la falta de un padrón todavía permite una asignación manual
aprobada. **Si existe un registro institucional y está inactivo, el acceso se bloquea
para cualquier rol**, incluso maestro. La importación de una baja revoca sus
sesiones; las comprobaciones HTTP y WebSocket también consultan el estado vigente.
El rol asignado se conserva: una baja institucional no convierte a una persona en
otro rol ni libera automáticamente su asignación administrativa de local.

### Cargar el padrón autorizado

Desde `backend/`, con configuración y migraciones preparadas:

```shell
python -m snackup.cli import-roster padron.csv --source "control-escolar-2026-10" --dry-run
python -m snackup.cli import-roster padron.csv --source "control-escolar-2026-10"
```

El archivo debe ser UTF-8, con estas columnas exactas (el orden puede variar):

```csv
email,institutional_id,display_name,kind,career_id,career_name,group_id,group_name,is_active
alumno@alumnos.example.edu,A-0001,Persona de ejemplo,student,DS,Desarrollo de Software,DS-1,Grupo 1,true
personal@personal.example.edu,E-0001,Personal de ejemplo,staff,,,,,true
```

Los dominios anteriores son ficticios y no se configuran automáticamente. Sustituirlos
por los dominios aprobados en `SNACKUP_STUDENT_EMAIL_DOMAINS` y
`SNACKUP_ADMIN_EMAIL_DOMAINS`. Las contraseñas no forman parte del padrón.

Reglas de la importación:

- Solo usar información cuya procedencia haya autorizado la universidad.
- La importación valida y aplica el conjunto en una transacción; un conflicto
  revierte el conjunto. `--dry-run` también revierte los cambios.
- Toda persona de tipo `student` debe tener carrera; el grupo es opcional y debe
  pertenecer a esa carrera. Los IDs son referencias institucionales opacas.
- `is_active` admite `true`, `false`, `1` o `0`.
- Actualiza las filas incluidas; **omitir una persona no la da de baja**. Para una
  baja debe enviarse explícitamente `is_active=false`.
- No reasigna silenciosamente un correo a otra identidad institucional, ni una
  identidad a otro correo. Los conflictos requieren una corrección autorizada.
- El padrón admite como máximo 10 MiB. No guardarlo con datos reales en Git.

## Registro, confirmación y sesión

`POST /student/register` acepta exclusivamente:

```json
{"email":"alumno@alumnos.example.edu","password":"<contraseña de 12 a 128 caracteres>"}
```

Requiere SMTP configurado, dominios estudiantiles configurados y, para crear la
cuenta, un registro activo de estudiante con ese correo y dominio permitido.
El nombre se toma del padrón. No se aceptan `displayName`, `role`, `careerId`,
`groupId` ni campos de privilegios en esta ruta.

Responde `202 {"status":"received"}` sin sesión. El acuse es igual para correos
sin registro, no elegibles o ya existentes: evita revelar el padrón y no significa
que se haya autorizado la cuenta. Un duplicado no cambia contraseña ni permisos.
Falta de SMTP: `503 EMAIL_UNAVAILABLE`; falta de dominios estudiantiles:
`503 INSTITUTION_NOT_CONFIGURED`.

El correo de confirmación lleva a:

```text
https://<dominio>/api/v1/auth/verify-email#token=<token>
```

El token se envía en el fragmento, no en la consulta URL. `GET /auth/verify-email`
solo muestra HTML: no confirma automáticamente. La página retira el fragmento y,
después de pulsar **Confirmar correo**, envía:

```http
POST /api/v1/auth/verify-email
Origin: https://<dominio>
Content-Type: application/json

{"token":"<token de confirmación>"}
```

La respuesta correcta es `204`. El token caduca en 30 minutos, se vincula al correo
y solo se usa una vez. Un token inválido, usado o vencido devuelve
`422 VERIFICATION_TOKEN_INVALID`. Confirmar no inicia sesión ni autoriza al personal.

`POST /auth/resend-verification {"email":"..."}` responde `202` genérico. Si la
cuenta existe, no está confirmada y no fue rechazada, envía un nuevo enlace e
invalida los anteriores. Una entrega SMTP fallida devuelve `503`; el backend no
simula haber enviado correos.

Después se utilizan las rutas existentes del contrato de paneles:

| Operación | Comportamiento relevante |
|---|---|
| `POST /auth/login` | Correo y contraseña; devuelve access token y cookie de renovación. El alumno debe estar confirmado y autorizado por el padrón. |
| `POST /auth/refresh` | Rota la cookie y renueva el access token. Reutilizar una cookie ya rotada revoca la familia de sesión. |
| `POST /auth/logout` | Revoca la sesión y borra la cookie. |
| `GET /users/me` | Perfil de la propia sesión, incluida la información académica disponible. |
| `POST /auth/forgot-password` | Recuperación por SMTP con respuesta genérica. |
| `POST /auth/reset-password` | Token de un uso; cambia la contraseña y revoca sesiones anteriores. |

Login, refresh, logout, reset y confirmación exigen `Origin` igual a
`SNACKUP_PUBLIC_ORIGIN`. Un cliente nativo debe enviarlo explícitamente. En web,
mantener el access token en memoria y enviar las cookies con las peticiones al
mismo origen. La renovación de varias pestañas debe coordinarse para no reutilizar
simultáneamente la misma cookie.

La información adicional de `GET /users/me` tiene esta forma cuando existe padrón
activo; `academic` se omite cuando no existe:

```json
{
  "id":"<id propio>","displayName":"Persona de ejemplo","role":"user",
  "businessId":null,"isMaster":false,"email":"alumno@alumnos.example.edu",
  "emailVerified":true,
  "academic":{
    "institutionalId":"A-0001","kind":"student",
    "careerId":"DS","careerName":"Desarrollo de Software",
    "groupId":"DS-1","groupName":"Grupo 1","verified":true
  }
}
```

No existe una ruta pública para obtener la carrera de otra persona introduciendo
su correo. Esta información personal corresponde al perfil autenticado.

## Catálogo y pedidos

Todas estas rutas requieren Bearer y `role=user`; una cuenta administrativa o de
Cocina no puede utilizarlas para suplantar a un estudiante.

| Método y ruta | Resultado |
|---|---|
| `GET /student/businesses?page=1&limit=20` | Locales activos. Un local cerrado sigue visible, con `isOpen=false`. |
| `GET /student/businesses/{id}/products?page=1&limit=20` | Productos disponibles y no eliminados de un local activo. |
| `POST /student/orders` | Crea el pedido y reserva inventario. |
| `GET /student/orders?page=1&limit=20` | Pedidos propios, del más reciente al más antiguo. |
| `GET /student/orders/{id}` | Estado y código de entrega de un pedido propio. |
| `POST /student/orders/{id}/cancel` | Cancela un pedido propio todavía pendiente. |
| `POST /student/orders/{id}/review` | Una opinión por pedido propio entregado. |

Las listas devuelven `data` y `pagination {page,limit,total,totalPages}`. `page`
empieza en 1; `limit` permite hasta 200 en locales y pedidos, y hasta 100 en catálogo.
Un pedido de otra persona se responde como inexistente. Los IDs son opacos.

### Crear y reintentar una compra

```http
POST /api/v1/student/orders
Authorization: Bearer <access token>
Idempotency-Key: <UUID nuevo para esta intención de compra>
Content-Type: application/json

{
  "businessId":"<id local>",
  "items":[{"productId":"<id producto>","quantity":2,"notes":"Sin cebolla"}],
  "paymentMethod":"cash"
}
```

Solo se admite efectivo (`cash`); es el valor predeterminado si se omite. El
backend no realiza cobros electrónicos ni confirma que el efectivo se haya pagado.
El campo de salida `paymentStatus` permanece `pay_at_pickup`; no interpretarlo
como comprobante de pago.

Se permiten de 1 a 50 renglones, cantidades enteras de 1 a 99 y notas de hasta 500
caracteres. Un producto no puede repetirse: sumar sus unidades en un solo renglón.
Todo el pedido pertenece a un local. El cliente no envía precios, total, alumno,
carrera, estado, número de pedido ni código de entrega.

El servidor verifica el local abierto y activo, recalcula importes en MXN desde
SQL y reserva existencias dentro de la misma transacción. `stock=null` significa
que ese producto no tiene un límite de unidades configurado. Nombre y precio de
cada renglón se conservan como copia del momento de compra.

`Idempotency-Key` es obligatorio: 16–128 caracteres ASCII entre letras, números,
`.`, `_`, `:` y `-`. Crear una clave por intención de compra y conservarla si la
red se corta. Repetir la misma clave y el mismo body devuelve la respuesta original
con `201`; otra carga con la misma clave devuelve `409 IDEMPOTENCY_CONFLICT`.
El resultado original puede mostrar un estado anterior: después de recuperarlo,
consultar el pedido con GET. No crear otra clave automáticamente tras un timeout.
El límite actual para esta ruta, incluidos reintentos, es 30 por minuto por usuario.

La respuesta de pedido incluye `version`, importes, renglones, fechas y
**`pickupCode` de ocho dígitos**, exclusivo del propietario. Cocina recibe otro DTO
sin ese código y confirma la entrega introduciendo el código mostrado por el alumno.
No publicar el DTO estudiantil en canales compartidos ni enviarlo al panel de otro rol.

### Estados y cancelación

El flujo operativo es `pending → accepted → preparing → ready → completed`.
El alumno solo puede cancelar mientras está en `pending`:

```json
{"expectedVersion":1}
```

La versión debe coincidir con la última respuesta. La cancelación devuelve el
pedido actualizado, restaura únicamente el inventario reservado y deja
`cancelReason=student_cancelled`. No admite motivo o notas del alumno. Un intento
con versión anterior devuelve `409 VERSION_CONFLICT`; si Cocina ya lo aceptó,
`409 INVALID_STATUS_TRANSITION`. Actualizar la vista antes de repetir.

### Opinión y carrera

Tras `completed`, `POST /student/orders/{id}/review` acepta:

```json
{"rating":5,"foodRating":5,"serviceRating":4,"comment":"Entrega rápida."}
```

`rating` es obligatorio, entero de 1 a 5. Las otras calificaciones son opcionales
y aceptan `null`; comentario opcional de hasta 2,000 caracteres. Solo se permite
una opinión por pedido. No hay edición de opiniones en esta extensión.

El servidor toma carrera y grupo del padrón vigente **al enviar la opinión** y
guarda sus IDs y nombres como copia histórica. Una actualización del padrón no
reescribe opiniones anteriores. El cliente no puede enviar `careerId`, `groupId`,
matrícula o identidad alternativa. El DTO de opinión no incluye nombre, correo,
matrícula, ID del usuario ni ID del pedido; internamente sigue vinculado a ambos
para validar su origen. Por ello no debe presentarse como una opinión anónima.

## Avisos en tiempo real

El backend utiliza el WebSocket ya documentado en el contrato de paneles:
`wss://<dominio>/api/v1/realtime`, sin credenciales en la URL y con `Origin` válido.
El alumno autentica por mensaje y solo puede suscribirse a su canal:

```json
{"action":"auth","token":"<access token>"}
{"action":"subscribe","topics":["user:<id de users/me>:orders"]}
```

Los avisos indican que debe consultarse el pedido por REST; no reemplazan los datos
autorizados del servidor. Responder a `ping` con `{"action":"pong"}`, renovar el
token por REST cuando corresponda y reenviar `auth` al menos cada 60 segundos
(el servidor cierra conexiones sin reautenticación durante más de 90 segundos).
Tras una desconexión, volver a consultar los pedidos: no se ofrece reproducción
de eventos anteriores. Cada notificación vuelve a comprobar autorización.

## Errores y puntos de integración pendientes

Los errores JSON usan `{"error":{"code":"...","message":"..."}}`, con `details`
opcional. Preservar el código al traducir mensajes al usuario.

| Caso | Respuesta habitual |
|---|---|
| Sesión expirada | `401 TOKEN_EXPIRED`; renovar una vez y coordinar las peticiones. |
| Sesión revocada o repetición de refresh | `401 UNAUTHENTICATED` o `SESSION_REPLAY`; volver al acceso. |
| Correo sin confirmar | `403 EMAIL_NOT_VERIFIED`. |
| Baja institucional | `403 ACCESS_REVOKED`, o 401 cuando ya se revocó la sesión. |
| Local cerrado | `409 BUSINESS_CLOSED`. |
| Producto agotado o ya no disponible | `409 INSUFFICIENT_STOCK` o `PRODUCT_UNAVAILABLE`; recargar catálogo. |
| Versión antigua | `409 VERSION_CONFLICT`; consultar de nuevo. |
| Opinión anticipada o repetida | `409 ORDER_NOT_COMPLETED` o `REVIEW_EXISTS`. |
| Formato inválido | `422 INVALID_INPUT`, u otro código específico de validación. |
| Demasiadas solicitudes | `429`; respetar `Retry-After`. |
| Correo no disponible | `503 EMAIL_UNAVAILABLE`; no mostrar “correo enviado”. |

La integración del alumno aún debe conectar registro, confirmación, sesión,
catálogo, compra con idempotencia, pedidos, código de entrega y opinión a estas
rutas. El proveedor institucional puede reemplazar la carga CSV en el futuro,
pero todavía no se ha implementado una conexión específica ni un inicio SSO.
Antes de producción se requieren SMTP real, padrón autorizado, configuración,
HTTPS, respaldo, validación en PostgreSQL y pruebas de carga con el servidor asignado.
