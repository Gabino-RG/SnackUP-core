# SnackUP: cotejo de los adjuntos FastAPI V3.2 con las tres aplicaciones

Revisión: 23 de octubre de 2026. **Sí faltan contratos y servicios; no procede declarar V3.2 terminada.**

Este informe actualiza `AUDITORIA_APP_Y_API_V3_2.md` y `REVISION_V3_2.md` con los
adjuntos Python, el código publicado y el requisito nuevo de un contenedor de
aplicación. Prevalece sobre sus afirmaciones de ausencia de rutas administrativas.
No sustituye el análisis funcional detallado de esos documentos.

## Fuentes y resultado reproducible

| Fuente | Revisión inspeccionada |
|---|---|
| Backend | `1c3459bfd58a083acf4a1638c5013db93873f057`, `backend/snackup/`; su código coincide con `88bc0b7`, la revisión siguiente añadió evidencia documental |
| Alumnos original | `b7abff6593e84dda69ad2909abbf699dd17ff890`, `lib/` |
| PWA empaquetada de alumnos | `a00d0bf4ecdae74a89f3afbe8ec3d0758efb8884`; mismo código Dart de main |
| Cocina/Administración | `19c81fdee29600d66d9dcb1a4f109a78aeba51f6`, `app/lib/` |
| Adjuntos nuevos | `API_V3_2_FASTAPI_SQLALCHEMY.md`, `models.py`, `GUIA_DE_MIGRACION.md` |

El inventario [v32-current-inventory.json](evidence/v32-current-inventory.json)
incluye las huellas SHA-256 del contrato y modelo, todas las operaciones y las
tablas. Se genera desde el OpenAPI vivo, no solo desde un archivo exportado:

```bash
python tools/audit_v32.py --contract /ruta/API_V3_2_FASTAPI_SQLALCHEMY.md \
  --models /ruta/models.py --output reports/v32-current-inventory.json
```

Resultado: **55 operaciones canónicas actuales**, excluyendo salud, y **55
operaciones distintas en las tablas del adjunto**. Comparten 40; hay **15 rutas
del documento ausentes** y **15 existentes omitidas en esas tablas**. La igualdad
de totales no demuestra cobertura. La inspección de DTO y servicios detecta,
además, comportamientos distintos bajo rutas que sí coinciden.

## 1. Funciones actuales que el contrato no debe perder

Todas las rutas siguientes son relativas a `/api/v1`, salvo indicación legacy.

| Hallazgo | Evidencia y corrección de contrato necesaria |
|---|---|
| Historial privado del alumno ausente en V3 y V3.2 | `lib/features/user/profile_orders_screen.dart` muestra terminados/cancelados y permite volver a pedir/calificar. Solo existe el listado completo en `/api/legacy/v1/student/orders`. Proponer `GET /users/me/orders/history` privado, paginado y ordenado; el historial del negocio no lo reemplaza. |
| Carrusel global de destacados sin consulta acordada | `lib/features/home/user_home_screen.dart` consulta destacados de varios negocios. La API solo lista menú por negocio. Definir una consulta global, por ejemplo `GET /products/featured`, o un filtro global con paginación. Tres destacados por negocio y cinco tarjetas globales son límites diferentes. |
| Detalle de producto omitido del catálogo documental | `GET /products/{id}` ya existe en `v3_operations.py`; se debe preservar para revalidar favoritos y recompras. No necesita una nueva implementación. |
| Administración académica y seguimiento omitidos del adjunto | **Ya están montadas** en `/api/v1`: `GET /institution`, `/admin/academic-catalog`, `/admin/reviews`, `/admin/followups`, `/admin/reviews/{id}/followup`, `/admin/reviews/{id}/followup/history` y `PUT /admin/reviews/{id}/followup`. `main.py` monta expresamente esas extensiones; tienen contratos propios, no todos los DTO V3 normalizados. |
| Tres operaciones administrativas permanecen solo en legacy | `GET /admin/access-requests`, `POST /admin/access-requests/{id}/decision`, `POST /admin/users`. El portal las utiliza. Mantener el adaptador y documentar su futura ruta canónica; crear negocio+COCINA no sustituye dar de alta un administrador. |
| Otras rutas implementadas omitidas de tablas | `GET /admin/users`, `PATCH /users/me`, `GET /auth/options`, `GET /auth/google/start`, `POST /auth/resend-verification`, `POST /auth/verify-email`, `GET /products/{id}/reviews`. Inventario no implica que Google esté habilitado; revisar la capacidad devuelta por `/auth/options`. |
| Estadísticas incompletas para conservar la pantalla original | `lib/features/business/statistics_screen.dart` calcula serie diaria, productos principales y métodos de pago. `SalesSummaryResponse` solo ofrece completed/cancelled/totalSold. Definir agregados y fecha de agrupación, sin confundir importe de pedidos con dinero cobrado. |
| Favoritos contienen notas | `profile_orders_screen.dart` reutiliza instrucciones al añadir al carrito. El PUT de favoritos del documento debe admitir/documentar `notes`; no copiar precios antiguos como precio autorizado. |
| Chat necesita descubrimiento | Las cuatro rutas de chat propuestas no permiten listar conversaciones recibidas mientras Cocina estaba desconectada. Faltan contratos de listado de chats propios/al negocio, payloads de eventos y resolución del cierre repetido tras borrar los participantes. Es una necesidad nueva, no una pantalla heredada de main. |

