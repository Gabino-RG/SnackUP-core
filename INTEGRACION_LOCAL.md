# SnackUP: aplicación integrada en la laptop

Esta copia reúne alumnos, Cocina, Administración y la API en un único origen local. Los datos de prueba están en PostgreSQL, fuera del repositorio. El propósito es comprobar recorridos completos y persistencia en la laptop; no certifica capacidad de producción.

## Política activa de pruebas

Las acciones funcionales se realizan desde la interfaz de Alumnos, Cocina y Administración, con las cuentas locales existentes. Las pantallas se conectan a la API y a PostgreSQL reales de esta laptop; las identidades y el padrón son ficticios y no están conectados a los sistemas de la universidad.

Durante esta auditoría no se crean nuevas semillas ni fixtures y no se ejecutan escrituras directas por API o base de datos para preparar o completar recorridos. Los pedidos, mensajes, productos y valoraciones nuevos se originan desde la UI. Si falta un servicio, una cuenta o un estado que no se puede alcanzar así, se registra como pendiente o bloqueado, sin fabricar resultados. El inventario y los límites están en [docs/qa-paneles-inventory.json](docs/qa-paneles-inventory.json) y [docs/qa-environment-limits.json](docs/qa-environment-limits.json).

El inicio habitual conserva la base existente y **no ejecuta semillas**. El ensayo automatizado descrito al final es un antecedente anterior a esta política, no una instrucción para repetir escrituras durante la auditoría actual.

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
flutter build web --release --base-href / --no-web-resources-cdn --pwa-strategy=none
Push-Location app
try {
    flutter build web --release --target lib/main_portal_api.dart --base-href /paneles/ --dart-define=API_BASE_URL=/api/legacy/v1/ --no-web-resources-cdn --pwa-strategy=none
} finally {
    Pop-Location
}

& ./tools/start_integrated_local.ps1
```

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

Campos utilizados del JSON: `database_url`, `secret_key` (mínimo 32 caracteres aleatorios) y `media_dir` (ruta absoluta fuera del repositorio). `students_web` y `panels_web` permiten indicar otras carpetas de build. El preparador genera también `public_origin` y `port` como referencia; el lanzador mantiene el origen y puerto fijos. No imprimir el JSON ni pegarlo en un chat. Las migraciones leen los secretos dentro del proceso Python, sin incluirlos en argumentos de consola, y no cargan un `.env` ajeno.

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
3. En Alumno, comprobar los cambios y valorar el negocio después de la entrega. Las reseñas de platillos se envían y se consultan por separado en Alumnos.
4. En Administración, comprobar que la opinión del negocio aparece con su comentario, estrellas y filtros; las reseñas individuales de platillos no alimentan este dashboard. Revisar los demás controles según el inventario.
5. Probar cierres programados y fallos de conexión con los pedidos creados desde la UI, respetando los tiempos reales y sin alterar fechas en la base.
6. Cuando corresponda comprobar un reinicio, detener e iniciar con los scripts y confirmar desde la UI que siguen los registros. No usar `-SeedDemoData` ni ejecutar `seed_integrated.py`.

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

## Alcance y pendientes de servidor

SMTP, el buzón de pruebas y las notificaciones push están desactivados en este lanzador. El registro y la recuperación por correo no están habilitados: sus endpoints pueden responder 503 `EMAIL_UNAVAILABLE`. Para estas pruebas se usan cuentas ficticias ya autorizadas. No se ha validado la entrega de correos ni de notificaciones a un teléfono.

Esta configuración utiliza **HTTP en localhost, un solo worker y ningún Redis**. Es adecuada para comprobar integración funcional local con datos ficticios; no demuestra soporte de 1000 usuarios simultáneos, alta disponibilidad, despliegue real ni acceso seguro desde móviles por LAN. La emulación de pantalla móvil en la laptop sí permite revisar el diseño; probar un teléfono real por red requiere preparar HTTPS y el origen correspondiente, no abrir simplemente un puerto.

Antes de producción siguen siendo necesarios el servidor definitivo, dominio/HTTPS, secretos propios, correo institucional y proveedores autorizados, política de copias/restauración, monitorización, pruebas de carga con el hardware y la arquitectura elegidos, y validación de todos los flujos de los tres equipos. El padrón local es ficticio y no acredita alumnos reales. Una prueba API de chat tampoco certifica una interfaz de chat en alumnos si esa interfaz no existe en la entrega de su equipo.

## Antecedente: ensayo del 4 de noviembre de 2026

Los siguientes resultados pertenecen al ensayo anterior a la política de pruebas exclusivamente desde UI. Se conservan como evidencia histórica; no significan que hoy se hayan recorrido todos los botones ni sustituyen la auditoría actual.

El detalle verificable está en [docs/local-integration-2026-11-04.json](docs/local-integration-2026-11-04.json). Se aprobaron 139 pruebas del backend sobre PostgreSQL real, 7 pruebas de paneles, 10 comprobaciones HTTP del recorrido completo y 6 de cierre automático. Tres casos que requieren Redis quedaron sin ejecutar (dos omitidos y uno deseleccionado). El apagado y encendido de API y PostgreSQL conservó disponibilidad, inventario, pedidos y valoraciones.

En el navegador se creó el pedido ficticio #3 desde Alumnos y se aceptó, preparó y entregó desde Cocina. Se comprobó el chat de Cocina, el historial y las valoraciones con seguimiento en Administración. La pantalla de Alumnos mostró el error al detener la API y recuperó el pedido al reiniciar. Cocina y Administración se revisaron en tamaño móvil y PC. Se corrigió la traducción de métodos de pago canónicos en paneles y una incompatibilidad de fechas entre versiones de PowerShell en los controles de procesos.

En aquel ensayo se usaron `tools/test_integrated_flow.py` y `tools/test_integrated_closures.py`; sus reportes y los datos creados se conservan como antecedentes. Esos scripts realizan escrituras y **no se deben repetir durante la auditoría actual**. Tampoco se borra historial ni se cambian fechas para forzar otra ejecución: el cierre automático solo se procesa una vez por día/local. La persistencia y los cierres se comprueban ahora con operaciones desde UI y espera real cuando sea necesaria.
