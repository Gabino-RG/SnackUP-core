# SnackUP: un contenedor de aplicación y PostgreSQL

El nuevo requisito reemplaza la propuesta de tres contenedores de aplicaciones.
**Un contenedor `app` ejecuta FastAPI y sirve Alumnos, Cocina y Administración
en tres orígenes separados.** Incluye Caddy para HTTPS y Redis para coordinación interna.
PostgreSQL se mantiene en `db`, con su propio volumen persistente y sin publicar
su puerto. Son dos contenedores totales, uno de ellos para las tres aplicaciones.

| Origen o ruta | Componente |
|---|---|
| `https://snackup.example.edu/` | Alumnos con API REST en PostgreSQL |
| `https://cocina.snackup.example.edu/` | Cocina, solo cuentas de local |
| `https://administracion.snackup.example.edu/` | Administración, solo cuentas administrativas |
| `/api/v1/` | Contrato canónico FastAPI |
| `/api/legacy/v1/` | Compatibilidad del portal actual |
| `/socket.io/` | Socket.IO V3 |
| `/api/legacy/v1/realtime` | WebSocket del portal actual |
| `/media/` | Imágenes gestionadas por backend |

Los dominios son ejemplos configurables. Las rutas API pertenecen al origen de
cada interfaz; el backend valida su audiencia y rol. Las cookies de sesión no
incluyen atributo `Domain` y no se comparten entre portales. La ruta anterior
`/paneles/` devuelve 404 y no ofrece un selector ni redirecciones entre roles.

En esta rama las pantallas integradas de Alumnos, Cocina y Administración trabajan
contra FastAPI. Para incorporar datos institucionales anteriores, TI debe validar
la fuente y acordar el procedimiento de importación.

## Levantamiento en un servidor nuevo

Requisitos: Docker Engine y Compose **2.24.4 o posterior** con BuildKit,
acceso a los registros Docker y a los paquetes Python/Flutter, tres nombres DNS
apuntando al servidor y puertos públicos 80/443. El override de CI usa `!override`;
no se utiliza en producción. Las imágenes Flutter fijadas requieren un servidor
de construcción compatible con esa imagen (CI valida Linux amd64).

Desde esta rama, en `backend/`:

```bash
cp deploy/unified/env.example .env
# Completar .env; generar cada secreto separadamente con openssl rand -hex 32.
docker compose -f compose.unified.yaml config --quiet
docker compose -f compose.unified.yaml up -d --build --wait --wait-timeout 180
docker compose -f compose.unified.yaml ps
```

`SNACKUP_DOMAIN` es el dominio de Alumnos, sin esquema ni ruta. Configurar
`SNACKUP_KITCHEN_PUBLIC_ORIGIN` y `SNACKUP_ADMINISTRATION_PUBLIC_ORIGIN` con sus
orígenes HTTPS completos, en hostnames distintos de Alumnos y entre sí.
Caddy obtiene de esa configuración los nombres que debe servir; no hace falta
duplicarlos en otras variables de dominio. Las contraseñas generadas
en hexadecimal evitan caracteres reservados dentro de `DATABASE_URL`. Configurar
dominios institucionales reales y SMTP; el ejemplo no acredita acceso al padrón.
El enlace de recuperación de contraseña abre `/` en el origen correspondiente
al rol persistido de la cuenta; también se separan las cookies y el almacenamiento.
Los campos de secretos vacíos bloquean Compose, no generan credenciales por defecto.

El arranque espera PostgreSQL, abre Redis por un socket Unix privado, aplica
`alembic upgrade head` una sola vez y después inicia el proceso `snackup.jobs`, Uvicorn y Caddy. El proceso de tareas
ejecuta cierres, avisos y limpieza de chats cada minuto, con bloqueo PostgreSQL
y heartbeat incluido en el healthcheck; no se replica por worker HTTP. Uvicorn
ejecuta cada worker en un puerto loopback propio (8000–8007), y Caddy distribuye
peticiones y sockets con `least_conn`. Uvicorn conserva conexiones HTTP 130 s y
Caddy 30 s. Solo se confía en ese proxy. Redis no abre TCP.
El supervisor y sus hijos usan UID/GID 10001, sistema de archivos de imagen de
solo lectura, `/tmp` temporal y volúmenes de datos. Solo se publican 80/443.

