# Entrega de frontend: Administración y Cocina

**Equipo de backend y asistente de IA:** comenzar por [EQUIPO_BACKEND.md](EQUIPO_BACKEND.md).
Incluye orden de trabajo, entregables y un bloque de instrucciones listo para copiar.

**Actualización del 22 de octubre de 2026:** el backend se desarrolla en este mismo
repositorio, en [`backend/`](../../backend/README.md), con FastAPI, PostgreSQL y Redis.
Su instalación y pruebas son independientes del simulador `scripts/review`.
El objetivo actualizado es **1,000 alumnos simultáneos**, pendiente de medición en
el servidor asignado. Las menciones a 500 sesiones en manuales anteriores son históricas.

Versión de entrega: **1.0.0 para integración**, preparada el 20 de octubre de 2026.
Base recuperada: `respaldo/2026-10-13-antes-restablecimiento`, commit `006ef99`.
El SHA de esta entrega, su compilador y sus huellas están en `VERSION.json` del ZIP.

## Qué recibe el equipo de backend

- `web/`: aplicación Flutter web compilada para Administración y Cocina/Local.
- `documentos/openapi.json`: contrato OpenAPI 3.1 con 43 operaciones, modelos, permisos y errores.
- `documentos/REALTIME.md`: mensajes del WebSocket y consulta REST de respaldo.
- `documentos/ACEPTACION.md`: condiciones para aceptar la conexión al servidor definitivo.
- `documentos/nginx.conf.example`: referencia de publicación en un mismo origen.
- `fuente.zip`: código y pruebas del commit exacto, incluyendo las áreas históricas del repositorio.
- `VERSION.json` y `SHA256SUMS.txt`: identificación y verificación del paquete.

El binario de entrega entra por `lib/main_portal_api.dart`, con `BACKEND=rest`,
`REVIEW_MODE=false` y API predeterminada `/api/v1/`. No inicia Firebase, no crea
cuentas, no muestra contraseñas de prueba y no ofrece generar pedidos ficticios.
El repositorio conserva el resto de la aplicación para no perder trabajo anterior.
La creación de pedidos y opiniones por alumnos se integra por separado con el backend.

**Estado:** frontend preparado para integración y backend implementado en `backend/`.
La instalación en el servidor institucional, la conexión de la interfaz del alumno,
el correo real y la capacidad siguen pendientes. Google permanece deshabilitado.
Consultar los resultados del workflow de backend para el commit recibido.
El servidor Python/SQLite de `scripts/review` se utiliza exclusivamente para pruebas.

## Conexión acordada

Publicar los archivos de `web/` en la raíz de un origen HTTPS. En ese mismo origen,
el backend atiende `/api/v1/` y los medios se sirven bajo `/media/` o una URL HTTPS
cargable por el navegador. No abrir `index.html` mediante doble clic.

Por ejemplo, si la universidad asigna `https://cafeteria.example`, la aplicación
consume `https://cafeteria.example/api/v1/`. Este dominio es ilustrativo.
No se requiere cambiar el JavaScript compilado para este despliegue de mismo origen.
El nombre real se elige al publicar el servidor. Las credenciales SQL, secretos JWT,
correo y OAuth pertenecen al backend; nunca se incorporan a Flutter.

Para un origen diferente hay que recompilar con `--api-base-url` HTTPS. La política
de cookies `SameSite=Strict` requiere un despliegue same-site compatible; habilitar
CORS por sí solo no permite cookies cross-site. Mantener mismo origen es la opción
de referencia. Ningún dato de conexión a SQL se solicita al usuario del portal.

El ejemplo de Nginx es una referencia que el equipo adapta a sus certificados y
backend. `/api/v1/` no debe terminar en `index.html`; los errores de API son JSON.
Se conserva el prefijo `/api/v1/` al enviar peticiones al backend.

## Orden de implementación

1. Sesión: `auth/options`, login, refresh, logout y `users/me`. Cookie HttpOnly/Secure,
   Origin/CSRF, rotación y revocación. El nombre de cookie lo elige el backend.
2. Institución y administración: locales, cuentas, solicitudes y catálogo académico.
   Bootstrap del maestro por procedimiento del servidor, fuera del registro público.
3. Catálogo: productos e imágenes; control de versión y stock omitido frente a null.
4. Cocina: lectura de pedidos, acciones, verificación de entrega, cancelación, historial
   y ventas. Los pedidos proceden de la app del alumno, no de un generador del portal.
5. Opiniones y seguimientos: paginación, versiones e historial atómico.
6. WebSocket y funciones opcionales: mantener Google deshabilitado hasta tener OAuth.
   Recuperación de contraseña requiere correo real y tokens de un uso.
7. Ejecutar la matriz de aceptación y las pruebas de concurrencia y capacidad.

