# Frontend de alumnos conectado a FastAPI

## Revisión pendiente de calificaciones

Queda pendiente reproducir el reporte de una valoración de platillo que terminó
en la cafetería. En la comprobación local se encontró una valoración de negocio
en `/rating`, sin reseña de producto. Esta versión conserva la implementación
actual; no cambia esa valoración ni considera resuelto el reporte.

Este cambio corresponde al equipo de alumnos. Usa el contrato canónico `/api/v1` del backend existente. No modifica `backend/`, sus modelos, migraciones, reglas de negocio ni las pantallas `lib/features/business/`.

Base: `feature/migracion-postgresql`, commit `f26ca222021c92b09f46873a41add42bc1d01b92`. Rama local de implementación: `codex/conectar-alumnos-api`.

## Funciones conectadas

Se recuperó también el catálogo de `codex/cliente-firebase`: tres negocios y
seis productos, con sus datos originales. Las funciones de reseñas de platillos,
lectura de opiniones y acceso al historial desde Perfil ya utilizan la API.
Consulta `CATALOGO_Y_FUNCIONES.md` para ver la procedencia, el alcance y la carga.

El modo actual usa exclusivamente `@utsjr.edu.mx`. Consulta
`REGISTRO_INSTITUCIONAL.md`: el padrón y SMTP institucionales siguen pendientes;
el filtro de dominio no sustituye la confirmación del correo.

- Inicio y cierre de sesión, renovación, registro institucional, reenvío de verificación, recuperación y cambio de contraseña.
- Registro con los documentos de protección de datos y privacidad, y casilla de aceptación obligatoria antes de habilitar **Crear cuenta**. La comprobación ocurre en el formulario; se conserva el contrato de cuatro campos del backend.
- Acceso exclusivo de ALUMNO; las cuentas COCINA/ADMIN utilizan el portal de los compañeros.
- Locales, destacados, menú, búsqueda, detalle, disponibilidad e imágenes.
- Favoritos con notas y carrito persistido por el servidor.
- Compra por negocio, cuatro métodos de pago admitidos, notas y recogida programada opcional.
- Pedidos activos, historial paginado, cancelación pendiente, volver a pedir, calificación del negocio de 0 a 5 y código privado de recogida.
- Actualizaciones Socket.IO por WebSocket y reconciliación REST al reconectar. No hay un temporizador que consulte periódicamente los pedidos.

La aplicación de alumnos ya no inicia Firebase ni carga sus scripts en el HTML. Se conservan las dependencias necesarias para que el código anterior de Cocina permanezca sin modificaciones; ese código no es una ruta del portal de alumnos.

## Requisitos

Flutter 3.32.x con Dart 3.8 o compatible, como el SDK usado en la imagen del equipo. Para el servidor de desarrollo incluido: Node.js 18 o posterior. Python 3.12 es necesario solo para la comprobación opcional del backend aislado.

```powershell
flutter pub get --enforce-lockfile
flutter test --no-pub
flutter build web --release --no-pub --no-web-resources-cdn --pwa-strategy=none
```

Se fija `socket_io_client` en 3.0.2 para compatibilidad con las dependencias antiguas conservadas. El archivo `pubspec.lock` forma parte de la entrega. No se necesita configurar Firebase para entrar al portal de alumnos.

## Dirección de la API y sesión

En web, la dirección predeterminada es el mismo origen de la página, más `/api/v1`. Ejemplo: abrir `https://snackup.ejemplo.edu` utiliza `https://snackup.ejemplo.edu/api/v1`. La aplicación y la API deben compartir esquema, dominio y puerto: el backend actual no publica CORS entre orígenes.

El access token queda en memoria. El navegador renueva con la cookie HttpOnly creada por el backend; Web Locks coordina login, refresh, logout y cambio de contraseña entre pestañas. Usar HTTPS en operación real o `localhost` durante desarrollo, con un navegador compatible con Web Locks. No se guardan contraseñas ni tokens en SharedPreferences/localStorage.

En nativo, los tokens se mantienen en memoria y la petición omite Origin para activar el modo nativo previsto por V3. Al cerrar completamente la aplicación habrá que iniciar sesión otra vez. Configurar el endpoint al compilar:

```powershell
flutter run --dart-define=SNACKUP_API_BASE_URL=https://snackup.ejemplo.edu/api/v1
```

Android tiene permiso de Internet y macOS tiene permiso de conexiones salientes. Esta entrega verifica la PWA; la compilación y distribución Android/iOS/macOS requieren sus SDK y configuración de plataforma.

## Desarrollo web sin cambiar el backend

### Arranque local preparado en este equipo

Docker tiene `snackup-postgres` y Windows también tiene un servicio PostgreSQL
en el puerto 5432. La configuración privada de esta instalación apunta directamente
al PostgreSQL de Docker para evitar ese conflicto. No se detuvo ni sustituyó el
contenedor original. El usuario de desarrollo y las tablas de las migraciones ya
se crearon con autorización del usuario. Posteriormente se habilitó una prueba
de registro con dos alumnos ficticios y un buzón Mailpit local en el puerto 8025.

Con Docker Desktop abierto y `snackup-postgres` iniciado, desde la raíz del proyecto:

```powershell
# Terminal 1: API. Comprueba y actualiza la dirección interna de Docker si cambió.
.\tools\iniciar_backend.ps1
```

```powershell
# Terminal 2: frontend y proxy. Con la compilación ya generada:
.\tools\abrir_alumnos.ps1 -SinCompilar
```

Abre `http://localhost:8000`. Conserva `backend/.env` privado y no lo subas a GitHub.
La prueba permite registrar `alumno.demo@students.example.edu`, matrícula
`DEMO-001`, y confirmar el correo capturado en `http://localhost:8025`. No se envían
correos reales. El registro institucional real requiere los datos del equipo.

