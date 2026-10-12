# Contrato de integración de los paneles

Complementa `api_v3_agnostica.md` aportado por el equipo. Base `/api/v1/`, JSON UTF-8, fechas UTC y dinero numérico en MXN. Los importes se muestran en centavos enteros dentro del frontend; el servidor calcula totales y conserva snapshots de cada pedido. Todas las operaciones requieren el rol y el local del token verificados por el backend.

## Cocina — rutas v3

- `GET businesses/{id}`: Business con `id,name,category,description,isOpen,timezone,version`.
- `GET businesses/{id}/orders/active?page=&limit=200`: `{data:Order[],pagination?}`. Incluye pending, accepted, preparing y ready. Si pagina, `pagination` debe indicar `page,totalPages,total`. El frontend carga todas las páginas antes de reemplazar el tablero.
- `GET orders/{id}`: Order de ese negocio, sin pickupCode ni número de control. Los códigos los aporta el cliente en la entrega; no se imprimen en las tarjetas.
- `POST orders/{id}/accept|start|ready`: `{expectedVersion}`. Transiciones pending→accepted→preparing→ready. Accepted y preparing comparten la columna Preparando.
- `POST orders/{id}/complete`: `{expectedVersion,method:"qr"|"manual",code}`. Solo ready→completed. Verifica el código en el servidor.
- `POST orders/{id}/cancel`: `{expectedVersion,reason,notes?}`. Solo pending/accepted/preparing. Catálogo: product_unavailable,cannot_prepare,store_issue,store_closing,other; other requiere nota.
- `PATCH businesses/{id}/status`: `{isOpen,expectedVersion}`. Existe un único estado de recepción; cerrar no cancela pedidos recibidos.
- `GET businesses/{id}/orders/history?date=YYYY-MM-DD&page=&limit=30`: `{data:Order[],summary:{completed,cancelled,totalSold},pagination?}`. La fecha es de la universidad. Propuesta de precisión: filtrar por completedAt/cancelledAt en la zona del negocio, no por el día de creación.
- `GET businesses/{id}/stats?from=YYYY-MM-DD&to=YYYY-MM-DD`: forma propuesta `{completed,cancelled,totalSold}` del periodo completo, ambas fechas incluidas. No sumar solo la página visible.

Cada Order trae `id,businessId,orderNumber,version,status,customerName,createdAt,items:[{name,price,quantity,notes?}],total,paymentMethod,scheduledPickupTime?,cancelReason?,cancelNotes?`. El servidor también conserva los timestamps por transición, verification y cancelledBy. Devolver `409 VERSION_CONFLICT` ante expectedVersion obsoleta; `422 VERIFICATION_FAILED` para un código incorrecto. El frontend no repite mutaciones tras un timeout o desconexión.

## Tiempo real

WebSocket `realtime`, mismo origen de la API convertido a ws/wss. El token viaja en mensaje `{action:"auth",token}` y nunca en la URL. Suscripción a `business:{id}:orders` y `business:{id}`. El servidor confirma `{type:"subscribed",topics:[...]}`; eventos con `id,type,topic,occurredAt,data`. Se atienden order.created, order.updated y business.updated; se descartan IDs duplicados y temas ajenos. Ping se contesta con pong. Los eventos provocan una lectura REST agrupada; no sustituyen la autorización ni el estado confirmado.

Mientras no hay suscripción: consulta REST cada 10 s. Con suscripción: reconciliación cada 60 s. Se detienen conexiones/temporizadores al ocultar o cerrar el panel y se recarga al regresar. El cliente reautentica el socket cada minuto con el token vigente. Tres fallos espacian reconexiones a 60 s. El backend debe cancelar suscripciones al revocar cuentas y notificar errores de autorización.

## Extensiones propuestas de gestión

| Método y ruta | Entrada |
|---|---|
| `PATCH businesses/{id}` | `{name,category,description,expectedVersion}`; solo negocio propietario |
| `GET admin/businesses?page=&limit=&q=` | Listado administrativo con búsqueda y paginación |
| `POST admin/businesses` | `{name,category,description,isActive,timezone}` |
| `PATCH admin/businesses/{id}` | `{name,category,description,isActive,expectedVersion}` |
| `GET admin/users?page=&limit=&q=` | Listado paginado con búsqueda por nombre/correo |
| `POST admin/users` | `{displayName,email,password,role,businessId,isActive}` |
| `PATCH admin/users/{id}` | `{displayName,email,role,businessId,isActive,expectedVersion}` |

Respuestas de creación/edición: recurso guardado con id, version y updatedAt. Listas: `{data,pagination:{page,limit,total,totalPages}}`. Business agrega `isActive,cafeteriaId,cafeteriaName`; User incluye `id,email,displayName,role,businessId,isActive,isMaster,version`. Jamás devolver contraseñas/hashes. Límites: nombre100, categoría60, descripción local600, correo160; contraseña inicial12–128 caracteres. La API debe definir entrega segura y cambio de la contraseña inicial en operación real.

