# Backend SnackUP V3.2: ampliación compatible

Implementación del 23 de octubre de 2026 sobre el backend existente. La revisión
`0003_v32` conserva las 23 tablas previas y añade seis; no sustituye el esquema
por las 18 tablas del adjunto. No elimina rutas REST, cuentas, pedidos, precios
históricos, reseñas, padrón, sesiones, auditoría, dispositivos ni seguimientos.

El inventario pasa de 55 a **78 operaciones canónicas**. Las 15 operaciones del
documento antes ausentes están montadas. Evidencia reproducible:
[inventario posterior](evidence/v32-implemented-inventory.json) y
[OpenAPI generado](contracts/v3.openapi.json). El inventario anterior se conserva
como línea base para la prueba que impide quitar rutas.

## Compatibilidad de los contratos

| Función | Comportamiento |
|---|---|
| Rutas de paneles | Se conserva íntegro `/api/legacy/v1`, incluidos sus DTO y WebSocket. |
| Carrito | GET/POST/PATCH/DELETE privados. POST establece cantidad y notas por producto; no suma unidades implícitamente. Precios consultados en vivo, nunca autorizan el importe de compra. Máximo 100 productos por usuario. |
| Favoritos | GET/PUT/DELETE privados, con notas. Repetir PUT sin notas conserva las anteriores. Máximo 500 favoritos. |
| Búsqueda y destacados | `/products/search?q=...` escapa comodines; `/products/featured` lista globalmente con paginación. Solo productos disponibles de negocios activos. Cocina ve su ámbito. |
| Historial privado | `GET /users/me/orders/history`, paginado y descendente, solo completed/cancelled; filtro opcional `status`. |
| Estadísticas | Conserva completed/cancelled/totalSold; añade daily, topProducts y paymentMethods. Fechas de terminación/cancelación en la zona del negocio. No representa conciliación de cobros. |
| Calificación de negocio | `/orders/{id}/rating` acepta el formato anterior `rating` y el nuevo `stars` (enteros 0–5). La respuesta conserva rating y añade stars. Una fila por pedido entregado. |
| Compatibilidad de `/reviews` | `{reviews:[...]}` mantiene reseñas de productos; `{stars,comment?}` usa exactamente la operación de calificación del negocio. No mezcla ambos cuerpos ni duplica promedios. |
| Reseñas públicas | `/businesses/{id}/ratings`, paginadas; omite usuario, pedido y datos académicos. Incluye cero en promedios/conteos. |
| Administración | Solicitudes, decisiones y alta de cuentas también están montadas en V3 como extensiones institucionales. Conservan DTO y permisos de cuenta maestra; no amplían privilegios. |

Los cuerpos nuevos de `stars` limitan el comentario a 1.000 caracteres. Los cuerpos
anteriores de `rating` y reseñas de productos conservan su límite de 2.000. El
endpoint legacy de creación de opiniones mantiene su validación 1–5; sus consultas
pueden leer las nuevas calificaciones de cero. Las categorías libres existentes se
conservan junto a `subcategory`; no se reclasifican ni renombran datos históricos.

## Decisiones operativas explícitas

- **Programados:** `scheduledPickupTime` debe ser una cadena ISO 8601 con zona,
  del mismo día local del negocio, al menos cinco minutos en el futuro y anterior
  al cierre conocido. No se admiten reservas para otro día. La versión del adjunto
  dejaba abierta la anticipación mínima; esta implementación la fija en cinco minutos.
- **No recogido:** solo Cocina, desde ready, después de
  `max(readyAt, scheduledPickupTime) + pickupTimeoutMinutes`. Por defecto 30 minutos,
  configurable entre 5 y 180 mediante PATCH de negocio. No repone existencias.
  Completed/cancelled siguen siendo terminales.
- **Pagos:** Efectivo, Transferencia, Tarjeta y ValeComida registran el medio
  previsto; no ejecutan cargos, transferencias ni conciliación bancaria.
- **Vale:** una reserva/consumo global por alumno y fecha del campus
  America/Mexico_City. Se reserva con pedido, stock, consecutivo e idempotencia
  en una transacción; se consume al entregar con código correcto. Si cruza
  medianoche, la entrega de ese vale se rechaza con MEAL_VOUCHER_DATE_EXPIRED;
  no se traslada silenciosamente al día siguiente.
- **Liberación del vale:** una cancelación mantiene la reserva salvo confirmación
  explícita de Cocina. Puede enviar `voucherNotRedeemed:true` al cancelar o usar
  `POST /orders/{id}/meal-voucher/release` con `{notRedeemed:true}` después de la
  cancelación. Se verifica pertenencia, se conserva el uso histórico y se audita
  la confirmación sin datos sensibles. Un vale consumido nunca se libera.
- **Destacados:** máximo tres productos no eliminados por negocio, aunque estén
  temporalmente agotados. Tanto V3 como legacy bloquean Business antes de contar.
  Si ya había más de tres, la migración conserva sus flags y bloquea nuevas altas
  de destacados hasta reducirlos; no elige cuáles quitar por el operador.
- **Portada:** `coverImageUrl` usa medios del propio negocio y evita borrar un
  archivo que todavía está asociado. `imageUrl` conserva su propósito anterior.

