# Backend de SnackUP

API propia para conectar la aplicación del alumno con los paneles existentes de Administración y Cocina. Implementación inicial con FastAPI, SQLAlchemy, PostgreSQL en producción, sesiones JWT con renovación mediante cookie, correo SMTP y eventos WebSocket respaldados por un outbox SQL y Redis.

**Estado:** el código y los procedimientos están preparados para validarse e integrarse. No hay servidor universitario, dominio, servicio SMTP ni padrón institucional confirmados. La capacidad de **1,000 alumnos simultáneos más personal es un objetivo pendiente de medición**, no una certificación. Los datos de prueba nunca se crean automáticamente al iniciar la API.

## Contratos y alcance

- [Contrato de los 43 endpoints de paneles](contracts/panels.openapi.json), conservado respecto de la entrega del frontend.
- [API del alumno y verificación de identidad](API_ALUMNOS.md) y [contrato de extensiones](contracts/extensions.openapi.json).
- [Manual funcional de los paneles](../docs/MANUAL_BACKEND_PANELES.md) y [protocolo de tiempo real](../docs/integracion/REALTIME.md). Las referencias históricas a 500 sesiones del manual quedan sustituidas por el objetivo de 1,000 alumnos indicado aquí.

El backend implementa cuentas, permisos, solicitudes, locales, catálogo, imágenes, pedidos, reserva de existencias, recogida, opiniones con carrera/grupo, seguimiento e historial. El panel administrativo nunca opera cocina; solo el maestro administra cuentas y autoriza solicitudes. El alumnado utiliza sus propias rutas y solo sus pedidos.

El pago disponible es **efectivo al recoger** (`cash`, `pay_at_pickup`); no existe una pasarela ni conciliación bancaria. La recogida exige el código del pedido en estado listo: **no se usa matrícula como alternativa**. La API del alumno existe; queda conectar y validar su interfaz. Google/inicio de sesión institucional no está habilitado. Verificar `GET /api/v1/auth/options` en lugar de mostrar capacidades que no están configuradas.

## Correo, carrera e institución

El correo institucional identifica a la persona. La posesión del correo se comprueba con un enlace de un solo uso; su carrera y grupo se obtienen de un **padrón autorizado**, no se deducen del nombre del correo ni se aceptan del formulario del alumno. No se han inventado dominios, reglas de matrícula o datos de la universidad.

El padrón distingue `student` y `staff`; pertenecer al personal no concede por sí solo permisos administrativos de SnackUP. Las solicitudes del personal siguen requiriendo revisión de la cuenta maestra, correo verificado, dominio permitido cuando corresponda y asignación exclusiva de local para un operador activo.

El adaptador inicial es una importación CSV privada y transaccional. Puede sustituirse o complementarse después con una API/base institucional, conservando la validación y los IDs. Las columnas exactas del CSV UTF-8 son:

```csv
email,institutional_id,display_name,kind,career_id,career_name,group_id,group_name,is_active
```

Cada alumno requiere carrera; el grupo es opcional y debe pertenecer a esa carrera. `kind` admite `student` o `staff`; `is_active` admite `true/false` o `1/0`. Los IDs académicos deben ser oficiales y estables. La importación actualiza por correo, rechaza conflictos y revierte el lote ante errores. **Omitir una persona del CSV no la elimina ni la suspende:** se requiere una fila explícita con `is_active=false`. Resolver cambios de correo/identidad institucional de manera controlada. Guardar la procedencia mediante `--source`.

## Desarrollo local

Requisitos: Python 3.12. Los siguientes comandos se ejecutan desde `backend/`; activar el entorno virtual según el sistema:

```bash
python -m venv .venv
# Linux/macOS: source .venv/bin/activate
# PowerShell: .\.venv\Scripts\Activate.ps1
python -m pip install -r requirements.lock
```

Copiar `.env.example` a `.env` y completar la configuración. Generar `SNACKUP_SECRET_KEY` con un generador criptográfico; mantenerlo privado y estable. Definir los IDs/nombres reales de institución/cafetería y los dominios autorizados cuando sean proporcionados. Un entorno de desarrollo puede utilizar valores ficticios claramente identificados. No versionar `.env`, padrones ni contraseñas.

SQLite se admite únicamente para desarrollo y pruebas funcionales. **No demuestra bloqueo de filas, concurrencia ni capacidad de PostgreSQL.** En producción la configuración exige PostgreSQL, Redis y HTTPS.

```bash
python -m alembic upgrade head
python -m snackup.cli create-master --email EMAIL --name "NOMBRE"
python -m snackup.cli import-roster /ruta/privada/padron.csv --source "PROCEDENCIA_AUTORIZADA" --dry-run
python -m snackup.cli import-roster /ruta/privada/padron.csv --source "PROCEDENCIA_AUTORIZADA"
uvicorn snackup.main:create_app --factory --host 0.0.0.0 --port 8000
```