Para preparar padrón o cuenta inicial, usar el CLI existente desde el contenedor:

```bash
docker compose -f compose.unified.yaml exec app python -m snackup.cli --help
```

Los comandos de padrón y cuenta inicial figuran en [README.md](README.md).
Para Web Push, guardar la clave VAPID de producción fuera del checkout, con
permiso de lectura para el UID 10001. Definir una ruta absoluta en
`SNACKUP_WEBPUSH_KEY_ON_HOST` y el contacto `SNACKUP_PUSH_WEBPUSH_SUBJECT` en el
archivo privado de entorno. Usar ambos archivos de Compose al crear o actualizar
el servicio con push habilitado:

```bash
docker compose -f compose.unified.yaml -f deploy/unified/compose.webpush.yaml config --quiet
docker compose -f compose.unified.yaml -f deploy/unified/compose.webpush.yaml up -d --build --wait
```

## Ajustes incorporados después de la prueba de carga

La composición transmite las variables de rendimiento de `.env` a la aplicación:

| Variable | Predeterminado | Uso |
|---|---|---|
| `SNACKUP_POOL_TIMEOUT_SECONDS` | 2 | Espera máxima por conexión SQL |
| `SNACKUP_ADMISSION_WAIT_SECONDS` | 5 | Cola asíncrona antes del handler |
| `SNACKUP_WRITE_CONCURRENCY` | 1 | Mutaciones SQL simultáneas por worker; login usa sus hilos propios |
| `SNACKUP_LOGIN_WAIT_SECONDS` | 8 | Cola de las olas de login |
| `SNACKUP_PASSWORD_CONCURRENCY` | 4 | Hilos dedicados a Argon2 por worker |
| `SNACKUP_OUTBOX_RETENTION_DAYS` | 7 | Antigüedad de publicaciones eliminables |
| `SNACKUP_OUTBOX_CLEANUP_BATCH` | 1000 | Máximo de publicaciones purgadas por minuto |

El pool sigue siendo 10 + 5 por worker. La admisión permite 11 peticiones HTTP
simultáneas por worker con esos valores y reserva cuatro plazas para tareas
auxiliares. La espera de admisión no retiene un hilo ni una conexión SQL; al
agotarse responde 503 con `Retry-After: 1`. El frontend debe conservar la misma
clave de idempotencia cuando reintente la creación del mismo pedido.

La batería de carga mide tres workers en el perfil base de cuatro CPU, y un
worker con dos hilos Argon2 en el perfil de dos CPU. Esas son configuraciones de
medición, no detección automática de hardware: definir `SNACKUP_WORKERS` y
`SNACKUP_PASSWORD_CONCURRENCY` según el perfil elegido. No modificar los
parámetros criptográficos de Argon2 para ocultar un límite de capacidad.

La purga afecta exclusivamente publicaciones antiguas del outbox; conserva
pedidos, transiciones, datos académicos, publicaciones pendientes y cualquier
publicación con push todavía pendiente. La reconexión real de Redis obliga a
los sockets afectados a reconectar y recuperar el estado por REST.

Protocolo reproducible: [pruebas de Fase C](load/phase_c/README.md). Las pruebas
siguen sin desplegar el servicio en producción ni migrar Firestore.

## Fuentes y construcción reproducible

Registrar el resultado de `git rev-parse HEAD` de la entrega y compilar desde una
copia limpia de esa revisión. El contexto del Dockerfile es la raíz del repositorio.
La primera etapa Flutter toma Alumnos de la raíz; desde `app/` se generan dos
builds de paneles, con `PORTAL_AUDIENCE=cocina` y `PORTAL_AUDIENCE=administracion`.
La imagen final incorpora la API de `backend/`. El archivo
`deploy/unified/Dockerfile.dockerignore` limita los archivos enviados al constructor.
Los tres builds incorporan el script de notificaciones propio. Todos usan base
`/`, cada uno en su origen, con service workers y suscripciones independientes.

