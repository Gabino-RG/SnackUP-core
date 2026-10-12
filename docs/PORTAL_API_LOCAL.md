# SnackUP · Acceso y administración mediante API local

Actualización: 11 de octubre de 2026, hora de México.

## Estado del frontend

| Área | Implementado en esta revisión | Pendiente de integración real |
| --- | --- | --- |
| Acceso web | Login, recuperación, restauración con cookie, renovación coordinada, cierre, rutas por perfil del servidor | Servidor de autenticación, cookie HTTPS y cuentas autorizadas |
| Negocios | Catálogo completo con REST, imágenes, precio, stock, versión y paginación | Confirmar las rutas CRUD y probar contra SQL |
| Administración | Monitor existente conectado a REST: locales, opiniones, filtros sobre datos cargados, seguimiento e historial | Aprobar rol/rutas administrativas y agregados oficiales del servidor |
| Pedidos y cocina | Flujo anterior disponible en la entrada Firebase | Migrar a acciones v3, verificación de entrega y tiempo real |
| Capacidad local | Arquitectura y plan de 500 sesiones sostenidas documentados | Medir backend, SQL, servidor y red con carga representativa |

Este portal no crea una API ni instala una base SQL. El acceso REST de negocios
abre el catálogo; los pedidos de la aplicación anterior aún no están incluidos
en ese acceso. No se presenta la compilación como una aplicación SQL completa.

## Compilar y ejecutar

Desde `app`, para desarrollo:

```bash
flutter pub get
flutter run -d chrome --dart-define=BACKEND=rest --dart-define=API_BASE_URL=https://servidor-del-campus.example/api/v1/
```

El dominio anterior es un ejemplo: sustituirlo por el servidor del equipo.
También se puede ejecutar `lib/main_portal_api.dart` directamente.

Para servir frontend y API bajo el mismo origen en el servidor local:

```bash
flutter build web --no-web-resources-cdn --target lib/main.dart --dart-define=BACKEND=rest --output build/portal-api
```

Sin `API_BASE_URL`, el portal utiliza `/api/v1/` del mismo servidor que sirve
la página. El servidor web debe servir los archivos de `build/portal-api` y
dirigir `/api/v1/` al backend. No abrir `index.html` mediante `file://`.
No usar `localhost` como dirección del servidor para otros dispositivos.
La configuración por defecto de la entrada anterior sigue siendo Firebase;
la selección REST sucede antes de inicializar Firebase y no utiliza sus SDK
de autenticación o base de datos.

La entrada REST es web. No se ha implementado almacenamiento seguro de
refresh tokens para una aplicación nativa de Android, iOS o Windows.
El catálogo de ejemplo continúa disponible mediante `main_catalog_local.dart`.

## Sesión y permisos

Se usa `api_v3_agnostica.md` para `/auth/login`, `/auth/refresh`, `/auth/logout`,
`/auth/forgot-password` y `GET /users/me`.

- El access token vive solo en memoria. No se guardan contraseñas ni tokens
  en preferencias, URLs, logs o almacenamiento del navegador.
- El backend emite y renueva la cookie de sesión `HttpOnly; Secure;
  SameSite=Strict`. Los cuerpos web de refresh y logout son `{}`: el navegador
  envía la cookie, el código no la lee. El backend debe borrar esa cookie al
  cerrar sesión, incluso si el access token ya caducó.
- Login y refresh deben devolver `tokens.accessToken` y
  `tokens.accessTokenExpiresAt` en UTC ISO 8601. La respuesta `user` del login
  no decide la navegación: se verifica `GET /users/me` antes de abrir el panel.
- `business` necesita un `businessId` válido asignado por el servidor.
  `admin` abre administración. Este último rol es una **extensión propuesta**:
  v3 solo enumera `user` y `business`; el backend debe aprobarlo e implementar
  la autorización administrativa. No hay selector de rol ni registro público
  de administradores en el portal.
- Un rol distinto o un negocio sin asignación muestra una pantalla de acceso
  pendiente; no abre ninguno de los paneles.
- Las solicitudes de una sesión no pueden enviar el bearer fuera del origen
  y prefijo de API configurados. No se siguen redirecciones autenticadas.
- Varios `401 TOKEN_EXPIRED` simultáneos comparten una renovación. Solo esa
  respuesta autoriza un reintento. Errores de red, timeout, 409 y 5xx no
  repiten escrituras automáticamente.
- Si no se puede renovar, se elimina el acceso local. Cuando cambia el rol,
  local o cuenta, se reemplaza la navegación y se descartan respuestas del
  contexto anterior. La API debe comprobar permisos en **cada** operación;
  ocultar pantallas no sustituye la autorización del servidor.
