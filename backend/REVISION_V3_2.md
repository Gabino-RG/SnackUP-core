# SnackUP: revisión de API V3.2 y esquema revisado

> Actualización posterior: [implementación V3.2](IMPLEMENTACION_V3_2.md). Este documento conserva la revisión previa; los faltantes de backend identificados se implementan en la nueva entrega.

Fecha de revisión: 23 de octubre de 2026.

**Estado: análisis y propuesta previa a implementación.** Este informe no declara implementada V3.2. Se conserva la implementación anterior y se pausa su publicación mientras se resuelven las discrepancias que el usuario pidió conocer antes de aplicar cambios.

## Aclaración de alcance tras revisar `main`

La inspección de Flutter de esta revisión inicial se hizo sobre `app/lib` de la rama de paneles (`17ad782`), junto con los cambios locales anteriores. **No representa todas las condiciones de la app original en `main` (`b7abff6`), cuyo código está en `lib/`.** La auditoría posterior de ambas ramas se documenta en `AUDITORIA_APP_Y_API_V3_2.md` y prevalece para atribuir funciones ya existentes.

En particular, la suma de cantidades, los límites de ocho líneas/99 unidades y la validación de programación dentro de 24 horas son mejoras de la rama de paneles. La app original reemplaza cantidades y no aplica esa ventana de 24 horas. La ventana y otras políticas propuestas a continuación siguen siendo propuestas, no autorizaciones derivadas de `main`.

## 1. Dictamen

Mantener **FastAPI + SQLAlchemy 2.x + Pydantic + Alembic + PostgreSQL + Socket.IO** es una buena decisión para este backend. SQLModel sería viable, pero no resuelve una limitación identificada del proyecto ni elimina la complejidad de las transacciones de inventario, entrega, sesiones y vales. Cambiar de ORM junto con las reglas V3.2 añadiría una migración innecesaria al mismo cambio.

La nueva versión sí amplía y modifica el contrato funcional. Su apartado 16.2 contiene veinte operaciones: **quince todavía no existen en el OpenAPI actual y cinco ya existen, aunque varias cambian de significado o de campos**. Además modifica creación, cancelación y entrega de pedidos. No basta cambiar nombres de clases o copiar el archivo Prisma.

El nuevo Prisma contiene cinco entidades adicionales respecto del adjunto original. Sin embargo, **falla `prisma validate` con dos errores de relaciones** y no incluye diez modelos que ya existen en el backend. La incorporación debe ser aditiva sobre el esquema real, conservando las garantías actuales.

Hay decisiones funcionales pendientes en programación de pedidos, fecha y liberación del vale, contrato del carrito y cierre de chats. Las propuestas de este documento están identificadas como tales; no se presentan como requisitos ya aprobados.

## 2. Fuentes y estado de partida

Se compararon cuatro documentos y el código actual, no solamente los dos adjuntos nuevos:

| Fuente | Resultado del inventario |
|---|---|
| `upload/SnackUP_API_V3_Consolidada.md` | Versión documental 3.1-consolidada, 1.010 líneas |
| `upload/API_V3_2_CONSOLIDADA.md` | Versión documental 3.2-revisada, 1.138 líneas |
| `upload/schema.prisma` | 13 modelos y 10 enums |
| `upload/schema_SnackUP_V3_2_revisado.prisma` | 18 modelos y 11 enums |
| `backend/schema.prisma` actual | Referencia de las 23 tablas reales, con `@map` y `@@map` |
| `backend/contracts/v3.openapi.json` actual | 55 operaciones de API y 2 de salud |
| Código Flutter y FastAPI | Contratos, validaciones, repositorios, modelos, transacciones, medios y eventos |

Huella SHA-256 de los adjuntos nuevos, conservados sin modificar:

```text
API_V3_2_CONSOLIDADA.md
af8d188c176195266cabbb08e8183a381ff3b5c80b6d7b384ebb7a8ab4ca404d

schema_SnackUP_V3_2_revisado.prisma
885ee4d615d6621f4e2f7ef20acb899c9f327692520bf99964ac15ca3b55925e
```

La base de implementación anterior tiene **206 pruebas aprobadas, sin fallos ni omisiones, con PostgreSQL y Redis**. La evidencia está en `evidence/v3-pytest-postgres.xml` y su alcance se explica en `VALIDACION_V3.md`. Esas pruebas **no certifican V3.2**: los nuevos flujos aún no están aplicados.

Durante esta revisión se leyó código y se validó el Prisma nuevo. No se ejecutaron migraciones, modificaciones de datos, despliegues ni nuevas publicaciones.

