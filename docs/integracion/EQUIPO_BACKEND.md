# Empezar aquí: equipo de backend y asistente de IA

Entrega de **Administración y Cocina/Local de SnackUP**, 20 de octubre de 2026.

**Rama de entrega:** [`codex/entrega-paneles-rest`](https://github.com/Gabino-RG/SnackUP-core/tree/codex/entrega-paneles-rest).
**Base de respaldo conservada:** `respaldo/2026-10-13-antes-restablecimiento`, commit `006ef99`.
**Frontend y contrato validados localmente:** commit `6fbe5d6260b76d35960fe2e165b738766e4b81b4`.
Las instrucciones de este documento se añaden después de esa validación; consultar
el SHA de cada paquete y de su ejecución de CI para identificar la versión exacta.

## Qué se necesita de ustedes

Implementar y conectar el backend que utilizarán los dos paneles existentes.
El frontend web ya está implementado y compilable; conserva su presentación y
sus flujos. El trabajo pendiente es identidad, autorización, persistencia SQL,
reglas de negocio, medios, comunicación en tiempo real e integración con la app
del alumno. Las decisiones internas de lenguaje, framework, ORM y motor SQL
corresponden al equipo, respetando el contrato externo del frontend.

**No hay un backend definitivo conectado en esta entrega.** El servidor de
`scripts/review/review_server.py` usa Python/SQLite y datos ficticios para comprobar
la interfaz. No debe desplegarse como backend productivo ni copiar sus cuentas
automáticas, contraseñas, generador de pedidos o inicializadores de ejemplos.

## Leer en este orden

1. [Guía de integración](README.md): alcance, conexión, compilación y decisiones pendientes.
2. [Contrato OpenAPI 3.1](openapi.json): 43 operaciones, entradas, respuestas y permisos.
3. [Manual completo](https://github.com/Gabino-RG/SnackUP-core/blob/6fbe5d6260b76d35960fe2e165b738766e4b81b4/docs/MANUAL_BACKEND_PANELES.md): reglas y explicación de los flujos (también incluido en el paquete).
4. [Protocolo WebSocket](REALTIME.md): mensajes realmente consumidos por Cocina.
5. [Matriz de aceptación](ACEPTACION.md): pruebas que deben pasar con su backend.

El PDF/manual 1.0 referencia el snapshot `476d89c`. Para el trabajo nuevo, usar esta
rama y el contrato actual. Cuando haya una diferencia, comprobar las peticiones
reales en el código y registrar el acuerdo entre frontend y backend; no modificar
nombres o estructuras por suposición. Las rutas de administración son extensiones
del contrato v3 original del equipo y requieren que ustedes las implementen.

## Obtener el código correcto

```sh
git clone --branch codex/entrega-paneles-rest --single-branch https://github.com/Gabino-RG/SnackUP-core.git
cd SnackUP-core
git rev-parse HEAD
```

Registrar el SHA que se recibió. Desarrollar el backend en su repositorio acordado
o en una rama de trabajo propia. No sobrescribir la rama de respaldo ni fusionar
cambios en `main` como parte de esta integración sin una instrucción del responsable.
No usar simplemente el ZIP de la rama predeterminada: esa rama contiene una versión
anterior de la aplicación.

## Archivos del frontend que deben respetar

| Ubicación | Contrato que determina |
| --- | --- |
| `app/lib/main_portal_api.dart` | Entrada exclusiva al portal web REST y base `/api/v1/`. |
| `app/lib/api/rest_session.dart` | Login, cookie de renovación, perfil, expiración y logout. |
| `app/lib/api/access_repository.dart` | Opciones de acceso, solicitud de cuenta y entrada Google. |
| `app/lib/operations/operations_repository.dart` | Locales, cuentas, cocina, historial y ventas. |
| `app/lib/operations/models.dart` | Campos y tipos que interpretan las pantallas. |
| `app/lib/catalog/rest_catalog_repository.dart` | Productos, stock, versiones y subida de imágenes. |
| `app/lib/features/admin/data/rest_admin_repository.dart` | Opiniones, referencias, seguimientos e historial. |
| `app/lib/features/operations/access_requests_screen.dart` | Solicitudes pendientes y decisión del maestro. |
| `app/lib/operations/realtime_web.dart` | WebSocket nativo, autenticación, temas y reconexión. |

`main.dart` arranca Firebase por defecto. Para estos paneles usar
`main_portal_api.dart`, o seleccionar explícitamente `BACKEND=rest`. La entrega
debe compilarse con `REVIEW_MODE=false`. No migrar ni eliminar por accidente las
áreas históricas del alumnado que siguen dentro del repositorio.

## Secuencia de trabajo para el equipo

1. **Revisar compatibilidad.** Comparar el backend existente, si lo hay, con OpenAPI.
   Entregar una tabla de rutas compatibles, faltantes y diferentes. Resolver el
   registro de alumnos frente a solicitudes de personal antes de cambiar `auth/register`.
2. **Identidad y configuración.** Crear esquema/migraciones, institución, cafetería,
   padrón académico y procedimiento privado de alta del maestro. Implementar login,
   refresh, `users/me`, logout, revocación y opciones reales de acceso.
3. **Permisos y gestión.** Implementar locales, cuentas y solicitudes de acceso.
   Admin, incluido maestro, nunca opera Cocina. Business solo opera su local.
   `isMaster` se valida en servidor; registro público no lo concede.
4. **Catálogo y medios.** CRUD de productos, imágenes y control de versión.
   En PATCH, `stock` omitido conserva existencias; `stock:null` cambia la política
   de inventario. Responder imágenes mediante una URL accesible desde los dispositivos.
5. **Pedidos reales.** Integrar la creación desde la app del alumno y alimentar
   Cocina. Mantener snapshots de precios, reserva al crear el pedido según v3,
   transiciones válidas, entrega verificada y devolución única al cancelar.
6. **Administración y reportes.** Proveer opiniones y referencias paginadas,
   seguimientos con versiones e historial atómico. Las gráficas usan las opiniones
   cargadas; no cambiar ese contrato por un endpoint de analítica que la UI no consume.
7. **Servicios complementarios.** WebSocket autorizado por local; recuperación por
   correo; Google solo cuando OAuth esté implementado y configurado. Mientras tanto,
   devolver `googleEnabled=false`.
8. **Integración y aceptación.** Servir frontend y `/api/v1/` en el mismo origen HTTPS,
   comprobar todas las filas de la matriz y registrar resultados y límites reales.

Reglas transversales: JSON camelCase, importes numéricos en MXN, fechas con zona,
IDs string, errores HTTP con `error.code`, paginación consistente y
`expectedVersion` validado dentro de la transacción. No exponer credenciales SQL,
hashes, tokens, códigos de recogida ni matrícula en lecturas de Cocina. El cliente
no reenvía escrituras ante fallos de red porque su resultado puede ser incierto.

## Compilación y descarga del frontend

La guía incluye comandos para compilar con Flutter 3.32.0. También puede utilizarse
el [workflow de entrega](https://github.com/Gabino-RG/SnackUP-core/actions/workflows/paneles-entrega.yml).
Elegir la ejecución de `codex/entrega-paneles-rest`, comprobar que terminó correctamente
y que su SHA corresponde al código recibido. Descargar el artefacto
**SnackUP-Paneles-Frontend**. GitHub puede requerir iniciar sesión para descargarlo.

El artefacto contiene un ZIP con `web/`, documentación, contrato, `fuente.zip`,
`VERSION.json` y `SHA256SUMS.txt`. Si la ejecución está pendiente o falló, no presentar
ese resultado como validado: consultar los logs y corregir la causa. Los artefactos
se conservan 30 días; guardar la entrega o reconstruirla desde el SHA.

No se requieren cambios visuales para empezar la integración. No colocar secretos
en `dart-define`: esas opciones son parte del JavaScript público. La configuración
por defecto espera `/api/v1/` en el mismo origen y evita recompilar por cada dominio.

## Evidencia ya disponible y alcance

En el código `6fbe5d6` se ejecutaron localmente 114 pruebas Flutter y 26 pruebas del
servidor de revisión, todas correctas. Se validaron 257 respuestas de esa suite y
65 respuestas del recorrido de navegador contra OpenAPI, además de las peticiones
JSON exitosas del navegador. Se comprobó acceso, aprobación, separación de roles,
catálogo, gráficas y pedido hasta entrega en escritorio, tablet y móvil.

El análisis estático conserva 199 avisos informativos y 2 advertencias del código
existente, con cero errores. Las pruebas locales no certifican un backend SQL real,
correo, Google, WSS, cámara física ni 500 sesiones simultáneas. La ejecución remota
de cada commit debe consultarse por separado en Actions.

## Qué deben devolver al terminar

- Repositorio y commit del backend; stack y motor SQL utilizados.
- URL del entorno de integración, acceso autorizado y forma segura de entregar cuentas.
- Migraciones, configuración de ejemplo sin secretos y procedimiento para crear/recuperar al maestro.
- Tabla por operación: ruta, controlador/servicio, permiso, prueba, estado y diferencias acordadas.
- Evidencias de la matriz, concurrencia, revocación, stock, entrega e historial.
- Instrucciones de despliegue HTTPS, respaldo/restauración de SQL y medios, y límites de capacidad.
- Relación exacta de cambios de frontend que resultaran necesarios, con motivo y prueba.

Compartir secretos por el canal privado acordado, nunca en commits, issues, documentos
compartidos o prompts de IA. No afirmar que el sistema está listo para operación
productiva solo porque el frontend compila o el simulador pasó sus pruebas.

## Texto listo para su asistente de IA

Copiar el siguiente bloque. Darle acceso real al repositorio o al código descargado.

```text
Trabaja en el backend para integrar los paneles web existentes de Administración
y Cocina/Local de SnackUP.

Repositorio frontend: https://github.com/Gabino-RG/SnackUP-core
Rama: codex/entrega-paneles-rest
Empieza leyendo docs/integracion/EQUIPO_BACKEND.md, README.md, openapi.json,
REALTIME.md y ACEPTACION.md, y después docs/MANUAL_BACKEND_PANELES.md.
Registra el SHA real que consultaste. No uses main ni el PDF antiguo como única fuente.

Inspecciona el backend existente y conserva el stack acordado. Antes de implementar,
presenta una comparación con las 43 operaciones del contrato, las decisiones
indispensables y una secuencia de trabajo. Si falta una decisión que bloquee
compatibilidad, identifícala; avanza en lo que no dependa de ella.

Implementa identidad, roles, gestión, catálogo, imágenes, pedidos, inventario,
historial, ventas, opiniones, seguimiento y WebSocket según las peticiones y modelos
reales del frontend. Comprueba los archivos fuente citados en la guía. Distingue
lo implementado, lo propuesto y lo pendiente; no inventes rutas ni respuestas.

Admin, incluido el maestro, no opera Cocina. Business solo opera su local.
Registro de personal solicita aprobación; no concede roles. Coordina por separado
el registro, los pedidos y las opiniones de alumnos. Toda autorización se impone
en el backend, también en WebSocket, no solo ocultando botones.

Respeta expectedVersion atómico, inventario al crear pedido según v3, snapshots,
cancelación que devuelve stock una vez y entrega verificada. Stock omitido en PATCH
no equivale a null. No exijas Idempotency-Key a acciones que el cliente no lo envía.
No copies credenciales, cuentas o seeds del simulador Python/SQLite a producción.

Conserva las pantallas y su diseño. Si una incompatibilidad exige cambiar frontend,
documenta el motivo, archivo, contrato y prueba; coordina ese cambio con su responsable.
Trabaja en el repositorio o rama de backend acordados. No sobrescribas la rama de
respaldo ni publiques o fusiones cambios en main sin autorización del responsable.

Entrega código, migraciones, configuración sin secretos, instrucciones HTTPS,
pruebas por endpoint, resultados de la matriz de aceptación y límites pendientes.
No afirmes 500 sesiones ni funcionamiento real de correo, Google, SQL o WSS sin
evidencia del entorno definitivo. No reveles contraseñas ni tokens en el reporte.
Si no puedes leer el código, indícalo y solicita acceso; no simules que lo revisaste.
```
