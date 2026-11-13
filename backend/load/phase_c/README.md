# Regresión de carga del informe del 27 de octubre de 2026

Este entorno usa PostgreSQL 17 y el supervisor, Caddy, Redis, API y scheduler reales del contenedor unificado. La imagen de medición sustituye los archivos estáticos de Flutter por páginas mínimas; el workflow del contenedor unificado verifica por separado las dos compilaciones Flutter. No envía correo ni push externos. El fixture contiene 1,000 alumnos, cuatro locales, cuatro operadores y un producto por local. Cada escenario reinicia los pedidos de la base aislada; los resultados de lectura no representan un catálogo grande ni una base histórica de producción.

El generador es Python (`aiohttp` y `python-socketio`) porque los scripts k6 originales citados por el informe no están en este repositorio ni entre los archivos recibidos. Envía tráfico HTTP y WebSocket real, con sesiones reales, y valida resultados en SQL. No inventa latencias ni acelera el reloj. `--quick` reduce duraciones; conserva los cinco escalones de tres minutos en P4 porque acortar los escalones anteriores ocultaba saturación sostenida. Sus resultados no certifican resistencia.

## Ejecución reproducible y aislada

En esta rama está disponible el workflow [realtime-load.yml](../../../.github/workflows/realtime-load.yml). Se activa al subir cambios de su configuración o de los archivos de prueba enumerados en su filtro, exclusivamente en `codex/integracion-local-completa`. Ejecuta **P8-1000 completo durante cinco minutos**, con cuatro procesos de API y dos escrituras simultáneas por proceso. Los demás escenarios de esta guía se ejecutan manualmente; esta rama no contiene los workflows históricos `phase-c.yml` ni `phase-c-soak.yml`.

La ejecución de GitHub usa PostgreSQL, Redis, Caddy y API reales en un proyecto Compose independiente. Un Caddy adicional termina TLS en `https://localhost:18443` y envía el tráfico al Caddy de la aplicación, que distribuye las conexiones a los cuatro procesos. La CA efímera se proporciona únicamente al cliente de carga; se verifican el certificado y el nombre del servidor. No se instala una CA en el sistema. El generador solo admite destinos HTTP/HTTPS de bucle local; la URL se configura con `SNACKUP_LOAD_BASE_URL` y la CA con `SNACKUP_LOAD_CA_FILE`, que debe ser un archivo absoluto existente.

El workflow conserva los JSON de resultados y diagnósticos de estado durante 30 días. No incluye credenciales de los fixtures, sesiones, claves ni archivos de la base en los artifacts. Al terminar retira sus contenedores, volúmenes y credenciales temporales. Sus métricas describen el runner Linux de GitHub, compartido con el generador, y no son mediciones de la laptop ni del servidor de TI. El monitor de recursos incluye el contenedor adicional de TLS y exige cuatro procesos de API medidos, entrega completa y cola de publicaciones vacía. Este escenario sostiene las conexiones; no fuerza reconexiones voluntarias ni renovación del token.

Para ejecutar manualmente desde `backend/`, instalar `requirements.lock`, configurar las mismas variables del workflow y usar:

```sh
docker compose -f load/phase_c/compose.yaml up -d --build --wait
python -m load.create_fixtures --confirm-isolated --output /tmp/phase-c-fixtures.json
python -m load.phase_c.runner --fixtures /tmp/phase-c-fixtures.json --profile base --scenario P5 --output reports/P5.json --full
docker compose -f load/phase_c/compose.yaml down --volumes --remove-orphans
```

El generador exige `ALLOW_LOAD=YES`, `SNACKUP_ENVIRONMENT=test`, host SQL loopback y una base llamada exactamente `snackup_loadtest`. Borra los pedidos de esa base antes de cada escenario. **Nunca usar estas credenciales, fixtures o composición para producción.** Los archivos privados de sesiones permanecen fuera de los artifacts.

## Perfiles y límites de comparación

El cuadro describe los perfiles manuales predeterminados. El workflow `realtime-load.yml` aplica su configuración específica de cuatro workers y dos escrituras por worker, indicada arriba.

| Perfil | CPU del servidor | Workers API | Memoria máxima de app / PostgreSQL | Argon2 simultáneos por worker |
|---|---|---|---|---|
| Base | 4 | 3 | 5 GiB / 2 GiB | 4 |
| Pesimista | 2 | 1 | 2300 MiB / 1 GiB | 2 |

