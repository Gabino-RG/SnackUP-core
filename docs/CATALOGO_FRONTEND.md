# SnackUP · Catálogo editable y conexión a API local

Actualización: 10 de octubre de 2026. Alcance: frontend de negocios.

## Lo que se puede hacer

- Agregar y editar nombre, descripción, categoría, precio en MXN, imagen,
  disponibilidad, destacado y existencias opcionales.
- Cambiar el precio desde la tarjeta del producto.
- Sustituir o quitar imágenes JPEG, PNG y WebP de hasta 5 MB.
- Eliminar un producto con confirmación; el frontend no modifica pedidos históricos.
- Buscar por nombre, descripción o categoría; filtrar disponibilidad; navegar en páginas de 20.
- Validar precios positivos de hasta $10,000 con dos decimales, cantidades
  enteras y longitudes. Los límites son provisionales y conservan los del código anterior.
- Conservar cambios de ejemplo al recargar el navegador usando el mismo origen.
- Avisar ante cambios sin guardar, error de almacenamiento, sesión vencida y conflictos.

Las pantallas están en app/lib/features/catalog. No importan Firebase ni un
controlador SQL. Los envoltorios de las rutas anteriores usan esas mismas pantallas.

## Ejecutar mientras llega el backend

Desde app:

    flutter pub get
    flutter run -d chrome -t lib/main_catalog_local.dart

Compilar para un servidor local:

    flutter build web --no-web-resources-cdn -t lib/main_catalog_local.dart --output build/catalog-local

Servir la carpeta compilada por HTTP/HTTPS; abrir index.html mediante file:// no
es el método de ejecución. Mantener el mismo dominio/IP y puerto para conservar
los datos de ejemplo del navegador.

La pantalla indica DATOS DE EJEMPLO. El selector Local 1–4 es solo para
desarrollo, no otorga permisos en un servidor. Estos cambios se guardan en el
dispositivo; no se comparten entre usuarios. Borrar los datos del sitio también
borra esta copia local. Las imágenes grandes pueden agotar la cuota del
navegador; se informa el error y no se confirma un guardado fallido.

## Conectar con la API del equipo

El adaptador RestCatalogRepository recibe:

- baseUri: URL de la API local, incluyendo /api/v1/.
- client: cliente HTTP compartido de la aplicación.
- accessToken: función que obtiene el token de la sesión actual.
- refreshSession: renovación coordinada con el acceso general.
- routes: CatalogRoutes, con las rutas y método de actualización centralizados.

El origen de la API se configura en el arranque, no en las pantallas. La sesión
real debe proporcionar el businessId autorizado de GET /users/me; no usar el
selector de locales del modo de ejemplo en el despliegue conectado.

Para alojar frontend y API en el mismo servidor/origen, la URL puede resolverse
con Uri.base.resolve('/api/v1/'). En equipos de alumnos, localhost apunta al
equipo del alumno: se utilizará el nombre o IP del servidor del campus.
El despliegue real requiere HTTPS para la cookie segura de renovación y las
capacidades del navegador como cámara; el certificado debe ser confiable en
los equipos que lo utilizan.

### Contrato provisional de catálogo

La fuente es api_v3_agnostica.md, propuesta del 7 de octubre. La disponibilidad y
media están definidos allí; CRUD completo y algunos formatos se remiten a v2.
Estas decisiones completan los huecos para desarrollar y probar, y deben
coordinarse con el responsable del backend antes de conexión:

| Operación | Ruta debajo de /api/v1 | Resultado esperado |
| --- | --- | --- |
| Listar | GET /businesses/{businessId}/products | data y pagination |
| Obtener | GET /products/{id} | Product |
| Crear | POST /businesses/{businessId}/products | Product |
| Editar | PATCH /products/{id} | Product actualizado |
| Eliminar | DELETE /products/{id} | 204 |
| Subir imagen | POST /media | id, url, width, height |

Listas: page, limit (20; máximo del cliente 100), q e isAvailable.
La respuesta propuesta es:

    { "data": [], "pagination": { "page": 1, "total": 0, "totalPages": 0 } }

