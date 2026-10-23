# Evidencia de separación y contenedores de SnackUP

Fecha de revisión: 23 de octubre de 2026. Esta entrega separa aplicaciones y
conserva el backend V3 ya implementado. **No declara implementadas las reglas
nuevas del documento V3.2.** Su auditoría encontró omisiones que deben cerrarse
antes de sustituir el contrato.

## 1. Fuentes y ramas publicadas

| Aplicación | Rama | Revisión de código de esta entrega |
| --- | --- | --- |
| Backend y despliegue conjunto | `codex/backend-api-v3-fastapi` | `88bc0b77ae713784a37eed3ec26b2cd8335322e2` |
| Alumnos / PWA | `codex/usuarios-pwa` | `a00d0bf4ecdae74a89f3afbe8ec3d0758efb8884` |
| Cocina / Administración | `codex/entrega-paneles-rest` | `19c81fdee29600d66d9dcb1a4f109a78aeba51f6` |

La implementación de API, configuración y modelos del backend se publicó en
`189dd52e4265566798d90879b2d932f84d0d0014`. Las revisiones posteriores de esa rama
incorporan la CI conjunta, su smoke, documentación, dos correcciones de
portabilidad del workflow y la separación del rango dinámico de direcciones de
la IP fija del proxy. El commit de este informe podrá ser posterior a las
revisiones de código que cita; se conservan los SHA de las ejecuciones probadas.

Se verificó mediante fetch y comparación de árboles que las tres ramas remotas
contenían exactamente los archivos preparados. La rama del backend no incluye
`app/`; la rama de paneles ya no incluye `backend/` ni su workflow. La app de
alumnos parte del `main` real y conserva su fuente en `lib/`.

Se comprobaron sin cambios:

- `main`: `b7abff6593e84dda69ad2909abbf699dd17ff890`.
- `develop`: `bda6cdad7712fd1ba8c1f2894d76ed6cbfbfeb03`.
- `respaldo/2026-10-13-antes-restablecimiento`: `006ef99e461d1ced33116ef338bcf3e9d7b2ec4d`.

No se fusionaron las tres aplicaciones entre sí ni se reescribió el historial.

## 2. Validación ejecutada en GitHub

### Backend