Redis comparte el contenedor de aplicación y conserva su límite de 256 MiB. Pool SQL de 10 + 5 por worker; la admisión reserva cuatro plazas para tareas auxiliares y limita las mutaciones a una por worker, con espera asíncrona sin conexión SQL. Los runners tienen cuatro CPU y el generador comparte CPU con los contenedores en el perfil base. En el perfil pesimista el servidor usa CPU 0–1 y el generador CPU 2–3; no reproducen la laptop de QA con turbo desactivado y generador separado. Las comparaciones son evidencia funcional y de capacidad de esta máquina, no una garantía de rendimiento del servidor de TI. Argon2 mantiene 19,456 KiB, dos iteraciones y paralelismo uno. `SNACKUP_WRITE_CONCURRENCY=1` evita concentrar todas las conexiones en la misma fila de stock; al cambiar ese límite deben repetirse P4, P5 y P6, además de la resistencia.

## Escenarios completos

| Escenario | Tráfico y duración | Comprobación |
|---|---|---|
| P0 | 5 alumnos, 45 s; crear, repetir clave y cancelar | Mismo cuerpo crudo, cancelación correcta |
| P2 | Base 100/200/300/400/600/800/1000; pesimista 50/100/150/200/250/300. Cada escalón: rampa 60 s + 300 s sostenidos. Tres lecturas cada 5–10 s por alumno | p95 <750 ms, p99 <2 s y CPU media de la fase sostenida <75% |
| P4 | Un local/producto, crear y cancelar a 2/5/10/20/40 por segundo, 180 s cada escalón | Sin pérdidas de llegadas, p95 creación <1.5 s |
| P5 | 200 compradores simultáneos, stock 50 | Exactamente 50×201 y 150×422 |
| P6 | 50 alumnos ×10 reintentos simultáneos por clave | 50 pedidos, respuestas 201 idénticas; 503 de admisión permitido |
| P7 | Rampa lineal 0→20/s durante 30 s, 20/s durante 240 s, bajada 20→0/s durante 30 s | 5,400 logins, todos exitosos, p95 <1.5 s |
| P7b | Tres olas de 200, separadas por 30 s | ≥99% por ola, cero 500, RSS <400 MiB por worker y objetivo propuesto p95 <3 s |
| P8 | 300 sockets durante 20 min; cuatro operadores cambian disponibilidad cada 5 s detrás de Caddy | Sin pérdida de eventos, p95 <1 s, CPU máxima entre workers <2× mínima |
| P8-1000 | 1,000 sockets durante 5 min | Sin pérdida, p95 <2 s y balance de CPU |
| P8-idle | 300 sockets durante 6 min; cambios con intervalos aleatorios 20–40 s | Cero pérdidas y desconexiones inesperadas |
| P9 | 90 pedidos/min durante 20 min; hasta 5 min de drenaje | ≥99% entregados, aceptación p95 <10 s, creación p95 <1.5 s |
| P9-burst | 270 pedidos/min durante 5 min + drenaje | Se lanzan las 1,350 llegadas; mismos criterios |
| P8b | 300 sockets; tras 2 min empieza P9 durante 20 min | Recepción de cada transición del alumno y de cada cambio de stock, p95 evento <1 s, mismos criterios de cocina |
| P12 | Dos horas reales de 300 lectores y 90 pedidos/min + drenaje | Integridad, cero errores internos/transporte, presupuesto de memoria, eliminación de 2,000 publicaciones vencidas |

Las cocinas son cuatro locales con dos tabletas cada uno, consultando cada dos segundos. Los alumnos con pedidos activos consultan cada cinco segundos. Preparar tarda 20–60 s y caminar 5–30 s. Los conflictos de versión 409 entre tabletas son esperados. Los tokens se renuevan mediante la API; los sockets reciben un token cuya vigencia cubre toda la prueba. P8 conserva la conexión durante toda la medición para probar también el silencio prolongado; no simula reconexiones voluntarias cada diez minutos.

Cada escenario comprueba ausencia de stock negativo, conservación del inventario, unicidad de números/códigos/claves y cero deadlocks PostgreSQL. Se registran CPU y RSS por proceso, memoria de los contenedores, transacciones abiertas y retraso del outbox. Los umbrales que fallen permanecen como fallos en el JSON y hacen fallar CI. Cada JSON identifica el commit y el perfil; comparar las duraciones y la CPU del generador antes de contrastar corridas. Un escalón que supera un umbral documenta un límite de capacidad y no se descarta del informe.

La prueba de retención inserta publicaciones con ocho días de antigüedad; los eventos nuevos se conservan siete días y por tanto su tabla puede crecer durante P12. Las publicaciones pendientes y los push pendientes no se borran. Las carreras de revocación, catálogo, stock y apertura de chat (20 repeticiones) se verifican en la suite PostgreSQL del backend, además de esta carga.
