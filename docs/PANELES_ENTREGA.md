# SnackUP · Paneles de negocios y administración

Versión de revisión integrada para Windows 10/11 de 64 bits. El mismo frontend Flutter utiliza repositorios REST tanto en la revisión como en la compilación destinada al backend definitivo. El paquete de revisión incluye una API de prueba con SQLite y datos ficticios persistentes; no representa el servidor de producción ni una certificación de capacidad para 500 usuarios.

## Abrir y probar

1. Extrae **todo** `SnackUP-Paneles-PC.zip` en una carpeta propia, por ejemplo Documentos/SnackUP.
2. Ejecuta `INICIAR_SNACKUP.cmd`. No requiere instalar Flutter, Python ni Git y no necesita permisos de administrador.
3. Se abre `http://localhost:8791/`. Mantén la consola abierta mientras utilizas los paneles.
4. Cuenta maestra: `admin@snackup.test`. Puede crear accesos desde **Crear cuenta**. Contraseña de las cuentas iniciales: **SnackUP-Prueba-2026**.
5. Para terminar, cierra sesión y cierra la consola. Los cambios permanecen en la carpeta `datos/`.

Una sola cafetería universitaria tiene inicialmente cuatro locales con cuentas separadas: `negocio@snackup.test` (Central), `antojitos@snackup.test`, `verde@snackup.test` y `dulce@snackup.test`. Cada cuenta consulta únicamente su catálogo y pedidos. Para usar dos cuentas simultáneamente, abre una ventana privada u otro perfil del navegador: las pestañas del mismo perfil comparten la cookie de acceso.

## Recorrido de revisión

| Área | Qué comprobar |
|---|---|
| Cocina | Aceptar un pedido, iniciar preparación, marcarlo listo, verificar y entregar. Los pedidos listos no se cancelan. |
| Pedido nuevo | Pulsar **Recibir pedido de prueba**. El comprobante muestra un QR y su código; úsalo al entregar. Los pedidos iniciales tienen código **4821**. |
| Cancelación | Seleccionar un motivo; “Otro motivo” requiere una explicación. El servidor de prueba repone las existencias reservadas una sola vez. |
| Productos | Agregar un producto, editar nombre/categoría/descripción/precio, subir/quitar una imagen, ajustar existencias, destacar, pausar disponibilidad y eliminar con confirmación. |
| Historial | Elegir una fecha y revisar pedidos entregados/cancelados, sus importes y sus motivos. |
| Resumen | Elegir un periodo y consultar ventas entregadas, entregas y cancelaciones calculadas por el servidor. |
| Mi local | Editar información y cerrar/abrir la recepción. Los pedidos ya recibidos siguen visibles cuando el local cierra. |
| Administración | Revisar opiniones y filtros, abrir un caso, registrar un responsable, cambiar el seguimiento y consultar su historial. |
| Gestión | Crear/editar locales. La cuenta maestra crea/edita cuentas, asigna un local y suspende accesos; permanece activa y administrativa. Los nuevos administradores usan correos institucionales autorizados (`@utsjr.edu.mx` en la revisión). |
| Carreras y grupos | Primero elegir carrera; después buscar su grupo. También aparecen grupos sin opiniones. Las carreras y grupos iniciales son ejemplos, no el padrón oficial. |
| Gráficas | Se recalculan al actualizar datos y al cambiar filtros; el tablero recarga cada minuto mientras está visible. Sin puntuaciones no muestra un promedio inventado. |
| Persistencia | Cambiar un precio, cerrar el programa, abrirlo otra vez y comprobar que sigue guardado. |
| Concurrencia | Abrir el mismo pedido en dos perfiles de navegador. Una modificación con versión antigua debe mostrar conflicto y actualizar los datos. |

