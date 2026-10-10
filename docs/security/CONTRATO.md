# Contrato de autorización y datos de SnackUP

Los archivos `app/firestore.rules`, `app/storage.rules` e `app/firestore.indexes.json` son la configuración versionada para revisar y desplegar en un entorno autorizado. **No se desplegaron ni se verificaron contra Firebase en esta implementación.** Las candidatas anteriores de `tests/api/candidates/` son material histórico de QA, no el archivo de despliegue de la aplicación.

## Cuentas y privilegios

| Actor | Acceso |
| --- | --- |
| Alumno autenticado | Su perfil, carrito/favoritos, pedidos propios y reseñas propias. Registro público únicamente con `role:user`, correo institucional y aceptación de aviso versión 2. |
| Negocio aprovisionado | El negocio cuyo `ownerId` coincide con su UID, sus productos, stock, imágenes y estados de pedidos. No puede transferir propiedad desde la app. |
| Administración | Claim firmado booleano `admin:true`; consulta de reseñas y seguimiento administrativo. Un campo de perfil no concede este privilegio. |
| Público | Catálogo de negocios/productos e imágenes del catálogo. |
| Otros datos | Denegados. Chat no tiene un contrato de participantes implementado y queda cerrado. |

El rol comercial y la propiedad del negocio se aprovisionan desde un entorno de confianza. El Admin SDK está fuera de las reglas de cliente: solo TI debe ejecutar el script con permisos adecuados.

## Pedidos y dinero

- Nuevo pedido: `schemaVersion:2`, estado inicial `pending`, usuario del token autenticado, negocio abierto, timestamp del servidor y código aleatorio de 32 caracteres hexadecimales.
- Entre 1 y 8 productos **distintos**, cantidad entera 1–99 por línea. El servidor comprueba negocio, disponibilidad, existencias al solicitar, nombre y precio de cada producto.
- Cada línea incluye `unitPriceCents:int` y `price=unitPriceCents/100`. El pedido incluye `totalCents:int`, igual a la suma de precio en centavos por cantidad, y `totalPrice=totalCents/100`.
- El precio procede de `products.priceCents`; para productos históricos sin ese campo se usa `math.round(price*100)`. El precio decimal del catálogo debe coincidir con esos centavos. Precio permitido: 1–1,000,000 centavos (hasta $10,000 MXN); stock: entero 0–1,000,000.
- Las reglas desdoblan las ocho líneas porque no admiten bucles: hasta ocho lecturas de productos y una del negocio por creación. Ni el carrito ni un total enviado por el navegador son la fuente de autoridad.
- Una hora programada debe ser posterior al timestamp de solicitud y estar dentro de las siguientes 24 horas. La app comprueba también esa condición antes de enviar.

Los productos históricos con campos inválidos, precio de más de dos decimales o metadatos incompletos deben revisarse/editarse antes de operar. No se altera el catálogo automáticamente ni se inventan nombres, precios o existencias.

## Stock y estados

La solicitud comprueba disponibilidad, pero **reserva stock al aceptar el negocio**, en una transacción que lee las existencias actuales, descuenta todas las líneas y marca `stockReserved:true`. Varias solicitudes pendientes pueden competir; una aceptación sin stock suficiente falla completa.

Transiciones permitidas: `pending → preparing → ready → completed`; cancelación desde `pending` o `preparing`. Se exige `updatedAt` del servidor y `completedAt`/`cancelledAt` al cerrar. Precio, items, usuario, código de recogida y negocio permanecen inmutables.

Un pedido histórico todavía pendiente que tenga más de ocho líneas, productos repetidos o cantidades fuera de 1–99 no puede aceptarse con el contrato nuevo: debe revisarse y cancelarse/recrearse. Los históricos que ya estén preparando o listos pueden continuar su transición, sin reservar stock por segunda vez.

El negocio es la autoridad para gestionar su propio stock; las reglas impiden que el alumno lo escriba. Cancelar un pedido en preparación **no repone stock automáticamente** porque los alimentos pueden haberse preparado. La reposición debe ser un ajuste consciente del negocio.

El QR nuevo identifica el pedido y su código: `snackup:<orderId>:<pickupCode>`. El cliente comercial comprueba el código contra el pedido actual al entregar. El propietario autenticado conserva la autoridad de completar el pedido; esta validación de QR en cliente no es una segunda credencial de autorización de Firebase. Los pedidos históricos sin código usan su ID y no vuelven a usar la matrícula como QR.

## Reseñas e historial administrativo