**Corrección de la auditoría anterior:** no son diez operaciones administrativas
ausentes de V3: siete ya se montan como extensiones y tres siguen solo en legacy.
No cambiar el `API_BASE_URL` del portal a V3 hasta adaptar sus roles, DTO, sesión
y protocolo realtime; la coincidencia de rutas no garantiza compatibilidad.

## 2. Las quince operaciones del adjunto que aún no existen

| Grupo | Operaciones faltantes |
|---|---|
| Cierres (2) | `PATCH /businesses/{id}/closing-schedule`; `POST /businesses/{id}/postpone-closing` |
| Carrito (4) | `GET` y `POST /users/me/cart/items`; `PATCH` y `DELETE /users/me/cart/items/{id}` |
| Favoritos (3) | `GET /users/me/favorites`; `PUT` y `DELETE /users/me/favorites/{productId}` |
| Búsqueda (1) | `GET /products/search?q=...` |
| Chat (4) | `POST /businesses/{id}/chats`; `GET` y `POST /chats/{id}/messages`; `DELETE /chats/{id}` |
| Reseñas públicas de negocio (1) | `GET /businesses/{id}/ratings` |

Estos faltantes son distintos del historial y los destacados, que faltan también
en el propio documento. No se cuentan de nuevo como parte de las quince.

## 3. Verificación de reglas del backend

| Regla | Resultado de lectura de servicios y pruebas |
|---|---|
| FastAPI + SQLAlchemy + Pydantic + Alembic + PostgreSQL | Implementados. El motor actual es SQLAlchemy **síncrono con psycopg**, con rutas síncronas en el threadpool; no AsyncSession/asyncpg como ejemplifica el adjunto. No es NestJS ni Prisma en ejecución. Cambiar a async requeriría una migración de servicios y pruebas, no copiar modelos. |
| Registro público ALUMNO y elegibilidad institucional | `v3_identity.py` reutiliza registro institucional y verificación de correo; no acepta elevación de rol. El padrón autorizado y SMTP reales siguen siendo configuración operativa pendiente. |
| JWT, refresh rotativo, revocación, cookie web | Implementados en identidad/auth; el contenedor mantiene el mismo origen y `/paneles/` para enlaces de recuperación. |
| Totales, snapshots, consecutivo por negocio e idempotencia | Implementados en `operations.create_order_transaction`: importes servidor, reservas de stock, bloqueo de negocio/productos, huella de request y consecutivo. Las garantías de carreras requieren PostgreSQL; SQLite no las certifica. |
| Código de retiro secreto y autorización por propietario | DTO de alumno incluye código; DTO de Cocina y eventos filtrados lo omiten. Validación y límite de intentos en servidor; no se usa matrícula como respaldo. |
| Seis estados y versiones | Implementados los seis estados y transiciones nominales. La excepción V3.2 `not_picked_up` desde ready **no existe**. |
| Descuento y reposición de stock | Implementados `reserved_quantity`, `stock_restored`, disponibilidad manual y efectiva. No deben desaparecer al sustituir modelos. |
| Programación y aviso T-10 | El DTO actual rechaza toda fecha no nula con `SCHEDULING_NOT_CONFIGURED`; no hay worker de aviso. Tener una columna no significa que el flujo esté habilitado. |
| Tarjeta y ValeComida | `CreateOrderInput` admite Efectivo/Transferencia. Faltan métodos nuevos, reserva global por día de campus y consumo/liberación transaccional del vale. |
| Cero estrellas y alias de reseñas | Actual: `rating` 1–5; `/reviews` escribe reseñas de productos. Adjunto: `stars` 0–5 y `/reviews` alias del negocio. Incompatibilidad que exige cambio coordinado de DTO, constraints, agregados y UI; no renombrar la ruta silenciosamente. |
| Portada, cierres, timeout y destacados | `coverImageUrl`, configuración de cierre y timeout no están en el DTO actual. `isFeatured` existe, pero no se impone máximo tres con bloqueo. |
| Socket.IO | Backend V3 sí autentica, autoriza salas, revalida sesión y filtra secretos. Nuevos eventos `chat.message`, `chat.closed`, `order.pickup_soon` no están habilitados. |
| Transporte del portal | Cocina/Administración usa WebSocket legacy y refresco periódico en `business_portal.dart`; aún no cumple la decisión V3 de Socket.IO sin polling HTTP de respaldo. El contenedor conserva compatibilidad mientras se migra. |
| PWA de usuarios | Sigue Firebase, incluye Cocina histórica, no reconoce todos los estados V3 y muestra QR basado en matrícula. No es todavía un cliente PostgreSQL/REST, aunque comparta imagen con FastAPI. |

