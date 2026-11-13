# SnackUP integrado · continuación de las pruebas de carga

El 10 de noviembre de 2026 se retomaron las comprobaciones interrumpidas al apagar la laptop. La rama de trabajo es `codex/integracion-local-completa`. El servidor de demostración conserva su base y sus cuentas. Los ensayos de carga usan cuentas sintéticas autorizadas y bases PostgreSQL independientes y temporales.

## Verificaciones de GitHub

La ejecución del 10 de noviembre verificó el commit `1a12094848b108252aae40d8b433f77554302a43`, que refuerza la detección de eventos inesperados en el generador de carga. No modifica la lógica de la aplicación. Cada informe de carga identifica el commit usado en su propia ejecución.

| Comprobación | Evidencia |
|---|---|
| Backend con PostgreSQL | [307 pruebas aprobadas](https://github.com/Gabino-RG/SnackUP-core/actions/runs/42904522749/job/130138913767), en 232.78 segundos. Un aviso de deprecación, sin fallos. |
| Contenedor integrado y navegadores | [Compilación, supervisión, HTTP y Socket.IO aprobados](https://github.com/Gabino-RG/SnackUP-core/actions/runs/42904522749/job/130138914407). Alumnos y Paneles abrieron en Chromium y WebKit: cuatro comprobaciones aprobadas. Las dos pruebas de supervisión también pasaron. |
| Flutter de Alumnos | [Análisis, 66 pruebas y compilación web aprobados](https://github.com/Gabino-RG/SnackUP-core/actions/runs/42288811143) en `a5f8c71`. Los archivos de esa aplicación y su workflow no cambiaron entre ese commit y `1a12094`. |

## Compras simultáneas con diez segundos de espera

El [informe completo](qa-carga-1000-four-queue10-2026-11-10.json) registra cuatro procesos de API con dos escrituras simultáneas por proceso. El generador distribuyó las solicitudes directamente entre puertos HTTP locales, con PostgreSQL y Redis en la misma laptop.

| Comprobación | Resultado |
|---|---|
| 1,000 compras lanzadas a la vez | 1,000 respuestas 201 al primer intento; ninguna respuesta 503. El percentil 95 fue de 5,070 ms. |
| Repetición de las 1,000 claves | Las 1,000 respuestas conservaron el pedido original. |
| Cancelación | Se cancelaron los 1,000 pedidos y se recuperó el inventario inicial. |
| 200 compradores por 50 unidades | Exactamente 50 compras aceptadas y 150 rechazos por falta de existencias. El stock llegó a cero y se recuperaron las 50 unidades al cancelar. |
| Diez envíos simultáneos de 50 compras | 500 respuestas 201, con un único pedido y cuerpos idénticos para cada clave. Los 50 pedidos se cancelaron. |
| Comprobación final de PostgreSQL | 1,100 pedidos cancelados y 1,100 claves. Sin duplicados, stock negativo, diferencias de inventario, bloqueos mutuos ni publicaciones pendientes. |

La integridad de esta ejecución pasó. La latencia de la ráfaga **no cumplió** el objetivo de creación p95 inferior a 1.5 segundos. Aumentar la espera de admisión permitió aceptar las compras, pero no hizo que cumplieran ese objetivo. No se cambió la configuración de la aplicación de demostración ni se relajaron los umbrales para presentar el ensayo como aprobado.

## Reintento automático ante saturación

La [ráfaga con cinco segundos de admisión](qa-carga-1000-four-auto5-2026-11-10.json) conservó los cuatro procesos y dos escrituras simultáneas por proceso. De 1,000 compras, 804 recibieron 201 en el primer intento y 196 recibieron 503 `SERVICE_BUSY` con `Retry-After: 1`. Cada una de esas 196 compras se repitió una sola vez, con la misma clave y el mismo contenido, tras esperar el segundo indicado más una dispersión de 0 a 1,499 ms. Las 196 recibieron 201. Se confirmaron las 1,000 compras sin recuperación manual posterior.

El p95 del primer intento fue de 5,289 ms. Al incluir la espera y el reintento, el p95 hasta confirmar la compra fue de 7,458 ms y el p99 de 7,734 ms. Las 1,000 repeticiones conservaron el ID original y se cancelaron los 1,000 pedidos. PostgreSQL confirmó el inventario completo, cero duplicados, cero bloqueos mutuos y ninguna publicación pendiente.

La recuperación automática y la integridad pasaron. El porcentaje de rechazo inicial, 19.6 %, superó el límite propuesto del 1 %, y la latencia superó el objetivo de 1.5 segundos. Estos resultados permanecen marcados como incumplimientos en el JSON.

El generador ejerció HTTP y PostgreSQL reales. Reproduce la política de un reintento y su rango de dispersión; usa números aleatorios, mientras Flutter obtiene la dispersión de la clave. No se ejecutaron 1,000 navegadores Flutter. La prueba individual del carrito compilado que recibió 503 y después 201 consta en la revisión del 6 de noviembre.

## Conexiones en tiempo real: medición parcial

El [ensayo WSS del 10 de noviembre](qa-carga-1000-ws-four-2026-11-10.json) mantuvo 1,000 suscripciones durante cinco minutos detrás de Caddy con TLS. Los 236 cambios de disponibilidad produjeron las 59,000 entregas esperadas, sin pérdidas, destinatarios inesperados, duplicados ni desconexiones inesperadas. El p95 de entrega fue de 243 ms.

El observador de Windows tomó los PID de los lanzadores del entorno virtual, en lugar de los procesos Python hijos que atendían las conexiones. Sus cifras de CPU y conexiones TCP fueron inválidas. El informe conserva `success=false` y el código de salida 1; esta ejecución **no aprueba el criterio completo de capacidad**. La [continuación del 13 de noviembre](qa-salida-integrada-2026-11-13.md) registra la comprobación pendiente en Linux y el bloqueo posterior del arranque local por Device Guard.

## Alcance

Los resultados de hoy se complementan con la [prueba sostenida de 30 minutos](qa-carga-1000-soak-four-2026-11-06.json), ya completada el 6 de noviembre. Esa prueba no se repitió. La [revisión anterior](qa-salida-integrada-2026-11-06.md) conserva las comprobaciones de sesiones, correo local, Android, notificaciones, QR y recuperación de compras.

La laptop tiene 12 núcleos físicos, 24 procesadores lógicos y 15.62 GiB de RAM. Las métricas del host incluyen otras aplicaciones y el generador. La memoria física disponible mínima fue de 12 MiB durante el primer perfil y 495 MiB durante el segundo: hubo presión de memoria que limita la comparación de tiempos entre ejecuciones. Estos mínimos no miden exclusivamente el consumo de la API.

Los recursos de TI siguen pendientes: servidor, dominio y HTTPS públicos, remitente SMTP y fuente académica autorizada. Las mediciones en la laptop no acreditan por sí solas la capacidad del servidor definitivo. Allí se deben repetir la carga con un generador separado y las pruebas de correo, notificaciones, respaldo y alertas con sus recursos reales.
