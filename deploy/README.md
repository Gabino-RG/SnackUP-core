# Contenedor de la aplicación de alumnos

Esta rama parte de `main` (`b7abff6593e84dda69ad2909abbf699dd17ff890`).
Conserva su aplicación Flutter y su integración actual con Firebase, incluidas
las pantallas de Cocina que el propietario retirará en otro cambio. Crear esta
imagen no conecta los flujos de alumnos con la API SQL ni implementa chat V3.2.

## Construir y ejecutar

```sh
docker compose up --build -d
curl --fail http://localhost:8081/healthz
```

El servicio `usuarios` utiliza la imagen `snackup-usuarios:local`, escucha en
8080 dentro del contenedor y publica por defecto `127.0.0.1:8081`. Tiene su
propio proceso Caddy; no ejecuta API, PostgreSQL, Redis ni Flutter en producción.
Flutter 3.32.0 se fija por versión y digest para compilar; Caddy 2.11.7 sirve el
resultado como usuario `10001:10001`. El único directorio que necesita escritura
es `/tmp`, montado como tmpfs. El build no recibe credenciales de servidor.

La configuración pública Firebase que ya utilizaba la app permanece en su
código. Las credenciales administrativas, SMTP y las claves de los proveedores
push pertenecen al backend y no deben pasarse como argumentos de compilación.

## Origen y subruta

`WEB_BASE_HREF` es un argumento de build y termina en `/`:

```sh
docker build --build-arg WEB_BASE_HREF=/alumnos/ -t snackup-usuarios:local .
```

En ese caso el proxy exterior debe servir `/alumnos/*` quitando ese prefijo
antes de enviar la petición a este contenedor. Para el despliegue conjunto,
alumnos utiliza `/` y Cocina/Admin `/paneles/`, cada aplicación con su imagen.
Cambiar la variable después del build no modifica los archivos ya compilados.

El proxy HTTPS conjunto envía `/api/*`, `/socket.io/*` y `/media/*` directamente
al backend; las dos aplicaciones conservan el mismo origen. El frontend no
habilita CORS ni modifica cookies u Origin.

Para una instalación standalone se puede establecer `SNACKUP_API_UPSTREAM`,
por ejemplo `http://api:8000`, siempre que ese nombre sea alcanzable desde su red
Docker. Solo admite un origen HTTP/HTTPS sin credenciales, ruta ni query. Conserva
la URI, el método y Host; Caddy soporta el upgrade WebSocket. El backend debe
estar configurado para el origen público real. Sin la variable, las rutas API,
Socket.IO y medios responden `503 BACKEND_NOT_CONFIGURED`; nunca devuelven el
HTML de la aplicación. Este proxy opcional no sustituye los repositorios Firebase.

## Alcance de la PWA

Se conserva el manifiesto instalable y se corrige el arranque oficial mediante
`flutter_bootstrap.js`. `pwa.js` registra un único worker propio en el scope de
la aplicación; si encuentra uno ajeno en ese mismo scope, no añade otro. El
build desactiva el worker generado por Flutter.

El worker propio guarda únicamente `offline.html`, una página genérica de
desconexión. No almacena pedidos, perfiles, sesiones, respuestas Firebase ni
archivos privados. Excluye explícitamente `/api/`, `/socket.io/`, `/media/` y
`/paneles/`, otros orígenes, métodos distintos de GET y solicitudes con
Authorization. La app necesita conexión para operar; una pantalla sin conexión
no confirma un pedido. Registro e instalación requieren HTTPS o localhost y
dependen del soporte del navegador. Esto no agrega notificaciones Web Push:
su worker, permisos y registro del dispositivo requieren una integración posterior.

## Validación

`node deploy/test_pwa.cjs` verifica exclusiones, respuesta sin conexión y
registro sin sustituir un worker ajeno. El workflow `web-container.yml` compila
la imagen, comprueba que no contiene Flutter/Dart en el runtime, la arranca
con filesystem de solo lectura y prueba health, recursos, fallback SPA y errores
de rutas reservadas. Estas pruebas no usan cuentas reales ni prueban pedidos
contra Firebase o SQL.

## Fuentes técnicas

- [Inicialización Flutter web](https://docs.flutter.dev/platform-integration/web/initialization)
- [Flutter Web FAQ y service workers](https://docs.flutter.dev/platform-integration/web/faq)
- [Imagen Flutter 3.32.0 y digest](https://github.com/cirruslabs/docker-images-flutter/pkgs/container/flutter/426799929?tag=3.32.0)
- [Caddy 2.11.7](https://github.com/caddyserver/caddy/releases/tag/v2.11.7)
- [Rutas SPA y subaplicaciones en Caddy](https://caddyserver.com/docs/caddyfile/patterns)
- [Proxy y WebSockets en Caddy](https://caddyserver.com/docs/caddyfile/directives/reverse_proxy)
- [Builds por etapas de Docker](https://docs.docker.com/build/building/multi-stage/)
