# Validación de la adaptación V3 a FastAPI

**Fecha:** 23 de octubre de 2026.

**Rama de entrega:** `codex/backend-api-v3-fastapi`.

**Base revisada:** `codex/entrega-paneles-rest`, commit `17ad7823321fe79b673e10f7a201af02bec79628`.

La entrega se implementó sobre el backend existente. Los resultados siguientes corresponden al código final de Python, los contratos generados, las migraciones y las pruebas de esta rama; no son una certificación de una instalación universitaria en producción.

## Resultado integral local

**206 pruebas aprobadas, 0 fallos, 0 omitidas, en 95.41 segundos.**

- [XML de la ejecución completa](evidence/v3-pytest-postgres.xml).
- [Reporte de respuestas contrastadas con contratos anteriores](evidence/v3-contract-responses.json).
- [Contrato OpenAPI V3](contracts/v3.openapi.json).
- [Mapa Prisma validado](schema.prisma).

Entorno: Python 3.12, dependencias exactas de `requirements.lock`, PostgreSQL **16.15** local aislado con UTF-8, Redis **7.0.15** local aislado. La suite crea esquemas SQL independientes por prueba. El workflow de GitHub utiliza PostgreSQL **17** y Redis **7.4**, por lo que su ejecución es una comprobación adicional del destino declarado de despliegue.

```bash
SNACKUP_TEST_DATABASE_URL=<base-PostgreSQL-exclusiva-de-pruebas> \
SNACKUP_TEST_REDIS_URL=<Redis-exclusivo-de-pruebas> \
python -m pytest -q --junitxml=reports/pytest-v3-postgres.xml
```

Hubo un aviso de deprecación del cliente de pruebas Starlette respecto de `httpx`. No produjo fallos y no corresponde a una vulnerabilidad detectada ni a una excepción de la API. No se cambió el lock a otra familia de cliente durante esta entrega.

## Qué se comprobó

| Área | Comprobación |
|---|---|
| Registro y sesiones | Correo/matrícula del padrón, confirmación de correo, protección frente a apropiación de cuentas, roles públicos, cookies web y tokens nativos, rotación/replay, revocación, recuperación y perfil. |
| Administración | Creación atómica de local con cuenta Cocina; reglas de propietario y rol; cuentas protegidas; bajas con pedidos activos; auditoría y revocación tras espera de bloqueos. |
| Pedidos e inventario | Totales del servidor, cambio de precio, UUID de idempotencia, compras simultáneas, ausencia de sobreventa, snapshots, numeración por negocio, colisión de código y restitución única. |
| Estados y entrega | Matriz nominal de transiciones, cancelación según perfil, privacidad de códigos, entrega manual/QR y auditoría de código incorrecto que sobrevive al rollback del pedido. |
| Versionado | Cambio coherente de `totalOrders`, versión y evento del negocio; el replay no vuelve a modificar contadores; deltas de pedidos incluyen estados terminales. |
| Revocación mientras se espera | Peticiones que esperan bloqueos de usuario, pedido, negocio o producto observan la sesión revocada y terminan sin persistir la mutación. Incluye calificaciones y administración. |
| Cancelación frente a pausa manual | Reproducción determinista del interbloqueo encontrado y corrección del orden de bloqueos: ambas operaciones terminan `200`, stock repuesto y pausa manual conservada. |
| Compatibilidad entre contratos | Pedidos V3 atendidos desde legacy; métodos de pago y códigos de seis/ocho caracteres; cambios de producto/reserva/reposición legacy generan avisos que consume V3. |
| IDs opacos | Flujo PostgreSQL con IDs de negocio/producto de más de 300 caracteres y tópicos íntegros del outbox. |
| Calificaciones y reseñas | Compra completada y propia, producto comprado, unicidad, lote atómico, agregados del servidor y conservación de carrera/grupo/seguimiento administrativo. |
| Medios | Propiedad, propósito, MIME real, tamaño, vinculación autorizada, rechazo del borrado en uso y limpieza de archivo al revertir su metadata. |
| Socket.IO | Tramas reales Engine.IO/Socket.IO, autenticación, ACK de suscripción, permisos de salas, Origin, plazo de autenticación, revocación y ausencia de datos privados. |
| Redis | Publicación y distribución entre procesos, dos gateways ASGI que reciben el mismo evento, y comprobaciones explícitas de servicios/límites. No todas las pruebas funcionales utilizan Redis. |
| Push | Propiedad de dispositivos y baja por sesión; deduplicación, leases, reintentos, estado obsoleto, falta de configuración y contratos de FCM/APNs/Web Push con transportes de ensayo. |
| Migraciones | Base V1 poblada → `0002_v3`, comparación de todas las columnas históricas, backfills, índices parciales, CHECK, claves foráneas y ausencia de drift, tanto en PostgreSQL como en SQLite. |