La compilación `--dart-define=SNACKUP_LOCAL_DEMO=true` muestra estas instrucciones
solo en la prueba local. Se puede generar con `tools/abrir_alumnos.ps1 -DemoLocal`.
El contenedor `snackup-correo-local` debe estar iniciado junto con PostgreSQL.

`flutter run` por sí solo inicia el servidor de Flutter; no inicia FastAPI ni
conecta automáticamente PostgreSQL. Un error 404 en `/api/v1/auth/refresh` desde
el puerto aleatorio de Flutter indica que se está llamando al servidor equivocado.

En Windows, con FastAPI ya disponible en el puerto 8001 y su origen público
configurado como `http://localhost:8000`, puedes abrir el frontend con:

```powershell
.\tools\abrir_alumnos.ps1
```

El script comprueba primero `/health/ready`, compila y sirve la página en
`http://localhost:8000`. Si solo está encendido PostgreSQL, indicará que todavía
falta iniciar FastAPI. No configura ni modifica el backend.

`tools/serve_students.mjs` sirve `build/web` y reenvía `/api`, `/socket.io`, `/media` y `/health` a un backend local. Solo escucha en loopback, conserva Host/Origin y rechaza peticiones de otros orígenes. No deshabilita las comprobaciones de seguridad del servidor.

Para trabajar con el backend del equipo:

1. Preparar PostgreSQL, migraciones y cuentas según `backend/README.md`, usando el entorno privado acordado por los compañeros.
2. El origen público de desarrollo del backend debe coincidir con la página: por ejemplo `http://localhost:8000`.
3. Arrancar la API en un puerto interno distinto. Desde `backend/`, con su entorno Python activo:

   ```powershell
   python -m uvicorn snackup.main:create_app --factory --host 127.0.0.1 --port 8001
   ```

4. Desde la raíz del proyecto, compilar y servir:

   ```powershell
   flutter build web --release --no-pub --no-web-resources-cdn --pwa-strategy=none
   node tools/serve_students.mjs --port 8000 --backend http://127.0.0.1:8001
   ```

5. Abrir `http://localhost:8000` e iniciar sesión con una cuenta ALUMNO autorizada por el backend.

El proxy no configura la base, cambia contraseñas ni crea cuentas. `db:5432` pertenece a la red de Docker; el contenedor `snackup-postgres` del chat anterior es una instalación local distinta hasta comprobar lo contrario.

## Incluir esta interfaz en el contenedor existente

El Compose de los compañeros permite sustituir solo el contexto de fuentes de alumnos mediante `SNACKUP_USERS_CONTEXT`. Para construir usando esta copia local, desde la raíz:

```powershell
$env:SNACKUP_USERS_CONTEXT = (Get-Location).Path
Set-Location backend
docker compose -f compose.unified.yaml build app
```

El resto de variables privadas y el arranque siguen las instrucciones del equipo. No se cambia el contexto de paneles. El frontend incluye `deploy/check_web_build.py`, que el Dockerfile existente espera copiar. Su argumento heredado `--mode firebase` es aceptado por compatibilidad con ese Dockerfile; la validación comprueba el frontend REST actual.

Al publicar fuentes en GitHub, el equipo puede fijar `SNACKUP_USERS_CONTEXT` al commit aprobado. Este cambio local no actualiza automáticamente el SHA de alumnos fijado actualmente en Compose.

## Comprobación con datos ficticios

`tools/run_student_fixture.py` importa el backend sin modificarlo y crea una base SQLite temporal con cuentas y productos de prueba. Ignora `.env` y variables SNACKUP heredadas y nunca se conecta al PostgreSQL del usuario. No certifica concurrencia PostgreSQL ni capacidad de producción.

Con Python 3.12 y las dependencias de `backend/requirements.lock` instaladas en un entorno de pruebas separado:

```powershell
python tools/run_student_fixture.py
python tools/run_student_fixture.py --serve
```

En otra terminal, después de compilar la PWA:

```powershell
node tools/serve_students.mjs --port 18080 --backend http://127.0.0.1:18081
```

Abrir `http://localhost:18080`. Cuenta ficticia: `alumno@students.example.edu`. Contraseña pública de pruebas: `Student-Fixture-Only-2026!`. Estas credenciales solo pertenecen a la base efímera del fixture; no son cuentas del equipo ni deben usarse en producción.

## Casos de compra y operación

- El carrito puede contener varios negocios. Cada compra confirma un negocio de forma explícita.
- El servidor recibe IDs, cantidades, notas, método de pago y total esperado; valida precios, stock e identidad.
- Una clave de idempotencia estable permite recuperar el mismo pedido si se pierde la respuesta. El intento pendiente se conserva por cuenta y negocio, sin guardar el código de recogida ni tokens. El usuario debe resolver ese intento antes de crear otro del mismo negocio.
- Tras confirmar el pedido, se comparan las filas actuales antes de limpiar el carrito; los cambios detectados se conservan. La comparación es del cliente, no una precondición transaccional añadida al backend.
- Un cambio de precio o disponibilidad requiere revisar el carrito. El cliente no sustituye el importe silenciosamente.
- El código de recogida corresponde al pedido privado y se valida en el servidor de Cocina. La matrícula ya no funciona como secreto de entrega.
- Transferencia, Tarjeta y ValeComida son métodos registrados por el backend. La aplicación no cobra tarjetas ni confirma transferencias bancarias.

El registro y la recuperación dependen del padrón autorizado y SMTP del servidor. El acuse genérico de registro no confirma la existencia de una cuenta ni inicia sesión. Las funciones nuevas sin pantalla heredada, como chat y administración de Cocina, quedan fuera de este cambio de integración del alumnado.
