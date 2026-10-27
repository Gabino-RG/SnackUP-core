# Regresión de carga del informe del 27 de octubre de 2026

Este entorno usa PostgreSQL 17 y el supervisor, Caddy, Redis, API y scheduler reales del contenedor unificado. La imagen de medición sustituye los archivos estáticos de Flutter por páginas mínimas; el workflow del contenedor unificado verifica por separado las dos compilaciones Flutter. No envía correo ni push externos.

El generador es Python (`aiohttp` y `python-socketio`) porque los scripts k6 originales citados por el informe no están en este repositorio ni entre los archivos recibidos. Envía tráfico HTTP y WebSocket real, con sesiones reales, y valida resultados en SQL. No inventa latencias ni acelera el reloj. `--quick` reduce duraciones; conserva tres minutos a 40 pedidos/s en P4 porque una ráfaga de 20 s ocultaba saturación sostenida. Sus resultados no certifican resistencia.

## Ejecución reproducible y aislada

Los workflows `phase-c.yml` y `phase-c-soak.yml` se ejecutan exclusivamente en la rama de revisión. Un commit cuyo mensaje contiene `[phase-c-full]` activa las duraciones completas y P12 de dos horas. Las suites usan proyectos Compose y bases independientes, eliminados al terminar. Las métricas y diagnósticos acotados quedan como artifacts durante 30 días.

Para ejecutar manualmente desde `backend/`, instalar `requirements.lock`, configurar las mismas variables del workflow y usar:

```sh
docker compose -f load/phase_c/compose.yaml up -d --build --wait
python -m load.create_fixtures --confirm-isolated --output /tmp/phase-c-fixtures.json
python -m load.phase_c.runner --fixtures /tmp/phase-c-fixtures.json --profile base --scenario P5 --output reports/P5.json --full
docker compose -f load/phase_c/compose.yaml down --volumes --remove-orphans
```

El generador exige `ALLOW_LOAD=YES`, `SNACKUP_ENVIRONMENT=test`, host SQL loopback y una base llamada exactamente `snackup_loadtest`. Borra los pedidos de esa base antes de cada escenario. **Nunca usar estas credenciales, fixtures o composición para producción.** Los archivos privados de sesiones permanecen fuera de los artifacts.

## Perfiles y límites de comparación

| Perfil | CPU del servidor | Workers API | Memoria máxima de app / PostgreSQL | Argon2 simultáneos por worker |
|---|---|---|---|---|
| Base | 4 | 3 | 5 GiB / 2 GiB | 4 |
| Pesimista | 2 | 1 | 2300 MiB / 1 GiB | 2 |

Redis comparte el contenedor de aplicación y conserva su límite de 256 MiB. Pool SQL de 10 + 5 por worker; la admisión reserva cuatro plazas para tareas auxiliares. Los runners tienen cuatro CPU y el generador comparte CPU con los contenedores en el perfil base. En el perfil pesimista el servidor usa CPU 0–1 y el generador CPU 2–3; no reproducen la laptop de QA con turbo desactivado y generador separado. Las comparaciones son evidencia funcional y de capacidad de esta máquina, no una garantía de rendimiento del servidor de TI. Argon2 mantiene 19,456 KiB, dos iteraciones y paralelismo uno.

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
