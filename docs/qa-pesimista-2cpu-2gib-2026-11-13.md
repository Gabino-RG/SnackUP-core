# Resultado pesimista: 2 CPU y 2 GiB

**La configuración ensayada no aprobó 1,000 alumnos simultáneos.** El mayor escalón de lecturas que cumplió los objetivos fue 300 usuarios durante 90 segundos estables. Esto no certifica 300 usuarios realizando todo el flujo ni demuestra que sea imposible soportar 1,000 tras optimizar la configuración.

- Ejecución: [43521552674](https://github.com/Gabino-RG/SnackUP-core/actions/runs/43521552674), concluida con fallos el 13 de noviembre de 2026.
- Código medido: `66ed757896274e719c72aaea62f43b107d919628`, rama `codex/integracion-local-completa`.
- Evidencia: [extracto de los informes JSON](qa-pesimista-2cpu-2gib-2026-11-13.json), con hashes de los archivos originales y primera muestra de OOM. El artifact completo permanece en la ejecución durante su retención de 30 días.
- Artifact `14085156921`; SHA-256 del ZIP: `7c131ef5e4eabb5588c038292b961543c94110c73e9f4767bc61ba303e964433`.

## Qué se limitó

Se usó la imagen unificada real con Alumnos y Paneles compilados. Aplicación, PostgreSQL y proxy HTTPS compartieron las CPU lógicas 0–1, con generador en 2–3. Memoria: aplicación 1,152 MiB, PostgreSQL 768 MiB y proxy TLS 128 MiB, en total 2,048 MiB. Swap adicional de los contenedores deshabilitado. Un worker de API, una mutación simultánea y dos verificaciones Argon2 simultáneas.

Los límites efectivos pasaron la comprobación inicial de Docker y cgroups. El host fue un runner Linux con procesador AMD EPYC 7763 y cuatro CPU lógicas disponibles; el sistema operativo, Docker y generador quedaron fuera del presupuesto. **No equivale a una máquina virtual completa con solo 2 GiB**, que necesita memoria para su sistema operativo.

Los fixtures fueron 1,000 alumnos, cuatro operadores, un administrador y cuatro productos, exclusivamente en una base temporal. No se modificó la base de la laptop ni la rama de respaldo.

## Lecturas concurrentes

Cada usuario consultó catálogo, menú y sus pedidos, con pausas de 5–10 segundos. Cada escalón tuvo 15 segundos de rampa y 90 segundos estables. Los percentiles siguientes excluyen la rampa.

| Usuarios | p95 | p99 | CPU media de las dos CPU | Resultado |
|---:|---:|---:|---:|---|
| 50 | 19.84 ms | 30.48 ms | 19.50% | Aprobado |
| 100 | 25.05 ms | 35.84 ms | 26.97% | Aprobado |
| 300 | 191.78 ms | 265.81 ms | 71.08% | Aprobado; 10,476 respuestas HTTP 200 |
| 500 | 1,959.15 ms | 2,455.99 ms | 82.80% | 11,416 respuestas HTTP 200, pero fallaron los objetivos de latencia y CPU |
| 1,000 | No interpretar el agregado como latencia de servicio | — | — | El proxy HTTPS murió durante este escalón |

Objetivos: p95 < 750 ms, p99 < 2,000 ms y CPU media < 75%. En el escalón de 1,000 hubo, durante la rampa, 2,280 respuestas 200 y 251 respuestas 503. Durante la fase estable hubo 538 respuestas 200, 143 respuestas 503 y 32,125 errores de transporte. Su p95 agregado de 87.80 ms y CPU media de 8.77% están sesgados por los fallos inmediatos de conexión: **no representan un servidor rápido ni capacidad sobrante**.

## Causa de la caída y límites de la conclusión

La primera muestra con `oom_kill=1` en el proxy TLS es de **22:58:20 UTC (16:58:20, Ciudad de México)**. El proxy alcanzó exactamente su límite individual de 134,217,728 bytes (128 MiB) y terminó con código 137; el diagnóstico final confirma `oomKilled=true`. La aplicación y PostgreSQL permanecieron en ejecución y saludables.

El pico conjunto muestreado por cgroups fue 734,048,256 bytes, aproximadamente **700.04 MiB**. Los picos individuales fueron aproximadamente 445.37 MiB de aplicación, 151.26 MiB de PostgreSQL y 128 MiB de TLS; no necesariamente ocurrieron simultáneamente. Son mediciones de cgroups, que incluyen memoria contabilizada como caché, y no deben mezclarse con el consumo reducido que muestra Docker stats.

**No se agotaron los 2 GiB totales. Se agotó la asignación de 128 MiB del proxy.** Por ello, el resultado rechaza esta distribución de recursos; no permite concluir que 2 GiB totales sean insuficientes por sí mismos. Sin embargo, los 500 lectores ya eran lentos antes del OOM: aumentar únicamente la memoria del proxy tampoco demuestra que 1,000 usuarios cumplirían los tiempos deseados.

Después de la muerte del proxy desapareció su cgroup. Las verificaciones finales de lectura de límites, CPU y swap resultaron negativas porque ese servicio ya no estaba vivo; no indican que se le hubieran ampliado los recursos durante la prueba.

## Otras comprobaciones

- **Integridad básica:** crear, repetir clave y cancelar aprobó.
- **Stock limitado:** 200 compradores para stock 50 produjeron exactamente 50 ventas y 150 rechazos por inventario. Las 50 cancelaciones restituyeron stock; sin sobreventa, duplicados ni deadlocks.
- **Idempotencia:** 50 claves enviadas diez veces produjeron 50 pedidos únicos. Hubo 474 respuestas 201 y 26 rechazos 503 iniciales; las verificaciones posteriores confirmaron las 50 intenciones, conservando cuerpos de respuesta idénticos.
- **Acceso:** tres olas de 200 logins, 600/600 exitosos; p95 4.588 segundos, por encima del objetivo de 3 segundos.
- **Compras sostenidas, ráfaga de 1,000 compras, 1,000 WSS y operación mixta:** se intentaron después del OOM y encontraron el endpoint HTTPS caído. Permanecen fallidas; no son mediciones independientes válidas de capacidad. La operación mixta no pudo crear los pedidos ni comprobar chat/calificaciones bajo esta carga.
- **Frontends:** las cuatro comprobaciones de Alumnos y Paneles en Chromium/WebKit aprobaron antes de la carga y fallaron después por la pérdida de HTTPS. Los pasos posteriores tienen `continue-on-error` para recoger evidencia; su estado técnico de paso no sustituye el resultado negativo de sus JSON.
- **Limpieza:** aprobada; no quedaron contenedores, volúmenes ni credenciales temporales del proyecto de prueba.

Por separado, el [workflow funcional 43521552569](https://github.com/Gabino-RG/SnackUP-core/actions/runs/43521552569) aprobó 367 pruebas PostgreSQL, cuatro comprobaciones de navegador, dos del supervisor y 28 comprobaciones HTTP/WebSocket antes y otras 28 después del reinicio controlado. Esa aprobación funcional **no acredita capacidad con 2 GiB**.

## Siguiente prueba necesaria

Redistribuir la memoria dentro del mismo total de 2,048 MiB para que TLS no tenga un límite insuficiente; medir y optimizar la saturación que ya aparece con 500 lectores; repetir la carga completa desde una instancia sana. Si un servicio vuelve a caer, distinguir los escenarios posteriores afectados de las mediciones realizadas mientras todo estaba disponible. Conservar este ensayo fallido para comparar y no elevar los umbrales para convertirlo en aprobado.

Hasta obtener esa nueva evidencia, **no aprobar esta configuración para 1,000 alumnos simultáneos en producción**.
