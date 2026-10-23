# Contenedor de Cocina y Administración

Esta imagen compila el portal REST `app/lib/main_portal_api.dart` de
`codex/entrega-paneles-rest`. El contenedor sirve exclusivamente sus archivos web;
el backend y la aplicación de alumnos tienen sus propias imágenes y servicios.
Las dependencias Firebase que conservan otros entrypoints del repositorio no
se inicializan en este portal.

## Construir y ejecutar

```sh
docker compose up --build -d
curl --fail http://localhost:8082/healthz
```

El servicio `cocina` utiliza `snackup-cocina:local` y escucha en 8080 dentro
del contenedor. Publica por defecto `127.0.0.1:8082`. Flutter 3.32.0 se fija por
versión y digest en la etapa de compilación; el runtime contiene Caddy 2.11.7,
sin SDK Flutter/Dart. Ejecuta el usuario `10001:10001`, con filesystem de solo
lectura y únicamente `/tmp` escribible mediante tmpfs. No recibe credenciales
administrativas ni de proveedores externos en el build.

## Origen, API y subruta

El build utiliza `BACKEND=rest`, `REVIEW_MODE=false` y
`API_BASE_URL=/api/legacy/v1/`. Esa ruta es necesaria para el contrato que
consume este portal: sus DTO y su WebSocket nativo todavía pertenecen a la API
de compatibilidad. El endpoint canónico `/api/v1/` y Socket.IO del backend V3
requieren una adaptación funcional del cliente; cambiar una URL no la realiza.
`API_BASE_URL` se puede pasar como argumento de compilación para instalaciones
con otro punto de entrada al mismo contrato legacy. No contiene un secreto ni
es una variable que pueda cambiarse únicamente al arrancar el contenedor.

Para probar el portal con un backend alcanzable desde la red del contenedor:

```sh
SNACKUP_API_UPSTREAM=http://api:8000 docker compose up --build -d
```

El upstream admite únicamente un origen HTTP/HTTPS sin credenciales, ruta ni
query. El proxy opcional conserva URI, método y Host, y permite el upgrade
WebSocket de `/api/legacy/v1/realtime`; también reserva `/socket.io/` y `/media/`.
El backend debe permitir el origen público real. Si no se configura el upstream,
las rutas reservadas devuelven `503 BACKEND_NOT_CONFIGURED`, nunca el HTML SPA.

`WEB_BASE_HREF` es un argumento de compilación, con `/` como valor por defecto.
Para el despliegue conjunto:

```sh
docker build --build-arg WEB_BASE_HREF=/paneles/ -t snackup-cocina:local .
```

El proxy exterior redirige `/paneles` a `/paneles/` y elimina el prefijo
`/paneles/` antes de enviar la petición a este servicio. El HTML compilado
mantiene `<base href="/paneles/">` para resolver sus recursos. Alumnos se sirve
en `/`; API, Socket.IO y medios se envían directamente al backend, bajo el mismo
origen HTTPS. Las cookies y Origin mantienen ese origen; el frontend no añade
reglas CORS. El reset de contraseña debe enlazar a
`/paneles/#/reset-password?token=...` en esta disposición.

## Actualizaciones y validación

El portal no registra un service worker propio. La compilación desactiva el
worker generado por Flutter y los recursos usan `Cache-Control: no-cache` para
revalidar sus nombres estables tras una publicación. Las rutas SPA usan
`index.html`; un recurso estático inexistente devuelve 404, y las rutas de API
conservan su respuesta independiente.

El workflow `web-container.yml` compila y arranca dos variantes, `/` y
`/paneles/`. Comprueba usuario sin privilegios, ausencia del SDK en runtime,
health, recursos, fallback y rutas reservadas. La comprobación de los artefactos
también rechaza marcas conocidas del modo de demostración. Estas verificaciones
no sustituyen una prueba de login, permisos, pedidos y entrega contra una API
configurada, ni implementan chat, horarios o las nuevas rutas de V3.2.

## Fuentes técnicas

- [Inicialización Flutter web](https://docs.flutter.dev/platform-integration/web/initialization)
- [Imagen Flutter 3.32.0 y digest](https://github.com/cirruslabs/docker-images-flutter/pkgs/container/flutter/426799929?tag=3.32.0)
- [Caddy 2.11.7](https://github.com/caddyserver/caddy/releases/tag/v2.11.7)
- [Rutas SPA y subaplicaciones en Caddy](https://caddyserver.com/docs/caddyfile/patterns)
- [Proxy y WebSockets en Caddy](https://caddyserver.com/docs/caddyfile/directives/reverse_proxy)
- [Builds por etapas de Docker](https://docs.docker.com/build/building/multi-stage/)