El rol `admin` amplía el documento v3 original. No se asigna mediante registro público. El backend impide cambios de rol por usuarios normales, ediciones sobre locales ajenos y la eliminación del último administrador activo. Al cambiar rol, asignación o suspensión revoca todas las sesiones anteriores. Suspender/desactivar conserva historial; desactivar local con pedidos activos devuelve `409 BUSINESS_HAS_ACTIVE_ORDERS`. Una cuenta activa de cocina por negocio como default v3; si ya está asignado, `409 BUSINESS_ALREADY_ASSIGNED`. Correos duplicados: `409 EMAIL_EXISTS`. Estas validaciones del cliente son ayudas de uso; las reglas reales son obligatorias en el backend.

Opiniones/seguimientos conservan las rutas y las versiones documentadas en `PORTAL_API_LOCAL.md`. Los filtros y gráficos actuales describen solamente los registros cargados, indicado en pantalla si faltan páginas. No son analítica global de toda la base hasta cargar todas las páginas o implementar agregados oficiales.

## Sesión y recuperación

Ver `PORTAL_API_LOCAL.md`: acceso en memoria, refresh cookie HttpOnly/Secure/SameSite=Strict, renovación coordinada, logout revocable y aislamiento por generación de sesión. La recuperación termina en un enlace `https://host/#/reset-password?token=TOKEN_DE_UN_SOLO_USO`; la pantalla envía `POST auth/reset-password {token,newPassword}`. Respuesta204. Token inválido/usado/expirado422. El backend emite el correo, aplica su política de contraseña y revoca sesiones tras el cambio.

## Proveedor de revisión local

`scripts/review/review_server.py` implementa un simulador persistente sobre SQLite exclusivamente para comprobar los paneles. Sus tokens opacos, cookie HTTP en loopback, password de muestra y endpoint `POST review/orders` son propios de la revisión; no reemplazan el contrato JWT/HTTPS del servidor definitivo. El frontend real no contiene un fallback automático a datos de ejemplo si falla la API. El modo revisión es una compilación identificada explícitamente.

## Institución, cuenta maestra y catálogo académico

Estas extensiones deben implementarse en el backend definitivo. El proveedor de revisión ya las implementa para probar el frontend.

`GET institution` autenticado devuelve:

```json
{
  "university": {"id": "utsjr", "name": "Universidad Tecnológica de San Juan del Río"},
  "cafeteria": {"id": "cafeteria-utsjr", "name": "Cafetería universitaria"},
  "adminEmailDomains": ["utsjr.edu.mx"]
}
```

Una cafetería contiene los locales; cuatro es el dato inicial, no un límite codificado. `POST admin/businesses` envía `cafeteriaId`; el servidor valida la pertenencia y devuelve también `cafeteriaName`.

El perfil de `GET users/me` agrega `isMaster:boolean`. Solo `role=admin` junto con `isMaster=true` habilita la gestión de cuentas. Sin esa marca no se concede el permiso. `GET/POST/PATCH admin/users` deben comprobar ambas condiciones en el servidor. Los demás administradores consultan opiniones y administran locales, sin administrar accesos. La cuenta maestra permanece activa y administrativa; no se puede crear/promover otra mediante estos formularios. El bootstrap inicial y cualquier recuperación del maestro pertenecen a un procedimiento administrativo del backend, fuera del registro público. No basta con conocer el correo ni modificar el frontend.

Las nuevas cuentas administrativas usan exclusivamente un dominio exacto de `adminEmailDomains`; se normalizan correo y dominio a minúsculas. `utsjr.edu.mx.ejemplo.com` no es válido. Los locales conservan cuentas propias vinculadas por `businessId`. Errores: `403 MASTER_REQUIRED`, `403 MASTER_PROTECTED`, `422 INSTITUTIONAL_EMAIL_REQUIRED`. Todo cambio de permiso/asignación/estado revoca sesiones. La marca maestra participa en la identidad de sesión del frontend para descartar pantallas y peticiones de permisos anteriores.

`GET admin/academic-catalog?page=1&limit=200` devuelve el catálogo completo, independiente de las opiniones existentes:

```json
{
  "data": [
    {"id":"software","name":"Desarrollo de Software","kind":"career"},
    {"id":"software-1","name":"DSM-1","kind":"group","careerId":"software"}
  ],
  "pagination":{"page":1,"limit":200,"total":2,"totalPages":1}
}
```

IDs únicos y estables; cada grupo referencia una carrera presente. Orden estable durante la paginación. El frontend carga y valida todas las páginas (máximo 20,000 entradas), incluye grupos sin opiniones y ofrece búsqueda. Primero se selecciona carrera, después grupo. `admin/reviews` agrega `careerId,groupId`, conservando `career,group` como nombres de presentación. Las referencias tienen prioridad sobre nombres repetidos. Los datos antiguos sin IDs admiten comparación por nombre mientras se migra; el backend debe completar esos IDs.

El tablero vuelve a consultar configuración, catálogo académico, locales, opiniones y atenciones al pulsar Actualizar, regresar de gestión o cada 60 segundos mientras está visible. Relee las páginas previamente cargadas y reemplaza los datos solo al completar la lectura; las gráficas se recalculan con puntuaciones válidas del resultado. No inventa puntuaciones para grupos vacíos. Si faltan páginas de opiniones, indica resultados parciales. Para grandes volúmenes, acordar endpoints agregados y filtros del servidor antes de certificar capacidad. El catálogo académico se mantiene en el backend; estos paneles permiten consultarlo y filtrarlo, no alterar el padrón escolar.
