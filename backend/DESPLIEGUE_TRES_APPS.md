# SnackUP: tres ramas y tres aplicaciones Docker

## 1. Qué se separó

| Aplicación | Rama | Fuente | Imagen local | Entrada |
| --- | --- | --- | --- | --- |
| API | `codex/backend-api-v3-fastapi` | `backend/` | `snackup-backend:local` | FastAPI, puerto interno 8000 |
| Alumnos / PWA | `codex/usuarios-pwa` | Flutter en raíz | `snackup-usuarios:local` | `lib/main.dart`, puerto interno 8080 |
| Cocina / Administración | `codex/entrega-paneles-rest` | Flutter en `app/` | `snackup-cocina:local` | `app/lib/main_portal_api.dart`, puerto interno 8080 |

Cada rama contiene el código ejecutable de su aplicación. El backend mantiene
sus contratos y documentación de compatibilidad; los paneles mantienen sus
repositorios REST y herramientas de revisión. El historial de Git no se borra.
`main` y `respaldo/2026-10-13-antes-restablecimiento` no se modifican.

**Alcance de alumnos:** la rama se deriva del `main` real, commit `b7abff6`.
Continúa utilizando Firebase y todavía incluye las pantallas históricas de
Cocina que el propietario indicó que retirará. No se inventó un adaptador REST
ni se eliminaron esas pantallas dentro de una tarea de contenedores. La auditoría
de integración está en [AUDITORIA_APP_Y_API_V3_2.md](AUDITORIA_APP_Y_API_V3_2.md).

Las imágenes web usan una fase Flutter de compilación y una fase Caddy para
servir los archivos. El SDK no se incorpora a la imagen final. Los servicios
de aplicación corren como usuario `10001:10001`, con raíz de solo lectura,
`/tmp` temporal, sin capacidades Linux adicionales ni puertos publicados al
host. Cada frontend expone `/healthz` internamente. La API conserva sus
healthchecks `/health/live` y `/health/ready`.

## 2. Un solo origen público

`deploy/Caddy.apps` distribuye las peticiones del dominio autorizado:

| Ruta pública | Destino | Tratamiento |
| --- | --- | --- |
| `/api/*` | API | Conserva el prefijo completo, incluido `/api/legacy/v1/realtime` |
| `/socket.io/*` | API | Socket.IO V3 con transporte WebSocket |
| `/media/*` | API | Imágenes publicadas por el backend |
| `/health/live`, `/health/ready` | API | Estado del proceso y dependencias |
| `/paneles` | Redirección 308 | Envía a `/paneles/` |
| `/paneles/*` | Cocina / Administración | Quita solo `/paneles` antes de servir archivos |
| Resto, incluido `/` | Alumnos | PWA y navegación Flutter |

La imagen del portal se compila con `WEB_BASE_HREF=/paneles/`; así sus recursos
se solicitan bajo ese prefijo aunque el servidor interno los tenga en `/`.
La base REST se mantiene absoluta respecto del origen:
`API_BASE_URL=/api/legacy/v1/`.

Mantener un origen HTTPS evita cambiar las reglas actuales de cookies y
validación de `Origin`. No se abre CORS a dominios arbitrarios. PostgreSQL y
Redis solo pertenecen a la red interna `data`. El proxy publica 80/443, conserva
sus certificados en volúmenes y tiene una IP interna explícita que la API
reconoce como proxy de confianza.

La app de alumnos aún no tiene pantalla de restablecimiento de contraseña.
El despliegue conjunto fija `SNACKUP_PASSWORD_RESET_FRONTEND_PATH=/paneles/`
para que los correos abran `https://DOMINIO/paneles/#/reset-password?token=…`.
La opción por defecto `/` conserva las instalaciones anteriores. Solo admite
una ruta local; no acepta un dominio de redirección externo. La verificación de
correo sigue llegando a su endpoint del backend.

## 3. Preparar los tres checkouts

Ejecutar en un directorio de trabajo vacío en el servidor o equipo de build:

```bash
git clone --single-branch --branch codex/backend-api-v3-fastapi https://github.com/Gabino-RG/SnackUP-core.git snackup-backend
git clone --single-branch --branch codex/usuarios-pwa https://github.com/Gabino-RG/SnackUP-core.git snackup-usuarios
git clone --single-branch --branch codex/entrega-paneles-rest https://github.com/Gabino-RG/SnackUP-core.git snackup-cocina
cd snackup-backend/backend
cp .env.example .env
```

Completar `.env` en privado con el dominio real, el contacto TLS, institución,
cafetería, dominios de correo permitidos, contraseñas distintas de SQL/Redis,
clave de aplicación y SMTP. No publicar `.env`, padrones ni credenciales push.
La configuración pública de Firebase web no es un secreto de servidor, pero
el proyecto, los dominios permitidos y sus reglas deben corresponder a la app
que se pretende ejecutar. No sustituirlo por una cuenta de servicio dentro de
la imagen web.

El overlay toma por defecto los directorios vecinos `../../snackup-usuarios` y
`../../snackup-cocina`. Para otra estructura, añadir rutas absolutas a `.env`:

```dotenv
SNACKUP_USERS_CONTEXT=/ruta/absoluta/snackup-usuarios
SNACKUP_PANELS_CONTEXT=/ruta/absoluta/snackup-cocina
```

Las rutas relativas de **todos** los archivos Compose se resuelven desde el
primer archivo, `backend/compose.yaml`, no desde `backend/deploy/`. Revisar el
resultado con `docker compose ... config --quiet`, sin volcar valores secretos
en logs compartidos.

