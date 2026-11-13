# SnackUP: aplicación integrada en la laptop

Esta copia reúne alumnos, Cocina, Administración y la API en un único origen local. Los datos de prueba están en PostgreSQL, fuera del repositorio. El propósito es comprobar recorridos completos y persistencia en la laptop; no certifica capacidad de producción.

El [informe de salida de la rama integrada](docs/qa-salida-integrada-2026-11-06.md) reúne las pruebas de correo, HTTPS, sesiones y disponibilidad, y distingue las que deben repetirse con el servicio de TI.

La [continuación del 10 de noviembre](docs/qa-salida-integrada-2026-11-10.md) registra los ensayos pendientes de compras simultáneas, reintentos automáticos y conexiones en tiempo real. Incluye los resultados de integridad y los límites de rendimiento observados, además de las verificaciones de PostgreSQL y navegadores en GitHub.

La [revisión del 13 de noviembre](docs/qa-salida-integrada-2026-11-13.md) continúa la comprobación WSS en Linux y documenta el bloqueo de PostgreSQL por Device Guard en esta laptop. El arranque local requiere que Windows permita ejecutar PostgreSQL mediante una instalación o autorización aprobada por el administrador del equipo.

## Política activa de pruebas

Las acciones funcionales se realizan desde la interfaz de Alumnos, Cocina y Administración, con las cuentas locales existentes. Las pantallas se conectan a la API y a PostgreSQL reales de esta laptop; las identidades y el padrón son ficticios y no están conectados a los sistemas de la universidad.

Durante esta auditoría no se crean nuevas semillas ni fixtures y no se ejecutan escrituras directas por API o base de datos para preparar o completar recorridos. Los pedidos, mensajes, productos y valoraciones nuevos se originan desde la UI. Si falta un servicio, una cuenta o un estado que no se puede alcanzar así, se registra como pendiente o bloqueado, sin fabricar resultados. El inventario y los límites están en [docs/qa-paneles-inventory.json](docs/qa-paneles-inventory.json) y [docs/qa-environment-limits.json](docs/qa-environment-limits.json).

El inicio habitual conserva la base existente y **no ejecuta semillas**. El ensayo automatizado descrito al final es un antecedente anterior a esta política, no una instrucción para repetir escrituras durante la auditoría actual.

Para medir la carga se autorizaron 1,000 cuentas y pedidos de ensayo exclusivamente en bases temporales separadas. El generador usa la API de esas instalaciones. Los pedidos de carga no aparecen en el historial, los reportes ni las gráficas de la demostración.

## Fuentes de esta integración

| Parte | Rama y revisión de origen |
|---|---|
| Alumnos y backend | `codex/conectar-alumnos-api` — `7c549b7b03ff05847cc6680d687237594e87e12e` |
| Cocina y Administración | `codex/entrega-paneles-rest` — `9d8f7cb05c57ec5d6b89aca288d04e9d9295d5f5` |

El backend de ambas entregas comparte el árbol `de365689c2ec2001bc05bba3c29908d1ea78828e`. Los paneles están en `app/`; la aplicación de alumnos permanece en la raíz. El lanzador reutiliza FastAPI y sus rutas, añade los dos frontends compilados y ejecuta los trabajos programados cada cinco segundos.

## Requisitos y carpetas

- Windows con PowerShell 5.1 o superior; no se necesita Docker.
- Python 3.12 con las dependencias de `backend/requirements.lock` ya instaladas. Por defecto se usa `C:/Users/video/Documents/Codex/2026-10-14/h/work/SnackUP-core/backend/.venv/Scripts/python.exe`. Se puede reemplazar mediante `-PythonPath`.
- PostgreSQL portátil existente en `C:/Users/video/Documents/JC/SnackUP-Integracion-Local/runtime/pgsql/bin`. Los scripts no descargan PostgreSQL, Python, Flutter ni dependencias.
- Flutter disponible para compilar alumnos y paneles cuando cambie el código. El inicio verifica que ambos builds existan con sus bases correctas.

