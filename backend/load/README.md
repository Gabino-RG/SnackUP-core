# Pruebas de carga para 1,000 alumnos

El escenario de k6 se ejecuta manualmente y utiliza el contrato V3 de FastAPI en `/api/v1`, con `expectedTotal`, claves UUID de idempotencia, método `Efectivo` y cancelación `user_other` con notas.

## Mediciones en la laptop de integración

El 6 de noviembre de 2026 se usaron bases PostgreSQL y servicios Redis temporales. Cada ensayo creó 1,000 alumnos distintos, cuatro locales y un producto por local. Las cuentas y los pedidos fueron sintéticos. FastAPI procesó cada solicitud y se comprobó el resultado en PostgreSQL. Las bases de carga se eliminaron al terminar.

| Ensayo | Resultado |
|---|---|
| [Ráfaga con dos procesos de API y una escritura simultánea por proceso](../../docs/qa-carga-1000-2026-11-06.json) | De 1,000 compras enviadas a la vez, 584 entraron al primer intento y 416 recibieron 503. El p95 fue de 5.28 s. Los reintentos con la clave original recuperaron las 1,000 compras. |
| [Ráfaga con cuatro procesos y dos escrituras simultáneas por proceso](../../docs/qa-carga-1000-four-workers-2026-11-06.json) | Entraron 743 compras al primer intento y 257 recibieron 503 con `Retry-After: 1`. El p95 fue de 5.52 s. Se confirmaron y cancelaron las 1,000 compras sin duplicar folios y se recuperó todo el stock. |
| [Uso sostenido de 1,000 sesiones durante 30 minutos](../../docs/qa-carga-1000-soak-four-2026-11-06.json) | Con cuatro procesos y dos escrituras por proceso, se completaron 7,200 compras a cuatro por segundo, se confirmó cada una con la misma clave y se cancelaron las 7,200. El p95 de creación fue de 211 ms y el de lectura, de 120 ms. En 733,252 solicitudes hubo once respuestas 503 y un corte de conexión. |
| [Ráfaga con espera de admisión de diez segundos, ensayo interrumpido](../../docs/qa-carga-1000-four-queue10-2026-11-06.json) | Con cuatro procesos y dos escrituras por proceso, las 1,000 compras entraron al primer intento. El p95 aumentó a 7.89 s. Al solicitarse el apagado, PostgreSQL contenía exactamente 1,000 pedidos pendientes. Se eliminó la base temporal con sus reservas. |

En el escenario sostenido se cumplieron los objetivos de menos de 1% de solicitudes fallidas, p95 de lectura inferior a 750 ms y p95 de creación inferior a 1.5 s. Los dos primeros perfiles superaron el objetivo de 1.5 s al concentrar las 1,000 compras en un solo instante.

Cada alumno del ensayo sostenido consultó los locales, el menú y sus pedidos, y esperó entre 5 y 10 segundos antes de la siguiente visita. Hubo 2,000 renovaciones de sesión por cookie. Los cortes de inventario durante la prueba coincidieron con las reservas activas. Al cierre se verificaron los cuatro stocks iniciales, la numeración de los 7,200 pedidos sin duplicados dentro de cada local y la cola de eventos vacía.

Para las mediciones HTTP, el generador compartió laptop con la API y PostgreSQL y distribuyó las peticiones directamente entre puertos locales. El ensayo sostenido repartió alumnos de cada local entre todos los procesos. Los tiempos y la tasa de rechazo de estas pruebas describen esa configuración. En el servidor de TI se deben repetir las mediciones con el dominio, el catálogo, la red y el número de procesos que se van a utilizar. Los escenarios equivalentes de lectura, compra, idempotencia y tiempo real se describen en la [guía de fase C](phase_c/README.md).

La [continuación del 10 de noviembre](../../docs/qa-salida-integrada-2026-11-10.md) completó los ensayos HTTP pendientes:

| Ensayo | Resultado |
|---|---|
| [Cuatro procesos y diez segundos de admisión](../../docs/qa-carga-1000-four-queue10-2026-11-10.json) | 1,000 compras iniciales, repeticiones y cancelaciones correctas. Con 200 compradores por 50 unidades se aceptaron exactamente 50. Diez envíos de cada una de 50 claves conservaron un solo pedido por clave. Inventario completo al cierre. p95 de la ráfaga: 5.07 s, por encima del objetivo de 1.5 s. |
| [Un único reintento automático ante 503](../../docs/qa-carga-1000-four-auto5-2026-11-10.json) | 804 compras iniciales y 196 respuestas de saturación. Las 196 se confirmaron al repetir una sola vez con la clave original, respetando `Retry-After` más la dispersión de espera. Sin recuperación manual posterior. p95 hasta confirmar la compra: 7.46 s. Todas las cancelaciones recuperaron el inventario. |
| [WebSocket, medición parcial](../../docs/qa-carga-1000-ws-four-2026-11-10.json) | 1,000 suscripciones durante cinco minutos y 59,000 entregas correctas, p95 243 ms. El observador tomó los PID de los lanzadores de Windows y sus cifras de CPU/TCP fueron inválidas. Se conserva como ensayo inconcluso, sin aprobar el criterio completo. |

