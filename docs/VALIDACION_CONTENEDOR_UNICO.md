# Validación del contenedor único de SnackUP

Fecha: 23 de octubre de 2026.

**Resultado: construcción y arranque de la imagen unificada aprobados en CI.**
La prueba utiliza las dos aplicaciones Flutter reales y un PostgreSQL vacío
aislado; no se desplegó el servidor universitario ni se migraron datos reales.

## Versiones exactas

| Componente | Commit |
|---|---|
| Backend y despliegue probados | `6e3fc8332cd37355b99ce43cf9132dabb1cd6bc4` |
| Árbol Git probado | `15474d46636aead59397ddd4d2478cbdf92215f2` |
| PWA alumnos | `a00d0bf4ecdae74a89f3afbe8ec3d0758efb8884` |
| Cocina/Administración | `19c81fdee29600d66d9dcb1a4f109a78aeba51f6` |

Los commits posteriores que agregan este informe solo documentan la evidencia.
La revisión se encuentra en el [PR #25](https://github.com/Gabino-RG/SnackUP-core/pull/25).

## Resultados ejecutados

| Verificación | Resultado | Evidencia |
|---|---|---|
| Dockerfile multietapa y compilación de ambas interfaces | Aprobado; imagen final UID/GID 10001 | [Workflow unificado](https://github.com/Gabino-RG/SnackUP-core/actions/runs/39925543133) |
| Topología Compose | Exactamente `app` y `db`; solo `app` publica puertos; Redis privado por socket Unix | Mismo workflow, validación de configuración |
| Arranque contra PostgreSQL 17 | Migraciones Alembic, API, Redis y Caddy sanos | Mismo workflow |
| Rutas, assets y errores de API | 27 comprobaciones HTTP/Socket.IO aprobadas | [smoke.json](evidence/unified-39925543133/smoke.json) |
| Caída de Redis y reinicio completo | `RestartCount >= 1`, contenedor saludable y las mismas 27 comprobaciones aprobadas | [smoke-after-restart.json](evidence/unified-39925543133/smoke-after-restart.json) |
| Backend con PostgreSQL y Redis | **229 aprobadas, 6 omitidas**, sin fallos | [Workflow backend](https://github.com/Gabino-RG/SnackUP-core/actions/runs/39925543175) |
| Proxy y supervisor locales | Las 8 pruebas nuevas aprobadas con Caddy real; la suite local completa tuvo 209 aprobadas y 26 omitidas por PostgreSQL | `backend/tests/test_unified_deploy.py` y `backend/reports/audit-unified-local.xml` en el entorno de trabajo |
| Estático y contratos | Ruff, Prisma, OpenAPI, Alembic upgrade/check aprobados; sin divergencia de metadata | Workflow backend |

Las seis omisiones del workflow backend son los casos de proxy que requieren
un Caddy local en ese job. Se ejecutaron localmente y el workflow unificado además
prueba el proxy real dentro de Docker. Las 26 omisiones locales correspondían a
PostgreSQL; no se presentaron como garantías de concurrencia comprobadas en SQLite.

El primer intento de integración encontró que copiar el binario Caddy conservaba
`cap_net_bind_service`, incompatible con `cap_drop: ALL`. Se retiró ese atributo
en la etapa de construcción y se añadió una ejecución del binario sin capabilities
al workflow. Se mantuvo el contenedor sin privilegios. La ejecución enlazada arriba
ya incluye y valida esa corrección.

## Qué demuestra y qué sigue pendiente

La prueba usa una sola imagen de aplicación para backend, alumnos y paneles.
Conserva el prefijo `/paneles/`, el API legacy del portal, el Socket.IO V3 y los
errores JSON de FastAPI. No devuelve HTML de Flutter para rutas privadas ausentes.
El reinicio vuelve a ejecutar Alembic sin inventar una nueva migración o borrar datos.

Los smoke no crean cuentas ni pedidos, no envían correo/push y no consultan
Firebase. Las pruebas del backend usan identidades y datos sintéticos aislados.
El proxy de CI utiliza HTTP solo en loopback: la emisión de certificados para el
dominio real no se probó. Tampoco se midió capacidad de carga o funcionamiento
con 1.000/2.000 alumnos simultáneos.

La PWA de alumnos **continúa en Firebase** y conserva su Cocina histórica. Los
servicios V3.2 pendientes siguen inventariados en
[AUDITORIA_FASTAPI_V3_2_ACTUAL.md](../backend/AUDITORIA_FASTAPI_V3_2_ACTUAL.md).
Un contenedor aprobado no convierte esos módulos ausentes en implementaciones.

Arranque y operación: [DESPLIEGUE_CONTENEDOR_UNICO.md](../backend/DESPLIEGUE_CONTENEDOR_UNICO.md).