| Ubicación | Contenido |
|---|---|
| `build/web/` | Compilación web de alumnos; base `/` |
| `app/build/web/` | Compilación web de paneles; base `/paneles/` |
| `tools/integrated_server.py` | API existente, archivos web y scheduler local |
| `tools/setup_local_postgres.py` | Prepara o vuelve a iniciar el cluster aislado |
| `tools/seed_integrated.py` | Preparación opcional de datos ficticios faltantes; no se ejecuta en el inicio habitual ni en la auditoría actual |
| `tools/test_integrated_flow.py` | Ensayo HTTP anterior que crea pedidos; no ejecutar en la auditoría actual |
| `C:/Users/video/Documents/JC/SnackUP-Integracion-Local/` | Configuración privada, PostgreSQL, archivos subidos, logs y registro del proceso |

No compartir ni subir a Git `config.json`, `postgres-data/`, `media/` o logs. El JSON contiene las credenciales locales y la clave de sesiones. Conservarlo junto al cluster; no regenerarlo para una base ya existente.

## Compilar e iniciar

Ejecutar en PowerShell desde esta copia del repositorio. Si los builds ya están actualizados, comenzar directamente con el script de inicio. Usar la misma versión de Flutter compatible con cada proyecto y revisar sus `pubspec.yaml`.

```powershell
flutter build web --release --no-web-resources-cdn --pwa-strategy=none
Push-Location app
try {
    flutter build web --release --target lib/main_portal_api.dart --base-href /paneles/ --dart-define=API_BASE_URL=/api/legacy/v1/ --no-web-resources-cdn --pwa-strategy=none
} finally {
    Pop-Location
}

& ./tools/start_integrated_local.ps1
```

La plantilla web de Alumnos ya fija `<base href="/">`. Su compilación usa ese valor; no se añade `--base-href /`. Los paneles sí se compilan con `--base-href /paneles/`.

El inicio comprueba los builds y el puerto 18080, inicia o reutiliza el cluster PostgreSQL propio, aplica las migraciones pendientes con `alembic upgrade head` y abre el servidor en segundo plano con ventana oculta. **No crea cuentas ni productos de demostración, no restablece existencias y no genera pedidos.** Para retomar la base ya existente basta con `./tools/start_integrated_local.ps1`, sin opciones de semillas. Espera que API y scheduler estén listos antes de anunciar éxito. Repetirlo con un servidor propio saludable no crea otro proceso. Un puerto ocupado por un servidor iniciado manualmente se respeta: hay que detener ese servidor de forma identificada antes de usar estos scripts.

El parámetro opcional `-SeedDemoData` vale falso por defecto. Solo si se proporciona explícitamente, y el script realiza un nuevo arranque, se llama a `seed_integrated.py` después de las migraciones. Existe para una preparación inicial de demostración solicitada expresamente; **no se utiliza para reiniciar esta base ni durante la auditoría actual**. La semilla inserta registros ficticios faltantes y conserva los existentes. Si el servidor propio ya está saludable, el script retorna sin ejecutar la semilla, incluso con ese parámetro.

Para elegir otro intérprete o una carpeta externa ya preparada:

```powershell
& ./tools/start_integrated_local.ps1 `
    -PythonPath 'C:/ruta/al/entorno/Scripts/python.exe' `
    -ConfigPath 'C:/ruta/privada/SnackUP/config.json' `
    -StartupTimeoutSeconds 90
```

`ConfigPath` debe llamarse `config.json`. Su carpeta contiene también `runtime/pgsql/bin`, `postgres-data`, `media` y `logs`. PostgreSQL queda fijo en `127.0.0.1:55432`, base `snackup_integration`, usuario técnico `snackup_local`; la web queda fija en `http://localhost:18080`. Los puertos no se cambian mediante el JSON.

Campos utilizados del JSON: `database_url`, `secret_key` (mínimo 32 caracteres aleatorios) y `media_dir` (ruta absoluta fuera del repositorio). `students_web` y `panels_web` permiten indicar otras carpetas de build. `services_file` permite indicar un JSON privado absoluto fuera del repositorio para correo y notificaciones reales; si se omite, esos servicios permanecen deshabilitados. El preparador genera también `public_origin` y `port` como referencia; el lanzador mantiene el origen y puerto fijos. No imprimir el JSON ni pegarlo en un chat. Las migraciones leen los secretos dentro del proceso Python, sin incluirlos en argumentos de consola, y no cargan un `.env` ajeno.

