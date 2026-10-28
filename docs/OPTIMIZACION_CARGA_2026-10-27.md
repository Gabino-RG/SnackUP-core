# Optimización del backend tras las pruebas de carga

La revisión parte del informe PDF y de los cuatro documentos de resultados/propuestas del 27 de octubre de 2026, sobre `81c76c5`. Se conserva el contrato HTTP V3/V3.2 y legacy, los datos y el contenedor de aplicación único con PostgreSQL separado. Esta fase no añade migraciones ni elimina endpoints.

## Cambios y motivo

| Hallazgo | Implementación |
|---|---|
| Inanición de conexiones entre autenticación y handler | La dependencia HTTP devuelve la conexión al terminar la lectura de autorización. Una admisión ASGI acota la concurrencia antes de ocupar conexiones. Las revalidaciones dentro de una escritura conservan su transacción. |
| Login retiene conexión y memoria durante Argon2 | Lee el hash, libera SQL, verifica en un grupo fijo de hilos y vuelve a bloquear/revalidar la cuenta antes de emitir sesión. Los hilos fijos evitan que los buffers de Argon2 queden retenidos en muchos hilos distintos. |
| Errores 500 al agotar el pool | Timeout SQL de 2 s y respuestas 503 con `Retry-After`. Cola HTTP de 5 s y de login de 8 s, sin conexión SQL durante la espera. |
| Consultas repetidas de autorización | Una consulta con joins valida sesión, usuario, padrón y negocio por petición HTTP. Después de un bloqueo se conserva una consulta nueva para observar revocaciones confirmadas durante la espera. |
| Silencio de Redis provoca desconexiones | Suscripción sin timeout de lectura, health check de 30 s y resincronización obligatoria tras un fallo real. |
| Fan-out secuencial por alumno | Validación fresca por lotes de hasta 250 destinatarios, con concurrencia SQL acotada. Conserva revocaciones y autorización de cada destinatario; no introduce caché de permisos. |
| EOF por keep-alive incompatible | Uvicorn 130 s, Caddy 30 s. |
| Reparto desigual de workers | Procesos Uvicorn en puertos loopback independientes y `least_conn` en Caddy. |
| Deadlock al abrir chat desde ambos lados | Bloqueo de actor `FOR NO KEY UPDATE`, compatible con las comprobaciones de llaves foráneas. |
| Outbox sin retención | Purga por lotes de publicaciones de más de siete días. Conserva eventos sin publicar y publicaciones con push pendiente. |
| Falso negativo de idempotencia en k6 | Compara el cuerpo crudo de las respuestas. |
| Cola de escrituras sobre un mismo producto | `SNACKUP_WRITE_CONCURRENCY=1` admite una mutación por worker antes de adquirir conexión SQL. Las lecturas conservan su concurrencia y el login usa su propia admisión. En el perfil base son tres workers: no es una única escritura global. |

El contador y la versión del negocio conservan la misma transacción y tabla. Compra y cancelación usan inicialmente `FOR KEY SHARE` sobre el negocio para excluir ediciones de catálogo. La compra reserva el número con `UPDATE ... RETURNING` después de adquirir los productos, actualizando contador y versión atómicamente; la cancelación no modifica el negocio. Ambos conservan el orden negocio→productos y excluyen las ediciones de catálogo con `FOR UPDATE`. Así, una compra que espera un producto no retiene desde antes el bloqueo exclusivo del contador de todo el local. Una prueba PostgreSQL específica comprueba esa coexistencia; las pruebas anteriores siguen comprobando la exclusión frente al catálogo. No se presenta como implementada una tabla nueva de contadores.

La creación PostgreSQL usa `INSERT ... ON CONFLICT` limitado al índice parcial del código de recogida, con `RETURNING`, para reintentar colisiones sin abrir un savepoint por pedido. Las colisiones de cualquier otra restricción siguen fallando y revierten la transacción. Se evita cargar la colección vacía de items o consultar calificaciones de un pedido recién creado. La atribución académica se obtiene antes del bloqueo del negocio; la autorización sensible se vuelve a validar dentro de la transacción. Se mantienen contador, inventario, vale e idempotencia atómicos.