`create-master` pide y confirma la contraseña mediante `getpass`, sin eco ni argumento de línea de comandos. Crea solo el primer maestro y no sobrescribe otra cuenta. **El responsable autorizado debe verificar la identidad del primer maestro por un procedimiento privado**; este bootstrap marca su correo como verificado y no lo valida por SMTP. Para recuperar su contraseña desde el servidor:

```bash
python -m snackup.cli reset-master-password --email EMAIL
```

La recuperación revoca sus sesiones. No hay cuentas ni contraseñas predeterminadas, endpoint público de bootstrap o elevación a maestro desde el registro.

La API estará en `SNACKUP_PUBLIC_ORIGIN/api/v1/`; en desarrollo, `/api/docs` muestra la documentación generada. El cliente debe usar ese mismo origen exacto, también en el encabezado `Origin` del login/refresh/logout. Los healthchecks son `/health/live` y `/health/ready`.

## Correo y configuración pendiente

Configurar `SNACKUP_SMTP_HOST`, puerto, remitente y credenciales privadas. Producción requiere TLS en puerto 465 o STARTTLS. La aplicación no inventa un envío exitoso cuando SMTP no está disponible: deshabilita el autorregistro anunciado y rechaza las operaciones que lo necesitan. Dar de alta cuentas desde el maestro también inicia verificación por correo. Los enlaces expiran y se consumen una sola vez; cambiar el correo retira su verificación y revoca sesiones.

Solicitar a la universidad: acceso de despliegue, sistema operativo, dominio y DNS, posibilidad de exponer 80/443, salida SMTP, valores institucionales autorizados, padrón/API y política de actualización/bajas. El servidor solicitado de 6–8 vCPU, 16 GB de RAM, SSD de 100–200 GB y red de 100 Mbps o más es una referencia de dimensionamiento; debe confirmarse antes de desplegar.

## Despliegue con Docker Compose