## 3. SQLAlchemy frente a SQLModel

### 3.1 Qué cambia realmente

SQLModel combina SQLAlchemy y Pydantic. Permite reducir repetición entre campos comunes de tablas y modelos de datos, pero conserva modelos distintos cuando la entrada, la persistencia y la respuesta difieren. También permite usar las capacidades subyacentes de SQLAlchemy. Por tanto, sería incorrecto afirmar que SQLModel no admite relaciones complejas o transacciones.

FastAPI no exige un ORM concreto. Con cualquiera de las dos opciones pueden mantenerse métodos HTTP, rutas, JSON, errores, autenticación y Socket.IO. **La independencia del contrato respecto del ORM no significa que V3.2 sea idéntica al contrato anterior:** `stars`, los medios de pago, las reseñas y la cancelación tienen cambios reales que Flutter debe conocer.

| Criterio | SQLAlchemy + Pydantic actual | SQLModel en este proyecto |
|---|---|---|
| Persistencia | Modelos tipados `Mapped` / `mapped_column` ya existentes | Tendría que representar las mismas tablas y restricciones |
| Entradas y respuestas | DTO explícitos; roles, secretos y campos calculados separados | También necesitaría modelos diferenciados para esos casos |
| Transacciones | Servicios compartidos, bloqueos ordenados, savepoints e idempotencia ya probados | Utilizaría el mismo motor transaccional de SQLAlchemy |
| Repetición de campos | Mayor; puede reducirse con tipos y DTO base cuidadosamente elegidos | Ventaja principal: compartir declaraciones sencillas |
| Migraciones | Alembic sobre metadata existente | Seguiría necesitando Alembic y comprobar equivalencia de metadata |
| Rendimiento | Depende de consultas, índices, bloqueos, conexiones y carga | No hay evidencia que permita prometer una mejora por cambiar de capa |
| Coste de adoptar ahora | Extender los servicios ya comprobados | Reescribir mappings y volver a verificar invariantes, además de V3.2 |

**Recomendación:** conservar SQLAlchemy para V3.2. Mantener una única autoridad de migraciones, Alembic, y regenerar Prisma como mapa verificable del esquema real. No ejecutar Prisma Migrate y Alembic como autoridades paralelas sobre las mismas tablas.

Fuentes primarias consultadas:

