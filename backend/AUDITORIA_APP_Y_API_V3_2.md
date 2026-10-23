# SnackUP: auditoría de la app y cobertura de API V3.2

Fecha: 23 de octubre de 2026.

**Estado: auditoría de código y propuesta de contrato. No se ha implementado V3.2 en esta revisión.**

## 1. Dictamen y alcance

**Sí hay omisiones adicionales a las recogidas en `REVISION_V3_2.md`.** La más importante para el alumno es la falta de una consulta canónica de su historial de pedidos terminados. La app utiliza ese historial para mostrar compras/cancelaciones, volver a pedir y abrir la calificación. La API V3.2 solo enumera pedidos activos del alumno y el historial exclusivo de Cocina. El backend canónico actual reproduce esa omisión, aunque el adaptador legacy conserva un listado propio completo.

También falta declarar cómo consultar el carrusel global de destacados, y el documento V3.2 omite `GET /products/{id}`, que ya existe en el backend y sirve para releer productos al reordenar o añadir favoritos. En administración hay diez operaciones que usa realmente el portal legacy y que no tienen sustituto canónico, y la pantalla estadística de main consume desgloses que el DTO actual de estadísticas no ofrece. Estas situaciones son diferentes: funciones ausentes en el contrato/API canónica, consultas que podrían componerse pero carecen de una estrategia acordada, y rutas implementadas que falta documentar.

La auditoría distingue la app de alumnos en **main** de las mejoras existentes dentro de la rama de paneles. No se atribuyen a main la suma de cantidades, el máximo de ocho líneas, el límite de noventa y nueve unidades, la ventana de veinticuatro horas ni el repositorio transaccional de pedidos: pertenecen a la rama de paneles.

Este documento contiene los recorridos trazables del alumno, Cocina, administración y acceso, además de las diferencias de configuración que afectan su integración con el backend. No se declara que una pantalla esté operativa por tener un nombre o un botón: se comprueba la lectura, escritura o navegación que realiza.

## 2. Fuentes verificadas y convención de citas