La reseña nueva ocupa `reviews/{orderId}`, exige pedido completado y propio, tres calificaciones enteras 1–5 y timestamp del servidor. No admite un nombre o correo adicional del alumno. Carrera (120 caracteres) y grupo (40) son opcionales y autodeclarados; comentario hasta 1500.

Las reseñas históricas aleatorias se consultan antes de enviar para evitar duplicados desde la app. La unicidad histórica completa requiere migración revisada; la unicidad de nuevas reseñas se impone por ID del pedido. Un pedido con el mismo ID que una reseña histórica ajena nunca otorga permiso para leer esa reseña.

Cada seguimiento incluye `eventId`. Las reglas exigen que la escritura del estado y el **nuevo** evento de historial ocurran juntos, con idénticos datos; un evento ya existente no puede reutilizarse. Ningún cliente puede editar ni borrar el historial. Responsable hasta 120 caracteres y nota hasta 2000; autor obtenido de la sesión, no elegido desde el formulario.

## Imágenes e índices

Las imágenes nuevas se almacenan en `product_images/{businessId}/{archivo}`, con lectura pública y escritura del propietario comprobado mediante `firestore.get`. Se admiten JPEG/PNG/WebP de hasta 5 MiB, con nombre/extensión admitidos. El tipo MIME es una validación de metadatos, no un escaneo del contenido. Imágenes históricas en el prefijo plano conservan lectura, pero no escritura.

Al desplegar Storage, TI debe habilitar el permiso de integración Storage→Firestore que solicita Firebase para esa comprobación. No se creó ni modificó IAM aquí.

Los índices incluidos cubren las consultas actuales y las vistas históricas con orden por fecha/categoría. El despliegue de índices debe finalizar antes de evaluar las consultas; una configuración JSON por sí sola no crea índices en el proyecto.

## Aprovisionamiento confiable

Ver `tools/access/provision_access.mjs` y `tools/access/package.json`. El script **solo muestra un plan local por defecto**, sin cargar Firebase ni realizar conexiones. Necesita UID y correo esperado de una cuenta de Firebase Auth ya existente; no crea cuentas ni maneja contraseñas.

```bash
node tools/access/provision_access.mjs --project=snackup-8fe96 --uid=UID_REAL --email=cuenta@ejemplo.mx --role=admin
node tools/access/provision_access.mjs --project=snackup-8fe96 --uid=UID_NEGOCIO --email=local@ejemplo.mx --role=business --business-id=local-real --name="Nombre real del local"
```

Tras revisar el plan, TI instala la dependencia de `tools/access/` y usa credenciales ADC apropiadas fuera del repositorio. Para ejecutar, agrega `--apply --confirm-project=snackup-8fe96`. El script verifica UID/correo, conserva los demás claims y rechaza apropiarse de un negocio de otro dueño. Repetir el aprovisionamiento no cierra un negocio existente.

El panel comercial actual abre un negocio por cuenta; aprovisionar una cuenta de operador diferente para cada local. No reutilizar un mismo UID para varios locales en esta versión.

`--role=revoke-admin` elimina solo el claim administrativo y revoca los refresh tokens. Los cambios de claims se reflejan al renovar la sesión; los ID tokens ya emitidos pueden seguir siendo válidos hasta su expiración. No ejecutar cambios de claims concurrentes sobre la misma cuenta.

## Evidencia y validación pendiente

- `node --test tools/access/provision_access.test.mjs`: pruebas **sin red** de argumentos, confirmación de proyecto, preservación de claims y bloqueo del modo de ejecución desde un plan sin aplicar.
- `tests/api/app-security.test.mjs`: contrato de pruebas de la configuración integrada, escrito y revisado; requiere ejecución futura en un entorno aprobado. No inicia emuladores y está omitido salvo activación explícita.
- `tests/api/admin-monitoring.test.mjs`: contrato de la candidata administrativa histórica, conservado separado.
- No se ejecutaron pruebas de reglas, Storage, Firebase Auth ni escrituras remotas. Las pruebas Flutter y revisiones estáticas no sustituyen la validación del servidor.

Antes de una activación real deben comprobarse permisos por actor, precios/total manipulados, ocho líneas, stock concurrente, transición/QR, privacidad de reseñas y creación atómica de historial; además de comparar la configuración con las reglas vigentes y revisar los datos históricos.

Referencias oficiales: [math.round](https://firebase.google.com/docs/reference/rules/rules.math), [condiciones de Firestore](https://firebase.google.com/docs/firestore/security/rules-conditions), [Storage con Firestore](https://firebase.google.com/docs/storage/security/rules-conditions), [custom claims](https://firebase.google.com/docs/auth/admin/custom-claims).
