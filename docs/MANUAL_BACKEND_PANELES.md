# SnackUP | Manual de backend y personalización

> Nota de compatibilidad del 23 de octubre de 2026: este manual 1.0 conserva sus
> ejemplos históricos. El portal REST actual usa `/api/legacy/v1/` y
> `/api/legacy/v1/realtime`; al aplicar sus ejemplos al backend actual, sustituir
> ese prefijo. `/api/v1/` corresponde ahora al contrato V3. Consultar
> [la guía vigente de integración](integracion/README.md) y [la instalación del backend separado](https://github.com/Gabino-RG/SnackUP-core/blob/codex/backend-api-v3-fastapi/backend/README.md).

**Entrega técnica para el responsable del backend y su asistente de IA**

Administración institucional y operación de locales de la cafetería universitaria.

Versión del documento: **1.0 - 12 de octubre de 2026**. Zona de referencia: America/Mexico_City.

**Código auditado:** `476d89c8c94fcdd4a371d87710904736d68f8455`.

**Repositorio:** [Gabino-RG/SnackUP-core](https://github.com/Gabino-RG/SnackUP-core)

**Rama de trabajo:** [test/api-aaa-sonarqube](https://github.com/Gabino-RG/SnackUP-core/tree/test/api-aaa-sonarqube)

**Versión exacta del código:** [abrir snapshot auditado](https://github.com/Gabino-RG/SnackUP-core/tree/476d89c8c94fcdd4a371d87710904736d68f8455)

Este manual describe lo que el frontend existente envía, interpreta y necesita para conectarse al backend definitivo. Separa la apariencia de las pantallas del contrato HTTP, la autorización y la persistencia SQL. Los ejemplos usan datos ficticios; los identificadores son ilustrativos.

**Objetivo de integración:** conectar los dos paneles existentes sin rehacerlos. El backend será dueño de las cuentas, permisos, precios confirmados, inventario, estados, fechas y almacenamiento. El frontend conservará la presentación y la interacción.

**Situación real:** existe un frontend Flutter web con repositorios REST y un servidor de revisión Python/SQLite. Este servidor permite probar flujos, pero no es la implementación productiva. Correo de recuperación, verificación de email, Google, WebSocket real y capacidad para 500 sesiones todavía requieren implementación o validación del backend definitivo.

**Regla central de acceso:** Administración, incluida la cuenta maestra, no opera Cocina. Un operador de local no entra a Administración ni a otro local. La API debe imponer esta separación en cada petición.

**Cómo utilizarlo:** frontend y personalización en los apartados 1-4; integración y contratos en 5-24; SQL, despliegue y capacidad en 25-28; compatibilidad, pruebas y entrega en 29-31; instrucciones para IA en 32. El índice de fuentes del apartado 33 permite ir directamente al código. Los títulos también aparecen como marcadores del PDF.

<!-- page -->
# 1. Responsabilidades y estado de la entrega

Las etiquetas de este documento distinguen lo observado de lo que se propone construir:

| Etiqueta | Significado |
| --- | --- |
| ACTUAL | Comportamiento comprobable en el frontend del commit auditado. |
| REQUERIDO | Condición que debe cumplir el backend para integrar ese frontend de forma correcta. |
| PROPUESTA | Diseño sugerido para el servidor; puede sustituirse conservando el contrato externo. |
| PENDIENTE | Decisión o trabajo que aún requiere implementación, acuerdo o validación. |

| Responsabilidad | Frontend | Backend |
| --- | --- | --- |
| Colores, tipografía, logo, espaciado y adaptación a pantalla | Define y renderiza | No determina estilos hoy |
| Nombre del local, cafetería, universidad, carreras y grupos | Consulta y presenta | Almacena y entrega |
| Permisos y aprobación de cuentas | Oculta opciones según perfil | Autoriza cada operación y revoca accesos |
| Productos, imágenes, precios y disponibilidad | Formularios y consultas REST | Valida, persiste y confirma versiones |
| Pedidos y entrega | Solicita acciones concretas | Valida transiciones, código, stock y fechas |
| Gráficas administrativas | Calcula la vista desde las opiniones cargadas | Provee opiniones y referencias confiables |
| Ventas e historial | Muestra el resumen recibido | Calcula el periodo completo, sin cancelaciones |

ACTUAL: las pantallas son dos áreas separadas dentro de una misma compilación web; no son dos bases de datos ni dos aplicaciones nativas. El servidor comparte identidad y datos, pero separa capacidades por rol.

REQUERIDO: una cafetería de la universidad contiene varios locales. Aunque se prevén cuatro locales reales, no se fija ese número en código. Los crea el equipo. La cuenta maestra inicial se provisiona mediante un procedimiento de backend; no se crea desde el registro público.

La revisión contiene un Local de prueba, 6 productos, 240 pedidos históricos y 90 opiniones. No se deben importar esos ejemplos, credenciales ni inicializadores en producción. Los ejemplos se cargan una sola vez; las fechas corresponden a su primera carga.

<!-- page -->
# 2. GitHub, versión y mapa del código

Sí: el trabajo está versionado en GitHub. Consultar la rama indicada en la portada. Para reproducir exactamente lo descrito, usar el commit auditado y no asumir que la punta de la rama permanecerá igual.

```bash
git clone https://github.com/Gabino-RG/SnackUP-core.git
cd SnackUP-core
git switch test/api-aaa-sonarqube
git show 476d89c8c94fcdd4a371d87710904736d68f8455
```

Para estudiar el snapshot sin modificar la rama de trabajo:

```bash
git switch --detach 476d89c8c94fcdd4a371d87710904736d68f8455
```

Si el repositorio pide autenticación, el propietario debe dar acceso al colaborador. No incluir tokens de GitHub en este manual ni en mensajes a la IA.

| Ubicación dentro del repositorio | Para qué sirve |
| --- | --- |
| `app/lib/api/` | HTTP, sesión, opciones de acceso, registro y cookies del navegador. |
| `app/lib/operations/` | Modelos y peticiones de cocina, gestión, configuración y WebSocket. |
| `app/lib/catalog/` | Contrato de productos, validaciones y repositorio REST. |
| `app/lib/features/admin/` | Tema institucional, filtros, gráficas, opiniones y seguimiento. |
| `app/lib/features/operations/` | Cocina, historial, resumen, locales, cuentas y solicitudes. |
| `app/lib/features/portal/` | Acceso, recuperación y selección del panel por perfil. |
| `scripts/review/` | Simulador local, datos ficticios, pruebas y empaquetado Windows. |
| `docs/CONTRATO_PANELES.md` | Contrato existente que complementa la propuesta v3 del equipo. |
| `docs/PORTAL_API_LOCAL.md` | Integración REST, sesión y particularidades administrativas. |

**Manual legible para una IA:** [docs/MANUAL_BACKEND_PANELES.md](https://github.com/Gabino-RG/SnackUP-core/blob/test/api-aaa-sonarqube/docs/MANUAL_BACKEND_PANELES.md). El PDF es la entrega para lectura; el Markdown mantiene código y peticiones copiables.

Validación del código de referencia: [Flutter CI, ejecución 38317548777](https://github.com/Gabino-RG/SnackUP-core/actions/runs/38317548777). Terminó correctamente: pruebas del servidor de revisión, análisis, pruebas Flutter, recorrido del navegador y cuatro compilaciones web. Esto no equivale a probar el backend productivo ni 500 usuarios.

<!-- page -->
# 3. Personalización visual del frontend

ACTUAL: los paneles REST usan `adminTheme()` en `app/lib/features/admin/admin_theme.dart`. La tipografía declarada es **Inter**, incluida mediante `app/pubspec.yaml`. No confundir este tema con `app/lib/theme/app_colors.dart`: ese archivo contiene la paleta morada de la aplicación anterior y no gobierna los paneles REST.

| Token de AdminColors | Valor actual | Uso |
| --- | --- | --- |
| `navy` | `#002855` | Azul institucional, títulos y acciones principales |
| `teal` | `#00A788` | Acento verde y elementos destacados |
| `cyan` | `#007C66` | Verde oscuro, textos y gráficos; el nombre del token es histórico |
| `background` | `#F8F9FA` | Fondo general |
| `muted` | `#64748B` | Información secundaria |
| `border` | `#E5EAF0` | Bordes y separadores |
| `red` | `#B42318` | Errores y alertas |

| Cambio deseado | Archivo o área a revisar |
| --- | --- |
| Colores y estilos base | `features/admin/admin_theme.dart` |
| Logo y textos del acceso | `features/portal/rest_portal_app.dart` |
| Archivo del logo | `app/assets/institution/utsjr-logo.png` |
| Atribución y procedencia del logo | `app/assets/institution/README.md` |
| Tipografías y recursos incluidos | `app/pubspec.yaml` y `app/assets/fonts/` |
| Gráficas, tarjetas y menú administrativo | `features/admin/admin_dashboard_screen.dart` |
| Navegación y columnas de cocina | `features/operations/business_portal.dart` |
| Catálogo y edición de productos | `features/catalog/` |

REQUERIDO al personalizar: mantener contraste, legibilidad y señales de estado. Existen colores literales en algunos widgets; cambiar únicamente el tema no recolorea cada detalle. Revisar los componentes afectados y no reemplazar globalmente todos los colores, porque algunos significan error, advertencia o disponibilidad.

ACTUAL: navegación amplia del local desde 980 px; columnas de cocina desde 1050 px de ancho disponible; menú administrativo amplio desde 1100 px. Son decisiones del frontend. La API no recibe tamaño de pantalla ni entrega layouts distintos para Android, tablet o PC.

El portal es una web adaptable. El lector QR requiere permiso de cámara y un contexto seguro en los dispositivos finales. Cambiar el logo, las fuentes, los textos estáticos o los estilos exige recompilar y volver a servir la web.

<!-- page -->
# 4. Qué se personaliza con datos y qué exige código

| Elemento | Mecanismo actual | Responsable |
| --- | --- | --- |
| Universidad, cafetería y dominios de correo autorizados | `GET institution` | Backend/configuración |
| Nombre, categoría y descripción de un local | `PATCH businesses/{id}` o gestión administrativa | Backend con formulario existente |
| Activación del local | `PATCH admin/businesses/{id}` | Administrador autorizado |
| Recepción abierta/cerrada | `PATCH businesses/{id}/status` | Operador del local |
| Productos, precios, stock, imagen y disponibilidad | REST del catálogo | Operador del local |
| Carreras y grupos | `GET admin/academic-catalog` | Backend/padrón de referencia |
| Opciones de acceso por contraseña, solicitud y Google | `GET auth/options` | Backend |
| Colores, logo, fuentes, textos fijos y distribución | Código Flutter y assets | Frontend |
| URL base del backend | `API_BASE_URL` al compilar | Integración/despliegue |

ACTUAL: no existe un endpoint de temas visuales ni una pantalla que guarde colores en SQL. Agregar campos `primaryColor` o `logoUrl` a `institution` no cambia la apariencia: el frontend actual no los consume. Si se desea personalización visual sin recompilar, se debe acordar y desarrollar una extensión de configuración, su validación y su consumo en Flutter.

ACTUAL: el nombre de la universidad es dinámico, pero algunos textos de identidad, incluido el pie del panel, siguen siendo estáticos. Renombrar una institución completamente requiere revisar ambas capas. Los nombres internos `campusNow` o `CampusTimeOfDay` son símbolos de código heredados; la interfaz debe hablar de **universidad**.

No traducir valores de protocolo al personalizar textos. Por ejemplo, el botón puede decir “Aceptar pedido”, pero la acción sigue siendo `accept` y el estado `accepted`. Tampoco cambiar `businessId`, `expectedVersion`, claves JSON o códigos de error por sus etiquetas españolas.

**Procedimiento para cambios:** clasificar primero si son visuales, de datos o de contrato. Un cambio visual requiere revisión de escritorio/móvil; un cambio de dato conserva IDs; un cambio de contrato exige actualizar repositorios, modelos y pruebas del frontend junto con el backend. No modificar rutas o tipos solo porque el framework del servidor utiliza otra convención.

<!-- page -->
# 5. Arquitectura y compilación de integración

PROPUESTA: navegador -> servidor HTTPS de la universidad -> frontend estático y `/api/v1/` -> backend -> SQL local. El mismo backend valida el HTTP y las suscripciones WebSocket. SQL y sus credenciales nunca se exponen al navegador.

El frontend no obliga a usar un lenguaje o framework particular. El equipo puede implementar el backend con su stack acordado, siempre que respete el contrato. Para la base productiva se propone un motor SQL de servidor; la elección entre PostgreSQL y MySQL debe quedar registrada. El SQLite del paquete de revisión no es el diseño de capacidad productivo.

Compilar desde `app/` con la versión Flutter compatible con el repositorio; la CI de referencia utiliza **Flutter 3.32.0**:

```bash
flutter pub get
flutter build web --no-web-resources-cdn --target lib/main.dart \
  --dart-define=BACKEND=rest --output build/portal-api
```

ACTUAL: sin `API_BASE_URL`, la base es `/api/v1/` en el mismo origen de la web. Para otro servidor, agregar una URL absoluta terminada en `/`:

```bash
--dart-define=API_BASE_URL=https://snackup.example/api/v1/
```

`snackup.example` es un marcador, no un servidor existente. Sustituirlo por el dominio real. Las opciones `dart-define` se incorporan a la compilación; editar una variable del sistema después no cambia una web ya compilada.

**Importante:** `main.dart` utiliza Firebase por defecto. Es obligatorio `BACKEND=rest` para estos paneles, o ejecutar explícitamente `lib/main_portal_api.dart`. La rama REST se selecciona antes de inicializar Firebase. No quitar archivos Firebase de otras áreas para conseguir esta integración.

Producción debe compilarse sin `REVIEW_MODE=true`. Ese modo añade el aviso de datos ficticios, el botón de entrada de prueba, credenciales de revisión y el generador de pedidos. El servidor productivo tampoco debe exponer `POST review/orders` ni ejecutar `ensure_review_local()` o `ensure_demo_data()`.

La compilación REST actual es **web**. Que se use en Android no implica un APK ni almacenamiento nativo de tokens. Servir el contenido de `build/portal-api`; no abrir `index.html` mediante `file://`.

<!-- page -->
# 6. Convenciones HTTP y JSON comunes

Todas las rutas de los apartados siguientes son relativas a **`/api/v1/`**. JSON UTF-8; claves en camelCase; IDs opacos y estables de tipo string. Los valores numéricos se envían como números JSON, nunca como texto con moneda o separadores.

```http
Authorization: Bearer <accessToken>
Accept: application/json
Content-Type: application/json
```

Excepto registro, login, recuperación y opciones públicas, las peticiones requieren autenticación. `refresh` y `logout` usan la cookie; sus cuerpos web son `{}`. `POST media` utiliza multipart, no JSON.

REQUERIDO: fechas con zona explícita UTC, por ejemplo `2026-10-12T18:20:00Z`. Dinero JSON en pesos MXN: `54.50`, no `5450` ni `"$54.50"`. El frontend convierte a centavos enteros. En SQL usar centavos o `DECIMAL`, con una política única de dos decimales; no sumar importes financieros con coma flotante binaria.

**Listas paginadas: forma canónica**

```json
{
  "data": [],
  "pagination": {
    "page": 1, "limit": 20, "total": 0, "totalPages": 0
  }
}
```

`page` comienza en 1. La API debe devolver la página solicitada y mantener orden estable, con ID como desempate. Responder listas vacías válidas, no 404. Catálogo, administración y referencias requieren paginación; activos e historial toleran formatos heredados, pero se recomienda el mismo sobre en todos los casos.

**Errores: forma canónica**

```json
{
  "error": {
    "code": "VERSION_CONFLICT",
    "message": "El registro cambió; vuelve a consultarlo.",
    "details": {"currentVersion": 8}
  }
}
```

El frontend decide varios comportamientos por `error.code`, no por `message`. No responder HTML de proxy, pantallas de login, 200 con un error escondido ni redirecciones en rutas REST. Los recursos individuales se devuelven preferentemente como objeto directo; los parsers no aceptan envoltorios arbitrarios como `{result: ...}`.

Tiempo de espera del cliente: 20 segundos. No repite escrituras ante timeout/red/5xx/409. Solo `401 TOKEN_EXPIRED` permite renovar y reintentar una vez: el servidor debe emitir ese error antes de cualquier efecto de la petición.

<!-- page -->
# 7. Sesión, login y renovación

Fuente principal: `app/lib/api/rest_session.dart`.

| Método y ruta | Body | Respuesta requerida |
| --- | --- | --- |
| GET `auth/options` | Sin cuerpo; público | 200 con tres booleanos del ejemplo |
| POST `auth/login` | `email,password` | 200 con `tokens` y cookie de renovación |
| POST `auth/refresh` | `{}` y cookie | 200 con `tokens`; rotar cookie |
| GET `users/me` | Bearer | 200 con perfil directo del usuario actual |
| POST `auth/logout` | `{}`; cookie y bearer si existe | 204; revocar y borrar cookie |

```json
{"passwordLogin": true, "selfRegistration": true, "googleEnabled": false}
```

```json
{
  "tokens": {
    "accessToken": "<token-de-acceso>",
    "accessTokenExpiresAt": "2026-10-12T18:35:00Z"
  }
}
```

La fecha de expiración debe ser futura respecto del reloj del cliente. El perfil del login, si se incluye como `user`, no sustituye la comprobación posterior `GET users/me`.

```json
{
  "id": "operador-1", "email": "operador@ejemplo.test",
  "displayName": "Operador del local", "role": "business",
  "businessId": "local-1", "isMaster": false,
  "isActive": true, "approvalStatus": "approved", "version": 1
}
```

ACTUAL: el access token vive en memoria. `BrowserClient.withCredentials=true` envía cookies. El frontend no lee un `refreshToken` del JSON y no lo guarda en localStorage. En recarga intenta `refresh`, luego `users/me`. Renueva cuando faltan 30 segundos para caducar y coordina expiraciones dentro de una instancia.

REQUERIDO: cookie operativa `HttpOnly; Secure; SameSite=Strict`, con ámbito de ruta/origen consistente. El nombre de cookie es decisión del backend porque el frontend no lo lee. Usar HTTPS y validar origen en operaciones con cookies. La cookie HTTP del simulador solo existe para loopback.

La propuesta v3 usa JWT de acceso. El frontend trata el token como string; el backend debe validar firma, audiencia, emisor, caducidad y revocación/asignación actuales. Un JWT vigente no autoriza una cuenta suspendida. Coordinar rotación de refresh entre varias pestañas; esa coordinación no la resuelve globalmente el cliente actual.

<!-- page -->
# 8. Solicitar cuenta y recuperar contraseña

**Registro de estos paneles: no concede acceso inmediato.**

```http
POST /api/v1/auth/register
Content-Type: application/json
```

```json
{
  "displayName": "Persona solicitante",
  "email": "persona@utsjr.edu.mx",
  "password": "<contrasena-elegida>",
  "requestedRole": "admin",
  "context": "Solicito acceso administrativo a la cafetería."
}
```

Respuesta: **202 `{"status":"received"}`**, sin tokens ni cookie operativa. `requestedRole` admite `business` o `admin`; representa una solicitud, nunca el rol efectivo. Límites actuales: nombre 100, correo 160, contraseña 12-128 y contexto 400 caracteres. No recortar espacios de la contraseña.

REQUERIDO: guardar contraseña con hash seguro; estado `pending`, acceso desactivado, `isMaster=false`, sin local asignado. Rechazar `role,isActive,isMaster,businessId,approvalStatus` inyectados en el registro. Un correo duplicado recibe el mismo acuse sin reemplazar su contraseña, permisos ni decisión anterior. Aplicar límites de intentos y verificación de email en producción.

Con contraseña correcta: pendiente -> `403 ACCESS_PENDING`; rechazado -> `403 ACCESS_REJECTED`; suspendido -> `403 ACCESS_REVOKED`. Con credenciales incorrectas, respuesta 401 genérica. Ninguno de esos casos debe emitir una sesión operativa.

| Método y ruta | Body | Resultado |
| --- | --- | --- |
| POST `auth/forgot-password` | `{"email":"persona@utsjr.edu.mx"}` | 204 genérico, exista o no la cuenta |
| POST `auth/reset-password` | `{"token":"<un-solo-uso>","newPassword":"<nueva>"}` | 204 y revocación de sesiones |

El correo enviado por el backend debe llevar a `https://<host>/#/reset-password?token=<token>`. El token de recuperación debe caducar, ser de un solo uso y validarse en servidor; no es un access token. Al cambiar contraseña, invalidar sesiones anteriores. Token inválido/usado/caducado: 422, por ejemplo `RESET_TOKEN_INVALID`.

ACTUAL: el formulario de restablecimiento exige 12-128 caracteres y muestra “enlace expirado o utilizado” para cualquier 422. Si el backend agrega otras políticas de contraseña, coordinar sus errores y la interfaz para no dar un mensaje equivocado. El simulador no envía correo y no restablece contraseñas realmente.

<!-- page -->
# 9. Google: identidad y aprobación son pasos distintos

ACTUAL: Google se habilita únicamente si `GET auth/options` devuelve `googleEnabled=true`. El frontend navega a `GET auth/google/start` del backend; no usa un token de Google para asignarse permisos ni envía un retorno libre.

REQUERIDO: implementar OpenID Connect del lado del servidor. Configurar cliente, secreto, callback exacto y dominio real; mantener secretos fuera de Flutter y Git. Utilizar una biblioteca mantenida y el flujo de autorización definido por Google. Comprobar `state`, `nonce`, firma, emisor, audiencia, expiración y `email_verified`. La identidad estable es `iss + sub`, no el texto del correo. [Referencia oficial](https://developers.google.com/identity/openid-connect/openid-connect).

| Resultado del callback | Acción del backend | Retorno a la web |
| --- | --- | --- |
| Identidad nueva | Crear solicitud pendiente, sin rol operativo | `/#/access-pending` |
| Cuenta todavía pendiente | No emitir sesión operativa | `/#/access-pending` |
| Cuenta rechazada | Mantener bloqueo | `/#/access-rejected` |
| Cuenta aprobada y activa | Emitir cookie segura; restaurar con refresh/users/me | Raíz del portal |
| Error o cancelación | Sin sesión nueva | `/#/google-error` |
| Correo existente sin vínculo autorizado | Exigir vinculación autenticada y aprobada | `/#/account-link-required` |

Los fragmentos URL anteriores solo muestran mensajes. Abrirlos manualmente no puede autorizar nada. Nunca poner access tokens, refresh tokens ni secretos OAuth en la URL del portal.

La cookie temporal de OAuth puede necesitar `SameSite=Lax` para el retorno externo; debe ser diferente de la cookie operativa, corta, HttpOnly y Secure, y eliminarse al terminar. La política final debe probarse en los navegadores objetivo. No desactivar la protección de origen de toda la API para habilitar OAuth.

PENDIENTE: todavía no hay interfaz de vinculación de cuentas locales con Google ni endpoints de vinculación consumidos por el frontend. El mensaje informa del caso; no representa una vinculación implementada. Diseñar ese flujo como trabajo adicional, sin enlazar cuentas automáticamente solo porque coinciden los correos.

Google y el envío externo de correo necesitan conectividad con sus proveedores. Un despliegue “local” puede almacenar SQL en la universidad y aun requerir Internet para estas funciones. Si no están disponibles, mantener el acceso local por contraseña y reportar opciones honestamente; el simulador responde `googleEnabled=false`.

<!-- page -->
# 10. Roles y administración de cuentas

| Operación | Maestro: admin + isMaster | Admin ordinario | Operador business |
| --- | --- | --- | --- |
| Consultar gráficas, opiniones y seguimientos | Sí | Sí | No |
| Crear/editar/activar locales vía admin/businesses | Sí | Sí | No |
| Listar/crear/editar cuentas y decidir solicitudes | Sí | No | No |
| Cocina, productos, entrega, historial y ventas operativas | No | No | Solo su local |
| Cambiar al panel de otro rol o suplantar un operador | No | No | No |

`isMaster` es una capacidad del rol `admin`, no un rol adicional ni un interruptor público. `role=user` pertenece al alumnado y no abre estos paneles. No confiar en un correo “maestro” fijo: la capacidad debe comprobarse en el registro autorizado del servidor.

| Método y ruta, solo maestro | Entrada | Salida |
| --- | --- | --- |
| GET `admin/users?page=1&limit=20&q=` | Búsqueda por nombre/correo | Lista paginada de perfiles |
| POST `admin/users` | Body de alta mostrado abajo | 201, perfil completo |
| PATCH `admin/users/{id}` | Campos editables y `expectedVersion` | 200, perfil actualizado |

```json
{
  "displayName": "Operador autorizado",
  "email": "operador@ejemplo.test", "password": "<inicial-segura>",
  "role": "business", "businessId": "local-1", "isActive": true
}
```

Editar envía `displayName,email,role,businessId,isActive,expectedVersion`; no cambia contraseña mediante ese formulario. Para admin, `businessId=null`. Responder como mínimo `id,email,displayName,role,businessId,isActive,isMaster,version`, y fechas recomendadas. No incluir hashes ni tokens.

REQUERIDO: correo normalizado único; nuevos admins solo de los dominios exactos de `institution.adminEmailDomains`; una cuenta operadora activa por local como regla actual. Dos dispositivos pueden iniciar con esa cuenta; no son dos operadores distintos registrados.

Proteger el maestro, la última cuenta administrativa activa y los cambios sobre la propia sesión. No promover otro maestro mediante estos endpoints. Pendientes se autorizan por el flujo de solicitudes, no por PATCH de usuario. Cambiar rol, local o suspensión debe revocar sesiones y suscripciones previas. Usar transacciones y restricciones para impedir dos asignaciones simultáneas al mismo local.

<!-- page -->
# 11. Solicitudes de acceso y decisión del maestro

GET `admin/access-requests?page=1&limit=30` devuelve únicamente pendientes y exige `role=admin` e `isMaster=true`. El frontend no envía búsqueda en esta lista.

```json
{
  "id": "solicitud-1", "displayName": "Persona solicitante",
  "email": "persona@utsjr.edu.mx", "requestedRole": "admin",
  "requestContext": "Apoyaré la supervisión de la cafetería.",
  "provider": "password", "emailVerified": true,
  "approvalStatus": "pending", "version": 1,
  "createdAt": "2026-10-12T17:00:00Z"
}
```

El frontend interpreta `provider=google` como Google; cualquier otro valor se muestra como contraseña de SnackUP. Envolver registros en `data` y `pagination`. Nunca exponer la contraseña guardada de una solicitud.

```http
POST /api/v1/admin/access-requests/solicitud-1/decision
```

```json
{
  "decision": "approve", "role": "business",
  "businessId": "local-1", "identityConfirmed": true,
  "note": "Identidad y asignación revisadas por el maestro.",
  "expectedVersion": 1
}
```

`decision`: `approve` o `reject`. Para administración, `businessId=null`. Nota de hasta 500 caracteres. La pantalla envía `identityConfirmed` como booleano, no como string. El campo indica la decisión humana; el backend debe aplicar además el requisito productivo de verificación de correo acordado.

En una transacción: validar actor maestro, versión y estado pendiente; confirmar identidad; comprobar dominio si se autoriza admin; comprobar local activo y libre si se autoriza business; asignar permisos; marcar aprobado/activo; incrementar versión; guardar auditoría. Al rechazar: mantener inactivo y sin rol operativo. Respuesta recomendada 200 con perfil actualizado; la pantalla recarga la lista.

Errores de integración: `409 REQUEST_ALREADY_REVIEWED`, `409 VERSION_CONFLICT`, `422 IDENTITY_CONFIRMATION_REQUIRED`, `422 BUSINESS_REQUIRED`, `409 BUSINESS_ALREADY_ASSIGNED`, `422 INSTITUTIONAL_EMAIL_REQUIRED`.

La pantalla carga los locales en páginas de 20, hasta 100 páginas, para asignar la solicitud. No debe existir una segunda ruta que permita saltarse la autorización. Si se necesitan varios operadores activos por local, hay que modificar explícitamente la regla de asignación y las validaciones del frontend; no habilitarlo solo en SQL.

<!-- page -->
# 12. Institución, carreras y grupos

GET `institution` requiere sesión y devuelve el siguiente objeto. Puede incluir otros campos, pero estos son los que la configuración actual utiliza:

```json
{
  "university": {
    "id": "utsjr",
    "name": "Universidad Tecnológica de San Juan del Río"
  },
  "cafeteria": {"id": "cafeteria-1", "name": "Cafetería universitaria"},
  "adminEmailDomains": ["utsjr.edu.mx"]
}
```

Los dominios deben ser strings válidos en minúsculas y la lista no debe estar vacía. La validación compara el dominio completo: `utsjr.edu.mx.ejemplo.com` no es `utsjr.edu.mx`. Los IDs de la institución y cafetería son estables aunque cambien sus nombres.

GET `admin/academic-catalog?page=1&limit=200`, solo administración:

```json
{
  "data": [
    {"id": "carrera-dsm", "kind": "career",
     "name": "Desarrollo de Software"},
    {"id": "grupo-dsm-1", "kind": "group",
     "name": "DSM-1", "careerId": "carrera-dsm"}
  ],
  "pagination": {"page": 1, "limit": 200, "total": 2, "totalPages": 1}
}
```

REQUERIDO: IDs únicos en todo el catálogo devuelto, incluso entre carreras y grupos. Cada grupo debe referenciar una carrera presente. No devolver solo grupos con opiniones: el catálogo representa las opciones completas. Mantener orden estable y relaciones consistentes mientras se cargan sus páginas.

ACTUAL: el cliente obtiene hasta 100 páginas de 200 entradas, valida duplicados/referencias y construye carrera -> grupo. Ofrece búsqueda y deshabilita grupo hasta elegir carrera. Superar 20,000 entradas requiere una evolución del selector y de la API, no una respuesta truncada silenciosamente.

Las opiniones deben incluir `careerId,groupId` además de `career,group` como nombres de presentación. Los filtros priorizan IDs y mantienen compatibilidad por nombre para registros antiguos sin IDs. Evitar nombres contradictorios para un mismo ID: algunas agrupaciones visuales siguen usando los nombres.

PENDIENTE: no existen formularios REST de alta/edición de carreras y grupos en estos paneles. El backend debe tener un proceso de importación o gestión del padrón acordado con la universidad. No suponer que esta pantalla ya lo administra.

<!-- page -->
# 13. Locales: operación y gestión administrativa

**Business: respuesta recomendada completa**

```json
{
  "id": "local-1", "name": "Local autorizado",
  "category": "Cafetería", "description": "Descripción del local",
  "cafeteriaId": "cafeteria-1", "cafeteriaName": "Cafetería universitaria",
  "timezone": "America/Mexico_City",
  "isOpen": false, "isActive": true, "version": 1,
  "createdAt": "2026-10-12T15:00:00Z",
  "updatedAt": "2026-10-12T15:00:00Z"
}
```

| Quién | Método/ruta | Body o consulta |
| --- | --- | --- |
| Operador propio | GET `businesses/{id}` | Sin body; devuelve Business |
| Operador propio | PATCH `businesses/{id}` | `name,category,description,expectedVersion` |
| Operador propio | PATCH `businesses/{id}/status` | `isOpen,expectedVersion` |
| Admin | GET `admin/businesses` | Gestión: `page,limit=20,q`; monitor: `page,limit=200` |
| Admin | POST `admin/businesses` | `name,category,description,isActive,cafeteriaId,timezone` |
| Admin | PATCH `admin/businesses/{id}` | `name,category,description,isActive,cafeteriaId,expectedVersion` |

Lecturas y ediciones responden 200; alta responde 201 con Business completo. Límites: nombre 100, categoría 60, descripción 600. No aceptar un cambio arbitrario de cafetería por copiar el body: validar la pertenencia en servidor.

`isActive` representa habilitación administrativa. `isOpen` representa recepción de pedidos. Son conceptos distintos. Crear un local con recepción cerrada; al desactivarlo, conservar productos/historial y detener recepción. Si tiene pedidos activos, responder `409 BUSINESS_HAS_ACTIVE_ORDERS` y exigir resolverlos antes.

Cerrar recepción no cancela pedidos recibidos: estos deben poder terminar su flujo. El endpoint de creación de pedidos del alumno rechaza pedidos nuevos con `409 BUSINESS_CLOSED` si el local está cerrado.

REQUERIDO: el operador solo puede modificar la ficha y recepción de su `businessId`. Administración utiliza las rutas `admin/businesses`, no las operativas. Incluso el maestro recibe 403 al intentar operar por las rutas del local.

ACTUAL: no hay botón para eliminar un local, reasignar la cafetería ni fijar horarios semanales. La desactivación mantiene trazabilidad. Las cuentas reales de los cuatro locales se crean por el equipo; el backend no debe generar cuentas automáticas por cada número de local.

<!-- page -->
# 14. Productos: contrato CRUD y precios

| Método/ruta, solo operador del local | Entrada | Respuesta |
| --- | --- | --- |
| GET `businesses/{id}/products` | `page=1,limit=20,q,isAvailable` | 200 con `data,pagination` |
| GET `products/{id}` | Sin body | 200 Product |
| POST `businesses/{id}/products` | ProductDraft | 201 Product |
| PATCH `products/{id}` | ProductDraft + `expectedVersion` | 200 Product actualizado |
| DELETE `products/{id}` | JSON `{"expectedVersion":4}` | 204 sin cuerpo |

```json
{
  "id": "producto-1", "businessId": "local-1",
  "name": "Torta de pollo", "description": "Preparada al momento",
  "category": "Comida", "price": 55.00,
  "stock": 40, "imageUrl": null,
  "isAvailable": true, "isFeatured": false,
  "version": 4, "updatedAt": "2026-10-12T18:00:00Z"
}
```

ProductDraft contiene `name,description,category,price,stock,imageUrl,isAvailable,isFeatured`. No enviar `id,businessId,version` como campos editables. El servidor obtiene el local de la ruta o del producto persistido, nunca de una asignación arbitraria del body.

| Campo | Regla compatible con el formulario |
| --- | --- |
| name / category / description | 1-160 / 1-120 / hasta 2000 caracteres |
| price | Número, 0.01 a 10,000.00 MXN; máximo dos decimales |
| stock | Entero 0-1,000,000 o null: sin inventario controlado |
| isAvailable / isFeatured | Booleanos JSON; stock=0 implica no disponible |
| imageUrl | String de imagen servida o null |
| version / updatedAt | Versión entera del servidor y fecha UTC válida |

**Omisión y null son diferentes:** al editar, si el usuario no cambió stock, el cliente elimina `stock` del PATCH. El backend debe conservarlo. Si llega `stock:null`, se solicita dejar de controlar inventario. Nunca convertir un campo omitido a null ni reiniciar stock con el valor de un formulario anterior. Este detalle protege las existencias al cambiar solo el precio.

La API compara `expectedVersion`, guarda e incrementa versión. `409 VERSION_CONFLICT` obliga a recargar. Cambiar precios no altera los snapshots de pedidos existentes. Para borrar productos con historial, se propone baja lógica y conservar order_items; no borrar en cascada las ventas. El cliente no dispone de DELETE media ni de un endpoint separado de disponibilidad: usa este mismo PATCH.

<!-- page -->
# 15. Imágenes de productos

ACTUAL: el catálogo envía la subida a `POST media` con autorización del operador. No manda `businessId` en el multipart; el servidor debe resolverlo desde la cuenta.

```http
POST /api/v1/media
Authorization: Bearer <token-operador>
Content-Type: multipart/form-data; boundary=<generado-por-cliente>
```

Campos multipart: **`purpose=product`** y **`file`** con nombre, tipo y bytes. La librería HTTP genera el boundary; no reemplazarlo manualmente por un encabezado JSON.

```json
{"id": "imagen-1", "url": "https://snackup.example/media/imagen-1.webp"}
```

Respuesta 201. El único campo obligatorio para el frontend actual es `url` string; se permite añadir `id,width,height`. Después, el formulario envía esa URL en `Product.imageUrl` al guardar el producto.

REQUERIDO: archivo no vacío de hasta **5 * 1024 * 1024 bytes**, tipos JPEG, PNG o WebP. Validar tamaño y contenido real, no solo extensión/MIME; generar un nombre interno seguro; impedir ejecución y recorridos de rutas; limitar dimensiones y costo de decodificación. El cliente ya revisa firmas básicas, pero no sustituye la validación del servidor.

Servir una URL que pueda cargar el navegador desde móvil y PC. Se recomienda HTTPS absoluto del dominio del despliegue. Una URL relativa al origen de la web también puede utilizarse si el proxy sirve allí `/media/`. No devolver `C:\\...`, rutas de disco, nombres internos del contenedor ni `http://localhost` para usuarios de otros equipos.

ACTUAL: la imagen se muestra mediante una URL y no hay un interceptor para añadir bearer a cada descarga de imagen. Si las imágenes requieren privacidad, diseñar URLs temporales o una ruta same-origin autorizada por cookie, y comprobar su integración. No exigir un encabezado personalizado que el widget no envía.

PROPUESTA de almacenamiento local: directorio de medios fuera del código desplegado, tabla de metadatos con dueño/local/tamaño/tipo y copia de seguridad. La carpeta debe sobrevivir a actualizaciones y restaurarse junto con SQL. Eliminar medios huérfanos con una tarea controlada; el frontend no ejecuta `DELETE media/{id}` hoy.

Errores compatibles: 413 para exceso de tamaño, 422 para formato inválido, 403 para falta de permiso. El proxy debe permitir el límite completo más la envoltura multipart; se propone `client_max_body_size 6m`, manteniendo en aplicación el máximo real del archivo.

<!-- page -->
# 16. Modelo de pedido que recibe Cocina

Los nombres y precios de `items` son snapshots confirmados al crear el pedido. No volver a consultarlos del producto actual para reconstruir ventas históricas.

```json
{
  "id": "pedido-1", "businessId": "local-1", "orderNumber": 1051,
  "version": 3, "status": "preparing", "customerName": "Cliente",
  "items": [{
    "id": "renglon-1", "productId": "producto-1",
    "name": "Torta de pollo", "price": 55.00,
    "quantity": 2, "notes": "Sin cebolla"
  }],
  "subtotal": 110.00, "total": 110.00, "paymentMethod": "Efectivo",
  "createdAt": "2026-10-12T18:00:00Z",
  "acceptedAt": "2026-10-12T18:01:00Z",
  "preparingAt": "2026-10-12T18:02:00Z",
  "readyAt": null, "completedAt": null, "cancelledAt": null,
  "updatedAt": "2026-10-12T18:02:00Z",
  "scheduledPickupTime": null,
  "cancelReason": null, "cancelNotes": null, "cancelledBy": null
}
```

REQUERIDO por el parser de cocina: `id,businessId` no vacíos; `orderNumber,version` enteros positivos; `status` válido; `createdAt` válido; `total` numérico no negativo; `items` no vacío y cada item con `name`, `quantity>=1`, `price>=0`. Los nombres/opciones adicionales deben tener tipos coherentes, incluso si hoy el parser es tolerante.

| Petición del operador | Resultado |
| --- | --- |
| GET `businesses/{id}/orders/active?page=1&limit=200` | Lista de pending, accepted, preparing y ready |
| GET `orders/{id}` | Un pedido de su local, en cualquier estado autorizado |

El cliente carga todas las páginas de activos antes de sustituir el tablero, deduplica por ID conservando la versión mayor y ordena por fecha de creación. Límite actual: 50 páginas de 200. No enviar deltas incompletos a esa llamada: el frontend **no envía `updatedSince`** y espera la foto completa.

No entregar `pickupCode` ni `customerNumeroDeControl` a las lecturas de cocina, al historial ni a eventos del negocio. El código debe aportarlo el cliente al entregar. La vista del alumno propietario puede recibir su código mediante su propio contrato; no reutilizar sin filtrar el DTO público de cocina.

`orderNumber` es entero por local y lo asigna el servidor sin duplicados. Los pedidos activos deben desaparecer de esa lista después de completed/cancelled, y aparecer en el historial correspondiente.

<!-- page -->
# 17. Acciones de Cocina y entrega

| Estado actual | POST `orders/{id}/...` | Estado nuevo | Campos del body |
| --- | --- | --- | --- |
| pending | `accept` | accepted | `expectedVersion` |
| accepted | `start` | preparing | `expectedVersion` |
| preparing | `ready` | ready | `expectedVersion` |
| ready | `complete` | completed | `expectedVersion,method,code` |
| pending / accepted / preparing | `cancel` | cancelled | `expectedVersion,reason,notes?` |

ACTUAL: Nuevos muestra pending; Preparando agrupa accepted y preparing; Listos muestra ready. La aceptación es explícita: el backend no debe crear el pedido directamente aceptado ni saltarse pasos para “simplificar” la cocina. No existe estado `rejected`; rechazar un pedido se representa como cancelled.

```json
{"expectedVersion": 3}
```

```json
{"expectedVersion": 4, "method": "manual", "code": "4821"}
```

```json
{"expectedVersion": 2, "reason": "other", "notes": "Falla del equipo"}
```

Toda transición correcta devuelve **200 con el Order actualizado completo**, mismo ID/local y `version` estrictamente mayor. El servidor escribe fecha y actor; el cliente no debe elegirlos. `completed` y `cancelled` son finales. `ready` no admite cancelación en este flujo.

Catálogo `reason`: `product_unavailable`, `cannot_prepare`, `store_issue`, `store_closing`, `other`. Para `other` se requiere nota no vacía; límite del formulario 500 caracteres. `cancelledBy` se calcula desde el actor, no desde el body.

Entrega: `method` admite `qr` o `manual`. `code` contiene el texto leído o escrito, hasta 128 caracteres en la pantalla. El QR actual entrega el código como texto; no se debe exigir un JSON nuevo sin adaptar también su emisor y el lector. Validar en servidor para ese pedido y local; un código incorrecto produce `422 VERIFICATION_FAILED` sin cambiar el estado.

ACTUAL: el formulario también ofrece número de control como respaldo manual, y el simulador lo acepta. Es una credencial fija más débil. PENDIENTE de decisión: mantener ese respaldo con límites/auditoría o retirarlo coordinando el texto y el backend. No asumir que ya se exige únicamente código de un solo pedido.

Guardar internamente `verification={method,verifiedAt,verifiedBy}`. Limitar intentos y registrar fallos sin escribir códigos completos en logs. Una entrega correcta no equivale a confirmar un cobro o ejecutar una transferencia bancaria.

<!-- page -->
# 18. Inventario, concurrencia e idempotencia

REQUERIDO: toda escritura de un recurso existente valida `expectedVersion` antes de modificarlo, dentro de la misma transacción. No basta con hacer SELECT, comprobar versión y luego UPDATE sin condición o bloqueo.

```sql
UPDATE orders
SET status = :new_status,
    version = version + 1,
    updated_at = :server_time
WHERE id = :order_id
  AND business_id = :authorized_business
  AND version = :expected_version
  AND status = :allowed_previous_status;
```

Este fragmento es una referencia SQL parametrizada, no una migración ejecutable completa. Si no se actualiza la fila, distinguir de manera autorizada entre inexistencia, conflicto de versión y transición inválida. No revelar datos de otro local en `details`.

La propuesta v3 del equipo reserva/descuenta stock al crear el pedido, no al aceptarlo. Mantener una sola política: comprobar disponibilidad e inventario de todos los renglones, copiar precios, asignar número y guardar pedido en una transacción. Si un producto no alcanza, no dejar reservas parciales ni un pedido incompleto.

Al cancelar: devolver una sola vez el stock controlado reservado y escribir cancelación/auditoría en la misma transacción. Stock null no se modifica. Bloquear o actualizar productos en orden estable para reducir interbloqueos. Actualizar su versión si cambian existencias/disponibilidad y mantener la regla stock=0 -> no disponible.

No reenviar automáticamente una mutación si se cortó la conexión: pudo guardarse. El frontend refresca ante `TIMEOUT`, `NETWORK`, `VERSION_CONFLICT` o transición inválida. La API devuelve el estado confirmado. El caso de dos tablets aceptando el mismo pedido debe producir un éxito y un conflicto, nunca dos efectos.

**Creación desde la app del alumno:** el documento v3 propone `Idempotency-Key` en `POST orders`. Guardar actor + clave + huella del body + resultado en una transacción; una repetición idéntica reutiliza resultado, una clave con otro body se rechaza. No caducar la clave antes del periodo de reintento acordado.

ACTUAL: las acciones de cocina envían versión, pero no `Idempotency-Key`. Si se desea exigir esa cabecera en esas acciones, es una extensión que también requiere cambio en el frontend. Mientras tanto, el control de versión y las transiciones deben impedir duplicaciones. Emitir eventos solo después del commit; se propone una outbox transaccional para no perder notificaciones entre SQL y WebSocket.

<!-- page -->
# 19. Historial y resumen de ventas

| Método/ruta, operador propio | Parámetros reales |
| --- | --- |
| GET `businesses/{id}/orders/history` | `date=YYYY-MM-DD&page=1&limit=30` |
| GET `businesses/{id}/stats` | `from=YYYY-MM-DD&to=YYYY-MM-DD` |

```json
{
  "data": [],
  "summary": {"completed": 0, "cancelled": 0, "totalSold": 0},
  "pagination": {"page": 1, "limit": 30, "total": 0, "totalPages": 0}
}
```

El ejemplo anterior representa un día sin pedidos finalizados. Con pedidos, devolver objetos Order completos en `data` y la paginación correspondiente. El resumen siempre corresponde al día completo, aunque sus pedidos ocupen varias páginas; no sumar únicamente las filas visibles.

Stats devuelve directamente el resumen del rango solicitado; por ejemplo, para un rango con actividad:

```json
{"completed": 12, "cancelled": 2, "totalSold": 860.50}
```

REQUERIDO: `completed` cuenta entregados; `cancelled` cuenta cancelados; `totalSold` suma solo el total confirmado de entregados. No incluir pendientes, aceptados, en preparación o listos. No interpretar “ventas entregadas” como conciliación financiera de efectivo o transferencias: esa parte no está implementada en estos paneles.

Filtrar entregas por `completedAt` y cancelaciones por `cancelledAt`, en la fecha local de la universidad, no por createdAt. Un pedido creado antes de medianoche y entregado después pertenece a las ventas del día de entrega.

Rangos inclusivos: convertir `from` 00:00 local y el día posterior a `to` 00:00 local a UTC; consultar `>= inicio` y `< fin_exclusivo`. Esto evita perder fracciones de segundo al usar 23:59:59. Validar `from<=to` y fechas reales. Resumen sin pedidos: tres ceros.

ACTUAL: Historial abre hoy; Resumen abre los últimos siete días, incluyendo hoy. El frontend calcula las fechas de la universidad con UTC-6 fijo. Aunque Business tenga `timezone`, cambiarlo a otra zona no cambia automáticamente esa lógica: soportar otras zonas exige adaptar frontend y pruebas.

PROPUESTA: índice por local + fecha de entrega y por local + fecha de cancelación, con orden estable para la paginación. El detalle público debe seguir ocultando códigos de recogida y números de control. Conservar los snapshots originales aunque se edite o se retire el producto.

<!-- page -->
# 20. Administración: opiniones y lecturas del monitor

| Método/ruta, solo admin | Consulta | Respuesta |
| --- | --- | --- |
| GET `admin/businesses` | `page=n&limit=200` | Lista de Business |
| GET `admin/reviews` | `page=n&limit=200` | Lista de Review |
| GET `admin/followups` | `page=n&limit=200` | Lista de Followup |

Cada lista debe devolver `data` y `pagination`. El repositorio usa paginación independiente para cada colección y no avanza sus contadores si una petición o un registro falla. `admin/businesses` también sirve gestión con límite 20: debe satisfacer el modelo Business completo del apartado 13, no devolver una proyección reducida que rompa esa pantalla.

```json
{
  "id": "opinion-1", "businessId": "local-1",
  "rating": 4, "foodRating": 5, "serviceRating": 3,
  "careerId": "carrera-dsm", "groupId": "grupo-dsm-1",
  "career": "Desarrollo de Software", "group": "DSM-1",
  "comment": "Buena comida; la entrega puede mejorar.",
  "createdAt": "2026-10-12T18:25:00Z"
}
```

REQUERIDO: `id,businessId` no vacíos; ratings enteros 1-5; comentario string; fecha UTC; referencias académicas consistentes. En opiniones antiguas sin una dimensión, enviar null u omitir esa dimensión; no convertir “no evaluado” en cero ni fabricar una calificación.

El backend puede almacenar `orderId,userId,schemaVersion` para validar propiedad y evitar reseñas duplicadas, pero el panel no necesita exponer matrícula, correo o nombre del alumno en el DTO de opinión. El comentario también puede contener datos personales: aplicar la política de contenido acordada sin alterar las calificaciones históricas en secreto.

La creación de opiniones corresponde a la app del alumno y a su backend. Validar pedido propio, local correcto, estado completed y unicidad antes de incorporar una opinión a este monitor. El panel administrativo **no crea ni edita calificaciones**.

ACTUAL: el monitor solicita referencias institucionales/académicas y páginas de las tres colecciones. Actualiza cada 60 segundos mientras está visible, al regresar de gestión y con Actualizar. Si faltan páginas muestra resultados parciales y permite cargar 200 más. La UI vuelve a leer las páginas ya cargadas durante una actualización.

No hay una llamada REST de agregados de gráficas en esta versión. Agregar `/admin/analytics` en el backend no hará que aparezca su resultado hasta modificar el repositorio y la pantalla. Mantener estas lecturas o acordar una migración de contrato explícita.

<!-- page -->
# 21. Cómo se calculan las gráficas y los filtros

Fuente: `features/admin/domain/admin_models.dart` y `admin_dashboard_screen.dart`. ACTUAL: las estadísticas del monitor se calculan en Flutter a partir de las opiniones **cargadas y filtradas**. Son dinámicas, pero no representan automáticamente toda la base SQL si faltan páginas.

| Indicador | Cálculo actual |
| --- | --- |
| Calificación general | Suma de rating válidos / cantidad de rating válidos |
| Servicio y alimentos | Media independiente de serviceRating y foodRating válidos |
| Opiniones recibidas | Número de registros de la vista filtrada |
| Opiniones negativas | Cantidad de rating 1 o 2 |
| Porcentaje negativo | Negativas / cantidad de rating válidos * 100 |
| Evolución diaria | Promedio por día local con opiniones; no rellena días sin datos |
| Distribución de estrellas | Conteo separado de 1, 2, 3, 4 y 5 |
| Opinión por carrera | Promedio y cantidad agrupados por nombre de carrera |
| Casos por atender | Negativas o con seguimiento cuyo estado no sea resolved |

No usar promedio de promedios por local para obtener el global: cada opinión válida pesa lo mismo. Las dimensiones ausentes tienen denominadores distintos. Si no hay valores válidos, devolver/presentar ausencia; un 0 no es una estrella válida. Con un único día se muestra el valor, sin fingir una tendencia.

Filtros actuales: local, carrera, grupo dependiente de carrera, periodo de 7/30/90 días o todo el historial, horario de publicación, texto del comentario y solo 1-2 estrellas. Los rangos de días incluyen el día actual desde medianoche de la universidad y excluyen fechas futuras.

Horario: mañana 06:00-11:59; tarde 12:00-17:59; noche 18:00-05:59. Se filtra la **fecha de publicación de la opinión**; no mide tiempo de espera. El grupo usa su ID y relación de carrera cuando están disponibles, con compatibilidad por nombre en datos antiguos.

**Qué llega al backend hoy:** estos filtros del monitor no se envían como query a `admin/reviews`; se aplican en el cliente. No cambiar unilateralmente la API para devolver solo un resumen o un rango oculto. Ordenar/paginar de forma estable y comunicar el total real de páginas.

PROPUESTA para volúmenes mayores: definir agregados SQL y filtrado de servidor con rango, zona, dimensiones, totales y semántica documentada. Ese trabajo requiere nuevos modelos, repositorio y pruebas de equivalencia en frontend. La propuesta v3 decía que el servidor calcularía promedios oficiales; ese agregado todavía no es el que consume este monitor.

<!-- page -->
# 22. Atención de opiniones: seguimiento e historial

“Atención” o “seguimiento y acuerdos” se refiere al registro administrativo de una respuesta a una opinión. No cambia un pedido ni ordena acciones de cocina. `assignee` es texto descriptivo; no asigna permisos ni envía mensajes a una persona.

| Método/ruta, solo admin | Body/consulta | Respuesta |
| --- | --- | --- |
| GET `admin/reviews/{id}/followup` | Sin cuerpo | 200 Followup; 404 específico si no existe |
| PUT `admin/reviews/{id}/followup` | `status,assignee,note,expectedVersion` | 200 Followup actualizado |
| GET `admin/reviews/{id}/followup/history` | `page=1&limit=50` | Lista paginada de eventos |

```json
{
  "reviewId": "opinion-1", "businessId": "local-1",
  "status": "in_review", "assignee": "Responsable de supervisión",
  "note": "Se revisará el procedimiento de entrega.",
  "version": 2, "updatedAt": "2026-10-12T19:00:00Z"
}
```

```json
{
  "status": "resolved", "assignee": "Responsable de supervisión",
  "note": "Se documentó el acuerdo y su revisión.", "expectedVersion": 2
}
```

Estados: `pending` -> Pendiente, `in_review` -> En revisión, `resolved` -> Resuelto. El formulario permite elegir cualquiera; no hay una máquina obligatoria de transiciones entre ellos. Responsable no vacío de hasta 120 caracteres y nota no vacía de hasta 2000.

Para una opinión existente sin seguimiento: **404 `FOLLOWUP_NOT_FOUND`**. Solo ese código crea en el cliente un caso vacío con `version=0`. PUT con `expectedVersion=0` significa “crear si todavía no existe”. Una opinión inexistente o ajena debe producir otro error, no este código.

REQUERIDO: seguimiento único por reviewId. En una misma transacción, comprobar versión, guardar el estado, incrementar versión y añadir un evento inmutable al historial con actor/fecha del servidor. La respuesta debe mantener reviewId/businessId correctos, versión mayor y updatedAt no nulo.

Si dos admins abren el mismo caso, solo uno puede guardar con la versión anterior; el otro recibe 409 y conserva su nota para revisar conscientemente. Historial sin eventos: lista vacía con paginación válida. El cliente muestra como máximo los 50 eventos de la primera página y avisa si hay más; no implementa navegación del historial completo.

Cada fila de `history.data` debe tener la misma forma de Followup: `reviewId,businessId,status,assignee,note,version,updatedAt`, con el snapshot de esa revisión. No devolver solo `{action,actor,timestamp}`: ese formato no lo interpreta el parser actual. Se pueden añadir `id,actorId` para trazabilidad; hoy la pantalla no consume esos campos. Orden recomendado: más reciente primero, con desempate estable.

<!-- page -->
# 23. WebSocket compatible con el cliente actual

ACTUAL: `OperationsRealtime` usa **WebSocket nativo**, no el protocolo Socket.IO. URL: base REST + `realtime`, convertida de https a wss o de http a ws. Ejemplo: `wss://snackup.example/api/v1/realtime`.

```json
{"action":"auth","token":"<accessToken>"}
{"action":"subscribe","topics":["business:local-1:orders","business:local-1"]}
```

El cliente envía auth y subscribe consecutivamente. El backend debe procesarlos en orden y no suscribir antes de validar la identidad. Confirmación requerida:

```json
{"type":"subscribed","topics":["business:local-1:orders","business:local-1"]}
```

```json
{
  "id":"evento-unico-1", "type":"order.updated",
  "topic":"business:local-1:orders",
  "occurredAt":"2026-10-12T18:20:00Z",
  "data":{"id":"pedido-1","version":4,"status":"ready"}
}
```

El contrato v3 permite Order completo como data; enviar una proyección autorizada sin códigos privados. El frontend actual usa el evento como aviso y vuelve a consultar REST, por lo que no necesita confiar en el payload para escribir su estado.

Eventos reconocidos: `order.created`, `order.updated`, `business.updated`. Se ignoran temas ajenos, tipos desconocidos e IDs repetidos; memoria de deduplicación limitada a 1000 IDs. No se suscribe a productos ni opiniones hoy; `product.updated` por sí solo no refresca este catálogo.

| Comportamiento actual | Tiempo |
| --- | --- |
| Espera de confirmación de suscripción | 10 s |
| Consulta REST de respaldo sin suscripción | Cada 10 s |
| Reconciliación REST con suscripción | Cada 60 s |
| Agrupación de avisos antes de recargar | 350 ms |
| Reautenticación del socket | Cada minuto |
| Reconexión | 10 s; desde tres fallos, 60 s |

Servidor puede enviar `{"type":"ping"}`; cliente responde `{"action":"pong"}`. Al ocultar el panel se cierran conexiones y temporizadores; al volver se recarga. No ofrecer notificaciones garantizadas con la pestaña cerrada: Web Push no está integrado aquí.

REQUERIDO: comprobar Origin, token y propiedad de cada topic; revalidar al reautenticar y cerrar accesos revocados. La cuenta maestra no puede suscribirse a pedidos de cocina. El simulador devuelve 503 `POLLING_MODE`: demuestra el respaldo, no un WebSocket productivo funcionando.

<!-- page -->
# 24. Errores y recuperación de la interfaz

Mantener el sobre `error.code,message,details` del apartado 6. Las frases pueden mejorar; los códigos que reconoce el cliente deben conservarse. No enviar trazas SQL, contraseñas, tokens ni datos de otra cuenta.

| HTTP | Código / situación | Comportamiento esperado |
| --- | --- | --- |
| 400 | Solicitud mal formada | Rechazar sin efectos; explicar campos públicos |
| 401 | TOKEN_EXPIRED | Renovar y reintentar una sola vez; sin efectos previos |
| 401 | Credenciales o sesión inválidas | Volver al acceso; mensaje genérico para login |
| 403 | ACCESS_PENDING / ACCESS_REJECTED | Informar estado; no crear sesión operativa |
| 403 | ACCESS_REVOKED / ROLE_REVOKED | Invalidar acceso previo; cerrar suscripciones |
| 403 | FORBIDDEN / MASTER_REQUIRED | No reintentar con otros IDs ni conceder privilegios |
| 404 | Recurso ausente o no visible | No revelar recursos de otros locales |
| 404 | FOLLOWUP_NOT_FOUND | Solo opinión válida sin seguimiento: permitir versión 0 |
| 409 | VERSION_CONFLICT | Volver a consultar; conservar cambios para revisar |
| 400 / 409 | INVALID_STATUS_TRANSITION | Refrescar pedido; no forzar estado |
| 409 | EMAIL_EXISTS / BUSINESS_ALREADY_ASSIGNED | Mostrar conflicto en alta/edición autorizada |
| 409 | BUSINESS_HAS_ACTIVE_ORDERS | Impedir desactivación hasta terminar pendientes |
| 409 | REQUEST_ALREADY_REVIEWED | Recargar solicitudes y decisión vigente |
| 413 | Archivo demasiado grande | Pedir imagen dentro del límite |
| 415 / 422 | Tipo o datos inválidos | Mostrar validación; mantener formulario |
| 422 | VERIFICATION_FAILED | Entrega rechazada; pedido continúa ready |
| 429 | Demasiados intentos | Aplicar espera y mensaje claro; sin bucle automático |
| 503 | Servicio indisponible | Permitir recuperación; no fingir una escritura exitosa |

Otros códigos relevantes del flujo: `BUSINESS_REQUIRED`, `INSTITUTIONAL_EMAIL_REQUIRED`, `IDENTITY_CONFIRMATION_REQUIRED`, `APPROVAL_REQUIRED`, `MASTER_PROTECTED` y `LAST_ADMIN`. Mantener las reglas específicas de los apartados 10-11 y los contratos del repositorio. El registro público duplicado conserva su acuse genérico; no aplicar allí el error de alta administrativa que revelaría cuentas.

La revisión devuelve 400 para `INVALID_STATUS_TRANSITION`; se propone 409 en el backend definitivo por conflicto de estado. El cliente reconoce el código en ambos casos. Acordar una convención y reflejarla en OpenAPI.

`TIMEOUT` y `NETWORK` pueden generarse dentro del cliente aunque el servidor haya guardado la operación. No son prueba de rollback. El usuario debe recargar y revisar el estado confirmado antes de repetir una acción. El backend puede añadir un `requestId` para soporte sin exponer información privada.

REQUERIDO: validar autenticación y permiso antes de devolver información de negocio. Para rechazos de acceso ajeno, usar una política consistente 403/404. Los errores no deben convertirse en respuestas 200 ni en páginas HTML del servidor web.

<!-- page -->
# 25. Modelo SQL propuesto y restricciones

PROPUESTA de esquema lógico normalizado, independiente del ORM. No es una migración ya implementada. Usar IDs estables y conservar el JSON externo en camelCase aunque las columnas SQL usen snake_case.

| Entidad | Datos y restricciones esenciales |
| --- | --- |
| institutions, cafeterias | Identidad, nombres, zona; FK cafetería -> institución |
| businesses | Cafetería, nombre, categoría, descripción, is_active, is_open, version |
| users | Email normalizado único, hash nullable si solo OAuth, rol, is_master, estado, version |
| business_assignments | Usuario/local activo; asignación exclusiva según regla vigente |
| auth_identities | FK usuario, proveedor, issuer, subject; UNIQUE(issuer, subject) |
| refresh_sessions | Hash del token, usuario, familia, expiración, revocación, rotación |
| access_requests | Solicitante, rol solicitado, contexto, proveedor, estado, versión, decisión |
| reset_tokens | Hash de token de un uso, expiración, consumo, FK usuario |
| careers, academic_groups | Grupo con FK carrera; IDs globalmente únicos al serializar catálogo |
| products | FK local, precio exacto, stock nullable, disponibilidad, imagen, versión, baja lógica |
| media | FK propietario/local, ruta interna, tipo real, tamaño, estado y fechas |
| orders | FK local/alumno, número, estado, importes, versión y fechas de cada transición |
| order_items | FK pedido/producto, snapshots de nombre/precio, cantidad y notas |
| reviews | FK pedido único, local, alumno interno, ratings 1-5, carrera/grupo y snapshots |
| review_followups | UNIQUE(review_id), estado, responsable, nota, versión, actualización |
| followup_events | FK seguimiento, cambio, actor y fecha; historial inmutable |
| audit_events | Actor, operación, recurso, resultado, request_id y fecha; sin secretos |
| outbox_events | Evento confirmado, tema autorizado, versión, publicación y reintentos |
| idempotency_keys | Actor + clave únicos, huella de petición, estado, resultado y caducidad |

REQUERIDO: claves foráneas y NOT NULL donde corresponda; CHECK de stock >=0 si no es null, cantidades >0, importes >=0, ratings entre 1 y 5 o null, versiones >=1. `expectedVersion=0` de un seguimiento nuevo no es una fila persistida de versión 0.

Usar tipo decimal exacto o enteros en centavos. Guardar instantes UTC y convertir rangos locales en las consultas. No usar timestamps como único control de concurrencia. Evitar borrados en cascada desde un local o producto hacia ventas/opiniones.

Índices iniciales: email normalizado único; productos(local, categoría, activo); pedidos(local, estado, created_at, id); pedidos(local, completed_at) y (local, cancelled_at); UNIQUE(local, order_number); opiniones(local, created_at, id); solicitudes(estado, created_at); seguimientos(review_id); sesiones(usuario, revocación). Ajustarlos con planes de consulta y carga real, no añadir índices sin medir.

<!-- page -->
# 26. Transacciones y construcción del servidor

Separar controladores HTTP, validación de DTO, autorización, servicios de dominio y acceso SQL. Los controladores no deben aceptar todos los campos del ORM mediante asignación masiva. Las reglas de dominio deben aplicarse también cuando una tarea interna llama al servicio.

**Creación de pedido, desde la app del alumno:**

```text
BEGIN
  Validar actor y clave idempotente; bloquear su registro.
  Validar que el local siga activo y abierto.
  Bloquear productos en orden estable o actualizar con condición.
  Verificar pertenencia, disponibilidad y stock de todos los items.
  Calcular importes con precios vigentes del servidor.
  Reservar stock controlado; incrementar versiones afectadas.
  Asignar número único; guardar pedido pending y sus snapshots.
  Guardar resultado idempotente, auditoría y evento outbox.
COMMIT
Publicar evento después del commit; responder pedido confirmado.
```

Si falla una validación, rollback completo. Nunca confiar en precios, subtotal, nombre del producto o dueño enviados por la app. Un cambio de precio concurrente debe respetar un orden transaccional definido; el pedido conserva el precio que el servidor confirmó.

**Otras unidades atómicas:** transición + versión + fecha + auditoría + evento; cancelación + devolución única de stock; aprobación + asignación exclusiva + revocación previa + auditoría; seguimiento + evento histórico. Para entregar, el código y `ready` deben validarse dentro de la misma transacción que marca completed.

PROPUESTA PostgreSQL: usar bloqueos de fila o UPDATE condicional y comprobar filas afectadas. La documentación de [bloqueos explícitos](https://www.postgresql.org/docs/current/explicit-locking.html) describe los conflictos y el alcance transaccional. Si se elige otro motor, implementar y probar garantías equivalentes. Una exclusión guardada solo en memoria no protege varios procesos backend.

No calcular `MAX(order_number)+1` sin protección. Usar un contador por local actualizado atómicamente o una estrategia equivalente con UNIQUE y reintento acotado. Tratar interbloqueos con reintento transaccional limitado; nunca repetir efectos externos como correos o cobros dentro de ese reintento.

La exclusividad de una cuenta activa por local necesita restricción SQL: tabla de asignación vigente con business_id único, o índice único condicionado cuando el motor lo admita. Verificar también el maestro y la última cuenta administrativa dentro de una transacción consistente.

Entregar migraciones ordenadas, mecanismo de bootstrap del maestro, rollback o restauración documentada y datos demo en un comando separado. No copiar la tabla genérica JSON, el bloqueo global, los tokens en memoria ni las credenciales públicas de `review_server.py` como arquitectura productiva. Elegir hash de contraseñas y parámetros con una biblioteca de seguridad mantenida; nunca cifrado reversible ni texto plano.

<!-- page -->
# 27. Despliegue local, HTTPS y operación

PROPUESTA: un dominio interno o institucional con HTTPS sirve Flutter estático, `/api/v1/`, `/api/v1/realtime` y `/media/`. El backend y SQL quedan en red privada. Usar el mismo origen simplifica cookies y CORS. Los móviles deben poder resolver y alcanzar ese dominio; `localhost` en un teléfono es el teléfono, no la PC del servidor.

Guardar archivos estáticos compilados separados de SQL y medios persistentes. El proxy conserva `/api/v1/` si esas son las rutas del backend. Ejemplo parcial NGINX para un upstream HTTP en la misma máquina, dentro del servidor HTTPS; faltan certificado, archivos estáticos y políticas del despliegue:

```nginx
location /api/v1/ {
    proxy_pass http://127.0.0.1:8080;
    proxy_set_header Host $host;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    client_max_body_size 6m;
}
location /api/v1/realtime {
    proxy_pass http://127.0.0.1:8080;
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_set_header Host $host;
    proxy_read_timeout 90s;
}
```

La conexión WebSocket necesita cabeceras de actualización y tráfico/heartbeat antes del timeout del proxy. [Referencia oficial NGINX](https://nginx.org/en/docs/http/websocket.html). Si hay varias instancias backend, compartir sesiones, revocaciones y difusión de eventos mediante infraestructura adecuada; no depender de memoria de un proceso.

Si frontend/API usan orígenes distintos: lista exacta de orígenes permitidos, `Access-Control-Allow-Credentials: true`, preflight para Authorization, Content-Type y métodos utilizados, y cookies compatibles con la topología HTTPS. No usar origen `*` con credenciales. Revisar protección CSRF/Origin especialmente en refresh, logout y OAuth. Probar este caso; no basta con que Postman funcione.

Variables de servidor propuestas: conexión SQL, URL pública, orígenes, dominios admin, secreto/firma, vida de sesión, ruta de medios, proveedor de correo y OAuth. Sus nombres concretos dependen del backend; Flutter solo conoce sus `dart-define`. No guardar secretos en Git ni en el build web.

REQUERIDO antes de entregar: reloj sincronizado; cuenta de SQL con privilegios mínimos; logs estructurados sin secretos; copias de SQL + medios con restauración ensayada; monitor de errores, latencia, disco y conexiones. Se proponen health/readiness para operación, pero estos paneles no los consumen hoy. Validar cámara QR y certificados confiables en Android/tablet reales.

<!-- page -->
# 28. Capacidad: objetivo de 500 sesiones simultáneas

**No hay una certificación de 500 usuarios en el código actual.** Es un objetivo del sistema completo. Distinguir sesiones abiertas, conexiones WebSocket, personas activas y solicitudes por segundo; no son la misma medida. Debe medirse en el servidor local y con el patrón real de alumnos, cocina y administración.

| Carga que genera el panel | Comportamiento actual |
| --- | --- |
| Cocina visible sin WebSocket | Consulta Business y pedidos activos aproximadamente cada 10 s |
| Cocina con suscripción | Reconciliación cada 60 s y consultas agrupadas tras eventos |
| Monitor administrativo visible | Actualización periódica cada 60 s; carga de colecciones paginadas |
| Pantalla oculta | Pausa consultas de operación/monitor y conexión de cocina |
| Catálogo e historial | Consultas según navegación, búsqueda, página o acción |

Ejemplo de dimensionamiento, no pronóstico: 500 paneles de cocina visibles, dos GET por ciclo y una sola página de activos producirían cerca de `500 * 2 / 10 = 100 GET/s` sin WebSocket. Con ciclo de 60 s, unos 16.7 GET/s de respaldo, más eventos, renovaciones y escrituras. En el caso previsto, gran parte de las 500 sesiones serían alumnos y la carga dependerá de su app; no multiplicar cuatro locales como si fueran 500 operadores.

PROPUESTA de prueba: aumentar a 50, 100, 250 y 500 sesiones; mantener la fase objetivo al menos 30 minutos y añadir un pico de pedidos. Mezclar catálogo, creación de pedido, aceptación, preparación, entrega, cancelación, opiniones y lecturas administrativas. Probar también desconexión WebSocket con regreso a polling.

Medir p50/p95/p99 por endpoint, errores, throughput, conexiones, CPU, RAM, espera/bloqueos SQL, tiempo de transacción y retraso de eventos. Como objetivos iniciales a acordar: p95 de lecturas <1 s, escrituras <2 s y errores inesperados <1%. Son criterios propuestos, no resultados obtenidos ni garantía; separar conflictos esperados de fallas del sistema.

Verificar integridad además de velocidad: cero sobreventa, cero entregas dobles, una devolución por cancelación, importes coherentes y ningún acceso cruzado. La prueba crítica de dos compras por la última unidad debe terminar con una aceptada y otra rechazada, sin stock negativo.

SQL requiere un pool acotado por instancia; 500 sesiones web no deben abrir 500 conexiones SQL permanentes. Usar índices, límites de consulta, paginación estable, transacciones breves y evitar N+1. No mantener bloqueos mientras se envían correos o archivos.

PENDIENTE: monitor administrativo descarga opiniones para calcular gráficas; su volumen puede crecer aunque haya pocos administradores. Medir ese costo y acordar agregados de servidor si se supera el presupuesto. Entregar informe con hardware, tamaño de datos, mezcla, duración, resultados y límites antes de afirmar capacidad productiva.

<!-- page -->
# 29. Diferencias con la propuesta API v3 del equipo

La propuesta recibida `api_v3_agnostica.md`, del 7 de octubre de 2026, es una base de coordinación. El contrato del frontend auditado incluye extensiones administrativas y diferencias que deben resolverse explícitamente. No se debe implementar una mezcla silenciosa de ambos documentos.

| Tema | Propuesta / situación previa | Frontend de estos paneles |
| --- | --- | --- |
| POST auth/register | Alta de alumno con 201 y tokens | Solicitud business/admin, 202 received, sin sesión |
| Roles | user y business | Añade admin e isMaster; permisos separados |
| Disponibilidad | PATCH específico /availability | PATCH products/{id} con draft y versión |
| Control de versión | expectedVersion opcional en varios casos | Cliente lo envía en escrituras existentes; exigirlo |
| Pedidos activos | updatedSince opcional para deltas | No lo envía; espera snapshot paginado completo |
| Tiempo real | Posible implementación con Socket.IO | Necesita protocolo WebSocket nativo descrito |
| Promedios | Agregados oficiales de servidor | Monitor calcula desde opiniones descargadas |
| Medios | También contempla DELETE de medios | Solo POST multipart de producto |
| App del alumno | Crear pedido, opinar, registrar dispositivo | Esas peticiones no salen de estos dos paneles |

**Registro:** coordinar con el responsable de la app del alumno. Puede existir un endpoint separado para solicitudes de personal, pero cambiarlo exige modificar `AccessRepository`. Si se conserva una ruta compartida, documentar dos DTO explícitos y validar cada flujo: la presencia de requestedRole jamás concede ese rol. No convertir a los alumnos en solicitantes administrativos por accidente.

**Catálogo del alumno:** algunos nombres de rutas `businesses/{id}` o productos también pueden necesitarse para lectura pública/alumno. El contrato operativo del panel exige pertenencia para administrar. Diseñar proyecciones y permisos de lectura del alumno sin exponer datos privados ni permitir mutaciones. Una solución son rutas de catálogo separadas; se debe coordinar con su cliente. No habilitar acceso operativo del admin como atajo.

**Pedido y opinión:** el backend de la app del alumno debe producir los registros y eventos que consumen Cocina y Administración. Este manual define los invariantes necesarios, pero no afirma haber migrado toda esa app a REST. Permanecen entradas y servicios Firebase en el repositorio fuera del portal REST.

En caso de conflicto, inspeccionar el código del commit auditado y acordar el cambio con ambos responsables antes de renombrar campos/rutas. Registrar la decisión en OpenAPI y pruebas; actualizar este manual y el frontend cuando corresponda. No añadir dependencias nuevas al frontend para adaptar una elección interna del backend sin necesidad contractual.

<!-- page -->
# 30. Pruebas de aceptación de la integración

Ejecutar contra el backend SQL real, además de las pruebas existentes del frontend. El simulador y sus pruebas verifican una referencia funcional, no las transacciones de un servidor nuevo.

| Caso | Evidencia de aceptación |
| --- | --- |
| Accesos separados | Admin/maestro reciben 403 al operar cocina; business no entra a admin ni a local ajeno |
| Solicitud y alta | Pendiente no entra; solo maestro aprueba; dominio y asignación se validan |
| Manipulación de body | isMaster, rol, dueño y precios no permiten escalar permisos ni alterar cálculo |
| Sesión | Recarga, renovación, logout, expiración y revocación funcionan en navegador real |
| Dos pestañas | Rotación de refresh no causa pérdida arbitraria ni revive sesión revocada |
| Productos | Alta, edición, imagen, precio, disponibilidad y baja se reflejan al consultar |
| Stock omitido | Cambiar precio sin stock no reemplaza existencias concurrentes |
| Última unidad | Dos compras simultáneas: solo una reserva; stock nunca negativo |
| Pedido | pending -> accepted -> preparing -> ready -> completed, sin saltos |
| Concurrencia | Dos tablets con misma versión: un efecto y un conflicto; sin duplicados |
| Cancelación | Motivo obligatorio según regla, devolución de stock solo una vez |
| Entrega | Código ajeno/incorrecto no entrega; entregado no se vuelve a entregar |
| Historial/ventas | Medianoche local correcta; cancelados no suman ventas; resumen de todo el periodo |
| Opiniones/gráficas | Calificaciones 1-5, denominadores correctos, filtros y totales parciales visibles |
| Carreras/grupos | IDs únicos, relación válida, carrera antes del grupo; opciones sin opiniones aparecen |
| Seguimiento | Creación versión 0, conflicto al editar simultáneamente, historial conserva actor |
| Realtime | Temas autorizados, revocación, reconexión y respaldo polling sin perder estado |
| Despliegue | HTTPS, cookies, CORS si aplica, medios accesibles y QR en dispositivos objetivo |

Pruebas existentes para consultar: `app/test/api/`, `app/test/catalog/`, `app/test/operations/`, `app/test/admin/`, `scripts/review/test_review_server.py` y `scripts/review/browser_smoke.cjs`. Consultar el workflow para versiones y preparación exactas.

```bash
# Desde la raiz del repositorio: referencia del simulador
python -m unittest discover -s scripts/review -p 'test_*.py'
# Desde app/: frontend
flutter pub get
flutter analyze
flutter test
```

Revisar anchos 320/360, 768 y 1440 px: sin desbordamientos, controles táctiles utilizables, diálogos y tablas navegables. La validación visual no sustituye pruebas de HTTP/SQL ni las de carga. Guardar resultados, versión del servidor, migración aplicada y commit del frontend utilizados.

<!-- page -->
# 31. Orden de implementación y entregables del backend

| Fase | Trabajo concreto | Criterio para avanzar |
| --- | --- | --- |
| 1. Acordar contrato | Resolver registro alumno/personal, motor SQL y decisiones pendientes | OpenAPI y matriz de permisos revisados |
| 2. Base e identidad | Migraciones, maestro, sesiones, users/me, opciones, institución | Login/refresh/logout y separación de roles comprobados |
| 3. Gestión | Locales, cuentas, solicitudes, padrón académico | Maestro aprueba y asigna un local sin duplicaciones |
| 4. Catálogo | CRUD, stock, versiones, precios y medios | Flujo real de producto e imagen desde el formulario |
| 5. Operación | Entrada de pedido del alumno, acciones, entrega, historial y ventas | Pedido completo con pruebas de concurrencia |
| 6. Administración | Opiniones, seguimiento, historial y datos para gráficas | Filtros y resultados coinciden con un conjunto conocido |
| 7. Tiempo real y acceso externo | WebSocket, correo y Google si se habilitan | Funciones activas reflejan capacidad real de servidor |
| 8. Operación local | HTTPS, backups, monitoreo, carga y dispositivos | Informe de aceptación y restauración comprobada |

**Entregar al equipo:** código del backend; OpenAPI con ejemplos y códigos de error; migraciones; `.env.example` sin secretos; instrucciones para crear el maestro y desplegar; comando separado de fixtures; pruebas automatizadas; colección HTTP o comandos reproducibles; respaldo/restauración; informe de capacidad; decisiones de contrato y lista de limitaciones restantes.

**Configuración inicial real:** universidad/cafetería y dominios autorizados; padrón académico; cuenta maestra con contraseña privada y procedimiento de recuperación. El equipo crea sus locales y cuentas. No distribuir las contraseñas de prueba ni crear automáticamente los cuatro operadores reales.

**Pendientes que requieren decisión del equipo:** motor/stack SQL; dominio y certificados locales; proveedor de correo; disponibilidad de Internet/Google; respaldo de entrega por número de control; política de conservación y acceso a datos; integración de pagos y conciliación; regla de más de un operador por local; umbral para agregados de gráficas; alcance del registro de alumnos.

Se puede implementar primero el flujo por contraseña con Google deshabilitado, siempre que las opciones públicas lo indiquen. No habilitar botones de funciones que solo responden éxito simulado. Cada capacidad que se declare lista debe poder probarse desde la web y contra SQL persistente.

Mantener cambios de integración en una rama de trabajo y coordinar los cambios compartidos. La rama auditada es `test/api-aaa-sonarqube`; no implica autorización para publicar producción o sustituir la rama principal. El manual no es un informe de seguridad ni una certificación de disponibilidad.

<!-- page -->
# 32. Instrucciones listas para el asistente de IA

Copiar este bloque y entregar también el repositorio y este documento. La IA debe tener acceso real a los archivos: un enlace privado sin permisos no sustituye el código.

```text
Implementa el backend de SnackUP para integrar los paneles
Flutter web existentes de Administracion y Cocina/locales.

Repositorio: https://github.com/Gabino-RG/SnackUP-core
Rama de referencia: test/api-aaa-sonarqube
Snapshot auditado: 476d89c8c94fcdd4a371d87710904736d68f8455
Manual: docs/MANUAL_BACKEND_PANELES.md

1. Lee el manual y los repositorios REST/modelos citados.
   Comprueba el commit real antes de asumir compatibilidad.
2. Inspecciona el backend que ya exista. Conserva su stack
   acordado. No inventes endpoints ni tipos distintos.
3. Separa lo ACTUAL, REQUERIDO, PROPUESTO y PENDIENTE.
   No conviertas una propuesta en una funcion ya implementada.
4. No redisenes colores, logo, widgets ni navegacion.
   Los cambios visuales estan separados del contrato backend.
5. Admin, incluido el maestro, no opera Cocina. Business
   solo opera su local. Impone permisos en HTTP y WebSocket.
6. Registro de personal solicita acceso; no concede un rol.
   Solo el maestro decide. Coordina el registro de alumnos.
7. Implementa SQL normalizado, migraciones, transacciones,
   versiones, inventario, snapshots e idempotencia acordada.
8. No copies credenciales, seeds ni arquitectura del simulador
   de revision como produccion. No crees los cuatro locales.
9. Respeta JSON, pagination, errores, cookie de renovacion,
   omision de stock en PATCH y respuestas de transiciones.
10. Conserva toda mutacion atomica y comprueba propiedad de IDs.
    No guardes secretos en Git ni en el frontend compilado.
11. Entrega OpenAPI, configuracion de ejemplo, instrucciones,
    pruebas, informe de carga y limites que sigan pendientes.
12. No afirmes soportar 500 sesiones sin una prueba medible
    sobre el servidor local y la mezcla real de usuarios.

Antes de programar, presenta diferencias con el contrato,
decisiones indispensables y una secuencia de implementacion.
Si no puedes leer el repositorio, pide los archivos exactos;
no reconstruyas sus peticiones por suposicion.
```

Después de implementar, pedir a la IA una tabla por endpoint con archivo controlador, servicio, validación, prueba y estado; más una lista de cambios necesarios en frontend. Toda diferencia debe quedar explícita para que el equipo pueda revisarla.

<!-- page -->
# 33. Índice de fuentes verificables

Todos los enlaces siguientes apuntan al snapshot auditado. El manual describe ese código; los enlaces a documentación externa orientan las propuestas de implementación.

| Fuente de código | Contenido que debe consultar el backend |
| --- | --- |
| [api_client.dart](https://github.com/Gabino-RG/SnackUP-core/blob/476d89c8c94fcdd4a371d87710904736d68f8455/app/lib/api/api_client.dart) | URL base, HTTP, errores y timeout |
| [rest_session.dart](https://github.com/Gabino-RG/SnackUP-core/blob/476d89c8c94fcdd4a371d87710904736d68f8455/app/lib/api/rest_session.dart) | Cookie, tokens, perfil y renovación |
| [access_repository.dart](https://github.com/Gabino-RG/SnackUP-core/blob/476d89c8c94fcdd4a371d87710904736d68f8455/app/lib/api/access_repository.dart) | Opciones, registro y Google |
| [operations_repository.dart](https://github.com/Gabino-RG/SnackUP-core/blob/476d89c8c94fcdd4a371d87710904736d68f8455/app/lib/operations/operations_repository.dart) | Rutas de locales, pedidos, gestión y resúmenes |
| [operations/models.dart](https://github.com/Gabino-RG/SnackUP-core/blob/476d89c8c94fcdd4a371d87710904736d68f8455/app/lib/operations/models.dart) | Tipos, estados y campos de respuesta |
| [catalog.dart](https://github.com/Gabino-RG/SnackUP-core/blob/476d89c8c94fcdd4a371d87710904736d68f8455/app/lib/catalog/catalog.dart) | Validaciones de producto, stock e imagen |
| [rest_catalog_repository.dart](https://github.com/Gabino-RG/SnackUP-core/blob/476d89c8c94fcdd4a371d87710904736d68f8455/app/lib/catalog/rest_catalog_repository.dart) | CRUD y subida multipart |
| [rest_admin_repository.dart](https://github.com/Gabino-RG/SnackUP-core/blob/476d89c8c94fcdd4a371d87710904736d68f8455/app/lib/features/admin/data/rest_admin_repository.dart) | Colecciones, institución, padrón y seguimiento |
| [admin_models.dart](https://github.com/Gabino-RG/SnackUP-core/blob/476d89c8c94fcdd4a371d87710904736d68f8455/app/lib/features/admin/domain/admin_models.dart) | Filtros y fórmulas de gráficas |
| [realtime_web.dart](https://github.com/Gabino-RG/SnackUP-core/blob/476d89c8c94fcdd4a371d87710904736d68f8455/app/lib/operations/realtime_web.dart) | Protocolo WebSocket del navegador |
| [admin_theme.dart](https://github.com/Gabino-RG/SnackUP-core/blob/476d89c8c94fcdd4a371d87710904736d68f8455/app/lib/features/admin/admin_theme.dart) | Colores y tema visual; responsabilidad frontend |
| [CONTRATO_PANELES.md](https://github.com/Gabino-RG/SnackUP-core/blob/476d89c8c94fcdd4a371d87710904736d68f8455/docs/CONTRATO_PANELES.md) | Contrato de referencia ya versionado |
| [PORTAL_API_LOCAL.md](https://github.com/Gabino-RG/SnackUP-core/blob/476d89c8c94fcdd4a371d87710904736d68f8455/docs/PORTAL_API_LOCAL.md) | Integración y límites del portal REST |
| [review_server.py](https://github.com/Gabino-RG/SnackUP-core/blob/476d89c8c94fcdd4a371d87710904736d68f8455/scripts/review/review_server.py) | Simulador de referencia; no backend productivo |

Referencias primarias consultadas el 12 de octubre de 2026:

- [OWASP REST Security Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/REST_Security_Cheat_Sheet.html): HTTPS, autorización por endpoint y validación de tokens. Complementa las reglas de los apartados 7, 10 y 27.
- [Google OpenID Connect](https://developers.google.com/identity/openid-connect/openid-connect): flujo e identidad de Google, apartado 9.
- [PostgreSQL: Explicit Locking](https://www.postgresql.org/docs/current/explicit-locking.html): transacciones y bloqueos de fila, apartado 26.
- [NGINX: WebSocket proxying](https://nginx.org/en/docs/http/websocket.html): actualización HTTP y timeouts, apartado 27.

**Control de entrega:** documento 1.0; ejemplos ficticios; fuente de verdad de compatibilidad: código auditado + contrato acordado. Revisar este manual cuando cambien rutas, permisos, modelos, sesión, gráficas o reglas del negocio.