## 4. Construir y arrancar

Desde `snackup-backend/backend/`, usar siempre los dos archivos en este orden:

```bash
docker compose -f compose.yaml -f deploy/compose.apps.yaml config --quiet
docker compose -f compose.yaml -f deploy/compose.apps.yaml build --pull
docker compose -f compose.yaml -f deploy/compose.apps.yaml up -d db redis
docker compose -f compose.yaml -f deploy/compose.apps.yaml run --rm migrate
docker compose -f compose.yaml -f deploy/compose.apps.yaml up -d --wait api usuarios cocina proxy
docker compose -f compose.yaml -f deploy/compose.apps.yaml ps
```

Las migraciones son un paso explícito. No se ejecutan en cada worker ni en
paralelo desde los frontends. En una actualización con datos, aplicar antes el
[procedimiento de respaldo y migración V3](API_V3_FASTAPI.md#8-migración-y-actualización-de-una-instalación-existente).

Crear el primer maestro únicamente en la primera instalación autorizada:

```bash
docker compose -f compose.yaml -f deploy/compose.apps.yaml exec api python -m snackup.cli create-master --email EMAIL --name "NOMBRE"
```

La contraseña se introduce sin eco. Importar el padrón autorizado siguiendo
el [README del backend](README.md). No existen usuarios de producción
predeterminados, ni datos de prueba que se creen durante el arranque.

Tras el arranque, verificar el certificado HTTPS, la PWA en `/`, el portal en
`/paneles/`, la API en `/api/v1/auth/options` y un correo de recuperación de una
cuenta controlada. Probar login, refresh y cierre de sesión del portal en el
navegador; las cookies seguras necesitan HTTPS. La pantalla del alumno seguirá
consultando Firebase hasta que se haga su integración REST.

La ausencia de servidor, dominio, SMTP o padrón autorizados impide dar por
completada una instalación institucional. Los comandos anteriores son un
procedimiento ejecutable, no evidencia de un despliegue que ya exista.

## 5. Builds, actualizaciones y funcionamiento sin conexión

Las ramas web incluyen Dockerfile, configuración Caddy, Compose independiente
y un workflow de build/smoke. Se pueden validar sin clonar el backend. Su
variable opcional `SNACKUP_API_UPSTREAM` permite un proxy al backend en una
instalación independiente; debe ser un origen HTTP/HTTPS válido sin usuario,
contraseña, query ni ruta. El despliegue conjunto no la necesita: el proxy
exterior enruta las peticiones directamente.

Los builds de web reciben configuración pública en compilación. Cambiar
`WEB_BASE_HREF` o `API_BASE_URL` exige reconstruir la imagen. No intentar cambiar
un `--dart-define` mediante una variable puesta únicamente al arrancar Caddy.

La PWA usa una pantalla de desconexión y excluye API, Socket.IO, medios, paneles,
solicitudes autenticadas y operaciones de escritura de su caché. No promete
crear pedidos sin conexión ni mantener un saldo/inventario local. El portal
operativo no instala un worker que pueda cachear respuestas de negocio.

Para una liberación reproducible, anotar el SHA de cada una de las tres ramas
y los digests de las imágenes. Después de construir y validar una versión,
promover esas mismas imágenes entre entornos. Las etiquetas locales son útiles
para construir; no son un identificador inmutable de una liberación.

Conservar volúmenes SQL, Redis, medios y certificados al actualizar. `down`
detiene servicios; **no usar `down --volumes` sobre datos reales**. La limpieza
con volúmenes en CI se limita al proyecto efímero de prueba.

## 6. Qué verifica cada entrega

La suite del backend cubre contratos, permisos, migraciones y concurrencia con
PostgreSQL/Redis. Los workflows de frontend construyen sus imágenes y validan
su servicio HTTP, healthcheck, prefijos y proxy. La configuración conjunta
se valida con ambos archivos Compose y Caddy.

El workflow [apps-integration.yml](../.github/workflows/apps-integration.yml)
descarga las tres ramas y registra sus SHA, construye las cuatro imágenes
(tres aplicaciones y el proxy), aplica las migraciones y arranca los seis
servicios en un proyecto efímero. Comprueba las dos interfaces, recursos y
prefijos, rutas de API y el upgrade/rechazo sin credenciales de Socket.IO.
`deploy/compose.apps.ci.yaml` utiliza HTTP solo en el proxy de esa prueba y
publica únicamente `127.0.0.1:18080`; no se usa para producción. Su limpieza
elimina únicamente el proyecto de CI identificado por la ejecución. Los
artefactos registran las fuentes exactas y el resultado, sin cuerpos privados.

Esas comprobaciones no sustituyen una prueba de extremo a extremo del alumno
contra FastAPI, porque ese cliente aún usa Firebase. Tampoco acreditan 1,000
usuarios simultáneos ni entrega real SMTP/push. Consultar resultados por commit
en GitHub Actions y [VALIDACION_V3.md](VALIDACION_V3.md); distinguir siempre un
workflow preparado de una ejecución que haya terminado correctamente.

## Referencias técnicas

- [Docker: combinación de archivos Compose y resolución de rutas](https://docs.docker.com/compose/how-tos/multiple-compose-files/merge/).
- [Docker: orden de arranque y healthchecks](https://docs.docker.com/compose/how-tos/startup-order/).
- [Caddy: eliminación del prefijo con handle_path](https://caddyserver.com/docs/caddyfile/directives/handle_path).
- [Flutter: compilación y publicación web](https://docs.flutter.dev/deployment/web).