El API del portal conserva `/api/legacy/v1/`. Cambiarlo a `/api/v1/` sin adaptar
payloads/roles/realtime rompería la integración. Los dos paneles implementan el
tratamiento del token de recuperación en la raíz de su propio origen.

Referencias de configuración: [contextos de Docker](https://docs.docker.com/build/concepts/context/),
[Compose build](https://docs.docker.com/reference/compose-file/build/),
[Caddy handle_path](https://caddyserver.com/docs/caddyfile/directives/handle_path).

## Persistencia, recuperación y transición desde el despliegue anterior

Volúmenes: `database` (PostgreSQL), `media`, `redis` (AOF) y `tls_data`. Detener
con `docker compose -f compose.unified.yaml down` conserva los volúmenes.
No usar `down --volumes` en producción.

Durante una ventana con las escrituras detenidas y los contenedores activos, ejecutar
`sh deploy/backup.sh --unified /ruta/privada/respaldos` desde `backend/`. El script
copia la base del servicio `db` y los archivos del volumen de `app`. Verificar el
archivo de sumas SHA-256 y conservar una copia cifrada fuera del host. En un
entorno aislado, restaurar el dump con `pg_restore --exit-on-error --single-transaction
--no-owner` sobre una base vacía y los medios en un volumen nuevo. Comprobar tablas,
pedidos, archivos y tiempo de recuperación. TI debe custodiar por separado las
claves de sesión y VAPID y acordar la retención, la pérdida máxima de datos y el
tiempo máximo de recuperación.

El proyecto nuevo se llama `snackup-unified`. **No reutiliza automáticamente** los
volúmenes del proyecto anterior `snackup`. Para una instalación existente, tomar
backup y comprobar restauración de PostgreSQL y medios; conectar los volúmenes
correctos con un override explícito o restaurar en el proyecto nuevo. No arrancar
ambos sobre los mismos puertos ni sobre la misma base durante una migración sin
coordinar las versiones. `up` aplica las migraciones existentes: respaldar antes
de actualizar una base con datos. Este cambio no migró ninguna base productiva.

No mezclar este archivo con `compose.yaml` ni `deploy/compose.apps.yaml`, que
describen la topología anterior. El comando nuevo usa exclusivamente
`-f compose.unified.yaml`.

Si Redis, Uvicorn o Caddy terminan, el supervisor detiene el resto y sale con
error; `restart: unless-stopped` reinicia el conjunto. Docker no reinicia por
un estado `unhealthy` aislado: supervisar ese estado en operación. La comprobación
de salud recorre Caddy → API → PostgreSQL/Redis y los HTML de ambas interfaces.
El puerto interno 8081 de diagnóstico solo escucha en loopback y no se publica.

Concentrar la aplicación facilita el arranque, pero también une sus reinicios:
un despliegue de frontend reinicia API y conexiones. No ejecutar réplicas de este
paquete sin externalizar Redis y revisar la coordinación/migraciones. No se
promete capacidad para 1.000 o 2.000 usuarios sin una prueba de carga.

## Pruebas y estado de entrega

`.github/workflows/unified-container.yml` construye la imagen, inicia una base
PostgreSQL vacía con usuario de aplicación no superusuario, comprueba ambas
interfaces, errores API y upgrade Socket.IO, provoca la salida de Redis y verifica
la recuperación completa. No envía correo ni notificaciones a usuarios reales.
El override `deploy/unified/compose.ci.yaml` publica únicamente HTTP en loopback y
**no se debe usar en el servidor público**.

La validación local de rutas utiliza Caddy real y HTML sintético. La compilación
Flutter, los montajes Docker y el ciclo de arranque completo deben acreditarse
con el workflow del commit correspondiente; no con la sola existencia de archivos.
Tampoco se ha emitido un certificado del dominio real ni desplegado al servidor.
