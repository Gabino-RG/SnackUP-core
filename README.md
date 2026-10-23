# SnackUP · Cocina y Administración

Esta rama contiene el portal Flutter REST de **Cocina/Local y Administración**.
El backend tiene su propia rama, `codex/backend-api-v3-fastapi`; su código ya no
está incluido aquí. La app de alumnos se construye en `codex/usuarios-pwa`.

| Aplicación | Rama | Despliegue |
| --- | --- | --- |
| Cocina / Administración | [`codex/entrega-paneles-rest`](https://github.com/Gabino-RG/SnackUP-core/tree/codex/entrega-paneles-rest) | [Contenedor del portal](deploy/README.md) |
| Backend | [`codex/backend-api-v3-fastapi`](https://github.com/Gabino-RG/SnackUP-core/tree/codex/backend-api-v3-fastapi) | [Instalación y tres contenedores](https://github.com/Gabino-RG/SnackUP-core/blob/codex/backend-api-v3-fastapi/backend/DESPLIEGUE_TRES_APPS.md) |
| Alumnos / PWA | [`codex/usuarios-pwa`](https://github.com/Gabino-RG/SnackUP-core/tree/codex/usuarios-pwa) | [Contenedor de alumnos](https://github.com/Gabino-RG/SnackUP-core/blob/codex/usuarios-pwa/deploy/README.md) |

La entrada de esta imagen es `app/lib/main_portal_api.dart`, con
`BACKEND=rest`, `REVIEW_MODE=false` y API de compatibilidad
`/api/legacy/v1/`. No inicia Firebase. El resto del código histórico se conserva
como referencia y para evitar perder trabajo; no se incluye como otra app en
el contenedor del portal.

El despliegue conjunto publica alumnos en `/` y este portal en `/paneles/`,
compilado con `WEB_BASE_HREF=/paneles/`. Cada uno tiene su proceso Caddy y su
imagen. API, PostgreSQL, Redis y el proxy HTTPS son servicios independientes.

## Integración y validación

- [Construir y ejecutar el contenedor](deploy/README.md).
- [Contrato de los 43 endpoints del portal](docs/integracion/openapi.json).
- [Integrar el portal con el backend separado](docs/integracion/EQUIPO_BACKEND.md).
- [Protocolo WebSocket de compatibilidad](docs/integracion/REALTIME.md).
- [Auditoría de funciones existentes y contrato V3.2](https://github.com/Gabino-RG/SnackUP-core/blob/codex/backend-api-v3-fastapi/backend/AUDITORIA_APP_Y_API_V3_2.md).
- [Workflow del contenedor](.github/workflows/web-container.yml).
- [Compilación y recorrido visual del portal](.github/workflows/paneles-entrega.yml).

Cambiar la URL a `/api/v1/` no migra el portal: la API canónica utiliza otros
roles, DTO y Socket.IO. Se conserva el adaptador legacy hasta hacer esa
integración de forma explícita. Los códigos de entrega admiten el formato nuevo
de seis caracteres y el histórico de ocho; no se usa matrícula para entregar.

El servidor `scripts/review` sirve únicamente para revisión de interfaz y
pruebas con datos ficticios. La instalación institucional, SMTP, dominio y
padrón están pendientes. La capacidad de 1,000 alumnos simultáneos necesita
medición. Consultar los resultados por commit en GitHub Actions; un workflow
preparado no acredita por sí solo un build correcto.

El respaldo `respaldo/2026-10-13-antes-restablecimiento` sigue en `006ef99`.
`main` se mantiene sin cambios.
