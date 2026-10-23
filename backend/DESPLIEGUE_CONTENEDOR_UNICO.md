# SnackUP: un contenedor de aplicación y PostgreSQL

El nuevo requisito reemplaza la propuesta de tres contenedores de aplicaciones.
**Un contenedor `app` ejecuta FastAPI, sirve la PWA de usuarios y sirve
Cocina/Administración.** Incluye Caddy para HTTPS y Redis para coordinación interna.
PostgreSQL se mantiene en `db`, con su propio volumen persistente y sin publicar
su puerto. Son dos contenedores totales, uno de ellos para las tres aplicaciones.

| URL del mismo dominio | Componente |
|---|---|
| `/` | PWA de alumnos, actualmente Firebase |
| `/paneles/` | Cocina/Administración REST |
| `/api/v1/` | Contrato canónico FastAPI |
| `/api/legacy/v1/` | Compatibilidad del portal actual |
| `/socket.io/` | Socket.IO V3 |
| `/api/legacy/v1/realtime` | WebSocket del portal actual |
| `/media/` | Imágenes gestionadas por backend |

**No representa una migración completa de datos:** la PWA de usuarios sigue
utilizando Firebase y aún contiene la interfaz Cocina histórica. Su retirada y
adaptación REST requieren cerrar la [auditoría V3.2](AUDITORIA_FASTAPI_V3_2_ACTUAL.md).
No anunciar que todos los datos ya están en PostgreSQL.

## Levantamiento en un servidor nuevo

Requisitos: Docker Engine y Compose **2.24.4 o posterior** con BuildKit y contextos
adicionales; acceso a GitHub, registros Docker, paquetes Python/Flutter; dominio
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

`SNACKUP_DOMAIN` es solo el dominio, sin esquema ni ruta. Las contraseñas generadas
en hexadecimal evitan caracteres reservados dentro de `DATABASE_URL`. Configurar
dominios institucionales reales y SMTP; el ejemplo no acredita acceso al padrón.
Los campos de secretos vacíos bloquean Compose, no generan credenciales por defecto.

El arranque espera PostgreSQL, abre Redis por un socket Unix privado, aplica
`alembic upgrade head` una sola vez y después inicia Uvicorn y Caddy. Uvicorn
escucha exclusivamente en loopback y solo confía en ese proxy. Redis no abre TCP.
El supervisor y sus hijos usan UID/GID 10001, sistema de archivos de imagen de
solo lectura, `/tmp` temporal y volúmenes de datos. Solo se publican 80/443.

Para preparar padrón o cuenta inicial, usar el CLI existente desde el contenedor:

```bash
docker compose -f compose.unified.yaml exec app python -m snackup.cli --help
```

No pasar contraseñas a argumentos de shell. Los comandos y permisos del CLI se
describen en [README.md](README.md). Push necesita las credenciales/montajes de su
proveedor; el ejemplo lo deja deshabilitado y no prueba envíos externos.

## Fuentes y construcción reproducible

El Dockerfile está en `deploy/unified/Dockerfile`. El contexto principal es
`backend/`; los contextos adicionales son revisiones concretas del mismo repo:

- Alumnos: `a00d0bf4ecdae74a89f3afbe8ec3d0758efb8884`, rama `codex/usuarios-pwa`.
- Cocina/Administración: `19c81fdee29600d66d9dcb1a4f109a78aeba51f6`, rama `codex/entrega-paneles-rest`.

Las dos etapas Flutter se descartan al producir la imagen final; no hace falta
Flutter en el servidor de ejecución. Para probar cambios frontend locales,
definir `SNACKUP_USERS_CONTEXT` y `SNACKUP_PANELS_CONTEXT` con rutas de checkouts.
Revisar/actualizar los SHA al integrar nuevas versiones; no se toma silenciosamente
la punta de una rama. `WEB_BASE_HREF` queda `/` y `/paneles/` respectivamente.
La PWA excluye API, medios, sockets y paneles de su caché de navegación.

El API del portal conserva `/api/legacy/v1/`. Cambiarlo a `/api/v1/` sin adaptar
payloads/roles/realtime rompería la integración. Enlaces de recuperación apuntan
a `/paneles/`, que sí implementa el tratamiento del token.

Referencias de configuración: [contextos de Docker](https://docs.docker.com/build/concepts/context/),
[Compose build](https://docs.docker.com/reference/compose-file/build/),
[Caddy handle_path](https://caddyserver.com/docs/caddyfile/directives/handle_path).

## Persistencia, recuperación y transición desde el despliegue anterior

Volúmenes: `database` (PostgreSQL), `media`, `redis` (AOF) y `tls_data`. Detener
con `docker compose -f compose.unified.yaml down` conserva los volúmenes.
No usar `down --volumes` en producción.

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