Product incluye id, businessId, name, description, category, price, stock,
imageUrl, isAvailable, isFeatured, version y updatedAt en UTC ISO 8601.
stock null significa sin conteo. stock 0 se representa como no disponible.
Se admiten respuestas individuales directas o envueltas en data.

Crear/editar manda solo campos editables, nunca calificaciones calculadas.
En editar/eliminar se envía expectedVersion. Un 409 VERSION_CONFLICT preserva
el formulario y pide recarga; no pisa silenciosamente la versión del servidor.
Si el usuario solo modifica el precio, PATCH omite stock cuando no fue editado.
El backend debe validar expectedVersion en la misma transacción que actualiza
el producto y calcular la disponibilidad definitiva si el stock cambió.

La disponibilidad se guarda actualmente por el PATCH general del producto;
el equipo puede enrutar esta acción a /products/{id}/availability sin modificar
las pantallas. No se añadió ningún endpoint al servidor desde este trabajo.

La subida de imagen usa multipart, purpose=product y el MIME de la imagen.
Si una imagen se sube pero falla el guardado del producto, el backend debería
limpiar archivos sin referencia; quitar una imagen del producto no borra
automáticamente un archivo que podría tener otras referencias.

Los tiempos de espera y fallas de red no disparan reintentos automáticos de
escritura: el usuario debe actualizar para verificar el resultado. Solo se
reintenta una vez tras TOKEN_EXPIRED y renovación exitosa.

## SQL local y 500 usuarios simultáneos

Despliegue objetivo:

1. Los dispositivos acceden al frontend desde la red autorizada.
2. El servidor local sirve el frontend y dirige /api/v1 a la API.
3. La API valida sesión, roles y negocio; consulta la base SQL local.
4. El servidor mantiene el canal de tiempo real y la gestión de imágenes.

El frontend no contiene usuario, contraseña ni conexión directa a SQL.
El motor SQL concreto y sus tablas se eligen con el equipo del backend.
El catálogo conectado manda búsqueda y paginación al servidor: no descarga
todos los productos para filtrarlos en el navegador.

500 es una meta de sesiones concurrentes, no una capacidad medida ni 500
transacciones simultáneas. La base local del modo de ejemplo no participa en
esa prueba. El backend deberá usar un conjunto limitado de conexiones SQL,
consultas e índices adecuados y transacciones para precios/stock/pedidos.

Prueba de aceptación a acordar con el equipo:

- Ambiente local de pruebas con datos ficticios y hardware/red equivalentes.
- Subir por etapas a 50, 100, 250 y 500 sesiones durante un pico representativo.
- Predominio de consulta de menú y seguimiento; pocos operadores cambian
  productos, estados y precios. Usar un ritmo de creación de pedidos acordado
  con los locales, sin equiparar sesiones con pedidos por segundo.
- Medir latencia p95/p99, errores, CPU/RAM, conexiones y esperas SQL, uso de red,
  recuperación del canal de tiempo real y pedidos/stock duplicados.
- Objetivos iniciales propuestos: p95 de catálogo <=1 s, acciones <=2 s,
  errores inesperados <1%, sin duplicados ni sobreventa. Ajustar y aprobar
  con el equipo según hardware y red; no se presentan como resultados.

No se ejecutó una prueba con 500 usuarios ni se modificó una base SQL desde
este módulo. La integración de autenticación REST general, pedidos en tiempo
real y el panel administrativo continúa dentro del plan del proyecto.

## Compatibilidad con la aplicación anterior

app/lib/main.dart compone FirebaseCatalogRepository para conservar el acceso
existente. Ese adaptador exige stock entero y usa las reglas anteriores, sin
modificarlas ni desplegarlas. No representa la arquitectura SQL objetivo.
La sustitución por REST se hace en el arranque una vez integrada la sesión de
la nueva API. Ninguna caída de red selecciona automáticamente datos ficticios.

## Verificación

La suite app/test/catalog cubre altas, edición, precios, eliminación,
persistencia, aislamiento entre locales, existencias, conflictos de versión,
paginación, imágenes, peticiones REST, renovación y formularios en móvil.
El workflow Flutter CI compila la aplicación integrada y el catálogo local.
Consultar el resultado de la ejecución del commit entregado para distinguir
las comprobaciones ejecutadas de las pruebas de carga e integración pendientes.