- [SQLModel: definición y relación con SQLAlchemy/Pydantic](https://sqlmodel.tiangolo.com/).
- [FastAPI: libertad para elegir biblioteca de base de datos](https://fastapi.tiangolo.com/tutorial/sql-databases/).
- [SQLModel: modelos separados de creación, tabla y respuesta](https://sqlmodel.tiangolo.com/tutorial/fastapi/multiple-models/).
- [SQLAlchemy 2: transacciones y savepoints](https://docs.sqlalchemy.org/en/20/orm/session_transaction.html).
- [SQLAlchemy 2: restricciones e índices](https://docs.sqlalchemy.org/en/20/core/constraints.html).

## 4. Diferencias funcionales verificadas

### 4.1 Las quince operaciones nuevas respecto del backend actual

Todas las rutas son relativas a `/api/v1`. La enumeración procede del apartado 16.2 del documento nuevo; no incluye las rutas adicionales que este informe propone más adelante.

| Método | Ruta | Finalidad |
|---|---|---|
| PATCH | `/businesses/{id}/closing-schedule` | Configurar cierre diario |
| POST | `/businesses/{id}/postpone-closing` | Posponer el cierre de hoy |
| POST | `/users/me/cart/items` | Crear o actualizar una línea privada |
| GET | `/users/me/cart/items` | Recuperar el carrito |
| PATCH | `/users/me/cart/items/{id}` | Cambiar cantidad y notas |
| DELETE | `/users/me/cart/items/{id}` | Quitar una línea |
| GET | `/users/me/favorites` | Listar favoritos |
| PUT | `/users/me/favorites/{productId}` | Añadir favorito |
| DELETE | `/users/me/favorites/{productId}` | Quitar favorito |
| GET | `/products/search?q=...` | Búsqueda de productos disponibles de negocios activos |
| POST | `/businesses/{id}/chats` | Abrir o recuperar la conversación del par autorizado |
| GET | `/chats/{id}/messages` | Leer mensajes mientras el chat siga activo |
| POST | `/chats/{id}/messages` | Enviar texto al otro participante |
| DELETE | `/chats/{id}` | Cerrar y borrar conversación y mensajes |
| GET | `/businesses/{id}/ratings` | Leer calificaciones públicas del negocio |

### 4.2 Operaciones existentes ampliadas o redefinidas

| Operación | Estado actual | Cambio V3.2 |
|---|---|---|
| `PATCH /businesses/{id}` | Datos públicos e imagen | Añadir portada separada `coverImageUrl` |
| `PATCH /businesses/{id}/status` | Cierre y apertura manuales | Integrar prioridad del cierre manual y avisos a pedidos programados |
| `PATCH /products/{id}` | Edición de catálogo con `isFeatured` | Aplicar límite de tres destacados y aclarar clasificación general/subcategoría |
| `POST /orders/{id}/rating` | `rating` entero 1–5; negocio | `stars` entero 0–5; negocio |
| `POST /orders/{id}/reviews` | Lote de reseñas por producto comprado | Alias opcional de la misma calificación del negocio; no otra fila |
| `POST /orders` | Efectivo/Transferencia; fecha programada no nula rechazada expresamente | Tarjeta/ValeComida, reserva diaria y fecha programada validada |
| `POST /orders/{id}/cancel` | Cocina solo antes de `ready`; reposición exactamente una vez | Excepción `not_picked_up` desde `ready`, con espera vencida y sin reposición |
| `POST /orders/{id}/complete` | Verifica código y entrega | Consumir también la reserva de vale en la misma transacción |

### 4.3 Reglas nuevas que están suficientemente definidas

- `not_picked_up`: solo Cocina, solo `ready`, nunca desde un estado terminal, y después de `max(readyAt, scheduledPickupTime o readyAt) + pickupTimeoutMinutes`. Default 30 minutos. No devolver stock. Antes del vencimiento: `422 PICKUP_TIMEOUT_NOT_REACHED`.
- Cierre automático deshabilitado inicialmente; hora local del negocio; una ejecución efectiva por fecha local; nunca apertura automática ni cancelación automática de pedidos existentes.
- Aviso `order.pickup_soon`: una creación lógica del aviso en la ventana de los últimos diez minutos, sin avisar después de la hora acordada ni para pedidos terminales. Marcador y evento en la misma transacción.
- Tarjeta es intención de medio de pago. No se incorpora un procesador de cobro ni se presupone que el pago fue recibido.
- Vale global por alumno y fecha del campus, con una restricción única real en PostgreSQL. No depende del negocio ni de una ventana móvil de 24 horas.
- Calificación cero válida; debe entrar en promedio y contador. Una calificación de negocio por pedido completado y propio.
- Chat solo entre alumno y Cocina del negocio; una conversación activa por pareja; texto máximo 1.000 caracteres; sin adjuntos; borrado físico al cerrar y al cumplir la inactividad establecida.
- Carrito y favoritos privados; el carrito no reserva stock ni convierte sus precios en autoridad para el pedido.

## 5. Hallazgos que deben comunicarse antes de aplicar

### D01. El Prisma adjunto no valida

Validación realizada con Prisma CLI 7.10.1:

```text
prisma validate --schema upload/schema_SnackUP_V3_2_revisado.prisma
Exit code: 1
Error code: P1012
Validation Error Count: 2
```

Faltan las relaciones inversas en `Platillo` correspondientes a `ItemCarrito.platillo` y `Favorito.platillo` (líneas 451 y 467 del adjunto). La corrección conceptual es añadir las colecciones inversas en `Platillo`. No requiere cambiar rutas ni introducir nuevas tablas, pero sí corregir el mapa antes de considerarlo válido. No se modificó el adjunto.

### D02. El esquema nuevo no es un reemplazo del esquema real

Los cinco modelos nuevos son `ItemCarrito`, `Favorito`, `UsoValeComida`, `ConversacionChat` y `MensajeChat`. Incorporarlos a las 23 tablas actuales produce **al menos 28**, según las entidades auxiliares que se decidan para los contratos pendientes.

El adjunto omite diez modelos actuales: `Carrera`, `GrupoAcademico`, `RegistroInstitucional`, `SolicitudAcceso`, `DecisionAcceso`, `TokenVerificacion`, `SeguimientoOpinion`, `EventoSeguimiento`, `EventoAuditoriaCuenta` y `EntregaPush`.

También faltan campos que mantienen reglas ya comprobadas: `manual_available`, `reserved_quantity`, `stock_restored`, `email_verified`, `auth_version`, `is_master`, vínculo de medios a negocio, familia de sesión del dispositivo y unicidad de versión en transiciones. No deben desaparecer por copiar un esquema más corto.

Otros cambios no solicitados por V3.2 incluyen estrechar importes y longitudes, convertir enums físicos, exigir códigos históricos de seis caracteres, cambiar la dirección del vínculo Usuario–Negocio y sustituir unicidad parcial por global. El adjunto tampoco contiene `@map`/`@@map` para dirigirse a las tablas existentes.

**Propuesta:** migración aditiva, mantener nombres y datos físicos existentes y regenerar la referencia Prisma. Conservar la cuenta Cocina activa única por negocio y los operadores históricos inactivos. Conservar negocios nuevos cerrados hasta apertura expresa. Los campos nuevos de horarios se inicializan deshabilitados; los nuevos marcadores se dejan nulos y no se inventan eventos pasados.

### D03. Reseñas: misma ruta, significado diferente

`snackup/v3_reviews.py` implementa actualmente `/rating` para negocio y `/reviews` para productos. V3.2 exige que ambas rutas se refieran a la misma calificación del negocio cuando se conserve la segunda como alias.

**Propuesta:** adoptar `/rating` como ruta canónica y `/reviews` como alias del mismo servicio y la misma restricción única de pedido. No duplicar calificaciones ni promedios. Conservar datos de opiniones por producto; si se necesita mantener su escritura, publicarla en una ruta diferenciada, por ejemplo `/orders/{id}/product-reviews`, expresamente documentada como extensión. No aceptar cuerpos ambiguos que elijan el significado de la misma ruta por heurística.

V3.2 usa `stars` en el request; el backend y Flutter usan `rating`. Propuesta de transición: `stars` canónico y alias de entrada `rating` para clientes anteriores; rechazar ambos si discrepan. Fijar los nombres de respuesta en OpenAPI y en el adaptador, sin duplicar columnas por esa diferencia de JSON.

### D04. Cero estrellas requiere cambios coordinados en Flutter

Las restricciones SQL y Pydantic actuales aceptan 1–5. Flutter también rechaza cero en `features/user/review_submission.dart`. La pantalla `rate_order_screen.dart` inicializa la selección en cero y muestra cinco opciones de 1 a 5. El panel administrativo, `features/admin/domain/admin_models.dart`, convierte cero a valor ausente, lo excluye de promedios y no lo incluye en el histograma ni en negativas.

Cambiar solo el backend haría que una nota válida desapareciera de las estadísticas del cliente.

**Propuesta:** representar ausencia con `null` en la UI, ofrecer cero como opción explícita, incluirlo en conteos y revisar el criterio de negativa. Conservar sin alteración los valores históricos desconocidos; no transformar automáticamente un cero antiguo usado como marcador de ausencia en una evaluación real. Las dimensiones existentes de alimentos/servicio y los snapshots académicos se conservan aunque V3.2 no los enumere en su ejemplo.

### D05. Vale: falta cerrar fecha aplicable y liberación

La unicidad `(alumnoId, fechaLocal)` y los estados reservado/consumido/liberado están definidos. No queda cerrado qué fecha corresponde a un pedido creado hoy para recogerse mañana, ni cómo resolver una entrega que cruza medianoche. El código no debe escoger silenciosamente una interpretación que permita dos redenciones físicas el mismo día.

Además se exige que Cocina confirme que un vale no fue redimido antes de liberarlo, pero no hay endpoint, campo ni respuesta para esa confirmación.

**Propuesta para revisión:** usar la fecha prevista de retiro en el campus, exigir revalidación si la entrega cruza de fecha y añadir una operación explícita de liberación por Cocina sobre un pedido cancelado. Esa operación bloquearía pedido y reserva, exigiría confirmación de no redención, quedaría auditada y nunca liberaría un vale consumido. La ausencia de certeza conserva la reserva. Alumno no puede liberar su vale por sí mismo. La ruta y el DTO concretos son una extensión por aprobar.

Al reasignar una fila liberada a otro pedido, registrar el vínculo anterior y el nuevo en auditoría, sin contenido sensible, y mantener coherentes sus timestamps. Las FK aisladas no aseguran por sí mismas que el vale y el pedido pertenezcan al mismo alumno.

### D06. Pedidos programados y cierres: hay opciones contradictorias

El apartado 16.5 afirma que el endpoint ya acepta fechas programadas. La implementación actual tiene el campo, pero rechaza valores no nulos con `SCHEDULING_NOT_CONFIGURED`, precisamente porque la política anterior estaba pendiente.

El servicio compartido de creación tampoco asigna hoy `scheduled_pickup_time` al construir el pedido, coherentemente con esa prohibición. Habilitar V3.2 exige validar y persistir el instante dentro de la transacción; ampliar solo el DTO dejaría un pedido sin su fecha acordada.

El apartado 16.4 dice tanto «no aceptar» recogidas incompatibles con el cierre como «mostrar advertencia o bloquear». El apartado 16.5 deja la antelación mínima por definir. También falta establecer horizonte de fechas, qué hacer con una posposición después del cierre ejecutado y cómo cambiar un horario cuyo cierre ya se procesó hoy.

**Propuesta basada en la rama de paneles, pendiente de decisión:** utilizar una ventana de las próximas 24 horas, exigir una fecha estrictamente futura con zona y rechazar el retiro incompatible con el cierre efectivo conocido. Una antelación mínima adicional debe acordarse con Cocina; el flujo actual solo exige futuro. No abrir ni cancelar pedidos automáticamente. Una advertencia de UI no reemplaza una regla de aceptación del servidor.

La ventana de 24 horas de `features/user/order_checkout.dart` puede cruzar medianoche, por lo que exige resolver fecha del vale y cierre del día siguiente. Limitar al mismo día sería una alternativa de menor alcance, pero reduciría la capacidad actual del cliente y no se propone aplicarla silenciosamente.

El catch-up debe distinguir un negocio abierto desde ayer de uno reabierto manualmente hoy. Puede requerir guardar la apertura manual además de `fechaCierreProcesada`. Los jobs deben coordinarse entre procesos mediante bloqueo/claim y confirmar cambio, versión, marcador y evento de forma atómica.

`pickupTimeoutMinutes` se describe como configurable, pero no figura en un body de escritura. Propuesta: incluirlo explícitamente en la configuración de negocio con rango 5–180 y `expectedVersion`; decidir si su modificación afecta pedidos ya listos o si se conserva un snapshot por pedido.

El ejemplo nuevo de cancelación devuelve `cancelledBy: "business"`, mientras el DTO V3 actual devuelve `COCINA`. Propuesta: fijar un único enum público para todas las cancelaciones, conforme a V3.2, sin variar según el motivo; mantener traducción para el cliente legacy.

### D07. Chat: faltan descubrimiento, recibo de cierre y DTO de eventos

Las cuatro rutas permiten abrir, leer mensajes, escribir y borrar. No hay ruta para que Cocina descubra las conversaciones que le abrieron alumnos mientras estaba desconectada.

**Adiciones propuestas, fuera de las quince rutas nuevas del adjunto:**

- `GET /users/me/chats`, para el alumno.
- `GET /businesses/{id}/chats`, para la Cocina propietaria.

Se propone respuesta paginada con ID, contexto autorizado y última actividad; mensajes ordenados por `(createdAt, id)` y cursor estable. Un chat ya abierto debe devolverse de forma idempotente y no crear un segundo chat por una carrera concurrente.

El documento exige borrar físicamente conversación y mensajes, pero también devolver `204` a cierres repetidos autorizados. Tras borrar toda evidencia del participante ya no puede probarse su autorización histórica con la fila original.

**Propuesta por aprobar:** conservar durante 24 horas un recibo mínimo de cierre —ID, participantes autorizados, fecha de cierre y expiración— sin mensajes. En esa ventana, un cierre repetido del participante devuelve `204`; después, `404`. Esto acota la idempotencia y exige aceptar explícitamente esa retención de metadatos. La alternativa es devolver `204` para cualquier ID ausente a un usuario autenticado, sin afirmar comprobación de participación histórica.

Los eventos nuevos `chat.message`, `chat.closed` y `order.pickup_soon` no están incorporados a la matriz previa de salas/eventos. El gateway actual filtra por una lista permitida: añadir un evento al outbox por sí solo no basta para entregarlo.

**Propuesta técnica:** outbox de chat con IDs y metadatos mínimos; recuperar el texto de la base solo si el chat sigue activo al preparar el envío autorizado. No persistir texto en outbox, auditoría, logs ni push. Definir `messageId`/`eventId` para deduplicación, permisos de sala y conducta tras cierre. La limpieza de chats vacíos usa la fecha de creación si aún no hay último mensaje. El envío concurrente con el cierre debe quedar serializado o rechazado sin resucitar la conversación.

La promesa de privacidad es la del documento: sin historial de chats cerrados en la base activa ni recuperable por API. No equivale a borrar instantáneamente copias ya recibidas o todos los respaldos.

### D08. Carrito: actualizar no especifica sumar o reemplazar

El Flutter de la rama de paneles usa un solo negocio por carrito, suma cantidades al añadir y elimina las líneas compradas al confirmar. V3.2 solo dice que POST crea o actualiza. Tampoco define cómo `/orders` identifica qué líneas/versiones debe retirar del carrito.

**Propuesta:** un negocio por carrito; POST y PATCH expresan cantidad absoluta; el botón Añadir calcula el total deseado. Cuando exista la línea, Flutter envía `expectedVersion`; un conflicto requiere releer y reconciliar, no repetir un incremento ciegamente. Esto necesita añadir `version` al nuevo modelo/DTO, que no aparece en el Prisma adjunto. Si la versión se omite, no debe prometerse protección contra actualizaciones perdidas entre dispositivos.

La alternativa es conservar POST como incremento y exigir una clave idempotente propia. Es válida, pero necesita almacenamiento y contrato de claves adicional; la tabla actual de idempotencia exige un pedido y no se reutiliza sin cambios.

No borrar todo el carrito tras comprar: retirar solo las líneas y cantidades confirmadas, con control de versiones para conservar ediciones concurrentes. Debe declararse cómo se envían esas referencias o cómo el repositorio realiza la reconciliación. No descontar stock al añadir al carrito.

Favoritos tiene otra omisión concreta: Prisma incluye `Favorito.notas` y Flutter guarda instrucciones al marcar un producto como favorito y las reutiliza al añadirlo al carrito. El PUT nuevo no define body. Propuesta: documentar `{ notes?: string }`, con máximo 500 caracteres, para conservar ese comportamiento sin copiar precios como autoridad.

### D09. Destacados, categorías y medios

«Máximo tres platillos activos» no define si activo significa no eliminado o disponible. Si solo se cuentan disponibles, un destacado agotado podría liberar un cupo y, al reponer stock, producir cuatro destacados.

**Propuesta:** contar destacados no eliminados, incluso temporalmente agotados o pausados; comprobar bajo el bloqueo del negocio que ya utiliza el catálogo. Si hay datos existentes con más de tres, informar y pedir selección de Cocina; no desmarcar arbitrariamente productos durante la migración.

La API permite categorías libres, mientras el Prisma exige DESAYUNO/COMIDA/SNACK/BEBIDA y una subcategoría. No existe una tabla de equivalencias ni campo público inequívoco para la clasificación general. «Hamburguesas» no debe convertirse a un enum por adivinanza.

**Propuesta:** conservar la etiqueta visible y los valores históricos; definir un campo de clasificación general explícito o una tabla aprobada antes de volverlo obligatorio. El catálogo no debe perder productos existentes por la introducción del enum.

`coverImageUrl` puede utilizar el propósito de medio `business`. Debe pasar la misma validación de propietario/negocio y añadirse a la comprobación de uso antes de permitir borrar un medio. Actualmente esa comprobación contempla `image_url`, no una portada aún inexistente.

La búsqueda se registra antes de `/products/{id}` para evitar interpretar `search` como un ID. Se fijarán paginación, longitud de consulta y disponibilidad efectiva. Conforme a la segregación de §2.5, Cocina busca únicamente dentro de su negocio; la palabra «Autenticado» de la tabla nueva no elimina ese alcance por recurso. El índice trigram es una posible optimización a medir, no una condición necesaria para copiar el campo `name_searchable` de Firestore.

### D10. Contradicciones heredadas y aceptación

La tabla de autenticación todavía promete registro `201 {user,tokens}`, pero deja pendiente probar titularidad del correo. La implementación anterior usa `202` sin sesión hasta verificación de correo y padrón autorizado. **Propuesta: conservar ese flujo y actualizar la documentación**, no devolver tokens por la mera existencia de la matrícula. El padrón local dentro de SnackUP no equivale a consultar la base remota institucional en cada login.

Los casos T10 y T12 de la matriz vieja todavía exigen devolución de stock en toda cancelación y prohibición absoluta de cancelar `ready`. Deben dividirse para reflejar `not_picked_up` sin devolución y con espera vencida. Es una inconsistencia documental resuelta por la precedencia explícita de V3.2.

Los eventos actuales transportan invalidaciones mínimas seguidas de GET. El aviso de retiro no debe descartarse por compartir `Order.version` con un evento anterior; tendrá identidad de evento propia o una versión de recurso coherentemente incrementada. El aviso de cierre anticipado al alumno también necesita destinatario y transporte definidos; `business.updated` público no prueba que ese alumno recibió una alerta.

## 6. Qué cambia en el modelo persistente

| Entidad | Ampliación requerida por V3.2 | Conservación importante |
|---|---|---|
| Business / Negocio | Portada, cierre habilitado, hora local, posposición, fecha procesada, minutos de espera | Versión, zona IANA, apertura manual, operador activo y datos históricos |
| Order / Pedido | Marcador del aviso de recogida y relación de vale/chat | Snapshots, código histórico, versión, entrega verificada, reserva real y reposición controlada |
| Review / CalificacionNegocio | Rango inclusivo 0–5 y DTO `stars` | Una fila por pedido, dimensiones anteriores, datos académicos y seguimiento |
| ProductReview / Resena | Rango 0–5 si se conserva la escritura de producto | Historial y unicidad por pedido/producto; no confundir con negocio |
| Product / Platillo | Regla transaccional de tres destacados; relaciones inversas de carrito/favoritos | Precio decimal, pausa manual, stock, baja lógica y categorías existentes |
| ItemCarrito | Nueva tabla; alumno/producto único, cantidad positiva, notas | Versión y semántica de actualización pendientes de contrato |
| Favorito | Nueva tabla; alumno/producto único | Propiedad privada y comportamiento ante producto retirado |
| UsoValeComida | Nueva tabla; alumno/fecha único y pedido único | Fecha aplicable, confirmación de liberación y auditoría de reasignaciones |
| ConversacionChat | Nueva tabla; alumno/negocio único | Pedido opcional validado y borrado físico al cerrar |
| MensajeChat | Nueva tabla; relación con chat y remitente | Texto acotado, orden estable, borrado en cascada y ausencia de texto en outbox |

Los comentarios Prisma que mencionan CHECK no crean restricciones. Alembic debe generar y verificar las restricciones SQL: estrellas 0–5, cantidad positiva, stock no negativo, hora HH:mm válida, rango de espera, estado del vale y unicidad. Los índices de limpieza de chats y de avisos se diseñan según las consultas reales de los jobs.

## 7. Integración Flutter que hay que contemplar

No basta cambiar `API_BASE_URL`. La app original de alumnos en main y los flujos Firebase conservados en paneles siguen usando Firestore; las implementaciones y sus validaciones no son idénticas. El portal REST de Cocina/Admin usa `/api/legacy/v1`, cuyos códigos de rol y algunos DTO difieren de V3.

Cambios concretos detectados:

1. Métodos de pago actuales: `Efectivo`, `Tarjeta`, `Vale`; V3.2: `Efectivo`, `Transferencia`, `Tarjeta`, `ValeComida`. Traducir `Vale` en el adaptador y conservar valores históricos sin reescritura engañosa.
2. Calificaciones: separar ausencia de cero, adaptar `stars`/`rating`, incluir cero en estadísticas y diferenciar producto de negocio.
3. Carrito: establecer cantidades, versión, negocio único, conciliación tras pedido y conservación de ediciones concurrentes.
4. Chats: listas, cursor, reconexión REST, eliminación de caché al cerrar y mensajes recibidos solo mientras la conversación esté autorizada.
5. Pedidos: fecha con zona, aviso de cierre, estado no recogido y mensajes claros para conflicto de vale/horario/versiones.
6. Sesión: roles ALUMNO/COCINA/ADMIN en el adaptador V3; mantener compatibilidad del panel anterior durante el cambio.
7. Eventos: Socket.IO, reconciliación al reconectar y sin introducir polling HTTP periódico en el cliente V3.

Además, `features/user/order_checkout.dart` rechaza hoy `stock: null` y limita a ocho líneas, mientras REST V3 permite inventario no controlado y hasta cincuenta líneas. El detalle del producto también trata stock nulo como cero. Son diferencias del adaptador del alumno que deben revisarse al migrarlo; no demuestran por sí mismas un fallo de la API.

Los lectores de pedidos y el contrato de compatibilidad también deben reconocer Tarjeta/ValeComida al leer un pedido creado por V3.2. No deben convertir un medio desconocido a efectivo para poder deserializarlo.

Las interfaces públicas se pueden conservar o ampliar desde FastAPI. Los cambios de comportamiento anteriores proceden del contrato V3.2, no de la elección entre SQLAlchemy y SQLModel.

## 8. Implementación propuesta después de cerrar las decisiones

1. Publicar un anexo de adaptación FastAPI V3.2 que incorpore las correcciones aprobadas y enumere los DTO/errores/eventos nuevos.
2. Añadir una migración sobre la revisión actual, sin reescribir la migración anterior ni usar el adjunto como sustituto de la base. Verificarla con una base anterior poblada.
3. Extender servicios compartidos para que `/api/v1` y `/api/legacy/v1` no se salten mutuamente restricciones de inventario, destacados, vales o estados.
4. Incorporar rutas, autorización por recurso, jobs con claims transaccionales y eventos. Evitar dos schedulers independientes que emitan el mismo aviso lógico.
5. Actualizar el exportador Prisma y OpenAPI y ejecutar sus comprobaciones de correspondencia con el código.
6. Actualizar los adaptadores de Flutter afectados y conservar la compatibilidad durante la migración progresiva.
7. Ejecutar las pruebas de regresión existentes más las nuevas de V3.2; publicar evidencias separadas para no atribuir pruebas antiguas al nuevo contrato.

Orden de bloqueos: preservar el orden ya verificado de usuario/pedido/negocio/productos, incorporando el vale y los claims sin introducir esperas inversas entre servicios. No lanzar llamadas a push o Socket.IO dentro de la transacción de inventario. Confirmar primero datos y outbox; publicar después.

## 9. Pruebas necesarias de V3.2

| Área | Casos que deben añadirse |
|---|---|
| Prisma y migración | Relaciones válidas, modelos preservados, upgrade de base poblada, CHECK y FK reales, referencia sin divergencias |
| No recogido | Antes/en/después del límite; programado posterior a ready; solo Cocina; sin reposición; reintentos; carrera entrega/cancelación |
| Vale | Dos pedidos simultáneos en negocios distintos; misma clave idempotente; medianoche del campus; fecha programada; vale consumido no liberable; liberación confirmada y auditada |
| Horarios | Cierre manual, cierre diario, posposición de hoy, siguiente día, reinicio, dos workers, reapertura manual, fechas con zona y cierres incompatibles |
| Aviso | T-10 minutos, creación dentro de la ventana, horario ya pasado, pedido terminal, reinicio/reintento, dos workers, deduplicación del cliente |
| Reseñas | Cero válido y fracciones/bool fuera de contrato; promedio con cero; ambos aliases sin duplicado; dueño/pedido completado; privacidad y estadísticas Flutter |
| Destacados | Cuarto destacado rechazado; dos tablets compitiendo por tercer lugar; agotamiento/reposición; baja lógica; escritura legacy |
| Carrito | Otro usuario; otro negocio; quantity inválida; notas; reintento POST; versión vieja; edición concurrente con checkout |
| Chat | Apertura concurrente única; Cocina deriva alumno del pedido; otro participante rechazado; envío contra cierre; cierre repetido; limpieza de chat vacío/inactivo; sin texto en outbox/push/logs |
| Medios y búsqueda | Portada de negocio ajeno rechazada, imagen en uso no borrable, prioridad de ruta search, productos retirados/agotados y negocio inactivo |
| Contratos | JSON real contra OpenAPI, enum de cancelledBy, errores nuevos, roles y eventos con campos mínimos autorizados |

Una ejecución funcional no sustituye la prueba de carga de 1.000 usuarios ni la validación de infraestructura y proveedores externos.

## 10. Decisiones que necesitan respuesta

Las correcciones de relaciones, la conservación de tablas y la adaptación de tecnología tienen una solución técnica identificada. Los siguientes puntos sí cambian políticas o contratos que el documento no termina de fijar:

| Decisión | Recomendación para revisar | Motivo |
|---|---|---|
| Programación | Propuesta de próximas 24 horas y fecha futura; acordar antelación; bloquear retiro incompatible con cierre | Es la ventana de la rama de paneles, no una regla ya aplicada en main |
| Vale | Fecha prevista de retiro; confirmación explícita de Cocina para liberar; definir el cruce de medianoche | La unicidad debe representar el uso diario real |
| Chat | Añadir los dos listados y aceptar recibo de cierre sin contenido por 24 h | Reconexión usable e idempotencia con autorización verificable |
| Carrito | Cantidad absoluta, versión en ediciones y un solo negocio; referencias de líneas confirmadas en checkout | Evita sumar por reintento o borrar cambios concurrentes |
| Destacados | Tres productos no eliminados; no liberar cupo al agotarse | La reposición no debe crear un cuarto destacado |
| Categorías | Clasificación general explícita o tabla aprobada; conservar etiquetas existentes | No asignar enums por adivinanza |
| Espera de retiro | Definir ruta de escritura y si el cambio se aplica a pedidos ya listos | Un cambio de configuración puede adelantar el límite de un pedido existente |

**Motivo de la pausa:** el usuario pidió ser informado de discrepancias y mejoras antes de aplicarlas. Este documento concreta esas diferencias y sus alternativas. No se ha iniciado una migración V3.2 ni se ha presentado como implementada.