## Abrir y probar los tres roles

En esta laptop también quedaron `INICIAR_SNACKUP.cmd` y `DETENER_SNACKUP.cmd` en `C:/Users/video/Documents/JC/SnackUP-Integracion-Local/`. Se pueden abrir con doble clic. El segundo detiene la API y el PostgreSQL de esta instalación, conservando los datos. Si se mueve el repositorio, actualizar las rutas de esos accesos.

| Rol | Dirección | Correo ficticio |
|---|---|---|
| Alumno | http://localhost:18080/ | `alumno.demo@utsjr.edu.mx` |
| Cocina | http://localhost:18080/paneles/ | `operator@staff.example.edu` |
| Administración maestra | http://localhost:18080/paneles/ | `master@staff.example.edu` |

La contraseña inicial pública para las tres cuentas de demostración es **`SnackUP-Prueba-V32!`**; si se cambió, el arranque conserva la contraseña actual. No sirve como credencial de producción. En la preparación inicial, la cuenta de alumno recibió matrícula `DEMO-001`, carrera `Desarrollo de Software (prueba)` y grupo `DEMO-1` en el padrón ficticio; el negocio `integration-local` se creó abierto con tres productos y 30 unidades de cada uno. Los valores actuales pueden haber cambiado durante las pruebas. Son cuentas persistidas en el backend local real, no identidades institucionales verificadas. Reiniciar no vuelve a sembrarlas ni restaura las existencias iniciales.

**Usar perfiles independientes de navegador para cada rol**, o navegadores distintos. Varias pestañas del mismo perfil comparten la cookie de renovación del backend y pueden reemplazar la sesión de otra cuenta. Dos ventanas privadas del mismo navegador también pueden compartir cookies entre sí. Usar siempre `localhost`, sin sustituirlo por `127.0.0.1` o una IP de la red, porque el origen forma parte de las comprobaciones de seguridad.

Recorrido de prueba vigente, realizado desde la UI:

El [informe HTML de la auditoría](docs/qa-real-ui-2026-11-04.html) resume lo observado y sus pendientes; el [registro JSON](docs/qa-real-ui-2026-11-04.json) conserva el detalle de cada evidencia. Las cuentas locales existentes siguen siendo ficticias, no identidades institucionales verificadas.

1. En Alumno, revisar el catálogo, crear un pedido y anotar el folio.
2. En Cocina, comprobar que aparece ese mismo pedido y avanzar por sus estados hasta la entrega.
3. En Alumno, comprobar los cambios y valorar el negocio después de la entrega, incluyendo la calificación general, alimentos, servicio y comentario. Las reseñas individuales de platillos se envían y se consultan por separado en Alumnos.
4. En Administración, comprobar que la opinión del negocio aparece con su comentario y calificaciones exactas; filtrar esa opinión y revisar los promedios y gráficas. Las reseñas individuales de platillos no alimentan este dashboard. Revisar los demás controles según el inventario.
5. En Alumno, abrir Perfil → Mis conversaciones o el chat de un pedido. Enviar un mensaje, abrir el chat correspondiente en Cocina y responder. Volver al chat de Alumnos y comprobar que ambos mensajes permanecen visibles.
6. Probar cierres programados y fallos de conexión con los pedidos creados desde la UI, respetando los tiempos reales y sin alterar fechas en la base.
7. Cuando corresponda comprobar un reinicio, detener e iniciar con los scripts y confirmar desde la UI que siguen los registros. No usar `-SeedDemoData` ni ejecutar `seed_integrated.py`.

