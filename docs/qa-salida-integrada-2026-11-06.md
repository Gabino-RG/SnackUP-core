# SnackUP integrado · pruebas para la entrega

El ensayo usa las tres aplicaciones de la rama `codex/integracion-local-completa`. La base de la demostración conserva los pedidos creados desde las pantallas. Las pruebas de infraestructura y de carga usan instancias desechables aparte.

## HTTPS, sesiones y recuperación

En la laptop se iniciaron dos procesos de la API en modo `production`, con PostgreSQL 17.11 y Redis 7.4.11. Caddy sirvió las rutas del despliegue y las dos compilaciones Flutter. Se restauró un respaldo de QA en una base temporal y se usó una autoridad certificadora efímera, confiada únicamente por el cliente de prueba.

| Prueba | Resultado observado |
|---|---|
| Conexión segura | El cliente con su almacén normal rechazó el certificado local. Al proporcionar la CA de la prueba, negoció TLS 1.3 y HTTP/2. |
| Rutas de las dos aplicaciones | Alumnos y Paneles devolvieron su propio HTML, código compilado y script de notificaciones. `/paneles` redirigió a `/paneles/`. Una ruta API desconocida y la documentación interna devolvieron 404. |
| Inicio, renovación y cierre | Las cuentas de Alumno, Cocina y Administración abrieron sus sesiones. Se verificaron las marcas de cookie `Secure`, `HttpOnly`, `SameSite=Strict` y su alcance `/api`. La renovación desde otro origen devolvió 403. Cada rol renovó desde el origen correcto y su token perdió acceso después de cerrar sesión. |
| Actualizaciones en tiempo real | Un alumno abrió una conexión WebSocket cifrada por el proxy y recibió confirmación de la suscripción a sus propios pedidos. |
| Caída del servicio compartido | Al detener Redis, la comprobación de disponibilidad devolvió 503. Tras reiniciar ese Redis volvió a 200. El intervalo observado, desde la parada hasta la recuperación, fue de 2.55 segundos. |

Las comprobaciones se hicieron por la red de bucle local. El certificado, los puertos y la base eran exclusivos del ensayo. La prueba del supervisor y el reinicio del contenedor completo son comprobaciones diferentes. En el dominio asignado por TI se deberá verificar la cadena pública y volver a activar y recibir un aviso en ese origen.

## Pruebas desde las pantallas

El [registro de pruebas de la laptop y el Samsung](qa-integracion-2026-11-06.md) relaciona los números de pedido con los resultados observados. Incluye el QR leído con la cámara, la opinión del alumno reflejada en Administración, la recuperación de una compra tras perder su respuesta y el aviso de Android que abrió el pedido correcto en Cocina.

**Carrito con el servidor ocupado.** En una copia de PostgreSQL se ocupó la única plaza de escritura de un proceso de prueba con una renovación de sesión que esperaba un bloqueo de fila. Al confirmar desde Chromium, la API de SnackUP devolvió 503 `SERVICE_BUSY` y `Retry-After: 1`. Se liberó el bloqueo. El carrito repitió la misma solicitud con la misma clave de compra y recibió 201. Transcurrieron 2.397 s entre las dos respuestas. Se abrió el detalle correspondiente al ID confirmado y el conteo de pedidos aumentó exactamente en uno. La base temporal se eliminó. Los proxies y el navegador transmitieron ambas respuestas de la API sin sustituirlas.

## Capacidad de la laptop

El [ensayo de 30 minutos con cuatro procesos](qa-carga-1000-soak-four-2026-11-06.json) mantuvo 1,000 cuentas distintas activas. Cada una consultó locales, productos y pedidos propios en ciclos de 5 a 10 segundos. En conjunto, se programaron cuatro compras nuevas por segundo. Las peticiones llegaron a la API y generaron transacciones reales en una base temporal. El generador y el servidor compartieron la laptop.

| Medición sostenida | Resultado |
|---|---|
| Lecturas | 709,640 respuestas correctas en 709,641 solicitudes. La conexión se interrumpió en una lectura. El 95 % terminó en 120 ms o menos. |
| Compras | 7,199 de 7,200 se confirmaron al primer intento. Se recuperó la restante al reintentar. El 95 % de las solicitudes de creación terminó en 211 ms o menos y el percentil 99 fue de 2.99 s. |
| Sesiones | Se completaron 2,000 renovaciones por cookie. El percentil 95 de renovación fue de 2.57 s. |
| Errores e integridad | En total hubo 11 respuestas de saturación y un error de transporte en 733,252 intentos HTTP. Las repeticiones de cada compra conservaron el ID original. Al cancelar los pedidos se recuperó el inventario inicial; no hubo folios duplicados, bloqueos mutuos de PostgreSQL ni publicaciones pendientes al cierre. |

La ráfaga de 1,000 alumnos que pulsaban comprar a la vez se midió por separado. Con [dos procesos](qa-carga-1000-2026-11-06.json), 584 recibieron el pedido al primer intento. Con [cuatro procesos](qa-carga-1000-four-workers-2026-11-06.json), fueron 743. En esos dos ensayos, el generador espació la recuperación posterior a 15 intentos por segundo hasta confirmar las 1,000 compras.

Al ampliar únicamente la espera de admisión a diez segundos, las 1,000 compras de la ráfaga devolvieron 201 al primer intento. El percentil 95 subió a 7.89 s. [Ejecución interrumpida para apagar la laptop](qa-carga-1000-four-queue10-2026-11-06.json). Se eliminó la base temporal antes de completar las repeticiones y cancelaciones de esa ejecución. Quedan pendientes el ensayo colectivo del reintento automático y el de 1,000 conexiones WebSocket permanentes. El recorrido individual 503 → 201 sí se completó en Chromium.

## Correo y padrón

Las pantallas de Alumnos y Cocina recibieron sus respectivos enlaces de recuperación en un buzón SMTP de la laptop que acepta únicamente correo de prueba. El envío usó STARTTLS con validación de certificado. Ambos usuarios cambiaron su contraseña y entraron desde el acceso correspondiente. Se rechazó el segundo uso de cada enlace. También se completó el alta de un alumno en una base temporal y la matrícula, carrera y grupo coincidieron con la fila del padrón de QA. Los detalles están en el [registro de correo](qa-correo-2026-11-06.json).

En el mismo tipo de instalación aislada, una cuenta de Cocina creada desde Administración tuvo que confirmar su correo para entrar. Otra cuenta, creada mediante solicitud, necesitó además aprobación de la cuenta maestra. La solicitud rechazada recibió 403 al iniciar sesión. Las dos cuentas admitidas pudieron consultar sus propios pedidos y recibieron 403 al intentar acceder al otro local o a la administración de usuarios. En ambas rutas de verificación de alumnos se volvió a comprobar que el registro académico siguiera vigente.

## Entrega de TI

| TI entrega | Validación para abrir el servicio |
|---|---|
| Servidor, dominio y DNS | Desplegar la revisión aprobada, comprobar HTTPS público y abrir ambas aplicaciones desde la red de los alumnos. |
| Remitente SMTP y destinatario autorizado | Confirmar que el buzón institucional recibe los enlaces de alta y recuperación y que ambos abren el dominio definitivo. |
| Fuente académica autorizada | Validar la coincidencia de correo y matrícula y contrastar la carrera y el grupo con un registro oficial autorizado. |
| Recursos y operación del servidor | Repetir la carga con un generador separado, restaurar una copia en un volumen independiente y comprobar que el responsable de TI recibe el aviso de caída de servicio. |
