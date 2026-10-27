# Pedidos simultáneos, desconexiones y cierres

Alcance: Cocina, Administración y sus contratos con el backend V3.2 fijado a
`81c76c5`. Datos sintéticos, SQL temporal y navegador Chromium compilado. La app
de alumnos no se modifica ni se abre: las compras se generan por HTTP como
estímulo del tablero.

## Problema reproducido y corregido

La entrega podía guardarse en el servidor y perder su respuesta en la red. Si
también fallaba la consulta posterior, el diálogo dejaba habilitada la confirmación.
Aunque el controlador bloqueaba operaciones con datos desactualizados, el botón
ofrecía un reintento sin haber comprobado el resultado.

Ahora una respuesta incierta (`NETWORK`, `TIMEOUT`, `INVALID_RESPONSE`), un tablero
desactualizado o una versión diferente bloquean la confirmación del diálogo y
piden volver al tablero y actualizar. Se conserva el código introducido mientras
el diálogo permanece abierto; no se reenvía automáticamente. El código incorrecto
continúa siendo corregible cuando la respuesta del servidor es inequívoca.

La prueba de regresión falló antes del cambio y pasó después. La inyección de
fallos en Chromium también reprodujo el botón habilitado antes de la corrección.

## Escenarios ejecutables

- Cuatro compras concurrentes, números/IDs únicos y descuento exacto del stock.
- Dos intentos de aceptar la misma versión: uno debe aceptar y otro devolver 409.
- Aceptación concurrente de pedidos diferentes.
- Lecturas sin red: conservar tablero visible, bloquear cambios y recuperar al
  volver la conexión.
- Aceptación guardada con respuesta perdida: reconciliar sin repetir el POST.
- Entrega guardada, respuesta perdida y consulta posterior sin red: bloquear
  reenvío; al recuperar conexión, el pedido ya entregado sale del tablero.
- Revocación de la cuenta desde Administración mientras Cocina está abierta:
  se retiran sesión y controles protegidos.
- Guardar cierre y posposición mediante API; ejecutar el ciclo real del scheduler
  al vencimiento, esperando tiempo real. El instante previo comprueba que la
  posposición impide cerrar antes. No se modifica el reloj del sistema.
- El cierre conserva todos los estados de pedidos existentes, rechaza nuevas
  compras y no se repite al ejecutar otro ciclo. Una reapertura manual posterior
  al cierre procesado permanece abierta.

## Reproducir

```sh
python scripts/integration/live_backend.py --backend RUTA/BACKEND/backend --web app/build/web --resilience
```

Primero compilar `lib/main_portal_api.dart` con base `/paneles/`, como indica la
validación V3.2. El runner crea cuentas y contraseñas efímeras, ejecuta la batería
base y luego los escenarios de resiliencia. No admite una URL desplegada.

Por defecto usa SQLite. En la prueba local, las compras simultáneas produjeron
conflictos porque SQLite no implementa los bloqueos por fila de PostgreSQL. Se
registra ese diagnóstico y únicamente se completa la creación de fixtures de
forma serial para continuar las pruebas independientes de interfaz y scheduler.
Eso NO acredita compras concurrentes en producción.

En GitHub, `backend-v32` utiliza un servicio PostgreSQL 17 efímero. La variable
`SNACKUP_TEST_POSTGRES_ADMIN_URL` apunta exclusivamente al servicio loopback.
Se crea una base `snackup_test_<uuid>` y se elimina solo esa base al terminar.
En PostgreSQL no se permiten conflictos en las cuatro compras: deben completarse
las cuatro simultáneamente. No configurar esa variable con credenciales reales.

Resultados por ejecución en `build/live-backend/resilience-api.json` y
`resilience-browser.json`, junto con capturas. El workflow conserva estos archivos
en el artefacto `SnackUP-Paneles-Backend-V32-chromium` o `SnackUP-Paneles-Backend-V32-webkit`. Consultar el resultado del commit
exacto; un resultado anterior no valida cambios posteriores.

## Límites

Es una prueba funcional de concurrencia pequeña, no una certificación de mil
usuarios. El ciclo de cierres es el código real `snackup.jobs.run_cycle`, ejecutado
por el runner; no demuestra supervisión, reinicio o disponibilidad del proceso
Docker institucional. Tampoco acredita SMTP, TLS, capacidad de infraestructura,
restauración de respaldos ni aceptación del personal.