La [validación ampliada de chat, calificaciones y notificaciones del 4 de noviembre](docs/qa-chat-ratings-push-2026-11-04.json) complementa el informe anterior. Desde las interfaces se verificó el intercambio de mensajes entre Alumnos y Cocina en el pedido #7 y su persistencia al volver a abrir la conversación. Tras entregar ese pedido, el alumno guardó una valoración general de 5, alimentos de 4 y servicio de 3, con un comentario identificable. Administración mostró esos mismos valores. Al filtrar esa única opinión, las gráficas reflejaron promedio general 5.0, servicio 3.0/60 %, alimentos 4.0/80 % y una opinión de cinco estrellas. Estos resultados proceden del recorrido UI sobre la API y PostgreSQL locales, sin insertar valoraciones ni mensajes directamente.

La tarjeta **Notificaciones de pedidos** está disponible en Perfil de Alumnos y Mi local de Cocina. Su botón **Activar notificaciones** solicita permiso de forma explícita; abrir la pantalla no lo solicita. En el navegador integrado se verificó que una solicitud sin respuesta deja de esperar a los 25 segundos, muestra una explicación y vuelve a habilitar los controles sin anunciar éxito. También existe **Cancelar activación**. El usuario activó la suscripción de Cocina en Edge. Tras corregir la validación del contacto VAPID, el aviso del pedido #8 terminó en `sent`, intento 5 y sin error. A petición del usuario se creó desde Alumnos el pedido #9: su aviso fue aceptado al primer intento y el usuario confirmó que apareció la notificación en Windows. La evidencia distingue la observación del agente, la consulta de solo lectura y la confirmación del usuario. Las observaciones completadas no equivalen a una revisión total de todos los controles y escenarios del inventario.

El script de inicio consulta únicamente los endpoints de salud `http://localhost:18080/health/ready` y `http://localhost:18080/health/integration`, que deben responder 200. El segundo devuelve 503 si el scheduler falla o lleva más de 30 segundos sin un ciclo correcto. Un GET a una ruta API inexistente responde 404 JSON; otros métodos pueden responder 405 JSON. No se devuelve el HTML del frontend como respuesta exitosa a una API inexistente. Estas comprobaciones de disponibilidad no crean datos ni acreditan el funcionamiento de botones: los recorridos funcionales actuales se comprueban desde el navegador.

## Detener y volver a iniciar

```powershell
# Detiene solamente la web/API propia; PostgreSQL sigue disponible.
& ./tools/stop_integrated_local.ps1

# Opcional: también detiene limpiamente el cluster local identificado.
& ./tools/stop_integrated_local.ps1 -StopPostgres

# Después de reiniciar la PC, retoma la base existente sin ejecutar semillas.
& ./tools/start_integrated_local.ps1
```

Si se usó otro `ConfigPath`, pasarlo también al detener. No se mata un proceso simplemente por escuchar en 18080: se comprueban PID registrado, fecha de creación, ejecutable, comando, copia del repositorio y configuración. El registro contempla que el lanzador del entorno virtual de Windows cree un intérprete hijo. Si no se puede demostrar la pertenencia, se informa y no se detiene el proceso. Para PostgreSQL se verifica el directorio exacto del cluster, su archivo de control, puerto y ejecutable antes de llamar a `pg_ctl`.

La parada de la web usa la terminación de procesos de Windows; no equivale a un despliegue con drenado de solicitudes. Evitar detenerla mientras se confirma un pedido. PostgreSQL conserva las transacciones confirmadas. Los scripts no borran datos ni cierran otros servidores. Los logs de cada inicio quedan en la carpeta externa `logs/`, con fecha en el nombre.

## Correo y notificaciones con proveedores reales

En la aplicación integrada, los enlaces de recuperación llevan a cada cuenta a su propio acceso. Los alumnos vuelven a `/` y el personal a `/paneles/`. El rol guardado en la cuenta determina la ruta.

El 6 de noviembre se comprobó el alta de alumno y la recuperación de Alumnos y Cocina desde las pantallas. Los mensajes llegaron por SMTP con STARTTLS a un buzón aislado de la laptop. La prueba usó una copia temporal de PostgreSQL y los registros locales de QA. El correo y el padrón institucionales siguen pendientes. [Resultados del ensayo de correo](docs/qa-correo-2026-11-06.json)