La prueba determinista de concurrencia se añadió porque una ejecución integral detectó un deadlock real entre catálogo y cancelación. Primero reprodujo `[200,503]`; el arreglo ordena las adquisiciones y evita un autoflush intermedio del pedido. La misma prueba exige `[200,200]`. No se cambió el resultado esperado para aceptar un error ni se ocultó el fallo mediante reintentos.

## Contratos, esquema y herramientas

- **OpenAPI 3.1 válido:** 46 rutas de negocio con 55 operaciones bajo `/api/v1`, más dos rutas/operaciones de salud: 48 rutas y 57 operaciones en el documento completo. Los errores tienen el envelope que devuelve realmente la aplicación y las extensiones institucionales conservan sus DTO.
- **Prisma 7 válido:** 23 modelos/tablas, 259 columnas, 43 claves foráneas. `prisma validate` con CLI **7.10.1**, instalado temporalmente fuera del backend, terminó correctamente. Node/Prisma no se añadieron al runtime Python.
- **Generación sin divergencias:** `python tools/export_prisma_reference.py --check` y `python tools/export_v3_openapi.py --check` aprobados.
- **Contrato anterior:** 725 respuestas comprobadas, las 43 operaciones observadas y ninguna operación ausente. Sus extensiones sumaron 104 comprobaciones y las 12 operaciones documentadas fueron observadas. Son conteos de validaciones; una respuesta puede participar en más de una cobertura.
- **Calidad básica:** Ruff, `git diff --check`, `pip check`, `node --check` del escenario de carga y del smoke de navegador aprobados. YAML de Compose, overlay push y workflow parseado correctamente.
- **Fixture de paneles:** 27 pruebas aprobadas, 260 respuestas comprobadas y 43 operaciones. Esta es una prueba del simulador y contrato del portal, adicional al backend SQL.
- **Preparación de carga:** el CLI creó en una base PostgreSQL temporal migrada 2 alumnos, 1 operador, 1 negocio, 1 producto y 0 pedidos; archivo de credenciales con permisos `0600`. La base y el archivo temporal se eliminaron al terminar. El escenario HTTP V3 pasó una simulación sin tráfico de carga.

Los XML y conteos almacenados son evidencias de esta ejecución fechada. Para cambios posteriores, repetir el workflow y consultar los artefactos del commit correspondiente. [Historial de GitHub Actions de esta rama](https://github.com/Gabino-RG/SnackUP-core/actions?query=branch%3Acodex%2Fbackend-api-v3-fastapi).

## Límites de la validación

No había Docker, Flutter/Dart ni k6 disponibles en el entorno local. Docker/Compose y los widgets Flutter se verifican adicionalmente mediante los workflows de GitHub que ejecutan esas herramientas; la existencia de un workflow no acredita por sí sola su resultado. La prueba visual anterior del frontend es independiente de la suite SQL y debe revisarse por ejecución.

No se realizó despliegue de producción, importación de datos reales de Firebase, entrega real de SMTP/push, prueba con padrón autorizado ni carga de 1,000 alumnos. La aplicación del alumno sigue requiriendo integración con los repositorios REST/Socket.IO V3. Transferencia no incluye verificación bancaria. La programación de recogida y políticas de no recogidos/retención requieren definición funcional.

La guía [API_V3_FASTAPI.md](API_V3_FASTAPI.md) identifica los cambios de contrato, las propuestas que se concretaron, el comportamiento pendiente y el procedimiento de respaldo, migración y reversión.

## Entradas analizadas

Se utilizaron los adjuntos del usuario, sin reemplazarlos ni atribuirles decisiones nuevas:

| Archivo de entrada | SHA-256 |
|---|---|
| `SnackUP_API_V3_Consolidada.md` | `75fd119f8df4b30b987fb384e4a93c7cc7c00de5d483a845e3de74d93a95bc30` |
| `schema.prisma` original | `b11b0fc6bed0d0a4f03ae6baf38bd9108311469084ac8234887eab84c535ef3d` |

El `schema.prisma` de esta rama es la referencia ampliada y adaptada a las tablas reales; por diseño no tiene el mismo hash que el adjunto original.
