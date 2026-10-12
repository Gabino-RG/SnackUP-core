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
- `GET businesses/{id}/orders/history?date=YYYY-MM-DD&page=&limit=30`: `{data:Order[],summary:{completed,cancelled,totalSold},pagination?}`. La fecha es del campus. Propuesta de precisión: filtrar por completedAt/cancelledAt en la zona del negocio, no por el día de creación.
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

Respuestas de creación/edición: recurso guardado con id, version y updatedAt. Listas: `{data,pagination:{page,limit,total,totalPages}}`. Business agrega `isActive`; User incluye `id,email,displayName,role,businessId,isActive,version`. Jamás devolver contraseñas/hashes. Límites: nombre100, categoría60, descripción local600, correo160; contraseña inicial12–128 caracteres. La API debe definir entrega segura y cambio de la contraseña inicial en operación real.

El rol `admin` amplía el documento v3 original. No se asigna mediante registro público. El backend impide cambios de rol por usuarios normales, ediciones sobre locales ajenos y la eliminación del último administrador activo. Al cambiar rol, asignación o suspensión revoca todas las sesiones anteriores. Suspender/desactivar conserva historial; desactivar local con pedidos activos devuelve `409 BUSINESS_HAS_ACTIVE_ORDERS`. Una cuenta activa de cocina por negocio como default v3; si ya está asignado, `409 BUSINESS_ALREADY_ASSIGNED`. Correos duplicados: `409 EMAIL_EXISTS`. Estas validaciones del cliente son ayudas de uso; las reglas reales son obligatorias en el backend.

Opiniones/seguimientos conservan las rutas y las versiones documentadas en `PORTAL_API_LOCAL.md`. Los filtros y gráficos actuales describen solamente los registros cargados, indicado en pantalla si faltan páginas. No son analítica global de toda la base hasta cargar todas las páginas o implementar agregados oficiales.

## Sesión y recuperación

Ver `PORTAL_API_LOCAL.md`: acceso en memoria, refresh cookie HttpOnly/Secure/SameSite=Strict, renovación coordinada, logout revocable y aislamiento por generación de sesión. La recuperación termina en un enlace `https://host/#/reset-password?token=TOKEN_DE_UN_SOLO_USO`; la pantalla envía `POST auth/reset-password {token,newPassword}`. Respuesta204. Token inválido/usado/expirado422. El backend emite el correo, aplica su política de contraseña y revoca sesiones tras el cambio.

## Proveedor de revisión local

`scripts/review/review_server.py` implementa un simulador persistente sobre SQLite exclusivamente para comprobar los paneles. Sus tokens opacos, cookie HTTP en loopback, password de muestra y endpoint `POST review/orders` son propios de la revisión; no reemplazan el contrato JWT/HTTPS del servidor definitivo. El frontend real no contiene un fallback automático a datos de ejemplo si falla la API. El modo revisión es una compilación identificada explícitamente.
