# Catálogo y funciones del cliente Firebase en el frontend REST

Referencia confirmada por el usuario: `codex/cliente-firebase`, commit
`0f93fa6db49a304e70df95bfa5a4899252d114e8`.
La rama conserva el código del cliente; el catálogo que consultaba está en
Cloud Firestore del proyecto `snackup-8fe96`. Se leyeron solamente las
colecciones públicas `businesses` y `products`, sin escribir en Firebase.

## Datos recuperados

| Cafetería/negocio | Productos guardados |
|---|---:|
| Negocio 1 Prueba | 6 |
| Negocio prueba 2 | 0 |
| Negocio prueba 3 | 0 |

| Platillo | Precio MXN | Existencias al importar |
|---|---:|---:|
| Tacos al Pastor | 50.00 | 30 |
| Agua de Horchata | 25.00 | 20 |
| tacos | 20.00 | 20 |
| tortas | 20.00 | 20 |
| Polinesios | 53.00 | 0 |
| sopa | 12.00 | 0 |

Se conservaron los IDs, nombres, descripciones, categorías, precios, stock,
destacados y enlaces de imágenes de los negocios. Los seis platillos no tenían
foto guardada; la app muestra su marcador visual. Los dos negocios sin menú
siguen sin productos: no se inventaron platillos. Los productos con stock cero
permanecen en SQL y se ocultan del menú disponible.

## Funciones de alumnos

| Función del cliente de referencia | Integración actual |
|---|---|
| Inicio, destacados y cafeterías | Catálogo REST de PostgreSQL |
| Menú y búsqueda | Paginación, categorías, disponibilidad e inventario |
| Detalle y personalización | Notas, cantidad y disponibilidad actual |
| Favoritos | Notas y guardado por cuenta en el servidor |
| Carrito y pedido | Confirmación e idempotencia; precios calculados por el backend |
| Historial | Pedidos entregados/cancelados, detalle y volver a pedir |
| Seguimiento | Estados reales y avisos Socket.IO |
| Código de recogida | Solo se muestra cuando el pedido está listo y desaparece al entregar |
| Calificar cafetería | Puntuación y comentario tras entregar el pedido |
| Calificar platillos | Selector de productos comprados y reseña independiente de la cafetería |
| Leer reseñas | Sección paginada en el detalle de cada platillo |
| Perfil | Datos institucionales, acceso al historial y confirmación de cierre de sesión |
| Cuenta | Correo UTSJR, padrón existente, verificación, recuperación y cierre de sesión |
| Diseño | Se conserva la paleta azul marino, lima y turquesa |

El contrato actual admite puntuaciones de 0 a 5. Una reseña por platillo/pedido
y una calificación de cafetería por pedido: el backend rechaza duplicados y no
ofrece edición. Las reseñas públicas de productos no muestran nombre, matrícula
ni el ID del pedido; el backend conserva la autoría internamente. No se envía
un campo de anonimato que el contrato no admite.

Esta migración no copia usuarios, contraseñas, permisos de Cocina, pedidos ni
reseñas históricas de Firebase. Las cuentas y el padrón locales se conservan.
El código original del backend y las pantallas de Cocina permanecen intactos.

## Repetir la carga del catálogo

La copia revisada está en `data/catalogo-cliente-firebase.json`. Desde la raíz
del proyecto, con la configuración local del backend preparada:

```powershell
.\backend\.venv\Scripts\python.exe tools\importar_catalogo_firebase.py --source data\catalogo-cliente-firebase.json --backend backend
```

El comando anterior solo valida y muestra el plan. Para insertar los registros
faltantes en esta instalación de desarrollo:

```powershell
.\backend\.venv\Scripts\python.exe tools\importar_catalogo_firebase.py --source data\catalogo-cliente-firebase.json --backend backend --apply
```

La carga usa una transacción y conserva los registros existentes, incluso sus
existencias actuales. Una repetición no repone stock ni duplica cafeterías.
No necesita credenciales de Firebase y no modifica sus reglas.

## Verificación

Se comprobó la importación en PostgreSQL y una segunda ejecución sin inserciones.
Una sesión ALUMNO consultó las tres cafeterías, los seis productos, los cuatro
disponibles, favoritos, carrito y destacados por la API existente.

Las 58 pruebas Flutter cubren además stock cero/sin límite, puntuación cero,
pedido ajeno o pendiente, cambio de cuenta, reseña duplicada y paginación.
Una prueba aislada con el backend original y SQLite temporal completó pedido,
entrega y ambas reseñas; comprobó el rechazo del duplicado y la ausencia de
identidad en la reseña pública. No generó pedidos en la base personal.

## Vista de pedidos

La vista de pedidos adopta la referencia visual proporcionada por el usuario:
cabecera «Mis pedidos / CAMPUS DINING», pestañas Activos, Historial y Favoritos,
tarjetas con total verde, resumen de productos y progreso de tres pasos.
Los estados `pending` y `accepted` se agrupan visualmente en Recibido;
`preparing` corresponde a Preparando y `ready` a ¡Listo!. El estado exacto
sigue disponible al tocar la tarjeta. Sus opciones permiten abrir el detalle,
mostrar el código solo cuando corresponde y cancelar mientras sigue pendiente.
En escritorio el logo permite volver a Inicio y en móvil se conserva la barra
de navegación. Los importes, cantidades y pedidos provienen de la API.