El porcentaje de rechazo inicial del ensayo de reintentos fue del 19.6 %, superior al límite del 1 %. La recuperación y la integridad pasaron; los objetivos de latencia de ambas ráfagas no se cumplieron. El generador reprodujo la política de reintento mediante HTTP real, sin ejecutar 1,000 navegadores Flutter. La [revisión del 13 de noviembre](../../docs/qa-salida-integrada-2026-11-13.md) documenta la continuación de la comprobación WSS en Linux y las limitaciones del entorno local.

## Entorno aislado

Usar otro despliegue, otra base PostgreSQL cuyo nombre contenga `loadtest`, otro Redis y un generador de carga separado del servidor. Nunca reutilizar cuentas, padrón, imágenes ni credenciales de producción. Para generar fixtures, `SNACKUP_ENVIRONMENT` debe ser `development` o `test`; el comando rechaza producción. Aplicar las mismas migraciones primero y usar HTTPS/Redis/pool equivalentes al servidor final.

Desde `backend/`, con la configuración del entorno **aislado**:

```bash
python -m alembic upgrade head
python -m load.create_fixtures --students 1000 --businesses 4 --output /directorio/privado/fuera-del-repo/snackup-load.json --confirm-isolated
```

El archivo externo contiene credenciales ficticias y relaciones local/producto. El comando no imprime contraseñas, no sobrescribe archivos y marca las cuentas como datos de carga. Conservarlo con permisos privados; en Windows revisar también su ACL. Cada alumno utiliza una cuenta distinta. El número de cuatro locales es una configuración del ensayo, no una regla de negocio.

## Ejecución manual con k6

Instalar [k6 según su documentación oficial](https://grafana.com/docs/k6/latest/set-up/install-k6/). Comenzar con 10 usuarios; repetir con 100, 300 y finalmente 1,000 cuando el entorno permanezca estable.

```bash
k6 run -e ALLOW_LOAD=YES -e TARGET_ENV=isolated-loadtest \
  -e BASE_URL=https://carga.dominio-autorizado.example \
  -e CONFIRM_HOST=carga.dominio-autorizado.example \
  -e CREDENTIALS_FILE=/directorio/privado/fuera-del-repo/snackup-load.json \
  -e TARGET_VUS=10 -e MODE=read --summary-export=/directorio/privado/lecturas.json load/students.js
```

El dominio del ejemplo se sustituye por el entorno de carga autorizado. No usar `--http-debug`: puede registrar contraseñas, cookies o tokens. En PowerShell escribir el comando en una línea o usar su continuación de línea.

Para pedidos, repetir con `MODE=orders` y agregar `-e ALLOW_WRITES=YES`. Este modo crea pedidos, repite cada creación con la **misma clave de idempotencia**, mantiene una reserva brevemente y cancela el pedido propio. No envía pedidos a cocinas reales. La reserva y la devolución deben dejar el stock inicial intacto. Una prueba interrumpida puede dejar pedidos pendientes: revisar esos registros en el entorno aislado antes de interpretar diferencias de inventario.

## Qué mide

- Rampa de 2 minutos a 100 usuarios, 2 a 300, 2 a 1,000, **30 minutos sostenidos** y 2 de descenso: aproximadamente 38 minutos más el cierre. `TARGET_VUS` limita cada etapa. La fase sostenida permite ejercer la renovación de sesiones de 15 minutos.
- Login por usuario, renovación mediante cookie web y `Origin` cuando corresponde, consulta autenticada de locales, menú y pedidos activos propios; pausas de 5–10 segundos entre iteraciones.
- En modo pedidos: reserva, precio confirmado por servidor, reintento idempotente y cancelación. No prueba pago electrónico, recogida ni transición completa por cocina.
- Umbrales propuestos: menos de 1% de HTTP fallidos; p95 global <750 ms y p99 <2 s; p95 de creación <1.5 s; todos los reintentos deben conservar el ID y todas las cancelaciones intentadas deben confirmarse. Son criterios de aceptación a acordar, **no mediciones ya obtenidas**. [Semántica de umbrales](https://grafana.com/docs/k6/latest/using-k6/thresholds/).

Conservar el commit, características del servidor/generador, versión k6, duración, modo, alumnos activos, peticiones por segundo, p50/p95/p99, errores por código, CPU/RAM, esperas y conexiones SQL, locks, espacio SSD, conexiones WebSocket y retraso del outbox. No publicar el archivo de credenciales con el reporte.

Antes de aceptar la meta de 1,000 alumnos también falta: sostener conexiones WebSocket de alumnos y operadores, operar cocina y administración durante la carga, probar reconexión/renovación, repetir con inventario finito bajo contención, confirmar ausencia de sobreventa y duplicados con consultas SQL, verificar stock final y ensayar respaldo/restauración. Este script HTTP es una parte de esa validación, no una certificación integral.
