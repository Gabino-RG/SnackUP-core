# Accesos independientes de Cocina y Administración

SnackUP utiliza un origen web distinto para cada aplicación. Cocina y Administración tienen sus propias pantallas de acceso, compilaciones, cookies y preferencias. No hay un selector para pasar de un perfil al otro.

## En esta laptop

| Aplicación | Dirección |
|---|---|
| Alumnos | http://localhost:18080/ |
| Cocina | http://cocina.localhost:18080/ |
| Administración | http://administracion.localhost:18080/ |

Las tres direcciones corresponden al servidor local. Chrome y Edge reconocen los nombres bajo `.localhost` como locales; no se compra un dominio ni se cambia el archivo de hosts de Windows. El acceso anterior `/paneles/` se retira para que no siga funcionando como entrada compartida.

Cada portal acepta únicamente su rol: Cocina admite cuentas de local (`business`) y Administración admite cuentas administrativas (`admin`). El backend comprueba el rol en el inicio de sesión, renovación, consultas y conexiones en tiempo real. Cambiar la URL no concede permisos.

Abrir ambos portales en el mismo navegador conserva sesiones independientes. Cerrar Cocina no cierra Administración. Las cuentas y los datos existentes se conservan; los nuevos orígenes requieren iniciar sesión de nuevo. Los permisos de notificaciones pertenecen a cada origen y deben activarse nuevamente si se necesitan en las nuevas direcciones.

## Qué se separa y qué se comparte

- Se separan el origen del navegador, la pantalla de acceso, la sesión, el almacenamiento de preferencias y el ámbito del service worker.
- Se conserva el backend y la base de datos de SnackUP. Administración sigue pudiendo gestionar los locales y consultar sus resultados mediante sus permisos. Esta comunicación es necesaria para el funcionamiento del sistema.
- Alumnos conserva su aplicación y su dirección original.

Las cookies no declaran un `Domain` compartido. En HTTPS, las de personal usan el prefijo `__Host-`, `Secure`, `HttpOnly`, `SameSite=Strict` y `Path=/`. El modo HTTP local utiliza nombres independientes sin ese prefijo. El servidor exige el origen exacto del portal para las operaciones del navegador; no habilita acceso CORS con credenciales entre los paneles.

Las fotos ya guardadas conservan su URL canónica. Únicamente su lectura pública (`GET`/`HEAD` de `/media/`) permite CORS desde los dos orígenes de personal configurados, sin credenciales. Esto permite que Flutter dibuje las imágenes y mantiene cerradas las respuestas de la API a los otros orígenes.

La separación por subdominios mejora el aislamiento del navegador frente a servir ambos paneles bajo rutas del mismo origen. No sustituye los controles de autorización ni equivale a tener dos servidores o bases de datos físicamente aislados.

## Para el servidor de TI

Se necesitan tres nombres DNS distintos que apunten al servidor. Ejemplo de configuración; estos nombres son ilustrativos:

```dotenv
SNACKUP_DOMAIN=snackup.example.edu
SNACKUP_PUBLIC_ORIGIN=https://snackup.example.edu
SNACKUP_KITCHEN_PUBLIC_ORIGIN=https://cocina.snackup.example.edu
SNACKUP_ADMINISTRATION_PUBLIC_ORIGIN=https://administracion.snackup.example.edu
```

En `compose.unified.yaml`, `SNACKUP_DOMAIN` genera el valor de `SNACKUP_PUBLIC_ORIGIN` para Alumnos. Si se ejecuta el backend directamente, se configura `SNACKUP_PUBLIC_ORIGIN`. Los otros dos orígenes se proporcionan completos en ambos casos.

El despliegue unificado sirve la API en `/api/` dentro del origen de cada aplicación; el navegador no necesita conectarse al dominio del otro panel. El backend utiliza los orígenes configurados para validar solicitudes y generar los enlaces de recuperación correspondientes a cada cuenta.

Seguir la guía de [despliegue unificado](../backend/DESPLIEGUE_CONTENEDOR_UNICO.md) y configurar HTTPS para los tres nombres. No publicar las credenciales ni las cuentas de demostración de esta laptop. El dominio real, sus registros DNS y certificados siguen pendientes de TI.

## Compilaciones del personal

Ambas se generan desde `app/`, con base `/` y `API_BASE_URL=/api/legacy/v1/`:

- Cocina: `PORTAL_AUDIENCE=cocina`, salida `app/build/kitchen/web/`.
- Administración: `PORTAL_AUDIENCE=administracion`, salida `app/build/administration/web/`.

Los comandos de compilación e inicio local están en [INTEGRACION_LOCAL.md](../INTEGRACION_LOCAL.md). En producción, el Dockerfile unificado compila las tres aplicaciones desde el mismo checkout.

La comprobación local del navegador está en `tools/check_portal_browser_isolation.cjs`. Utiliza las cuentas de demostración existentes, realiza accesos y cierres de sesión mediante la interfaz y comprueba aislamiento de cookies, renovación y rechazo de perfiles cruzados. No crea alumnos, productos, pedidos ni valoraciones. Sus resultados de ejecución deben consultarse por separado; la existencia del script no significa que una ejecución haya aprobado.

## Verificación local del 13 de noviembre de 2026

La suite completa del backend se ejecutó contra PostgreSQL 17.11, en una base temporal separada que se eliminó al terminar: **426 pruebas aprobadas, 0 fallos y 4 omitidas**. Las omisiones corresponden a tres comprobaciones con Redis y una del supervisor de procesos POSIX; requieren el entorno Linux de CI. La suite incluye 60 casos de aislamiento de portales y lectura de medios entre orígenes, además de las pruebas del proxy Caddy real.

Chromium y WebKit aprobaron 14 comprobaciones funcionales por motor: acceso por rol, rechazo del otro rol, cookies de hosts distintos, restauración de identidad, API ilegible desde el otro origen y cierre de sesión independiente. Se revisaron capturas de escritorio (1440 × 1000) y móvil (390 × 844); las medidas móviles son de viewport, no una nueva prueba en teléfono físico. Las seis comprobaciones de las pantallas públicas también aprobaron. Una imagen pública existente se obtuvo sin credenciales y se decodificó correctamente desde cada portal en ambos motores, sin subir archivos nuevos.

El verificador exige `SameSite=Strict` en la cabecera enviada por el servidor. La lectura de ese atributo en el almacén de cookies de WebKit para Windows se registra como limitación: ese runtime devuelve `None`, un comportamiento reconocido en las [pruebas de Playwright](https://github.com/microsoft/playwright/blob/main/tests/library/browsercontext-cookies.spec.ts#L110-L131). La comprobación de ese metadato se mantiene en Chromium y en los otros sistemas; no se cambia la política de la aplicación para acomodar al verificador.

Se conservaron las cuentas, pedidos y archivos de la base local de demostración. Esta verificación funcional no mide capacidad de carga ni cambia el resultado anterior del ensayo de 2 CPU y 2 GiB.