La [ejecución 39922977135](https://github.com/Gabino-RG/SnackUP-core/actions/runs/39922977135),
commit `88bc0b77ae713784a37eed3ec26b2cd8335322e2`, terminó **success**.
El log del job `120312412783` registra:

```text
227 passed, 1 warning in 132.75s (0:02:12)
```

Pasaron también:

- Ruff y comprobación de referencias generadas OpenAPI/Prisma.
- Validación de Prisma 7.10.1 como documento, sin introducirlo como ORM runtime.
- Migraciones y correspondencia de modelos con PostgreSQL 17.
- Pruebas completas con PostgreSQL y Redis 7.4.
- Construcción de las imágenes API y proxy, comprobando `10001:10001`.
- Validación Caddy tanto para backend independiente como para las tres aplicaciones.
- Configuración Compose y arranque de API, PostgreSQL y Redis en un proyecto aislado,
  con el rol SQL de aplicación separado del administrador.

También pasaron las ejecuciones anteriores
[39921108846](https://github.com/Gabino-RG/SnackUP-core/actions/runs/39921108846),
commit `add37dc9fdf7a2889978591f76ab7b58ee546452`, con 227 pruebas en 130.74
segundos, y
[39920685917](https://github.com/Gabino-RG/SnackUP-core/actions/runs/39920685917),
commit `189dd52e4265566798d90879b2d932f84d0d0014`, con 227 pruebas en 138.89
segundos. No se suman las repeticiones como pruebas distintas.

### Cocina y Administración

La [ejecución Docker 39920949553](https://github.com/Gabino-RG/SnackUP-core/actions/runs/39920949553),
commit `19c81fdee29600d66d9dcb1a4f109a78aeba51f6`, terminó **success** para las dos
variantes de compilación: base `/` y base `/paneles/`.

En ambas se construyó la imagen real, se arrancó con filesystem de solo lectura,
`/tmp` temporal, capacidades eliminadas y usuario sin privilegios. Pasaron
healthcheck, recursos, base href, navegación SPA y errores de rutas reservadas.
El runtime no contiene Flutter ni Dart.

La [entrega visual 39920949582](https://github.com/Gabino-RG/SnackUP-core/actions/runs/39920949582)
del mismo SHA terminó **success**. Incluye **114 pruebas Flutter**, análisis,
compilación del portal, instalación de Chromium y recorrido de interfaz.
La traza del recorrido contrastó **68 respuestas** con el contrato del simulador.

Esto cierra el intento visual pendiente para esa revisión del frontend. Su
servidor era el fixture local de revisión: no certifica por sí solo login contra
SQL, correo real, OAuth, TLS institucional ni capacidad de usuarios simultáneos.

### Alumnos / PWA

La construcción y el smoke independientes corresponden a la
[ejecución 39920929661](https://github.com/Gabino-RG/SnackUP-core/actions/runs/39920929661),
commit `a00d0bf4ecdae74a89f3afbe8ec3d0758efb8884`.

Terminó **success**. Pasaron las comprobaciones del worker PWA, la compilación
Flutter y Docker, la inspección de artefactos y el arranque HTTP de la imagen
real con usuario sin privilegios y filesystem de solo lectura. El log registra:

```text
Web artifacts validated; base=/, mode=firebase
Container HTTP checks passed; base=/
```

Este resultado verifica el empaquetado de la aplicación existente. Su acceso a
datos e identidades sigue utilizando Firebase; no acredita una migración del
alumno al backend REST.

### Integración de las tres aplicaciones

La ejecución conjunta corresponde al backend
`88bc0b77ae713784a37eed3ec26b2cd8335322e2`:
[39922977131](https://github.com/Gabino-RG/SnackUP-core/actions/runs/39922977131).
El workflow registra el SHA real de cada checkout en `sources.json`.

Terminó **success**. Se construyeron las imágenes de API, alumnos, Cocina y
proxy; se aplicaron las migraciones `0001_initial` y `0002_v3`; los seis
servicios quedaron healthy. El job `120312411992` registra:

```text
Common proxy smoke passed: 27 HTTP/WebSocket checks; no account used.
```

Pasaron las **27 comprobaciones** del origen común, incluida la conexión
WebSocket real y el rechazo de un cliente Socket.IO sin credenciales. También
terminaron correctamente la recogida de diagnósticos, la limpieza del proyecto
efímero y la publicación de la
[evidencia de integración](https://github.com/Gabino-RG/SnackUP-core/actions/runs/39922977131/artifacts/12488306206).

Se conservaron en este repositorio las copias exactas de
[`sources.json`](evidence/apps-integration-39922977131/sources.json),
[`smoke.json`](evidence/apps-integration-39922977131/smoke.json),
[`images.txt`](evidence/apps-integration-39922977131/images.txt) y
[`tool-versions.txt`](evidence/apps-integration-39922977131/tool-versions.txt).
Los SHA de fuentes coinciden con las tres revisiones de la sección 1. Los IDs
de imagen corresponden a las imágenes cargadas en Docker durante CI; no
representan imágenes publicadas en un registro. El ZIP de origen tiene SHA-256
`d3539759e2447c560981044d774fadf6a090290bf5a8e2941b1bcc68e0b0cc5b`.

El entorno conjunto es efímero: base vacía, contraseñas aleatorias enmascaradas,
SMTP/push desactivados y dominio sintético. HTTP se limita al proxy de CI en
loopback; la configuración de producción mantiene HTTPS. Se comprueban los dos
frontends, sus recursos y prefijos, las rutas de API, healthchecks y el upgrade
Socket.IO con rechazo de una conexión sin credenciales.

## 3. Incidencias de CI corregidas

Las dos primeras ejecuciones conjuntas fallaron antes de construir imágenes.
La tercera completó las cuatro imágenes y las migraciones, y detectó una
colisión de direcciones al arrancar el proxy:

| Ejecución | Causa comprobada | Corrección |
| --- | --- | --- |
| [39921108960](https://github.com/Gabino-RG/SnackUP-core/actions/runs/39921108960) | `rg: command not found`, salida 127 | Leer la versión de websockets con Python, ya instalado en el runner. |
| [39921380150](https://github.com/Gabino-RG/SnackUP-core/actions/runs/39921380150) | Compose 5.6.1 omitía `migrate` del JSON al no activar su perfil; `KeyError: 'migrate'` | Añadir `--profile tools` únicamente a los comandos de inspección `config`. |
| [39921564135](https://github.com/Gabino-RG/SnackUP-core/actions/runs/39921564135) | API y frontends estaban healthy; el proxy falló con `Address already in use` porque su IP fija también pertenecía al rango de asignación dinámica. | Separar el rango dinámico de la IP del proxy en la red `edge`; conservar la confianza de Uvicorn limitada a la IP explícita del proxy. |

La segunda corrección no activa el perfil globalmente. Las migraciones siguen
siendo un paso explícito `run --rm migrate`; no se convierten en un servicio
permanente ni se ejecutan durante el inicio de cada worker.

## 4. Verificación local complementaria

- **22 comprobaciones focalizadas** del nuevo destino de recuperación: `/` y
  `/paneles/`, token de un uso, cambio de contraseña, revocación y validación de
  rutas locales. Se rechazan dominios externos y rutas ambiguas.
- **2 pruebas de contrato** tras retirar el frontend de la rama backend: rutas y
  snapshot de compatibilidad conservados.
- **27 pruebas del servidor de revisión** de los paneles, después de ajustar
  prefijo legacy y compatibilidad de códigos de entrega.
- Checks del worker de alumnos: exclusión API/Socket.IO/medios/paneles, navegación
  sin conexión y registro sin sustituir un worker ajeno.
- Caddy 2.11.7 real en loopback con fixtures: enrutamiento, subruta, encabezados,
  cookies, errores y upgrades WebSocket. Verificación de redirecciones del proxy
  común, incluido HTTP a HTTPS sin exponer el puerto interno.
- Ruff, scripts Python/shell, YAML y comprobación de espacios y enlaces locales
  principales de la documentación.

El entorno local no tiene Docker ni Flutter instalados. La evidencia de
construcción real de imágenes corresponde a GitHub Actions, no a los fixtures
locales.

## 5. Alcance pendiente y decisiones

La PWA de alumnos conserva **Firebase**. Su contenedor no migra identidades,
pedidos, carrito o favoritos a SQL. También conserva la interfaz histórica de
Cocina que el propietario indicó que retirará en otro cambio.

El portal separado conserva `/api/legacy/v1/`, sus DTO y WebSocket nativo.
La API canónica `/api/v1/` y Socket.IO están disponibles en el backend, pero
mover el portal a ese contrato requiere adaptar capacidades, modelos y eventos.

La auditoría de V3.2 identificó historial privado de alumnos, lectura global de
destacados, omisiones documentales de rutas existentes, diez operaciones
administrativas de compatibilidad y estadísticas más ricas que el DTO actual.
Las propuestas completas están en
[AUDITORIA_APP_Y_API_V3_2.md](../backend/AUDITORIA_APP_Y_API_V3_2.md) y
[REVISION_V3_2.md](../backend/REVISION_V3_2.md). La nueva programación, vales,
chat y demás reglas V3.2 no se consideran implementadas por esta separación.

Siguen pendientes servidor, dominio, SMTP, padrón autorizados e integración REST
del alumno. No se ejecutó una prueba de carga de 1,000 usuarios simultáneos.
Tampoco se acredita envío real de correo/push, emisión de certificados ni
operación institucional a partir del smoke de contenedores.