El lanzador admite una configuración privada explícita; nunca toma credenciales de un `.env` ni de variables `SNACKUP_*` heredadas. La plantilla sin secretos es [tools/integration-services.example.json](tools/integration-services.example.json). Copiarla a una carpeta privada fuera del repositorio y agregar en el `config.json` externo el campo `services_file` con la ruta absoluta a esa copia. No sobrescribir una configuración existente para repetir la preparación.

Correo requiere `smtp.enabled=true`, `host`, `port`, `from` y los datos autorizados por el proveedor. Para autenticación, indicar `user` y `password_file`: este último debe ser un archivo privado absoluto fuera de Git que contenga una sola contraseña o credencial SMTP, sin mostrarla en consola. El puerto 465 usa TLS implícito; los demás exigen `starttls=true`. Sin SMTP configurado, el registro y la recuperación permanecen deshabilitados. Configurar estos campos no demuestra recepción de un mensaje: se necesita una prueba de extremo a extremo con un buzón real autorizado. Los enlaces del correo apuntan a `localhost:18080` y deben abrirse en la misma laptop durante este ensayo.

Para notificaciones web se requiere `push.enabled=true` y `push.webpush.private_key_file` apuntando a una clave VAPID PEM EC P-256 privada, más `push.webpush.subject` con un contacto `mailto:` o HTTPS. El backend deriva solo la clave pública para `GET /api/v1/push/options`; nunca devuelve el PEM. El navegador requiere permiso del usuario y una suscripción registrada mediante el endpoint autenticado `POST /api/v1/users/me/devices`. `GET /api/v1/users/me/devices/current` consulta el dispositivo de la familia de sesión actual sin exponer su token; `DELETE /api/v1/users/me/devices/{id}` permite desactivarlo. La autorización del navegador y la recepción de una notificación deben comprobarse desde la interfaz real. El permiso o una respuesta exitosa del proveedor no equivalen a una notificación vista por el usuario.

