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