## Regresión funcional

Código final sometido a la batería completa: `750eee4ab8359f81da31891c5a4cbfeb57408e26`. Incluye los bloqueos compatibles, la transacción de creación abreviada, una escritura activa por worker, los parámetros de Compose y el simulador documentado. Su cambio respecto de `ba24427ef191d3d3188ed358d0bab1d249e42c69` es únicamente la aclaración de los fixtures en el README de carga; el código ejecutable es el mismo.

- [Backend PostgreSQL/Redis](https://github.com/Gabino-RG/SnackUP-core/actions/runs/40618617193): **295 pruebas aprobadas, seis omitidas** por requerir Caddy en el proceso de pytest. Incluye las 20 repeticiones de apertura concurrente de chat, la carrera de revocación durante el login, liberación de bloqueos antes de devolver el handler y devolución de permisos de admisión tras timeout o cancelación.
- Alembic upgrade/check, referencias OpenAPI/Prisma, Ruff, imágenes y arranque Compose aprobados. Los contratos y migraciones no cambian respecto de la entrega previa.
- [Contenedor único](https://github.com/Gabino-RG/SnackUP-core/actions/runs/40618617097): aprobado con ambas compilaciones Flutter, proxy, API, Redis, jobs y PostgreSQL. Incluye **27 comprobaciones HTTP/Socket.IO y otras 27** después de detener Redis y recuperar el conjunto. El [resumen final de regresión](carga_2026-10-27/final_regression.json) conserva los resultados y los identificadores de los artifacts originales.
- La carga atraviesa Caddy real; no se usa SQLite para certificar bloqueos, inventario ni concurrencia.

## Iteraciones de corrección

1. El simulador omitía las notas obligatorias al cancelar; se corrigió el payload para respetar el contrato existente.
2. Los observadores de dos pruebas PostgreSQL reconocían únicamente el texto `FOR UPDATE`; se ajustaron para reconocer `FOR NO KEY UPDATE` sin quitar las comprobaciones de revocación.
3. La cola inicial de 2 s rechazó 286 de 600 logins del perfil pesimista con 503. La cola específica de login permitió completar los 600.
4. El semáforo inicial de Argon2 limitó ejecuciones simultáneas, pero dejó un pico de 670 MiB por worker. Los hilos dedicados lo redujeron a 176 MiB en la siguiente medición corta, con 600 de 600 logins exitosos.
5. La medición corta del mismo perfil dio p95 3.71 s: **el objetivo propuesto de 3 s todavía falló**. La calibración de ese runner tardó 0.609 s por 40 verificaciones Argon2 con dos hilos, antes de sumar HTTP/SQL. No se redujo la seguridad del hash ni se cambió el umbral para ocultarlo.

6. La prueba completa anterior detectó saturación que la ráfaga corta ocultaba: a 40/s durante tres minutos se crearon 6,087 de 7,200 pedidos; 1,113 recibieron 503, con p95 de 7.47 s. Acortar la transacción permitió pasar una repetición sostenida en Intel Xeon: **7,200/7,200 creados y cancelados**, p95 de **29.98 ms**, sin 503 ni errores de integridad. El escalón de 40/s ahora dura tres minutos incluso con `--quick`.
7. Se corrigió la expectativa de P8b descrita abajo. La repetición recibió **360/360 transiciones y 6,750/6,750 avisos de stock**, con 90/90 entregas y cero desconexiones.

8. La repetición completa en AMD EPYC siguió fallando a 40/s: 6,488/7,200 creaciones, 712 respuestas 503 y p95 6.91 s. No basta con una repetición en otra CPU para certificar capacidad. Se movió el commit al mismo hilo del handler, después de guardar toda la operación y su respuesta idempotente, para no retener bloqueos mientras FastAPI agenda la limpieza. P4 conserva ahora sus cinco escalones completos incluso en modo corto. La prueba nueva comprueba que creación, reintento y cancelación devuelven el control sin una transacción abierta.

9. Confirmar dentro del handler redujo las respuestas 503 de creación a 509, pero no alcanzó el objetivo. El monitor mostró 28–30 sesiones esperando bloqueos de tupla. Se cambió el bloqueo inicial del negocio a `FOR KEY SHARE` y se pospuso la reserva atómica del consecutivo hasta adquirir los productos. Una nueva prueba PostgreSQL retiene un producto, deja un comprador esperando y exige que otro producto del mismo local pueda venderse con numeración única antes de liberar al primero.

10. Las escrituras agrupadas y un límite de dos mutaciones activas por worker pasaron una repetición con p95 de 140 ms a 40/s, pero fallaron de nuevo en la batería completa. Se redujo el límite a una mutación por worker y se repitió P4 completo. Se conservan ambos resultados, sin sustituir el fallo por la repetición favorable.

## Comparación de dos escrituras y una escritura por worker

Ambas mediciones usaron PostgreSQL 17, tres workers, perfil base de cuatro CPU, AMD EPYC 7763 y kernel `7.0.0-1017-azure`. El generador compartía el runner con el servidor. P4 mantuvo cinco escalones de 180 segundos (2, 5, 10, 20 y 40 pedidos/s), con creación y cancelación sobre el mismo producto. Son runners distintos; la diferencia observada no es una garantía de capacidad ni una atribución causal aislada.

| Métrica de P4 | Dos escrituras por worker | Una escritura por worker |
|---|---:|---:|
| Commit | `241218139d5bd31580d13d45318f9a175b8c10fe` | `ba24427ef191d3d3188ed358d0bab1d249e42c69` |
| Creaciones a 40/s | 6,592 de 7,200 | 7,200 de 7,200 |
| Respuestas 503 al crear a 40/s | 608 | 0 |
| p95 de creación a 40/s | 5,094.70 ms | 165.49 ms |
| Creaciones en los cinco escalones | 13,252 de 13,860 | 13,860 de 13,860 |
| Cancelaciones exitosas / intentadas | 12,737 / 13,252 | 13,860 / 13,860 |
| Respuestas 503 al cancelar | 515 | 0 |
| Stock negativo, discrepancias de inventario, duplicados y deadlocks | 0 | 0 |
| Resultado de P4 | Fallido | Aprobado |

Fuentes verificables: [ejecución con dos escrituras](https://github.com/Gabino-RG/SnackUP-core/actions/runs/40613603215), [JSON conservado](carga_2026-10-27/full_two_writers_intermediate.json); [repetición con una escritura](https://github.com/Gabino-RG/SnackUP-core/actions/runs/40616616418), [JSON verificado contra el artifact 12786017851](carga_2026-10-27/one_writer_repetition.json). La primera ejecución global fue cancelada al iniciar la siguiente validación, pero el job de seguridad terminó y publicó su P4 fallido. La segunda ejecución global terminó fallida por otros escenarios: aprobar P4 no significa aprobar toda la batería.

La segunda corrida figura como `quick=true`, pero P4 conservó los 15 minutos completos, incluida la historia de carga de los escalones anteriores. Los demás escenarios cortos no equivalen a la batería completa. En esa repetición el perfil de dos CPU completó 600/600 logins, aunque su p95 de 3,962.69 ms incumplió el objetivo de 3 s; la lectura de 1,000 alumnos incumplió el criterio de CPU sostenida. Estos fallos permanecen en [los JSON de login/lectura pesimista](carga_2026-10-27/one_writer_quick_pessimistic.json) y [lectura base](carga_2026-10-27/one_writer_quick_reading.json).

### Confirmación en la batería completa

El job de seguridad de la [ejecución final completa](https://github.com/Gabino-RG/SnackUP-core/actions/runs/40618617107) aprobó P0, P4, P5, P6, P7 y P7b en `750eee4ab8359f81da31891c5a4cbfeb57408e26`. En esta ocasión el runner fue AMD EPYC 9V74, con el mismo perfil de cuatro CPU y tres workers; se registra la diferencia de CPU para no confundir esta medición con una repetición en la misma máquina.

| Escenario completo, perfil base | Resultado final |
|---|---|
| P4, cinco escalones de tres minutos | 13,860/13,860 creados y cancelados; cero 503 |
| P4, 40 pedidos/s | 7,200/7,200 creados; p95 95.29 ms; p99 146.30 ms |
| P5, 200 compradores y stock 50 | Exactamente 50 respuestas 201 y 150 respuestas 422 |
| P6, 500 solicitudes con 50 claves | 500 respuestas 201 idénticas por clave; exactamente 50 pedidos |
| P7, login sostenido | 5,400/5,400 respuestas 200; p95 33.40 ms |
| P7b, tres olas de 200 logins | 600/600 respuestas 200; p95 2,430.04 ms; RSS máximo 234.27 MiB por worker |
| Integridad | Cero stock negativo, discrepancias, números/códigos/claves duplicados y deadlocks; outbox sin pendientes al terminar |

[Evidencia del job completo](carga_2026-10-27/final_full_safety.json), artifact `12786509144`. La aprobación de este job no sustituye los resultados de las demás suites.

### Lectura y login con las duraciones completas

En lectura se mantuvieron 60 segundos de rampa y 300 segundos sostenidos por escalón. Cada alumno consultó negocios, productos y pedidos activos cada 5–10 segundos. Los criterios siguen siendo p95 <750 ms, p99 <2 s y CPU media del servidor <75%; no se modificaron tras observar los resultados.

| Perfil base: alumnos | p95 | p99 | CPU media sostenida | Resultado |
|---:|---:|---:|---:|---|
| 100 | 11.40 ms | 13.84 ms | 10.66% | Aprobado |
| 200 | 11.89 ms | 16.15 ms | 18.63% | Aprobado |
| 300 | 15.57 ms | 21.24 ms | 26.31% | Aprobado |
| 400 | 18.28 ms | 25.49 ms | 35.00% | Aprobado |
| 600 | 39.47 ms | 67.49 ms | 54.50% | Aprobado |
| 800 | 262.35 ms | 331.36 ms | 81.99% | Fallido por CPU |
| 1,000 | 956.38 ms | 1,064.16 ms | 84.73% | Fallido por CPU y p95 |

Todas las solicitudes de esos escalones respondieron 200. El job completo **sigue fallido** por los tres criterios registrados en su JSON. En este runner se validaron 600 lectores dentro de todos los límites, no 1,000. El fixture contiene solo cuatro negocios, un producto por negocio y no incluye historial previo: estos resultados tampoco certifican un catálogo o base histórica grandes. [Evidencia de lectura base](carga_2026-10-27/final_full_reading.json), artifact `12787484156`; CPU AMD EPYC 9V74, kernel `6.17.0-1022-azure`, generador compartiendo CPU.

El perfil pesimista completo aprobó los seis escalones de 50–300 lectores. Con 300: p95 16.69 ms, p99 25.54 ms y CPU media 27.60%. Completó 5,400/5,400 logins sostenidos (p95 21.71 ms) y 600/600 logins en tres olas (p95 2,805.60 ms; RSS máximo 177.28 MiB durante las olas). [Evidencia pesimista](carga_2026-10-27/final_full_pessimistic.json), artifact `12788500449`.

Esta aprobación de dos CPU ocurrió en AMD EPYC 9V45 con generador en CPU separadas. La repetición corta en otro runner había fallado con p95 de 3.96 s, y se conserva. No se atribuye la diferencia al límite de escrituras: los logins quedan fuera de ese semáforo y los procesadores/condiciones fueron distintos. El objetivo de tres segundos no está garantizado para cualquier servidor de dos CPU.

### Tiempo real completo detrás de Caddy

| Escenario | Eventos recibidos / esperados | p95 del evento | Desconexiones inesperadas | Resultado |
|---|---:|---:|---:|---|
| P8: 300 sockets, 20 min | 71,700 / 71,700 | 248.91 ms | 0 | Aprobado |
| P8-1000: 1,000 sockets, 5 min | 59,000 / 59,000 | 248.46 ms | 0 | Aprobado |
| P8-idle: 300 sockets, 6 min e intervalos de 20–40 s | 3,450 / 3,450 | 232.07 ms | 0 | Aprobado |

Las razones de CPU entre el worker más y menos ocupado fueron 1.16 y 1.13 para P8 y P8-1000, por debajo del umbral de 2. [Evidencia de tiempo real](carga_2026-10-27/final_full_realtime.json), artifact `12787532694`.

### Cocina y receso completo

Se simularon cuatro locales con dos tabletas por local, consulta de cocina cada dos segundos y consulta de alumnos con pedidos activos cada cinco segundos. Se mantuvieron los tiempos documentados de preparación y traslado, sin acelerar el reloj.

| Escenario | Pedidos creados / entregados | p95 de creación | p95 hasta aceptación | Resultado |
|---|---:|---:|---:|---|
| P9: 90 pedidos/min durante 20 min | 1,800 / 1,800 | 38.63 ms | 1,987.49 ms | Aprobado |
| P9-burst: 270 pedidos/min durante 5 min | 1,350 / 1,350 | 475.80 ms | 2,494.91 ms | Aprobado |
| P8b: 300 sockets y 90 pedidos/min durante 20 min | 1,800 / 1,800 | 50.11 ms | 2,006.73 ms | Aprobado |

La ráfaga lanzó las 1,350 llegadas previstas. En P8b llegaron las 7,200/7,200 transiciones del alumno y los 135,000/135,000 avisos de stock, con p95 de 244.72 ms y 243.34 ms, respectivamente; no hubo desconexiones inesperadas. Los 409 entre tabletas son conflictos de versión esperados y no duplicaron transiciones. Las tres pruebas terminaron sin errores internos/de transporte, discrepancias de inventario, duplicados ni deadlocks. [Evidencia de cocina](carga_2026-10-27/final_full_kitchen.json), artifact `12789090290`.

## Simulación de Fase C

El [protocolo y los comandos](../backend/load/phase_c/README.md) describen perfiles, tasas, duraciones, criterios y limitaciones del generador. Se recrearon los escenarios con tráfico HTTP/Socket.IO real porque los scripts k6 citados en el informe no estaban incluidos. Los runners comparten CPU con el generador; no son la laptop de QA ni el futuro servidor de TI.

La [evidencia de la repetición corta](carga_2026-10-27/) conserva también los fallos: lectura de 1,000 alumnos, objetivo de login del perfil pesimista y una expectativa incorrecta del simulador P8b. En este último caso esperaba 450 eventos para 90 pedidos, pero el contrato del alumno recibe cuatro transiciones por pedido (360), sin `order.created`. La prueba final verifica esas transiciones y además todos los avisos de stock recibidos por los alumnos del local.

Otra corrida corta dio p95 de 3.54 s a 40 pedidos/s; motivó el ajuste final de bloqueos del negocio. No se omite esa variabilidad aunque otra repetición del mismo escenario hubiera pasado.

La batería completa del código `750eee4ab8359f81da31891c5a4cbfeb57408e26` terminó **fallida** por los criterios de lectura base de 800 y 1,000 alumnos detallados arriba. Las suites de compras/login base, tiempo real, cocina y perfil pesimista aprobaron. La resistencia P12 sigue pendiente de terminar y no se presenta como aprobada. La desconexión de la conversación no detuvo los workflows; se retomó su seguimiento sin reiniciarlos.

- [Batería completa con una escritura por worker](https://github.com/Gabino-RG/SnackUP-core/actions/runs/40618617107).
- [Resistencia P12 de dos horas con una escritura por worker](https://github.com/Gabino-RG/SnackUP-core/actions/runs/40618617105).
- [Repetición corta, con P4 completo](https://github.com/Gabino-RG/SnackUP-core/actions/runs/40616616418).

## Alcance operativo

No se desplegó producción, no se tocó una base real y no se migró Firestore. La PWA de alumnos conserva el estado de integración frontend documentado en la entrega V3.2. La actualización de rendimiento no elimina funcionalidades ni rutas existentes. La capacidad definitiva debe medirse en el servidor asignado, usando sus recursos, latencia de red y configuración institucional.