Edge en Windows puede entregar las notificaciones mediante Microsoft WNS. El backend admite un único subdominio DNS ASCII válido bajo `notify.windows.com`, conserva su query de canal sin mostrarla y aplica las cabeceras de entrega `wns/raw`. No permite el dominio raíz, niveles anidados, destinos arbitrarios, credenciales, fragmentos, puertos distintos de 443 ni redirecciones; los otros proveedores conservan hosts exactos y no admiten query. Los subdominios de WNS son variables según [Microsoft](https://learn.microsoft.com/en-us/windows/apps/develop/notifications/push-notifications/wns-overview), por lo que no se inventa un endpoint fijo ni se necesita otra clave VAPID. El HTTP 406 de WNS se reintenta respetando `Retry-After`. La aceptación del proveedor no demuestra por sí sola un aviso visible: para el pedido #9 también se obtuvo confirmación explícita del usuario de su aparición en Windows.

El contacto HTTPS de VAPID puede incluir una ruta según [RFC 8292, sección 2.1](https://www.rfc-editor.org/rfc/rfc8292.html#section-2.1). El backend valida esa URI antes de sustituir únicamente la comprobación restrictiva de `sub` de py-vapid 1.9.6. Conserva la clave existente, firma ES256, audiencia y expiración; no regenera credenciales para corregir el fallo. Los diagnósticos registran códigos y clases de excepción limitadas, sin tokens, endpoints completos ni respuestas privadas.

El helper `python -B tools/create_local_webpush_key.py --output C:/ruta/privada/webpush-vapid.pem` crea una clave nueva únicamente cuando el propietario autoriza esa configuración; exige una carpeta existente fuera de Git y se niega a sobrescribir archivos. No lo ejecuta el arranque, no habilita push y no envía mensajes. La carpeta debe tener permisos limitados a su propietario y a los administradores del equipo; en Windows los permisos POSIX del archivo no sustituyen a las ACL.

En esta laptop, tras la autorización del usuario del 4 de noviembre, se prepararon `services.json` y `webpush-vapid.pem` dentro de `C:/Users/video/Documents/JC/SnackUP-Integracion-Local/`, con ACL restringidas al usuario actual, SYSTEM y Administradores. La configuración habilita únicamente Web Push y utiliza el repositorio público del proyecto como contacto HTTPS. SMTP, FCM y APNs permanecen deshabilitados. La clave no debe regenerarse al reiniciar: las suscripciones existentes dependen de ella. Estos archivos privados no forman parte de la entrega Git. Su preparación no sustituye la verificación de entrega desde el navegador.

Para comprobar la configuración sin conectar a proveedores, mandar mensajes, crear dispositivos ni escribir datos SQL:

```powershell
python -B tools/check_integrated_services.py
```

El diagnóstico muestra únicamente indicadores de configuración y disponibilidad de la clave pública; no imprime remitentes, contraseñas, claves ni suscripciones. `deliveryVerified=false` significa que este comprobador no verifica entregas. Los cambios de configuración se aplican al reiniciar la API con los scripts identificados, conservando PostgreSQL y todos sus datos. El backend también admite proveedores FCM y APNs en el mismo archivo privado cuando exista una aplicación y credenciales autorizadas; no es necesario configurarlos para Web Push.

## Alcance y pendientes de servidor

La [revisión funcional del 6 de noviembre](docs/qa-integracion-2026-11-06.md) documenta los pedidos simultáneos, la recuperación tras perder una respuesta, los vales y la entrega con QR leído por la cámara de la laptop.

**Android por cable, sin exponer el servidor a la red.** Con el servidor listo, conecta un solo teléfono desbloqueado por USB y aprueba la depuración en ese dispositivo. Con Android SDK Platform Tools instalado, ejecuta `./tools/open_android_local.ps1 -AdbPath RUTA_A_ADB.EXE`. Añade `-Paneles` para abrir Cocina o Administración. El túnel conserva `http://localhost:18080` como origen en Chrome; no configura HTTPS para la red ni modifica el firewall. Al terminar, desconecta el cable o ejecuta `adb -d reverse --remove tcp:18080` para retirar ese túnel. Puedes desactivar la depuración USB en el teléfono.

El 6 de noviembre de 2026 se restauró una copia de PostgreSQL 17.11 en una base
vacía de la laptop. La revisión Alembic fue `0003_v32`. Coincidieron los contenidos
de las 30 tablas y las 347 filas de la misma instantánea. También se recuperó de
su archivo comprimido la imagen que se había subido desde el formulario de
producto y se verificó su SHA-256. El ensayo retiró su base temporal y dejó el
dump, las sumas y los medios en una carpeta privada fuera del repositorio.
Para repetirlo con PostgreSQL activo, usar el Python 3.12 del backend:

```powershell
& 'C:/Users/video/Documents/Codex/2026-10-14/h/work/SnackUP-core/backend/.venv/Scripts/python.exe' -B tools/verify_local_restore.py
```

El comando imprime la carpeta de respaldo creada para esa ejecución. La base de
origen se lee con una instantánea de PostgreSQL y los medios se copian después.
Durante un respaldo de operación, suspender las escrituras y cargas de archivos
para que ambas copias correspondan al mismo corte. Acordar con TI la retención,
el resguardo cifrado fuera del servidor y la custodia separada de los secretos.

| Entrega necesaria | Cómo comprobarla en el entorno de la universidad |
|---|---|
| Servidor y dominio HTTPS | Construir los tres componentes desde el mismo commit siguiendo la [guía de despliegue](backend/DESPLIEGUE_CONTENEDOR_UNICO.md). Verificar `/health/ready`, el estado de los contenedores y una alerta de monitorización al detener un servicio durante mantenimiento. |
| Teléfono con el dominio definitivo | Repetir en el dominio HTTPS el recorrido ya probado localmente con Android: abrir Alumnos y los paneles, comprobar el aviso con Chrome en segundo plano y abrir Cocina desde el aviso. Los permisos y las suscripciones pertenecen al origen del sitio. |
| SMTP y padrón oficial | Con un registro autorizado que incluya carrera y grupo, recibir el enlace de verificación, completar el alta, confirmar el perfil y recuperar la contraseña. Repetir con matrícula discrepante y comprobar el rechazo. |
| Capacidad de 1,000 alumnos | Usar una instalación y datos autorizados para carga, registrar vCPU, RAM y configuración, y medir consultas, conexiones activas y pedidos mientras los operadores usan Cocina. Comparar los percentiles, errores, duplicados y existencias con los criterios del [protocolo de carga](backend/load/phase_c/README.md). El generador de ese protocolo reinicializa su propia base de medición y requiere una autorización separada para usar sus fixtures. |
| Recuperación en el servidor definitivo | Restaurar base y medios en volúmenes independientes. Verificar integridad, acceso y tiempo real de recuperación, y compararlo con los objetivos acordados con TI. |

La instancia compartida de la laptop utiliza cuentas locales existentes y mantiene SMTP deshabilitado hasta recibir el proveedor y el remitente autorizados. Los endpoints de registro y recuperación pueden devolver 503 `EMAIL_UNAVAILABLE`. En la copia aislada se comprobó la entrega por STARTTLS al buzón local y el uso de sus enlaces. La entrega al buzón universitario queda pendiente. El aviso de nuevo pedido de Web Push se comprobó tanto en Edge/Windows (pedido #9) como en Chrome en un Samsung físico (pedido #13).

Esta configuración utiliza **HTTP en localhost, un solo worker y ningún Redis**. Es adecuada para comprobar integración funcional local con datos ficticios; no demuestra soporte de 1000 usuarios simultáneos, alta disponibilidad, despliegue real ni acceso seguro desde móviles por LAN. La emulación de pantalla móvil en la laptop sí permite revisar el diseño; probar un teléfono real por red requiere preparar HTTPS y el origen correspondiente, no abrir simplemente un puerto.

Antes de producción siguen siendo necesarios el servidor definitivo, dominio/HTTPS, secretos propios, correo institucional y proveedores autorizados, política de copias/restauración, monitorización, pruebas de carga con el hardware y la arquitectura elegidos, y validación de todos los flujos de los tres equipos. El padrón local es ficticio y no acredita alumnos reales. La interfaz de chat de Alumnos ya está incluida en esta rama y su intercambio con Cocina se comprobó desde ambas pantallas; esa evidencia no valida por sí sola todos los escenarios de permisos, desconexión o carga.

## Antecedente: ensayo del 4 de noviembre de 2026

Los siguientes resultados pertenecen al ensayo anterior a la política de pruebas exclusivamente desde UI. Se conservan como evidencia histórica; no significan que hoy se hayan recorrido todos los botones ni sustituyen la auditoría actual.

El detalle verificable está en [docs/local-integration-2026-11-04.json](docs/local-integration-2026-11-04.json). Se aprobaron 139 pruebas del backend sobre PostgreSQL real, 7 pruebas de paneles, 10 comprobaciones HTTP del recorrido completo y 6 de cierre automático. Tres casos que requieren Redis quedaron sin ejecutar (dos omitidos y uno deseleccionado). El apagado y encendido de API y PostgreSQL conservó disponibilidad, inventario, pedidos y valoraciones.

En el navegador se creó el pedido ficticio #3 desde Alumnos y se aceptó, preparó y entregó desde Cocina. Se comprobó el chat de Cocina, el historial y las valoraciones con seguimiento en Administración. La pantalla de Alumnos mostró el error al detener la API y recuperó el pedido al reiniciar. Cocina y Administración se revisaron en tamaño móvil y PC. Se corrigió la traducción de métodos de pago canónicos en paneles y una incompatibilidad de fechas entre versiones de PowerShell en los controles de procesos.

En aquel ensayo se usaron `tools/test_integrated_flow.py` y `tools/test_integrated_closures.py`; sus reportes y los datos creados se conservan como antecedentes. Esos scripts realizan escrituras y **no se deben repetir durante la auditoría actual**. Tampoco se borra historial ni se cambian fechas para forzar otra ejecución: el cierre automático solo se procesa una vez por día/local. La persistencia y los cierres se comprueban ahora con operaciones desde UI y espera real cuando sea necesaria.