## Cierres y proceso de tareas

PATCH `/businesses/{id}/closing-schedule` recibe autoCloseEnabled, closeTimeLocal
(HH:mm) y expectedVersion opcional. POST `/postpone-closing` recibe until (ISO 8601
con zona), posterior al cierre vigente, futura y del mismo día. No reabre el local.
El cierre manual bloquea nuevas compras inmediatamente y permite gestionar las
anteriores. Se avisa a los alumnos con pedidos programados sin cancelarlos.

`python -m snackup.jobs` ejecuta un ciclo al arrancar y cada minuto. El contenedor
unificado inicia **un proceso de tareas** separado de los workers HTTP, dentro del
mismo contenedor. Un advisory lock PostgreSQL coordina instancias accidentales o
réplicas; marcadores y outbox se confirman juntos. El healthcheck verifica además
que el ciclo haya completado en los últimos 180 segundos.

El proceso cierra una sola vez por fecha local, recupera cierres vencidos al
reiniciar y nunca abre automáticamente. Una reapertura manual posterior se
respeta. Una compra tampoco puede saltarse el cierre vencido mientras espera el
siguiente ciclo. Para pedidos programados activos emite `order.pickup_soon` cuando
faltan diez minutos o menos y la hora no ha pasado, con marcador de deduplicación.
La publicación outbox sigue siendo al menos una vez: el cliente deduplica event.id.

Si se utiliza el despliegue antiguo o ejecución manual de Uvicorn, se debe iniciar
el proceso de tareas por separado. `compose.unified.yaml` ya lo incluye.

## Chat efímero y privacidad

- Una conversación activa por alumno/negocio. Cocina necesita un orderId propio
  para abrirla; el alumno puede omitirlo o adjuntar un pedido suyo del negocio.
- Se descubren mediante GET `/users/me/chats` y GET `/businesses/{id}/chats`.
- Solo participantes pueden leer, enviar y cerrar; ADMIN no obtiene acceso.
- Mensajes de 1–1.000 caracteres, sin archivos, un envío por segundo y remitente,
  máximo 1.000 mensajes por conversación. Abrir admite 20 solicitudes/minuto.
- DELETE borra físicamente mensajes y conversación; el proceso elimina también
  chats con 24 horas de inactividad. Los vencidos dejan de ser legibles de inmediato.
- Para que DELETE repetido sea autorizado e idempotente se conserva únicamente
  `chat_closures`: ID aleatorio, fecha y dos pruebas HMAC, sin texto, pedido ni IDs
  de participantes. Esta sexta tabla nueva no contiene conversaciones recuperables.
  Rotar la clave del servidor invalida esas pruebas antiguas de cierre.
- El outbox y Redis llevan solo IDs del mensaje/conversación. El gateway carga
  el texto al entregar, revalida sesión y pertenencia y comprueba que el chat siga
  activo. Una notificación pendiente no recupera un mensaje borrado. No se manda
  contenido de chats a push, auditoría o logs de aplicación.
- Los mensajes ya recibidos por un dispositivo y las copias de seguridad externas
  tienen su propia retención; el borrado descrito afecta la base activa y la API.

Socket.IO mantiene sus salas anteriores y añade `user:{id}:chats` y
`business:{id}:chats`. Eventos: chat.opened, chat.message, chat.closed,
order.pickup_soon y order.business_closed. Las notificaciones no incluyen pickupCode.

## Migración y validación

Alembic `0003_v32` añade columnas con backfill conservador: cierre automático
desactivado, espera 30 minutos, portada/postergación/aviso nulos. Amplía CHECK de
estrellas a 0–5, añade índice parcial del vale y del aviso, y conserva IDs y
snapshots. Rechaza downgrade destructivo: la reversión exige restauración probada
del backup previo, con escrituras detenidas.

Las pruebas incluyen inventario de rutas sin eliminaciones, migración poblada
desde 0001 y 0002, comparaciones de todas las columnas antiguas, permisos,
reseñas cero, catálogo, vales, medianoche, cancelación, horarios, chat y Socket.IO.
Las carreras entre negocios, entre clientes legacy/V3, entre apertura de chat,
entre workers y entre entrega/cancelación se ejecutan con PostgreSQL real en CI.
Regresión local: **233 aprobadas y 32 omitidas por requerir PostgreSQL**, sin
fallos; Redis TCP y Caddy reales. Ruff, referencias generadas y diff también
aprobados. [Resumen local](evidence/v32-local-summary.json). La evidencia
PostgreSQL y del contenedor se registra con los enlaces a GitHub Actions.

## Integración pendiente fuera del backend

Esta entrega no migra datos productivos, cambia DNS ni envía correos reales.
La PWA de usuarios empaquetada sigue usando Firebase y conserva la Cocina antigua;
el portal mantiene el adaptador REST legacy. Conectar sus nuevas pantallas a V3.2,
retirar esa Cocina, sustituir el QR por pickupCode y migrar datos de Firestore son
trabajos de integración de frontend/datos. No presentar la implementación del
backend como si esas interfaces ya hubieran cambiado.