El rol `admin` (incluido maestro) no opera cocina ni productos. El rol `business`
solo opera su local. `isMaster` permite gestionar cuentas y solicitudes; no permite
suplantar operadores. La API debe verificar estas reglas en cada petición.

## Contrato y compatibilidad

Abrir `openapi.json` con un visor/importador OpenAPI 3.1. Las rutas son relativas a
`/api/v1`. Los esquemas definen la forma canónica; algunos parsers admiten sobres
heredados descritos en el manual, pero conviene implementar los objetos canónicos.

- Dinero: números JSON en pesos MXN, hasta dos decimales. No enviar texto ni centavos.
- Fechas: ISO 8601 con zona UTC; filtros de ventas usan fecha local America/Mexico_City.
- IDs: strings opacos. Versiones: enteros; validar `expectedVersion` atómicamente.
- Listas: `data` y `pagination {page,limit,total,totalPages}`. Vacías no son 404.
- Errores: `error {code,message,details?}` con código HTTP real; nunca HTML o 200 con error.
- `POST auth/register` solicita acceso de personal: 202 sin sesión. No sustituye el
  registro del alumnado. `requestedRole` no concede ese permiso.
- PATCH de producto sin `stock` lo conserva; `stock:null` desactiva control de inventario.
- Las acciones de cocina no envían `Idempotency-Key`; versión y estado impiden duplicados.
- La reserva de inventario REST ocurre al crear el pedido según v3, no al aceptarlo.
  No copiar la política distinta de la aplicación Firebase histórica.
- Lecturas de cocina no incluyen código de entrega ni matrícula.
- Gráficas: cálculo sobre opiniones cargadas; se indica si faltan páginas. No existe
  un endpoint de analítica agregada consumido por este frontend.

`MANUAL_BACKEND_PANELES.md` y el PDF 1.0 del 12 de octubre son referencias del código
`476d89c`. La base de respaldo añade documentación y una corrección de datos ficticios.
Esta entrega añade contrato ejecutable, empaquetado y validación; conserva las rutas
del frontend. La creación administrativa de un local también envía `timezone`:
está recogido en OpenAPI además de `cafeteriaId`. Cambiar rutas o formas requiere
acuerdo y actualización conjunta del frontend, contrato y pruebas.

## Compilar y verificar desde el código fuente

Requisitos: Git, Python 3.10+, Flutter **3.32.0** (Dart 3.8.0). Node y Playwright
solo se requieren para la comprobación de navegador. No actualizar dependencias
durante la entrega sin revisar cambios en `app/pubspec.lock`.

Desde la raíz del repositorio:

```sh
python -m pip install -r scripts/integration/requirements.txt
python scripts/integration/check_contract.py --review --report build/delivery/contract-report.json
cd app
flutter config --enable-web --no-enable-linux-desktop --no-enable-windows-desktop --no-enable-macos-desktop
flutter pub get
flutter test --reporter expanded
flutter analyze --no-fatal-infos --no-fatal-warnings
cd ..
python scripts/integration/build_delivery.py --output build/delivery/SnackUP-Paneles-Frontend.zip
```

`build_delivery.py` exige un checkout limpio y Flutter 3.32.0. Compila la entrada
REST con revisión deshabilitada, comprueba archivos esenciales y ausencia de marcadores
de demostración, incluye el código exacto y verifica todas las huellas del ZIP.
No sobrescribe un ZIP existente: seleccionar otro `--output` para una nueva entrega.
Admite `--flutter RUTA` y `--api-base-url https://dominio.example/api/v1/`.

El comando `flutter config` prepara el SDK para esta entrega web, igual que el
workflow. Evita que Flutter regenere archivos nativos de escritorio durante
`pub get` y permite conservar el checkout limpio que exige el empaquetado. En
Windows también evita pedir enlaces simbólicos de esas plataformas. La opción
persiste en ese SDK; se pueden volver a habilitar al trabajar en otro proyecto.
No se necesita generar un APK ni una aplicación nativa para entregar estos paneles.

El workflow `.github/workflows/paneles-entrega.yml` reproduce contrato, pruebas,
compilación y recorrido de navegador. Su resultado pertenece al commit que ejecuta;
no se atribuye a este trabajo una ejecución remota que todavía no se haya realizado.

## Límites que deben cerrar con backend

El contrato refleja el cliente disponible. La capacidad objetivo de 1,000 alumnos
simultáneos no está certificada. Google está deshabilitado; el envío SMTP requiere
configuración institucional. El backend verifica la entrega con el código del
pedido, admite efectivo al recoger y no implementa conciliación bancaria. La
retención de datos y los futuros medios de pago requieren acuerdo. El historial de
seguimientos muestra hasta 50 eventos; el monitor avisa de opiniones parciales.
Revisar `ACEPTACION.md` antes de declarar conectado o productivo el sistema.