## 4. Por qué no sustituir los modelos con el adjunto

El adjunto define 18 tablas; el backend actual define **23**. Son esquemas
físicos distintos, no una versión corta intercambiable. Por ejemplo, `reviews`
es la calificación del negocio en la implementación y la reseña de producto en
el adjunto. Además cambian nombres de columnas, enums y tablas de sesiones,
medios, idempotencia y transiciones.

Diez entidades semánticas existentes faltan en el archivo nuevo:
`Career`, `AcademicGroup`, `AcademicRecord`, `AccessRequest`, `AccessDecision`,
`VerificationToken`, `Followup`, `FollowupEvent`, `AccountAuditEvent` y
`PushDelivery`. Son necesarias para padrón, permisos, seguimiento y notificaciones.

Los cinco módulos nuevos de persistencia son carrito, favoritos, usos de vale,
conversaciones y mensajes. La incorporación conservadora parte de las 23 tablas
actuales y añade esas cinco (al menos 28), sin descartar sesiones, datos históricos
ni garantías de concurrencia. Alembic sigue siendo la única autoridad de migración.

El índice parcial de vale del adjunto permite mantener filas LIBERADO históricas;
es una buena base de diseño. Sigue faltando fijar fecha aplicable a recogidas en
otro día, verificación al cruzar medianoche y operación de Cocina para confirmar
que un vale cancelado no fue redimido. No simular esas decisiones con un flag de UI.

## 5. Cambios realizados en esta entrega

La instrucción condicionó los cambios funcionales a que no faltara nada. Como
hay brechas verificadas, **no se reemplazaron servicios, tablas ni pantallas**.
Se preparó el cambio independiente y explícitamente solicitado de infraestructura:

- `compose.unified.yaml`: exactamente `app` y PostgreSQL `db`.
- Una imagen `app`: ambos builds Flutter, FastAPI/Uvicorn, Caddy HTTPS y Redis
  privado mediante socket Unix. Sin contenedores separados para los frontends.
- Fuentes frontend fijadas por SHA y contexto backend en esta rama; las tres
  ramas siguen separadas para desarrollo.
- Supervisor sin privilegios: migración antes del API, cierre conjunto ante
  fallo de un proceso, señales a los grupos de procesos y healthcheck completo.
- CI con construcción, migración PostgreSQL, pruebas HTTP/Socket.IO y reinicio
  ante pérdida de Redis; usa datos sintéticos y no despliega un servidor real.

Instrucciones y límites: [DESPLIEGUE_CONTENEDOR_UNICO.md](DESPLIEGUE_CONTENEDOR_UNICO.md).

## 6. Validación

Prueba local del cambio: **209 aprobadas y 26 omitidas por requerir PostgreSQL**,
sin fallos, con Redis TCP local y Caddy real. Las ocho pruebas nuevas verifican
supervisión, señales, separación de interfaces y conservación de rutas/errores.
Ruff, `export_prisma_reference.py --check`, `export_v3_openapi.py --check` y
validación del Caddyfile de producción también aprobaron.

La conexión Unix de Redis y los montajes del contenedor se prueban en CI: este
entorno local no permite sockets Unix. Un fallo inicial de dos tests push se
resolvió instalando `socksio` en el entorno de pruebas, requerido por el proxy de
esta sesión; no se modificó la lógica del producto para hacer pasar esas pruebas.

Los resultados locales y los resultados del workflow se registran por separado.
Las pruebas existentes validan V3, no los flujos V3.2 que siguen ausentes.
No se usaron cuentas reales, SMTP, Firebase ni datos productivos. No se ejecutó
migración en un servidor del usuario ni se midieron usuarios concurrentes.

El entorno local dispone de Caddy y Python, pero no de Docker/Flutter ejecutables
ni de un PostgreSQL local accesible para estas pruebas. Por ello la comprobación
completa del contenedor y de la concurrencia SQL corresponde a GitHub Actions.
Consultar el resultado del commit; un workflow escrito no equivale a una prueba
aprobada. Las pruebas locales de proxy usan archivos HTML sintéticos claramente
separados de la compilación Flutter del workflow.
