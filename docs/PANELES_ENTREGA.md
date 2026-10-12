# SnackUP · Acceso autorizado y operación de locales

Paquete de revisión local para Windows 10/11 de 64 bits. El frontend web utiliza los mismos repositorios REST que se conectarán al backend definitivo. El servidor SQLite incluido permite revisar los flujos; no es el backend de producción.

## Abrir

Extrae todo `SnackUP-Paneles-PC.zip` y ejecuta `INICIAR_SNACKUP.cmd`. Se abre `http://localhost:8791/`. Mantén la consola abierta. No necesitas instalar Flutter, Python o Git.

**El panel del local ya está listo para entrar.** Pulsa **Entrar al local de prueba** o usa `negocio@snackup.test` con contraseña `SnackUP-Prueba-2026`. No requiere crear primero un local ni pasar por Administración.

El paquete de revisión incluye exactamente un **Local de prueba** con una cuenta operadora propia y la cuenta maestra `admin@snackup.test` (misma contraseña de prueba). No se crean los cuatro locales reales ni productos, pedidos, opiniones o grupos. El equipo conserva el alta de sus locales reales y cuentas adicionales.

## Dos paneles separados

El correo y la contraseña identifican una cuenta; el servidor determina su panel. **Administración, incluida la cuenta maestra, no puede entrar a Cocina ni operar productos o pedidos. Las cuentas de los locales no pueden entrar a Administración ni operar otro local.** La separación se aplica en las pantallas y en cada petición de la API; no hay cambio de panel ni suplantación de operadores.

Para probar el panel del local, usa **Entrar al local de prueba**. Abre directamente Cocina, Productos, Historial, Resumen y Mi local con una sesión `business` normal validada por la API.

Para crear cuentas adicionales:

1. Entra con la cuenta maestra. En **Gestionar locales y cuentas**, pulsa **Agregar local** si todavía no existe.
2. Vuelve a Administración y pulsa **Crear cuenta**. Selecciona **Local de cafetería**, asigna ese local e introduce el nombre, correo y contraseña que ustedes decidan. Guarda.
3. **Cierra sesión** y entra con la nueva cuenta del local. Verás Cocina, Productos, Historial, Resumen y Mi local.

La cuenta maestra conserva la gestión de accesos. El único acceso operativo preparado es el del Local de prueba. Las cuentas nuevas siguen sujetas a autorización y los locales inactivos permanecen bloqueados.

## Solicitar y autorizar acceso

1. La persona pulsa **Crea tu cuenta**, introduce nombre, correo, función solicitada, local o área y contraseña propia.
2. La solicitud queda pendiente. No obtiene sesión ni acceso a cocina o administración.
3. La cuenta maestra crea el local si todavía no existe y abre **Solicitudes de acceso**.
4. Comprueba la identidad de la persona, selecciona la función y el local, y autoriza o rechaza. El correo por sí solo no demuestra identidad; la revisión local no envía mensajes de verificación.
5. Una cuenta autorizada ya puede entrar con su contraseña. La solicitud no puede otorgarse privilegios ni modificar una cuenta existente.

La cuenta maestra también puede dar altas directamente mediante **Crear cuenta**. Los administradores nuevos usan un dominio institucional configurado (`utsjr.edu.mx` en la revisión). Solo el maestro administra accesos; cada operador entra únicamente a su local. Una cuenta activa de operación por local como acuerdo provisional del contrato v3.

**Google:** el frontend incluye el acceso mediante una ruta fija del backend y los mensajes de retorno para pendiente, rechazo o error. El botón queda deshabilitado mientras el servidor no habilite el proveedor. No es una simulación de Google: para activarlo hacen falta las credenciales OAuth, el dominio/retorno autorizado y la validación del backend. No se han creado proyectos o credenciales de Google. El contrato describe la integración y la aprobación obligatoria, también para Google.

## Recorrido del local

