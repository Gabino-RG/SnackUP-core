# SnackUP · backend independiente

**Actualización del 23/10/2026:** el despliegue solicitado usa ahora **un contenedor
para backend, PWA de usuarios y Cocina/Administración**, más PostgreSQL persistente.
Consulta [el arranque unificado](backend/DESPLIEGUE_CONTENEDOR_UNICO.md) y
[la auditoría de los adjuntos FastAPI V3.2](backend/AUDITORIA_FASTAPI_V3_2_ACTUAL.md).
Hay rutas y reglas pendientes: no se sustituyeron los modelos ni se declara
terminada la migración Firebase → REST. Las imágenes individuales anteriores
siguen disponibles para desarrollo.

Esta rama contiene la API **Python / FastAPI**, modelos **SQLAlchemy 2.x**,
migraciones **Alembic**, PostgreSQL, Redis y tiempo real. El esquema Prisma es
una referencia generada del modelo SQL; no se ejecuta un segundo ORM ni un
segundo sistema de migraciones.

## Las tres aplicaciones

| Aplicación | Rama | Código de origen |
| --- | --- | --- |
| Backend | [`codex/backend-api-v3-fastapi`](https://github.com/Gabino-RG/SnackUP-core/tree/codex/backend-api-v3-fastapi) | `backend/` |
| Alumnos / PWA | [`codex/usuarios-pwa`](https://github.com/Gabino-RG/SnackUP-core/tree/codex/usuarios-pwa) | Flutter en `lib/` |
| Cocina / Administración | [`codex/entrega-paneles-rest`](https://github.com/Gabino-RG/SnackUP-core/tree/codex/entrega-paneles-rest) | Flutter en `app/` |

Cada aplicación conserva su rama. `compose.unified.yaml` combina los tres orígenes
en la imagen `snackup-unified`; incluye Redis y el proxy HTTPS en ese contenedor.
PostgreSQL conserva un servicio persistente separado. Los contextos frontend se
fijan por commit; no es necesario copiar sus fuentes a la rama del backend.

La rama de alumnos parte de `main` (`b7abff6`) y todavía utiliza Firebase. Su
conexión a la API y la retirada de la interfaz histórica de Cocina siguen
pendientes; Docker no realiza esa migración. `main` y el respaldo
`respaldo/2026-10-13-antes-restablecimiento` se mantienen sin cambios.

## Lectura y puesta en marcha

- [Instalación, operación y respaldos](backend/README.md).
- [Desplegar las tres aplicaciones en un contenedor](backend/DESPLIEGUE_CONTENEDOR_UNICO.md).
- [Auditoría actual de los adjuntos FastAPI V3.2](backend/AUDITORIA_FASTAPI_V3_2_ACTUAL.md).
- [Validación ejecutada del contenedor único](docs/VALIDACION_CONTENEDOR_UNICO.md).
- [Auditoría de funciones existentes frente a V3.2](backend/AUDITORIA_APP_Y_API_V3_2.md).
- [Discrepancias del documento y esquema V3.2](backend/REVISION_V3_2.md).
- [Implementación V3 y decisiones técnicas](backend/API_V3_FASTAPI.md).
- [OpenAPI V3](backend/contracts/v3.openapi.json) y [mapa Prisma](backend/schema.prisma).
- [Contrato de paneles](backend/contracts/panels.openapi.json) y [tiempo real legacy](docs/integracion/REALTIME.md).
- [Evidencia de validación V3](backend/VALIDACION_V3.md).
- [Resultados de separación, contenedores e integración](docs/VALIDACION_SEPARACION.md).

Las integraciones nuevas utilizan `/api/v1/`. El portal actual mantiene
`/api/legacy/v1/`; cambiarle solo el prefijo rompería roles, payloads y respuestas.
Socket.IO V3 se publica en `/socket.io/` y el WebSocket anterior sigue en
`/api/legacy/v1/realtime`.

La revisión encontró omisiones del contrato V3.2 respecto de las aplicaciones
existentes. Sus nuevas reglas de horarios, vales, chat y calificación no se
aplican silenciosamente: están descritas en los informes para cerrar sus
decisiones antes de sustituir el contrato. El esquema SQL actual se conserva.

## Límites de esta entrega

Faltan servidor, dominio, SMTP y padrón autorizados para poner el sistema en
operación. La capacidad de **1,000 alumnos simultáneos** requiere medir una
carga realista; las pruebas funcionales no la acreditan. Las instrucciones de
CI y Docker no equivalen por sí solas a una ejecución exitosa ni a un despliegue.

Backend ampliado: [V3.2 compatible, migración y reglas implementadas](backend/IMPLEMENTACION_V3_2.md).