El despliegue propuesto usa PostgreSQL **17**, Redis **7.4** y Caddy **2**. Sus etiquetas mantienen la versión mayor seleccionada y reciben actualizaciones de mantenimiento; registrar los digests exactos al liberar una versión y probar las actualizaciones. [Política oficial de soporte de PostgreSQL](https://www.postgresql.org/support/versioning/).

La API y el proxy corren como UID/GID `10001`, sin privilegios de root y con raíz de solo lectura. PostgreSQL y Redis usan sus imágenes oficiales, volúmenes persistentes y una red interna sin puertos publicados. La API usa un rol SQL distinto del administrador, sin `SUPERUSER`, `CREATEDB` ni `CREATEROLE`; puede administrar sus tablas para aplicar migraciones. El proxy conserva certificados en sus propios volúmenes y publica solamente 80/443. El directorio de imágenes se conserva en el volumen `media`.

1. Instalar Docker Engine y Compose en el servidor asignado. Crear `.env` privado y completar todas las variables exigidas por Compose. Usar contraseñas distintas para `POSTGRES_PASSWORD` (administrador), `SNACKUP_DB_PASSWORD` (aplicación), `REDIS_PASSWORD` y `SNACKUP_SECRET_KEY`; generar valores hexadecimales aleatorios evita problemas de codificación en las URL. No utilizar los valores públicos del workflow de CI.
2. Configurar `SNACKUP_DOMAIN` con el dominio real, `TLS_ACME_EMAIL` con el contacto autorizado y DNS apuntando al servidor. Caddy obtiene y renueva TLS cuando ese dominio es accesible. Si la universidad termina TLS en otro proxy, adaptar esa capa con su equipo; no publicar una copia HTTP como solución final.
3. Comprobar que `SNACKUP_EDGE_SUBNET` no colisiona con la red de la universidad/VPN y que `SNACKUP_PROXY_IP` pertenece a esa subred. Uvicorn solo confía en los encabezados reenviados por esa IP; no sustituirla por `*`. La API tiene salida de red para SMTP, pero no expone su puerto 8000 al host.
4. Desde `backend/`, desplegar en este orden:

```bash
docker compose config --quiet
docker compose build --pull
docker compose up -d db redis
docker compose run --rm migrate
docker compose up -d api proxy
docker compose ps
docker compose exec api python -m snackup.cli create-master --email EMAIL --name "NOMBRE"
```

`depends_on` espera healthchecks de SQL/Redis y el proxy espera la API lista. Las migraciones son un paso explícito, no se ejecutan en cada worker. La primera inicialización de PostgreSQL crea el rol de aplicación con `deploy/init-db.sh`; cambiar contraseñas en `.env` posteriormente **no cambia automáticamente las credenciales del volumen existente**. Coordinar su rotación en SQL/Redis y los servicios.

Para importar un padrón externo sin copiarlo al repositorio o a la imagen:

```bash
docker compose run --rm --no-deps -v /ruta/privada/padron.csv:/input/padron.csv:ro api python -m snackup.cli import-roster /input/padron.csv --source "PROCEDENCIA_AUTORIZADA" --dry-run
```

Revisar el resultado y repetir sin `--dry-run` para persistirlo. El padrón debe ser legible por el usuario del contenedor. El uso de [`service_healthy`](https://docs.docker.com/compose/how-tos/startup-order/) y la [red interna](https://docs.docker.com/reference/compose-file/networks/) no sustituye controles de firewall o acceso al host.

### Frontend opcional del mismo origen

El Dockerfile no fabrica ni descarga una compilación Flutter. Primero preparar el frontend revisado, con backend REST, sin `REVIEW_MODE`, URL base `/api/v1/` y `index.html` presente. Definir `SNACKUP_FRONTEND_DIR` como su ruta absoluta en el host y aplicar el override:

```bash
docker compose -f compose.yaml -f deploy/compose.frontend.yaml up -d api proxy
```

El montaje es de solo lectura; la API sirve esos archivos y Caddy mantiene el mismo origen HTTPS para web, REST, imágenes y WebSocket. Un directorio inexistente no se crea silenciosamente. [Comportamiento del proxy Caddy](https://caddyserver.com/docs/caddyfile/directives/reverse_proxy).

### Ajuste inicial y operación

Dos workers son un punto inicial, no una promesa de capacidad. Con `pool_size=10` y `max_overflow=5` cada worker puede abrir hasta 15 conexiones; presupuestar también CLI, migraciones y monitoreo antes de aumentar workers. Se configuran `statement_timeout=20000 ms` y `lock_timeout=5000 ms` en PostgreSQL; ajustar con mediciones y planificar migraciones largas por separado.

Medir tiempos HTTP y errores, CPU/RAM, conexiones/esperas/locks SQL, ocupación SSD, conexiones WebSocket, retraso del outbox y fallos SMTP. Los eventos son avisos: REST conserva el estado confirmado. Los clientes deben reconciliar tras reconectarse. No registrar contraseñas, tokens, cookies, padrones o cuerpos de solicitudes. Conservar logs operativos con una retención definida; revisar también la retención de outbox, sesiones e idempotencia antes de operación prolongada.

## Respaldos y restauración

Desde el servidor Linux, `sh deploy/backup.sh /ruta/privada/de/respaldos` genera un `pg_dump` de formato personalizado, un archivo de imágenes y checksums. No imprime credenciales ni borra datos. Hacer el respaldo durante una ventana controlada o con una estrategia de snapshots consistente; copiarlo cifrado fuera del servidor. Un volumen en el mismo SSD no constituye por sí solo un respaldo.

Antes de aceptar producción, restaurar el dump con `pg_restore --exit-on-error --single-transaction` en **otra base vacía**, restituir las imágenes en otro volumen y validar login, pedidos, referencias y totales. No restaurar encima de producción como prueba. Para roles de propietario, recrear los mismos roles o restaurar con `--no-owner` bajo el rol de aplicación autorizado. Acordar RPO/RTO y retención con la universidad. Cambios de versión mayor de PostgreSQL requieren un procedimiento de migración, no solo cambiar la etiqueta del contenedor.

## Pruebas y evidencia

```bash
python -m ruff check snackup tests deploy load
python -m pytest -q --junitxml=reports/pytest-local.xml
python -m alembic check
```

Sin `SNACKUP_TEST_DATABASE_URL`, la suite funcional usa SQLite; las pruebas que necesitan PostgreSQL se omiten explícitamente. Configurar esa variable con una **base de pruebas exclusiva** para que la suite cree y elimine sus esquemas de ensayo. `SNACKUP_TEST_REDIS_URL` debe apuntar a un Redis de pruebas; habilita las comprobaciones del broker real. Nunca usar credenciales ni direcciones productivas para ejecutar la suite.

El [workflow de backend](../.github/workflows/backend.yml) instala el lock exacto, corre lint, aplica/verifica migraciones, ejecuta la suite con PostgreSQL/Redis, construye las imágenes y valida Caddy. También arranca un stack Compose aislado hasta el estado saludable de la API, con el rol SQL de aplicación, y elimina sus volúmenes de prueba al terminar. Publica los XML de pruebas y el reporte de respuestas contrastadas con el contrato. La existencia del workflow no significa que una ejecución haya pasado: verificar el resultado y el commit en GitHub Actions. En este entorno local no se dispone de Docker/PostgreSQL; la construcción y compatibilidad real se comprobarán en CI o en el servidor de integración.

La metodología y comandos de carga están en [load/README.md](load/README.md). El escenario está desactivado por defecto, requiere confirmación explícita de destino aislado y credenciales externas; no se lanza automáticamente contra ningún servidor. Entregar el reporte medido antes de afirmar soporte para 1,000 alumnos.