El sonido se activa voluntariamente con el icono del altavoz. La cámara requiere permiso del navegador; si no está disponible, funciona el código manual. El lector QR y los recursos web están incluidos localmente. La revisión usa actualizaciones por consulta cada 10 segundos; el frontend de producción también incluye el canal WebSocket del contrato v3 y recarga REST al recibir sus avisos.

## Datos y límites de esta entrega

- La franja amarilla identifica siempre la revisión con datos ficticios. Sus cuentas no dan acceso al servicio real.
- `datos/revision.sqlite3` y `datos/media/` conservan los cambios. Son datos de revisión, no datos del alumnado. Con el programa cerrado, copia la carpeta `datos/` para respaldarla.
- Para empezar nuevamente, cierra el programa y **renombra** `datos/` a `datos-respaldo/`. Al iniciar se generan ejemplos nuevos. No borres la carpeta si quieres conservar tus cambios.
- Si se ocupa el puerto 8791, el iniciador muestra el problema; no abre silenciosamente otro servicio. Cierra la instancia previa.
- La recuperación solicita correctamente el endpoint. La API de revisión no envía correos: utiliza las cuentas de ejemplo o crea una cuenta desde administración. La pantalla de restablecimiento para enlaces del backend sí está implementada.
- Los permisos, transacciones, cookies de producción y reglas SQL definitivas corresponden al backend. El servidor incluido escucha solamente en esta PC y **no debe publicarse en Internet ni utilizarse para atender 500 usuarios**.
- La aplicación de alumnos pertenece al otro equipo. Esta entrega cubre negocios y administración; el botón de pedido de prueba sustituye al cliente únicamente durante la revisión.
- La identidad usa el azul #002855, el turquesa #00A788 y el cintillo íntegro del sitio oficial de UTSJR. Se usa “universidad” en los paneles. “Atención de opiniones” registra responsable, acción y resolución de una opinión o queja.

## Entrega al equipo del backend

Consultar `CONTRATO_PANELES.md` y `PORTAL_API_LOCAL.md`. Las acciones de pedidos proceden de API v3. La gestión administrativa, edición de información del local y forma del resumen de ventas se documentan como extensiones propuestas para cerrar los huecos; deben acordarse con el otro equipo.

Compilación para integración real:

```sh
flutter build web --no-web-resources-cdn --target lib/main.dart --dart-define=BACKEND=rest --output build/portal-api
```

Sin `REVIEW_MODE` no aparecen cuentas de ejemplo ni generación de pedidos. Por defecto usa `/api/v1/` en el mismo origen. Para otro servidor se configura `API_BASE_URL` al compilar. No se conecta directamente a SQL desde Flutter.

Antes de la entrega operativa conjunta: verificar flujos contra la API definitiva, asignaciones y revocaciones de rol, correo real, cámara en los dispositivos destino, HTTPS, recuperación ante interrupciones y pruebas de carga con los 500 usuarios simultáneos esperados. El hardware, el motor SQL y el pico máximo siguen sin estar definidos. Las pruebas de esta revisión no sustituyen esas comprobaciones.

## Actualizar desde el ZIP anterior conservando tus cambios

1. Cierra la consola de SnackUP.
2. Haz una copia de respaldo de la carpeta anterior `datos/` completa.
3. Extrae el nuevo ZIP en otra carpeta y copia allí `datos/`, junto a `INICIAR_SNACKUP.cmd`.
4. Abre el iniciador e inicia sesión nuevamente. La migración conserva productos, precios, pedidos y contraseñas, agrega la estructura institucional y las cuentas faltantes. Solo renombra los nombres originales de ejemplo; conserva los nombres personalizados.

El maestro inicial de revisión sigue siendo `admin@snackup.test`; se exceptúa su correo ficticio de la política institucional mientras no se cambie. Las credenciales iniciales visibles corresponden a una instalación nueva; si ya cambiaste una cuenta se conserva tu cambio. La API de revisión no envía invitaciones por correo. La cuenta real inicial y el envío/cambio de contraseñas deben configurarse con el backend antes de operar.
