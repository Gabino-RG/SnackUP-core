# SnackUP integrado · comprobación de tiempo real

El 13 de noviembre se retomó la comprobación WSS pendiente. Los [ensayos HTTP del 10 de noviembre](qa-salida-integrada-2026-11-10.md) ya estaban completos y no se repitieron. Sus resultados de integridad y recuperación automática pasaron; la latencia de las ráfagas superó el objetivo propuesto.

## Estado de la laptop

El script habitual de inicio no pudo arrancar PostgreSQL. Windows rechazó `postgres.exe` con un mensaje explícito de la directiva Device Guard. Los puertos locales de la aplicación y PostgreSQL no estaban escuchando al realizar esta comprobación. Se conservaron el directorio de datos, la configuración privada y las compilaciones de ambas aplicaciones.

El bloqueo requiere una instalación o autorización de PostgreSQL aprobada por el administrador del equipo. No se modificaron las políticas de Windows. Hasta resolverlo, el servidor local no está disponible; una ejecución correcta en GitHub no cambia ese estado.

## Comprobación pendiente de WSS

El [ensayo anterior](qa-carga-1000-ws-four-2026-11-10.json) observó las 59,000 entregas esperadas a 1,000 suscripciones, con p95 de 243 ms y sin pérdidas ni duplicados. Su medición de CPU y conexiones TCP era inválida porque el observador de Windows tomó los procesos lanzadores. Se conserva con su fallo original, acompañado de una aclaración de instrumentación.

La continuación utiliza el generador P8-1000 en un entorno Linux de GitHub Actions, con PostgreSQL y servicios desechables. Debe sostener las 1,000 conexiones durante cinco minutos completos, comprobar cada destinatario y versión, medir latencia y CPU de los cuatro procesos reales y verificar el inventario y la cola de publicaciones al cierre. El certificado del ensayo se confía únicamente en el proceso cliente.

El resultado definitivo y el enlace a la ejecución se incorporarán después de comprobar el artifact. Esta descripción no declara aprobada una ejecución en curso.

## Límites de la entrega

La ejecución Linux mide ese entorno de GitHub, no la laptop ni el servidor de la universidad. El generador comparte máquina con los servicios. Las pruebas de carga usan cuentas sintéticas exclusivamente en una base temporal separada de la demostración. No prueban 1,000 navegadores Flutter, renovación o reconexión de los 1,000 sockets, ni el envío de notificaciones del sistema operativo.

Para producción siguen pendientes los recursos de TI: servidor, dominio y HTTPS públicos, remitente SMTP y fuente académica autorizada. En ese entorno deben repetirse capacidad, recepción de correo y notificaciones, restauración de copias y alertas de operación. La ráfaga extrema de compras tampoco ha cumplido todavía el objetivo de latencia de 1.5 segundos.