- Cerrar sesión quita inmediatamente los datos protegidos. Si la revocación
  no se confirma, la pantalla pide reintentar y bloquea otro login en esa
  instancia. Un indicador local no secreto recuerda el cierre pendiente al
  recargar y obliga a completarlo antes de restaurar la cookie. Ese indicador
  no contiene tokens ni información de la cuenta. Las operaciones que rotan
  cookies se serializan para que una respuesta tardía de login no revierta
  el logout. El cierre completo debe confirmarse con el servidor.

Para el despliegue local se recomienda el mismo origen HTTPS para frontend y
API. Si se usan orígenes diferentes, el backend debe permitir expresamente
el origen del frontend y las credenciales; debe mantener la protección de
origen/CSRF para operaciones que usan cookies. No usar un origen comodín con
credenciales. Estas opciones no se cambian desde el frontend.

## Contrato administrativo provisional

Las rutas están centralizadas en `AdminApiRoutes`. No están definidas en v3
y no se han añadido a un backend desde este trabajo.

| Operación | Ruta debajo de `/api/v1/` | Respuesta |
| --- | --- | --- |
| Locales | `GET admin/businesses?page=1&limit=200` | `{data: Business[], pagination}` |
| Opiniones | `GET admin/reviews?page=1&limit=200` | `{data: Review[], pagination}` |
| Seguimientos | `GET admin/followups?page=1&limit=200` | `{data: Followup[], pagination}` |
| Caso | `GET admin/reviews/{reviewId}/followup` | `Followup` o `{data: Followup}` |
| Guardar caso | `PUT admin/reviews/{reviewId}/followup` | `Followup` actualizado |
| Historial | `GET admin/reviews/{reviewId}/followup/history?page=1&limit=50` | `{data: Followup[], pagination}` |

`pagination` contiene `page` y `totalPages`. Cada lista tiene su propio
cursor. Si una petición o el análisis de un registro falla, no se consume
ningún cursor. Reiniciar los filtros no descarga todos los registros del SQL.
El monitor conserva la advertencia de resultados parciales hasta terminar de
cargar las páginas. Sus filtros y estadísticas describen los datos cargados;
los reportes globales oficiales requieren consultas y agregados del backend.

Campos que utiliza el monitor:

- `Business`: `id`, `name`, `isOpen`.
- `Review`: `id`, `businessId`, `rating`, `serviceRating`, `foodRating`,
  `career`, `group`, `comment`, `createdAt`. Las dimensiones históricas
  ausentes no se convierten en cero. No necesita correo o matrícula del alumno.
- `Followup`: `reviewId`, `businessId`, `status` (`pending`, `in_review`,
  `resolved`), `assignee`, `note`, `version`, `updatedAt`.

Guardar manda únicamente `status`, `assignee`, `note` y `expectedVersion`.
El backend decide autor, fecha, relación con el negocio e identificador del
evento. Debe actualizar el caso y añadir un evento de historial en la misma
transacción SQL. La respuesta incluye la nueva versión y fecha del servidor.

Un caso sin seguimiento devuelve `404 FOLLOWUP_NOT_FOUND`; el frontend usa
versión inicial `0`. PUT con `expectedVersion: 0` crea ese seguimiento solo
si todavía no existe. Si otra persona lo creó o actualizó, devolver
`409 VERSION_CONFLICT`. El formulario conserva la nota, permite recargar el
caso y exige que el operador vuelva a guardar conscientemente.

Una opinión inexistente o no autorizada no debe confundirse con un
seguimiento vacío: usar otro código de error. El historial devuelve una
lista vacía con paginación válida si aún no hay eventos.

## Verificación y límites

La suite comprueba roles recibidos del servidor, negocio asignado, expiraciones
simultáneas, revocación, respuestas tardías, solicitudes fuera de la API,
login móvil, retirada de diálogos protegidos, paginación administrativa,
versiones, historial y guardados sin reintentos por fallas de red.
Se utilizan respuestas HTTP simuladas; no prueban cookies, TLS, permisos o
transacciones de un servidor real. La prueba manual de conexión debe cubrir
login, recarga, renovación, pérdida de acceso, logout, catálogo, imágenes,
seguimiento concurrente e historial con las cuentas autorizadas del backend.

Flutter CI conserva tres compilaciones: aplicación anterior integrada,
catálogo local con ejemplos y portal REST. Ver el resultado del commit para
conocer las pruebas efectivamente ejecutadas. La prueba de 500 sesiones y la
aprobación de las rutas administrativas siguen pendientes.