| Código | Fuente exacta | Uso en la revisión |
|---|---|---|
| **M** | [Main b7abff6593e84dda69ad2909abbf699dd17ff890](https://github.com/Gabino-RG/SnackUP-core/tree/b7abff6593e84dda69ad2909abbf699dd17ff890/lib), checkout de auditoría `SnackUP-usuarios`, rama de trabajo `codex/usuarios-pwa` | App actual de alumnos. Flutter está en `lib/`, no en `app/lib/`. |
| **P** | [Paneles 17ad7823321fe79b673e10f7a201af02bec79628](https://github.com/Gabino-RG/SnackUP-core/tree/17ad7823321fe79b673e10f7a201af02bec79628/app/lib), árbol `app/lib/` | Comparar mejoras ya hechas en la rama de paneles, sin atribuirlas a main. |
| **B** | Árbol `backend/` de la implementación V3 preparada en esta sesión; checkpoint local `8ed8eb3623107bccfe736feb5e58ce6af346f613` | Rutas y servicios que existen realmente. No equivale al backend publicado en el SHA original de paneles. |
| **D** | `/workspace/scratch/a8f792a69674/upload/API_V3_2_CONSOLIDADA.md` | Contrato documental V3.2, 1.138 líneas. |
| **S** | `/workspace/scratch/a8f792a69674/upload/schema_SnackUP_V3_2_revisado.prisma` | Modelo propuesto revisado, 532 líneas. |
| **R** | `backend/REVISION_V3_2.md` | Hallazgos previos; esta auditoría no los presenta de nuevo como descubrimientos adicionales. |

Las citas `M:lib/...:línea` y `P:app/lib/...:línea` identifican esos commits, no archivos de versiones intercambiables. La sección 10 contiene enlaces a los archivos exactos, que siguen siendo válidos aunque la rama del backend retire sus carpetas de frontend. `B:snackup/...:línea` identifica el árbol de implementación inspeccionado. Las rutas REST de las tablas son relativas a `/api/v1`, salvo el prefijo legacy expresamente indicado.

Método: inventario de archivos, lectura de navegación y manejadores, trazado de consultas/escrituras Firestore, comparación con las rutas y DTO de FastAPI y con D/S. No se conectó a Firebase, no se probaron cuentas reales, no se modificaron datos ni se ejecutó carga. La revisión estática no sustituye la futura prueba de navegación con el repositorio REST.

## 3. Recorrido real del alumno en main

`main.dart` abre `AuthWrapper`; este escucha la sesión Firebase y `RoleGate` lee `users/{uid}`. El rol `user` abre `UserDashboardScreen`. El dashboard contiene Inicio, Buscar, Carrito y Pedidos; esta última pantalla contiene Activos, Historial y Favoritos. El único control global de cuenta del dashboard es cerrar sesión. Fuentes: M:lib/main.dart:284; M:lib/features/auth/auth_gate.dart:15–24,37–59; M:lib/features/home/user_dashboard_screen.dart:21–26,62–70,286–288; M:lib/features/user/profile_orders_screen.dart:81–95.

No hay un cliente REST de alumnos ni una selección de proveedor por `API_BASE_URL` en ese recorrido. Las pantallas llaman directamente a Firebase Auth/Firestore. Por tanto, desplegar la API no conecta automáticamente main: hay que introducir/adaptar repositorios y sustituir esas lecturas y escrituras. D:19,28,100,1136 ya pide esa migración.

### 3.1 Matriz funcional trazable

Estados: **Real** significa un manejador conectado a datos/navegación en el código inspeccionado; **visual** significa presentación sin la acción sugerida; **ausente** significa que no se encontró un flujo conectado en main. No significa que se haya certificado su ejecución contra producción.

| Función y evidencia en main | Lectura/escritura real | Ruta canónica actual o prevista | Cobertura y trabajo necesario |
|---|---|---|---|
| Entrada y rol — `auth_gate.dart:15–59` | Sesión Firebase; GET del documento `users/{uid}`; navegación por `user`/`business`. **Real.** | B `GET /users/me`; auth V3. | Cubierto en API; adaptar sesión, roles ALUMNO/COCINA y manejo de errores. No aceptar rol elegido por la UI como autorización. |
| Nombre de bienvenida — `user_home_screen.dart:37–39` | `FirebaseAuth.currentUser.displayName`, con fallback al correo. **Real.** | B `GET /users/me`. | Diferencia de origen del perfil, no ruta faltante. |
| Tiendas abiertas — `user_home_screen.dart:382–386,574–582` | Stream `businesses where isOpen=true`; abre menú con ID/nombre. **Real.** | B `GET /businesses?isOpen=true&page=&limit=`. | Cubierto. Reconciliar tras eventos y consumir paginación. |
| Carrusel global de destacados — `user_home_screen.dart:164–170,200–205` | Stream de todos los productos `isFeatured=true`, `isAvailable=true`, límite global cinco. **Real en lectura.** | No hay consulta global declarada de destacados. B solo lista productos por negocio; D añade búsqueda por nombre. | **Omisión nueva de consulta.** Definir filtro global de destacados o composición exhaustiva de menús; no confundir cinco tarjetas globales con el límite de tres destacados por negocio. |
| Flecha de una promoción — `user_home_screen.dart:214–350` | La tarjeta es un `Container` y la flecha un `Icon`; no recibe ID ni tiene `onTap`. **Visual.** | No necesita ruta nueva por sí sola; P ya conecta la tarjeta al detalle. | No declarar que main ya navega al producto desde promociones. Incorporar la navegación sería una mejora de cliente. |
| Menú por negocio/categoría — `menu_screen.dart:19–25,104–109,182–190` | Productos del negocio, disponibles, ordenados por categoría y nombre; agrupación visual; abre detalle. **Real.** | B `GET /businesses/{id}/products?isAvailable=true&page=&limit=`. | Cubierto. Mantener etiqueta visible y orden; resolver `stock:null`, que main trata como agotado. |
| Búsqueda global — `search_screen.dart:23–50,77–84,395–417` | Debounce 500 ms, desde dos caracteres; prefijo minúsculo sobre `name_searchable`, hasta veinte resultados; abre detalle. **Real.** | D propone `GET /products/search?q=`; ausente en B actual. | Omisión ya inventariada en R. Definir paginación y aceptar el cambio explícito de prefijo a contiene, sin copiar el índice de Firestore. |
| Detalle de producto — `product_detail_screen.dart:7–15,149–156` | Presenta el mapa obtenido del menú/búsqueda; precio, descripción, foto, stock y destacado. **Real.** | B `GET /products/{id}`. | Ruta implementada, **omitida en la tabla de D**. Usarla para refrescar antes de operaciones; resolver stock nullable. |
| Selección de cantidad/notas — `product_detail_screen.dart:73–80,99–107` | Incremento/decremento local con mínimo uno; notas libres; guarda cantidad absoluta. **Real.** | D POST/PATCH de carrito. | Main no impone máximo 99 ni suma lo ya guardado. Límites y semántica se deben documentar; son diferentes de P. |
| Añadir al carrito — `product_detail_screen.dart:93–110` | `set` de `users/{uid}/cart/{productId}` con producto, cantidad, notas y copia visual de datos. **Real.** | D `POST /users/me/cart/items`. | Falta implementar según R. Semántica absoluta coincide con main. El backend debe usar catálogo, no aceptar esos precios como autoridad. |
| Estado y alta/baja de favorito — `product_detail_screen.dart:33–61,172–175` | Lee el favorito concreto en stream; `set`/`delete`; guarda notas. **Real.** | D GET favoritos, PUT/DELETE por producto. | Puede reconstruirse el corazón desde el listado; no requiere necesariamente GET de favorito individual. Falta definir notas y respuesta de la colección, ya detectado en R. |
| Consultar carrito — `cart_screen.dart:201–227` | Stream de líneas privadas; suma precios guardados por cantidad en el cliente. **Real.** | D `GET /users/me/cart/items`. | Falta implementar. Devolver datos actuales para presentación y total orientativo; el pedido se recalcula al confirmar. |
| Quitar línea — `cart_screen.dart:427–433` | Confirmación visual y `delete` de la línea. **Real.** | D `DELETE /users/me/cart/items/{id}`. | Cubierto por ruta propuesta. Main no contiene un editor de cantidad dentro de esta pantalla; PATCH amplía la capacidad. |
| Selección de pago y hora — `cart_screen.dart:19–42,125–144` | Efectivo/Tarjeta/Vale; hora del mismo día del dispositivo guardada como Timestamp. **Real.** | `POST /orders` con `paymentMethod`, `scheduledPickupTime`. | V3 actual solo admite Efectivo/Transferencia y rechaza horario no nulo. V3.2 amplía métodos/programación; falta adaptar Vale→ValeComida y políticas, ya revisadas en R. |
| Confirmar compra/vaciar líneas — `cart_screen.dart:98–156` | Rechaza mezcla de locales al confirmar; copia precios/notas del carrito; crea orden y borra líneas en un batch Firestore. **Real.** | B `POST /orders` con UUID idempotencia y `expectedTotal`; integración con carrito pendiente. | Adaptación importante: datos del alumno, totales, inventario, número y código pertenecen al servidor. Confirmación y limpieza segura de líneas siguen pendientes en el contrato del carrito. |
| Pedidos activos — `profile_orders_screen.dart:29–33,113–116` | Lee todos los pedidos propios y filtra pending/preparing/ready. **Real.** | B `GET /users/me/orders/active`. | Cubierto; main debe incluir `accepted`. Sin ello, el pedido desaparecería al ser aceptado. |
| Historial propio — `profile_orders_screen.dart:138–153,391–401` | Filtra completed/cancelled desde el stream de pedidos propios, ordenados por creación descendente. **Real.** | **No hay ruta canónica de historial propio en D/B.** Legacy: `GET /api/legacy/v1/student/orders`. | **Omisión nueva prioritaria.** Añadir historial privado paginado con Order DTO. El historial del negocio es exclusivo de Cocina y no es un reemplazo. |
| Volver a pedir — `profile_orders_screen.dart:464–480,700–733` | Para completados, consulta cada producto actual, conserva los disponibles y escribe las líneas en batch; reutiliza nombre/precio históricos. **Real.** | Historial propuesto + B `GET /products/{id}` + D POST carrito. | No exige una ruta `/reorder` nueva. Sí exige historial, leer catálogo y dejar de reutilizar precio histórico como precio de compra. Acordar manejo visible de productos no disponibles/resultado parcial. |
| Favoritos desde Pedidos — `profile_orders_screen.dart:35–40,175–200,764–808` | Lista por `addedAt` descendente. Añadir al carrito revalida disponibilidad y precio actual, copia notas, fija cantidad uno. **Real.** | D GET favoritos, B GET producto, D POST carrito. | Cubierto con las nuevas rutas, más traducción `createdAt`/`addedAt` y notas. Main reemplaza la línea; P suma cantidades. |
| Calificar negocio — `profile_orders_screen.dart:483–535`; `rate_order_screen.dart:29–54` | Desde completados, lee nombre del negocio y añade documento `reviews` con rating/comment/orderId y nombre de usuario. **Real.** | B/D `POST /orders/{id}/rating`; D redefine `stars` 0–5. | Flujo de negocio, no reseña de producto. Ya revisado en R. Adaptar cero explícito y `isRated`; no copiar identidad del alumno en el body. Main no evita una segunda reseña. |
| Mostrar QR/entrega — `profile_orders_screen.dart:347–357`; `show_qr_screen.dart:19–20,46–85,174–175` | Escucha orden; abre solo en ready; QR con matrícula recibida como `qrData`; cierra al completar/cancelar. **Real, pero incompatible con V3.** | B `GET /orders/{id}` devuelve `pickupCode` al dueño; evento `order.updated` y GET. | No falta ruta: sustituir matrícula por código de pedido. Mantener rechazo de datos ajenos y salida al estado terminal. |
| Cerrar sesión — `user_dashboard_screen.dart:241–288` | Diálogo y `FirebaseAuth.signOut()`. **Real.** | B `POST /auth/logout`. | Cubierto; revocar la sesión REST y limpiar estado del repositorio. |
| Perfil editable, ajustes, chat, lectura pública de reseñas | No se encontraron pantallas/manejadores de esas acciones en el recorrido de main. **Ausentes en main.** | Hay capacidades nuevas o actuales en V3; el chat/reseñas públicas se amplían en V3.2. | No contarlas como funciones heredadas implementadas ni inventar rutas para conservar una pantalla que no existe. |

## 4. Omisiones nuevas respecto de la revisión anterior

### A01. Historial privado del alumno: contrato y ruta canónica ausentes

**Prioridad alta.** El historial es una pestaña real y alimenta dos acciones existentes. D:364,479 solo define pedidos activos del alumno; D:366,471 define historial de Cocina. B:snackup/v3_operations.py:612–618,632–641 confirma la misma separación. B:snackup/operations.py:633–636 conserva el listado completo, pero únicamente en el adaptador legacy.

El mecanismo `updatedSince` de activos incluye transiciones terminales para reconciliar una pantalla, no declara un historial de compras. Usar una fecha de origen arbitraria para convertirlo en un historial sería un acoplamiento a una implementación, sin contrato de orden, filtros ni finalidad adecuados. Tampoco basta un GET por ID: una instalación nueva no conoce los IDs antiguos.

**Propuesta no implementada:** `GET /users/me/orders/history?page=1&limit=20`, ALUMNO propietario, estados completed/cancelled, respuesta paginada de `Order`, con orden estable por `createdAt DESC, id`. Esto conserva el criterio visible de main. Un filtro opcional `status=completed|cancelled` puede añadirse si se documenta; no es necesario para recuperar la capacidad básica. El detalle sigue en `/orders/{id}`. No exponer un parámetro de usuario que permita seleccionar otro alumno.

Esta ruta debe incluir `isRated` para la acción de calificar, las líneas históricas para volver a pedir y el negocio asociado. No necesita exponer datos de otros alumnos ni ampliar permisos de Cocina.

### A02. Consulta global de destacados no cerrada

**Prioridad media.** M:lib/features/home/user_home_screen.dart:164–170 consulta cinco productos destacados disponibles en todos los locales. D:1125 define máximo tres activos por negocio, pero no una consulta para llenar ese carrusel. B:snackup/v3_operations.py:507–530 permite listar productos por negocio con disponibilidad, categoría y `q`; no posee un filtro `isFeatured` ni listado global. D:1048 añade una búsqueda por nombre, sin declarar el uso para destacados.

No es necesario inventar una entidad Promotion ni descuentos. Se trata de una selección de Product. Cinco tarjetas en Inicio y tres destacados por negocio pueden coexistir; no son límites contradictorios.

**Propuesta no implementada:** añadir `GET /products?isFeatured=true&isAvailable=true&page=1&limit=5`, con negocios activos y el alcance por rol ya definido. Fijar orden estable y documentar si se muestran productos de locales cerrados: la consulta real de main no filtra el estado del negocio, aunque la lista de tiendas sí muestre solo abiertos. Alternativamente puede acordarse la composición de `GET /businesses` y todos los menús/páginas, pero no basta consultar la primera página de cada local y prometer que aparecen todos los destacados.

No se propone usar `q` vacío con semántica especial no escrita ni asumir que límite tres resuelve por sí solo la lectura global.

### A03. GET de producto existe en código pero falta en el catálogo documental

**Prioridad media, documental.** La tabla D:353–378 enumera menú y mutaciones de producto, pero omite `GET /products/{id}`. B:snackup/v3_operations.py:533–538 ya lo implementa con autorización del negocio. La app lo necesita conceptualmente al releer los productos de un pedido anterior y de un favorito: M:lib/features/user/profile_orders_screen.dart:712,779–782.

**Acción propuesta:** incorporar la ruta existente y su Product DTO al documento V3.2; conservarla al regenerar OpenAPI. No crear un servicio duplicado ni otra lectura con permisos diferentes.

### A04. Diferencias entre ramas que cambian decisiones del contrato

Estas no son rutas faltantes; son correcciones a la referencia funcional que se usa para decidir V3.2.

| Tema | Main M, comportamiento comprobado | Paneles P, mejora separada |
|---|---|---|
| Añadir repetido al carrito | `set` con cantidad absoluta: `product_detail_screen.dart:99–110`. | Suma cantidad previa en `student_order_repository.dart:31–32,90–92`. |
| Reordenar/favorito | Reemplazan cada línea; favorito fija uno: `profile_orders_screen.dart:717–725,797–808`. | Reutilizan `StudentOrderRepository.addProducts`, que suma: `profile_orders_screen.dart:817–833,858–862`. |
| Negocio único | Puede mezclar al añadir; checkout lo rechaza: `cart_screen.dart:98–103`. | Se rechaza al añadir: `student_order_repository.dart:68–76`. |
| Límites de carrito | No hay un límite 8/99 en los manejadores de main inspeccionados; incremento solo comprueba mínimo al decrementar. | `order_checkout.dart:3–4,28–32` define 8 líneas y 99 unidades. |
| Horario | Hora del mismo día del dispositivo, sin validación de futuro en `_placeOrder`: `cart_screen.dart:125–132`. | Futuro y máximo 24h: `order_checkout.dart:64–72`. |
| Precios de reordenar | Reutiliza `item['price']` histórico: `profile_orders_screen.dart:721`. | Lee precio del catálogo: `student_order_repository.dart:58–65,98`. |
| Checkout | Batch de creación y borrado a partir de los documentos recibidos por la pantalla: `cart_screen.dart:114–156`. | Relectura y comparación transaccional del quote: `student_order_repository.dart:169–203,232–234`. |
| QR | Matrícula pasada por `qrData`: `profile_orders_screen.dart:356`; `show_qr_screen.dart:175`. | Código del pedido y función de QR vinculada a él: `show_qr_screen.dart:75–79,112`. Sigue necesitando adaptador al formato REST V3. |
| Tarjeta de promoción | Flecha decorativa sin acción: `user_home_screen.dart:214–350`. | `onTap` abre detalle: `user_home_screen.dart:208–214,229–233`. |
| Reseña | Nota general/comentario; documento nuevo en cada envío: `rate_order_screen.dart:46–54`. | Añade comida/servicio, segmentación y validación de pedido: `review_submission.dart:8–13,23–30,62–78,92–111`; evita repetición en UI. |

Adoptar mejoras de P en la rama de usuarios puede ser conveniente, pero debe describirse como incorporación deliberada, no como conservación de algo que main ya tuviera.

## 5. Diferencias de DTO y comportamiento que no justifican rutas nuevas

| Dato o comportamiento de main | Contrato/servidor V3 | Adaptación necesaria |
|---|---|---|
| ID implícito de `DocumentSnapshot.id` | JSON explícito `id` | Modelo/repositorio que lea el identificador de la respuesta. |
| `totalPrice` | `total` y `subtotal` | Cambiar parser; no devolver cero silenciosamente por buscar la clave anterior. M:profile_orders_screen.dart:211,394; B:v3_operations.py:250–251,350. |
| `userDisplayName`, `userNumeroDeControl` | `customerName`, `customerNumeroDeControl` restringido al dueño | Traducir modelo; dejar que el servidor derive identidad. M:cart_screen.dart:138–139; B:v3_operations.py:248,272,365. |
| `Timestamp` de Firestore | ISO 8601 UTC | Parseo explícito a DateTime y presentación local; no mantener casts a Timestamp. M:profile_orders_screen.dart:213,396. |
| Activos pending/preparing/ready | Incluye accepted | Mostrar accepted en la columna/etapa de preparación; no perderlo del listado. M:profile_orders_screen.dart:115; B:operations.py:35. |
| QR como matrícula | Código alfanumérico secreto por pedido, visible al dueño | Sustituir datos y eliminar credencial de matrícula. No cambia el endpoint de detalle. |
| Cero/no existe stock tratado como agotado | `stock:null` significa no controlado | Cambiar menú, detalle y búsqueda. M:menu_screen.dart:171–172; product_detail_screen.dart:154–155; search_screen.dart:400–401; D:286. |
| Precio histórico al reordenar | Precio actual validado por servidor | Usar productId/quantity/notes como intención; refrescar precio y confirmar expectedTotal. |
| `addedAt` en favoritos | Nuevo modelo tiene `createdAt` | Definir DTO/orden de favoritos, no duplicar campos de persistencia solo por el nombre viejo. S:469; M:profile_orders_screen.dart:39. |
| `Vale` | `ValeComida` | Traducción explícita del valor y política de vale; no confundirlo con cobro confirmado. |
| `rating` 1–5, cero significa sin seleccionar | `stars` 0–5, cero válido | Separar selección ausente de cero, adaptar body y evitar duplicados con `isRated`. |
| Streams Firestore | REST + Socket.IO autorizado | Repositorios para cargar/reconciliar; en reconexión GET, sin polling periódico automático según D. |

La calificación pública por negocio, el chat y las reglas del vale/cierre ya están identificados en R. No se han descubierto pantallas actuales de alumno que dependan de un procesador de pagos, cupones, componentes de combos o edición de reseñas. No deben agregarse esas capacidades por asociación con los nombres “Promociones”, “Vale” o “Perfil”.

## 6. Funciones visuales o ausentes: evitar ampliar el alcance por inferencia

- **Perfil:** `ProfileOrdersScreen` es una pantalla de pedidos/favoritos; no edita nombre, foto, correo o contraseña. La bienvenida solo lee nombre de Firebase Auth. `PATCH /users/me` existente puede conservarse, pero no procede decir que su ausencia en la tabla V3.2 rompe una pantalla de edición de perfil de main que no existe.
- **Ajustes:** el dashboard no tiene una pestaña o menú de ajustes. No se encontraron preferencias de idioma/tema/notificaciones del alumno. No confundir la mención a Ajustes de Cocina en D:474 con una pantalla del alumno.
- **Chat:** no hay pantalla, colección o envío de mensajes del alumno en main. Es una ampliación V3.2, no una restauración de código ya conectado.
- **Reseñas públicas:** main escribe una reseña del negocio; no tiene un listado público de reseñas en las pantallas inspeccionadas. D incorpora esa lectura como ampliación.
- **Cancelar pedido:** main no ejecuta una escritura de cancelación de orden desde el alumno. Los botones “Cancelar” de diálogos cancelan la interacción local. La API sí define cancelación propia en pending; incorporarla en UI es trabajo real, pero no una ruta adicional omitida.
- **Promoción:** el carrusel usa `Product.isFeatured` y precio ordinario, sin modelo de descuento. La flecha de main no navega. No hay razón para crear una tabla Promotion o procesamiento de descuentos para migrar esa vista.
- **Notificaciones:** `main.dart:36–44` solicita permiso de Firebase Messaging, pero no prueba un flujo de registro de tokens, recepción, navegación ni tratamiento en segundo plano. El permiso por sí solo no acredita push funcional.

## 7. Identidad y administración: capacidades reales que no cubre la tabla nueva

### 7.1 Matriz de identidad y acceso

Esta sección incorpora la revisión independiente de los flujos de identidad/administración y el cotejo de sus repositorios con los servicios existentes. **L** significa `/api/legacy/v1`; **C** significa `/api/v1`.

| Función | Implementación y estado | Cobertura REST / diferencia |
|---|---|---|
| Login alumno y Cocina en main | Firebase Auth `signInWithEmailAndPassword`, real. M:lib/features/auth/login_screen.dart:34–36; business_login_screen.dart:32. | C/L `POST /auth/login` existen. Main recorta la contraseña; el servidor conserva sus espacios. Adaptar sin alterar silenciosamente la contraseña ingresada. |
| Registro de alumno en main | Crea Firebase Auth y `users/{uid}`; escribe nombre/matrícula/rol user y actualiza displayName. M:register_screen.dart:38–60. **Real.** | C `POST /auth/register` responde 202 sin sesión hasta verificación; D promete 201 con tokens. La leyenda visual sobre matrícula no demuestra verificación institucional en main. Conservar el control de backend y adaptar la UI. |
| Recuperar contraseña en main | Botón con TODO vacío. M:login_screen.dart:209–211. **Placeholder.** | No atribuir a main un envío de recuperación existente. C forgot/reset ya existen y permiten implementar el flujo. |
| Recuperar/restablecer en paneles | Firebase repository y portal REST sí lo implementan. P:app/lib/features/auth/auth_repository.dart:158–168; api/rest_session.dart:245–252; features/portal/reset_access_screen.dart:38–41. **Real.** | Conservar `POST /auth/forgot-password` y `/auth/reset-password`, y dirigir el enlace de correo al frontend que contiene la pantalla de reset. Separar contenedores requiere revisar la URL, no solo mover archivos. |
| Solicitar acceso a paneles | `RequestAccessScreen` envía nombre, correo, password, requestedRole y context a `AccessRepository.register`. P:features/portal/request_access_screen.dart:30–43; api/access_repository.dart:45–69. **Real.** | L `POST /auth/register` recibe solicitud pendiente; C register solo crea ALUMNO y requiere matrícula. Misma ruta relativa, distinto propósito y body: no sustituir el prefijo sin diseñar la migración. La preferencia requestedRole no concede permisos. |
| Verificar correo/reenvío | C/L disponen de verificación y reenvío; los recorridos Firebase main/panel no llaman `sendEmailVerification` y no hay UI de reenvío en el recorrido auditado. | Añadir al contrato D los endpoints existentes `POST /auth/verify-email`, `POST /auth/resend-verification` y la verificación HTML enlazada. No retirar esos servicios por no aparecer en la tabla abreviada. |
| Opciones de acceso | Portal carga `GET /auth/options`; P:api/access_repository.dart:43–44. **Real.** | C/L existen; documentar passwordLogin/selfRegistration/googleEnabled y respetar las capacidades devueltas. |
| Google | Main no lo implementa; la mención de Google en role_selection_screen.dart:17 es un comentario. Portal tiene botón condicionado por googleEnabled. | C/L `/auth/google/start` está deshabilitado y devuelve GOOGLE_DISABLED; no afirmar soporte OAuth operativo ni contabilizarlo como función perdida. |
| Perfil y capacidades del portal | `PortalAccount` espera roles lower case, businessId y `isMaster`, que controla gestión de cuentas. P:api/rest_session.dart:30–65. | C usa roles uppercase y no devuelve isMaster. Hace falta un adaptador/capacidades explícitas antes de cambiar de prefijo; no deducir poder de maestro de cualquier rol ADMIN. |
| Completar perfil incompleto | Main contiene RoleSelectionScreen, pero no hay referencia que lo conecte al AuthWrapper. En P sí hay flujo de completar perfil de alumno. P:features/auth/auth_gate.dart:181–189; auth_repository.dart:215–258. | D no define una operación general de completar perfiles importados. Resolver migración de cuentas incompletas; no crear un endpoint que acepte rol libre. |
| Consentimiento de privacidad | P exige acceptedTerms y guarda privacyAcceptedAt/privacyVersion='2'. P:features/auth/auth_repository.dart:79–85. Main no contiene esa persistencia. | C register no acepta esos campos. Si se conserva esa UX de P al migrar, debe acordarse la conservación de evidencia; no inventar aceptación para cuentas antiguas. |
| Edición de perfil/contraseña autenticada/cierre de cuenta | No hay pantallas conectadas en main ni en los recorridos de panel auditados. | C `PATCH /users/me` solo vincula avatar con expectedVersion: B:snackup/v3_identity.py:67–69,319–333. No es un editor genérico. Edición de nombre/correo, cambio de password autenticado o cierre de cuenta serían capacidades nuevas. |
| Logout | Main y paneles tienen acciones reales; el portal usa sesión REST. | C/L logout cubiertos. Listar sesiones y logout-all no tienen UI actual y D los deja pendientes. |

La matrícula, el UID, el rol y los datos de sesión requieren una migración explícita. Copiar pantallas de una rama no convierte a PostgreSQL en fuente del perfil ni permite regenerar IDs de Firestore sin conservar relaciones. La política de padrón y verificación actual pertenece al servidor.

### 7.2 Diez operaciones administrativas existentes sin equivalente canónico

Todas las siguientes son usadas por repositorios/pantallas reales del portal y están implementadas en el backend legacy. Las notas “provisional” de algunos comentarios de frontend no convierten esos servicios en placeholders: hay invocaciones, parsers y persistencia.

| # | Operación actualmente bajo L | Consumidor y datos necesarios | Implementación B / situación C |
|---|---|---|---|
| 1 | `GET /institution` | OperationsRepository.configuration y referencias admin. Universidad, cafetería y dominios administrativos. P:app/lib/operations/operations_repository.dart:9–10; features/admin/data/rest_admin_repository.dart:178–181. | B:snackup/admin.py:81–88. No existe equivalente C. |
| 2 | `GET /admin/academic-catalog` | Carreras/grupos paginados con ID, name y careerId para filtros y referencias históricas. P:rest_admin_repository.dart:182–204. | B:admin.py:212–225. No existe equivalente C. |
| 3 | `GET /admin/reviews` | Dashboard de opiniones, segmentación académica y filtros. P:rest_admin_repository.dart:11,115–161. | B:admin.py:279–282. Ratings públicas de negocio no sustituyen este DTO privado administrativo. |
| 4 | `GET /admin/followups` | Estados/responsables de seguimiento que el dashboard cruza con opiniones. P:rest_admin_repository.dart:12,120–161. | B:admin.py:285–288. Sin equivalente C. |
| 5 | `GET /admin/reviews/{id}/followup` | Abrir caso y obtener versión actual. P:rest_admin_repository.dart:213–234. | B:admin.py:298–303. Sin equivalente C. |
| 6 | `PUT /admin/reviews/{id}/followup` | Guardar status, assignee, note, expectedVersion; validar incremento confirmado. P:rest_admin_repository.dart:269–302. | B:admin.py:306–328. Sin equivalente C. |
| 7 | `GET /admin/reviews/{id}/followup/history` | Historial del seguimiento paginado; notas y versiones. P:rest_admin_repository.dart:238–265. | B:admin.py:331–336. Sin equivalente C. |
| 8 | `GET /admin/access-requests` | Cuenta maestra lista solicitudes pendientes. P:features/operations/access_requests_screen.dart:34–37. | B:admin.py:162–166. Sin equivalente C. |
| 9 | `POST /admin/access-requests/{id}/decision` | Aprobar/rechazar con identidad confirmada, rol/local y expectedVersion. P:access_requests_screen.dart:139–154. | B:admin.py:169–209. Sin equivalente C; no reemplazar por cambio libre de rol. |
| 10 | `POST /admin/users` | Cuenta maestra crea cuenta administrativa separada del alta de local. P:operations/operations_repository.dart:247–257. | Existe en legacy. C `POST /admin/businesses` crea negocio+COCINA; no sustituye la creación administrativa independiente. |

**Omisión adicional de alcance:** D limita su inventario administrativo a locales y cuentas Cocina, pero el producto ya tiene análisis académico, seguimiento de opiniones y autorización de solicitudes. No basta preservar las tablas si sus pantallas pierden las operaciones para consultarlas y actuar.

**Propuesta no implementada:** mantener L para el portal durante la transición y documentar esas diez operaciones como capacidades que deben preservarse. Para moverlas a C, usar rutas equivalentes explícitas y el mismo servicio autorizado, con DTO/capacidades acordados. Conservar maestro, auditoría, verificación y versiones. No se propone exponer datos académicos o notas de seguimiento en las reseñas públicas V3.2.

### 7.3 Rutas con el mismo nombre que no admiten cambiar solo la base URL

| Operación | Diferencia que debe resolver el adaptador |
|---|---|
| `GET /admin/users` | Existe en C, aunque D omite el listado. Cambian roles/DTO y tratamiento de cuentas administrativas. El parser legacy requiere sus campos y capacidades. |
| `PATCH /admin/users/{id}` | C protege roles y pertenencia; no permite la reasignación arbitraria que el flujo autorizado de maestro legacy contempla. No traducir un formulario de maestro a este PATCH sin conservar el alcance real. |
| `GET /admin/businesses` | Misma familia de recurso, pero debe verificarse BusinessRecord/DTO y filtros consumidos por el portal. |
| `POST /admin/businesses` | Legacy crea el local y devuelve BusinessRecord; C crea negocio y cuenta Cocina transaccionalmente, exige datos de cuenta y devuelve `{business,user}`. |
| `PATCH /admin/businesses/{id}` | Adaptar campos, versiones y baja lógica; no tratar compatibilidad de nombres como identidad de contrato. |
| `POST /auth/register` | Solicitud de panel con requestedRole/context en L frente a alumno institucional con matrícula en C. |

Fuentes: P:app/lib/operations/operations_repository.dart:210–257; P:app/lib/api/access_repository.dart:45–69; B:snackup/v3_admin.py y v3_identity.py.

## 8. Cocina y catálogo: recorrido de main y portal REST

Main contiene también pantallas Cocina dentro de la misma app. Su presencia no equivale al portal REST separado de P. Se inspeccionaron ambos recorridos para no perder funciones ni confundir implementaciones.

| Función | Main M | Portal P / ruta actual | Cobertura y diferencia |
|---|---|---|---|
| Resolver local propio | Consulta businesses por ownerId del usuario: home/business_home_screen.dart:46–55. | Perfil de sesión incluye businessId; GET `/businesses/{id}`. P:operations_repository.dart:37–46. | Usar asignación autorizada del servidor, no selección libre de local. |
| Apertura manual | Stream de negocio y update isOpen: business_home_screen.dart:244–248,316–322. **Real.** | PATCH `/businesses/{id}/status` con versión; operaciones_repository:49–55. | Cubierto. Cierres diarios/posposición son ampliaciones V3.2 pendientes, no funciones existentes de main. |
| Aviso de pedido nuevo | Listener pending sin fecha programada; sonido y diálogo por cambio de conteo: business_home_screen.dart:62–89. **Real en primer plano.** | KitchenController + eventos y sonido habilitado por usuario: features/operations/business_portal.dart:64–67,119–125. | Conservar alerta de nuevos; no confundirla con aviso T−10 ni push con navegador cerrado. |
| Programados/Nuevos/Preparando/Listos | Cuatro pestañas reales: features/business/view_orders_screen.dart:71–92. Query scheduled futura o null: order_list_tab.dart:94–118. | GET `/businesses/{id}/orders/active` con scheduledPickupTime; P muestra recogida en business_portal.dart:655–656. | La API puede aportar los datos por activos; no hace falta endpoint por pestaña. El filtrado futuro de main no define una política segura al vencer la hora. |
| Abrir pedido | Stream orders/{id}; order_detail_screen.dart:17–18,212. | GET `/orders/{id}`; operations_repository.dart:114–115. | Cubierto con DTO por rol. |
| Preparación/cancelación | Main escribe status directamente; pending→preparing y cancelar sin motivo. order_detail_screen.dart:20–22,518–593. **Real, contrato anterior.** | POST nominal accept/start/ready/cancel con expectedVersion y motivo; operations_repository.dart:116–167. | Adaptar a la máquina única. No añadir PATCH status libre para reproducir una escritura anterior. |
| Entrega QR/manual | Compara matrícula en cliente y actualiza completed: order_detail_screen.dart:51–75,113–166. **Real, incompatible con V3.** | POST `/orders/{id}/complete` con method/code, verificación en servidor. | Mantener código de pedido y privacidad. No reintroducir matrícula como credencial para conservar una pantalla antigua. |
| Menú y edición de producto | Stream por negocio; editor lee producto y actualiza/crea nombre, descripción, precio, stock, disponibilidad, destacado, categoría y foto. manage_menu_screen.dart:14–18; add_edit_product_screen.dart:50–68,137–177. **Real.** | GET/POST menú, GET/PATCH producto; P:catalog/rest_catalog_repository.dart:118–158. | Cubierto por B; adaptar DTO, categorías y pausa manual. |
| Imagen de producto | ImagePicker y FirebaseStorage putFile/getDownloadURL: add_edit_product_screen.dart:77–119. **Real en código.** | POST `/media` multipart; P:rest_catalog_repository.dart:167–173. | El upload legacy no equivale al V3, que requiere purpose/businessId y devuelve su DTO. Validar el adaptador; no copiar URLs ajenas como medios propios. |
| Borrar producto | Botón vacío con TODO: add_edit_product_screen.dart:669–674. **Placeholder en main.** | P sí llama DELETE `/products/{id}` con expectedVersion: rest_catalog_repository.dart:162–164. | B usa baja lógica. Mantenerlo en P; no afirmar que main ya borraba productos. |
| Mi local/Ajustes | Main ofrece interruptor; no el editor equivalente de P. | P edita name/category/description y usa el mismo interruptor: business_portal.dart:711–791; operations_repository.dart:57–72. | Cubierto por B. Portada/cierre automático/timeout requieren ampliación de UI. |
| Historial Cocina | Main no tiene pestaña terminal equivalente en ViewOrders; estadísticas lee completados. | P GET `/businesses/{id}/orders/history?date=` y resumen paginado: operations_repository.dart:170–197. **Real.** | C/D lo conservan; no confundir este historial con el omitido del alumno. |
| Resumen/estadísticas | Main lee todos los completados y muestra total, cantidad, últimos siete días, top productos y métodos: statistics_screen.dart:21–25,58–96,728–775. **Real.** | P REST consume solo completed/cancelled/totalSold mediante `/stats`: operations_repository.dart:200–208. B SalesSummaryResponse:281–284. | **Brecha adicional de DTO** si se exige conservar las gráficas de main. La existencia de la ruta `/stats` no demuestra cobertura de los desgloses. |

### 8.1 Estadísticas: concretar el contrato de datos, no solo el nombre de ruta

D:374,475 conserva `GET /businesses/{id}/stats?from=&to=`, pero deja su shape heredado por cotejar. B:snackup/v3_operations.py:281–284,644–648 solo devuelve tres cifras. Main necesita también cantidades por producto y por método de pago y una serie temporal. Puede obtenerse de un listado completo de pedidos del periodo o de agregados de servidor; el historial diario actual no sustituye silenciosamente una consulta de todo el periodo/todo el historial.

**Propuesta no implementada:** ampliar el DTO de stats con `dailySales`, `topProducts` y `paymentMethods`, conservando sus cifras actuales, o documentar una lectura paginada de pedidos completados por rango para alimentar esas vistas. Fijar antes de aplicar: fecha de agrupación (main usa createdAt; el negocio puede requerir completedAt), zona horaria y rango de cada gráfica. Main calcula total/top/métodos sobre todos los completados y solo filtra siete días para la serie; no atribuirle un rango uniforme inexistente.

Los valores representan pedidos/importes, no confirmación de dinero cobrado. El cambio no autoriza a convertir Tarjeta/Transferencia/ValeComida en pagos liquidados ni a añadir un procesador de cobros.

### 8.2 Realtime y compatibilidad del portal

P:app/lib/operations/realtime_web.dart:29–50 abre WebSocket crudo en `<API_BASE>/realtime`, con mensajes auth/subscribe. P:features/operations/business_portal.dart:70–101 además hace polling cada diez segundos sin conexión y cada sesenta con conexión. D:27,41 exige Socket.IO y excluye polling HTTP periódico automático al perder conexión.

Es una diferencia de cliente y transporte, no una ruta REST faltante. El portal puede seguir operando explícitamente en L mientras se adapta; cambiar solo su `API_BASE_URL` a C no migra WebSocket a Socket.IO ni elimina el polling. También necesita reconocer nuevos eventos de retiro/chat y motivo `not_picked_up`, que hoy bloquea en su validación de cancelación. P:operations_repository.dart:124–131.

## 9. Separación de aplicaciones y contenedores: impacto sobre contratos

El estado inspeccionado inicial montaba el frontend dentro del proceso/contenedor API mediante `SNACKUP_WEB_DIR`; eso no constituía una separación operativa. La separación autorizada en paralelo deberá verificarse por sus archivos y builds finales; esta auditoría no declara realizados sus resultados.

Dependencias que deben conservarse al separar:

- App de alumnos main: Firebase inicializado en `lib/main.dart:17–39`. Separar contenedores no la vuelve cliente REST. No retirar las pantallas Cocina que aún contiene ni cambiar de proveedor por efecto lateral de una tarea de infraestructura.
- Portal REST: mantener su prefijo de compatibilidad hasta migrar DTO/auth/realtime; `BrowserClient.withCredentials=true` y refresh web dependen del origen/rutas de cookies. P:app/lib/api/platform_http_client_web.dart:4; api/rest_session.dart:74–88.
- Enlaces de restablecimiento/verificación: deben abrir la aplicación y ruta que implementan el manejo del token. El handler reset existe en paneles, no en main.
- Distribución prevista de un mismo origen: alumnos `/`, paneles `/paneles/`, API `/api/*` y Socket.IO `/socket.io/*`. Esto requiere base href, proxy y workers que no intercepten respuestas privadas de API ni rutas de otra aplicación. Es configuración de despliegue, no una nueva regla de negocio.
- La solicitud de permiso FCM de main no implementa por sí sola registro en `/users/me/devices`, notificaciones en segundo plano o navegación al pedido. El worker de instalación/desconexión tampoco debe describirse como implementación de esas capacidades.

## 10. Enlaces permanentes a fuentes frontend

Se usan commits fijados para que este informe siga siendo trazable después de retirar frontend de la rama del backend.

### Main: app actual auditada

- [Entrada main.dart](https://github.com/Gabino-RG/SnackUP-core/blob/b7abff6593e84dda69ad2909abbf699dd17ff890/lib/main.dart).
- [AuthGate](https://github.com/Gabino-RG/SnackUP-core/blob/b7abff6593e84dda69ad2909abbf699dd17ff890/lib/features/auth/auth_gate.dart), [login](https://github.com/Gabino-RG/SnackUP-core/blob/b7abff6593e84dda69ad2909abbf699dd17ff890/lib/features/auth/login_screen.dart), [registro](https://github.com/Gabino-RG/SnackUP-core/blob/b7abff6593e84dda69ad2909abbf699dd17ff890/lib/features/auth/register_screen.dart) y [RoleSelectionScreen](https://github.com/Gabino-RG/SnackUP-core/blob/b7abff6593e84dda69ad2909abbf699dd17ff890/lib/features/auth/role_selection_screen.dart).
- [Dashboard alumno](https://github.com/Gabino-RG/SnackUP-core/blob/b7abff6593e84dda69ad2909abbf699dd17ff890/lib/features/home/user_dashboard_screen.dart) e [Inicio/carrusel](https://github.com/Gabino-RG/SnackUP-core/blob/b7abff6593e84dda69ad2909abbf699dd17ff890/lib/features/home/user_home_screen.dart).
- [Menú](https://github.com/Gabino-RG/SnackUP-core/blob/b7abff6593e84dda69ad2909abbf699dd17ff890/lib/features/user/menu_screen.dart), [búsqueda](https://github.com/Gabino-RG/SnackUP-core/blob/b7abff6593e84dda69ad2909abbf699dd17ff890/lib/features/user/search_screen.dart) y [detalle de producto](https://github.com/Gabino-RG/SnackUP-core/blob/b7abff6593e84dda69ad2909abbf699dd17ff890/lib/features/user/product_detail_screen.dart).
- [Carrito](https://github.com/Gabino-RG/SnackUP-core/blob/b7abff6593e84dda69ad2909abbf699dd17ff890/lib/features/user/cart_screen.dart), [pedidos/historial/favoritos](https://github.com/Gabino-RG/SnackUP-core/blob/b7abff6593e84dda69ad2909abbf699dd17ff890/lib/features/user/profile_orders_screen.dart), [calificar](https://github.com/Gabino-RG/SnackUP-core/blob/b7abff6593e84dda69ad2909abbf699dd17ff890/lib/features/user/rate_order_screen.dart) y [QR](https://github.com/Gabino-RG/SnackUP-core/blob/b7abff6593e84dda69ad2909abbf699dd17ff890/lib/features/user/show_qr_screen.dart).
- [Inicio Cocina](https://github.com/Gabino-RG/SnackUP-core/blob/b7abff6593e84dda69ad2909abbf699dd17ff890/lib/features/home/business_home_screen.dart), [pestañas de pedidos](https://github.com/Gabino-RG/SnackUP-core/blob/b7abff6593e84dda69ad2909abbf699dd17ff890/lib/features/business/view_orders_screen.dart), [queries de pedidos](https://github.com/Gabino-RG/SnackUP-core/blob/b7abff6593e84dda69ad2909abbf699dd17ff890/lib/features/business/order_list_tab.dart) y [detalle/entrega](https://github.com/Gabino-RG/SnackUP-core/blob/b7abff6593e84dda69ad2909abbf699dd17ff890/lib/features/business/order_detail_screen.dart).
- [Gestión del menú](https://github.com/Gabino-RG/SnackUP-core/blob/b7abff6593e84dda69ad2909abbf699dd17ff890/lib/features/business/manage_menu_screen.dart), [editor/subida de imágenes](https://github.com/Gabino-RG/SnackUP-core/blob/b7abff6593e84dda69ad2909abbf699dd17ff890/lib/features/business/add_edit_product_screen.dart) y [estadísticas completas](https://github.com/Gabino-RG/SnackUP-core/blob/b7abff6593e84dda69ad2909abbf699dd17ff890/lib/features/business/statistics_screen.dart).

### Paneles: repositorios e implementaciones separadas

- [Repositorio de operaciones](https://github.com/Gabino-RG/SnackUP-core/blob/17ad7823321fe79b673e10f7a201af02bec79628/app/lib/operations/operations_repository.dart), [modelos](https://github.com/Gabino-RG/SnackUP-core/blob/17ad7823321fe79b673e10f7a201af02bec79628/app/lib/operations/models.dart) y [WebSocket](https://github.com/Gabino-RG/SnackUP-core/blob/17ad7823321fe79b673e10f7a201af02bec79628/app/lib/operations/realtime_web.dart).
- [Portal Cocina y polling](https://github.com/Gabino-RG/SnackUP-core/blob/17ad7823321fe79b673e10f7a201af02bec79628/app/lib/features/operations/business_portal.dart), [catálogo REST](https://github.com/Gabino-RG/SnackUP-core/blob/17ad7823321fe79b673e10f7a201af02bec79628/app/lib/catalog/rest_catalog_repository.dart) y [solicitudes de acceso](https://github.com/Gabino-RG/SnackUP-core/blob/17ad7823321fe79b673e10f7a201af02bec79628/app/lib/features/operations/access_requests_screen.dart).
- [Repositorio administrativo](https://github.com/Gabino-RG/SnackUP-core/blob/17ad7823321fe79b673e10f7a201af02bec79628/app/lib/features/admin/data/rest_admin_repository.dart), [sesión REST](https://github.com/Gabino-RG/SnackUP-core/blob/17ad7823321fe79b673e10f7a201af02bec79628/app/lib/api/rest_session.dart) y [solicitar acceso](https://github.com/Gabino-RG/SnackUP-core/blob/17ad7823321fe79b673e10f7a201af02bec79628/app/lib/api/access_repository.dart).
- [AuthRepository/consentimiento](https://github.com/Gabino-RG/SnackUP-core/blob/17ad7823321fe79b673e10f7a201af02bec79628/app/lib/features/auth/auth_repository.dart), [AuthGate](https://github.com/Gabino-RG/SnackUP-core/blob/17ad7823321fe79b673e10f7a201af02bec79628/app/lib/features/auth/auth_gate.dart), [pantalla de solicitud](https://github.com/Gabino-RG/SnackUP-core/blob/17ad7823321fe79b673e10f7a201af02bec79628/app/lib/features/portal/request_access_screen.dart) y [reset de acceso](https://github.com/Gabino-RG/SnackUP-core/blob/17ad7823321fe79b673e10f7a201af02bec79628/app/lib/features/portal/reset_access_screen.dart).
- [Repositorio de pedidos alumno de P](https://github.com/Gabino-RG/SnackUP-core/blob/17ad7823321fe79b673e10f7a201af02bec79628/app/lib/features/user/student_order_repository.dart), [validación de checkout](https://github.com/Gabino-RG/SnackUP-core/blob/17ad7823321fe79b673e10f7a201af02bec79628/app/lib/features/user/order_checkout.dart), [reseñas](https://github.com/Gabino-RG/SnackUP-core/blob/17ad7823321fe79b673e10f7a201af02bec79628/app/lib/features/user/review_submission.dart), [historial/favoritos](https://github.com/Gabino-RG/SnackUP-core/blob/17ad7823321fe79b673e10f7a201af02bec79628/app/lib/features/user/profile_orders_screen.dart), [QR](https://github.com/Gabino-RG/SnackUP-core/blob/17ad7823321fe79b673e10f7a201af02bec79628/app/lib/features/user/show_qr_screen.dart) e [Inicio](https://github.com/Gabino-RG/SnackUP-core/blob/17ad7823321fe79b673e10f7a201af02bec79628/app/lib/features/home/user_home_screen.dart).

## 11. Comprobaciones de aceptación para la futura migración del alumno

Estas son verificaciones propuestas, no resultados ejecutados en esta auditoría:

1. Un alumno recién autenticado puede recuperar su historial en un dispositivo nuevo sin conocer IDs previos; no puede consultar historial ajeno.
2. Un pedido cambia a accepted y sigue visible; al completar/cancelar sale de activos y aparece en historial; los deltas no duplican tarjetas.
3. Desde historial, reordenar conserva productos/cantidades/notas previstos, consulta precio actual, informa productos retirados y respeta la política de carrito aprobada.
4. El QR muestra el código de ese pedido, nunca matrícula; un evento terminal cierra o actualiza la pantalla.
5. Favoritos conserva notas y estado; añadir al carrito usa precio/disponibilidad actuales y la semántica absoluta/incremental acordada.
6. Inicio recupera destacados aunque estén fuera de la primera página de un menú; respeta el límite por negocio aprobado y el criterio de negocios activos/abiertos documentado.
7. `stock:null` permite comprar un producto disponible; cero no; cambiar cantidad no evade validación de stock al confirmar.
8. Un refresh, una reconexión y un reintento de compra no crean pedidos ni reservas adicionales. Los errores de versión/precio requieren actualización visible.
9. Cero estrellas tiene selección explícita y cuenta una sola vez; una reseña ya enviada deshabilita o resuelve correctamente una nueva tentativa.
10. La configuración del build de alumnos selecciona su repositorio; el flujo REST no conserva escrituras directas a Firestore por debajo de la misma pantalla.

## 12. Decisiones y trabajo pendiente

La instrucción de comenzar V3.2 solo si no falta nada no se cumple: A01 es una omisión real, A02/A03 completan la cobertura de lectura, y las secciones 7/8 identifican capacidades administrativas y datos estadísticos que no se deben perder. Por ello este documento propone contratos concretos, pero no los implementa. La separación de ramas y contenedores es trabajo independiente y puede continuar sin resolver mediante suposiciones los cambios de negocio.

Además de incorporar historial y documentar las consultas de catálogo, siguen vigentes las decisiones de R sobre fecha/liberación de vale, cierres, programación, timeout, categorías, destacados, carrito y chats. La diferencia de main frente a P obliga a actualizar cómo se justifican las propuestas: no convertir mejoras de una rama en requisitos históricos de la otra.

La auditoría de alumno no encontró necesidad de una ruta independiente para cada botón. Reordenar, añadir un favorito, abrir el menú o construir el QR pueden componerse con recursos ya definidos. Las rutas nuevas propuestas responden a lecturas que faltan o a una consulta global sin contrato, no a duplicar servicios por pantalla.
