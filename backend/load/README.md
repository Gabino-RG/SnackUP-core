# Prueba de carga pendiente: objetivo de 1,000 alumnos

Este directorio contiene una prueba **optativa**, no un resultado de capacidad. Utiliza el contrato V3 de FastAPI en `/api/v1`, con `expectedTotal`, claves UUID de idempotencia, método `Efectivo` y cancelación `user_other` con notas. No se ejecuta al iniciar la aplicación ni en CI. Las pruebas unitarias, PostgreSQL de CI y este escenario no sustituyen una medición en el servidor asignado.

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