| Área | Prueba |
|---|---|
| Productos | Crear, editar, subir imagen, cambiar precio, stock, disponibilidad y eliminar con confirmación. |
| Cocina | Abrir recepción. Un pedido nuevo debe aceptarse explícitamente; después iniciar preparación, marcar listo y verificar el código para entregar. |
| Pedido de revisión | El botón voluntario **Recibir pedido de prueba** crea un pedido con un producto disponible y muestra su QR/código. No se generan pedidos al iniciar. |
| Cancelación | Motivo obligatorio; “Otro” requiere detalle. No cancela pedidos listos y devuelve existencias una sola vez. |
| Historial y resumen | Fechas de la universidad e importes confirmados por el servidor. |
| Administración | Locales dinámicos, opiniones, gráficas, carrera → grupo y atención de opiniones. Sin valoraciones no inventa promedios. |

La cocina conserva listas de construcción progresiva, búsqueda, estados separados y acciones directas. El registro interno de pedidos observados se limita a los activos. En escritorio ancho se ven tres columnas; en móvil y tablet hay selector de etapa. Se conservan posiciones de desplazamiento por etapa. Las operaciones se bloquean mientras se guarda ese pedido y ante datos obsoletos.

Web adaptable a celular, tablet y PC. Se comprueban anchos de 320, 360, 768 y 1440 px mediante pruebas de widgets y navegador. Esto no sustituye la prueba en los dispositivos físicos finales. El ZIP abre solo en la PC; para abrir desde teléfonos/tablets de la red se necesita desplegar el frontend y la API en el servidor local autorizado, con HTTPS y dirección accesible. `localhost` en el teléfono se refiere al teléfono.

El canal WebSocket agrupa avisos y recarga REST; sin conexión en vivo consulta cada 10 segundos. Ocultar la aplicación detiene temporizadores/conexiones; regresar actualiza los datos. El tablero administrativo actualiza cada minuto mientras está visible. No se han certificado 500 usuarios simultáneos: esa prueba requiere el backend, SQL y el servidor definitivos.

## Conservar o comenzar vacío

Cierra SnackUP y respalda la carpeta `datos/` completa antes de actualizar. Extrae el ZIP en otra carpeta y copia allí `datos/`. La actualización retira a un archivo interno las cuentas automáticas conocidas (`owner`, `owner2`, `owner3`, `owner4` con sus correos originales) y revoca sus renovaciones. Conserva el maestro, cuentas creadas por ustedes, precios, productos, pedidos y demás trabajo. Si modificaste el correo de una cuenta antigua se conserva para no retirar por error una cuenta personalizada.

El acceso al Local de prueba se agrega una sola vez al actualizar y no modifica locales, precios ni cuentas existentes. Los cambios posteriores a su contraseña, asignación o estado también se conservan. Si el correo `negocio@snackup.test` ya pertenece a una cuenta creada manualmente, se respeta esa cuenta y su contraseña; no se reemplaza ni se le conceden privilegios nuevos.

Los datos anteriores no se borran automáticamente. Para comenzar de nuevo, renombra `datos/` como respaldo con la consola cerrada; al reiniciar aparecen el maestro y el Local de prueba. No hay base de datos prellenada dentro del ZIP.

## Integración

Consulta `CONTRATO_PANELES.md`. Se mantiene la rama `test/api-aaa-sonarqube`. Compilación real:

```sh
flutter build web --no-web-resources-cdn --target lib/main.dart --dart-define=BACKEND=rest --output build/portal-api
```

Sin `REVIEW_MODE` desaparecen el botón de acceso de prueba, las credenciales de ejemplo y el generador de pedidos. El alta del Local de prueba pertenece exclusivamente a `review_server.py`; el frontend no crea cuentas ni omite la autenticación. Por defecto utiliza `/api/v1/` en el mismo origen; `API_BASE_URL` permite configurar otro servidor al compilar. El navegador no se conecta directamente a SQL. El backend mantiene la autorización, transacciones, verificación de correos, OAuth, revocaciones y controles de capacidad. Los dominios institucionales y el catálogo académico se obtienen del backend; los grupos no se deducen de las opiniones.
