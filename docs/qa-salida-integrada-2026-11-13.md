# SnackUP integrado · comprobación de tiempo real

El 13 de noviembre se retomó la comprobación WSS pendiente. Los [ensayos HTTP del 10 de noviembre](qa-salida-integrada-2026-11-10.md) ya estaban completos y no se repitieron. Sus resultados de integridad y recuperación automática pasaron; la latencia de las ráfagas superó el objetivo propuesto.

## Estado de la laptop

El script habitual de inicio no pudo arrancar PostgreSQL. Windows rechazó `postgres.exe` con un mensaje explícito de la directiva Device Guard. Los puertos locales de la aplicación y PostgreSQL no estaban escuchando al realizar esta comprobación. Se conservaron el directorio de datos, la configuración privada y las compilaciones de ambas aplicaciones.

El bloqueo requiere una instalación o autorización de PostgreSQL aprobada por el administrador del equipo. No se modificaron las políticas de Windows. Hasta resolverlo, el servidor local no está disponible; una ejecución correcta en GitHub no cambia ese estado.

## Comprobación WSS completada en Linux

El [ensayo anterior](qa-carga-1000-ws-four-2026-11-10.json) observó las 59,000 entregas esperadas a 1,000 suscripciones, con p95 de 243 ms y sin pérdidas ni duplicados. Su medición de CPU y conexiones TCP era inválida porque el observador de Windows tomó los procesos lanzadores. Se conserva con su fallo original, acompañado de una aclaración de instrumentación.

La [ejecución completa P8-1000](https://github.com/Gabino-RG/SnackUP-core/actions/runs/43517178732) pasó en el commit `879412334a8b5a803713e7c3a272e7ae7033828b`. Se conservaron el [JSON original de métricas](qa-carga-1000-wss-linux-2026-11-13.json) y el [diagnóstico de servicios y versiones](qa-carga-1000-wss-linux-servicios-2026-11-13.json), copiados sin modificar desde el artifact.

| Comprobación | Resultado observado |
|---|---|
| Conexiones | 1,000 cuentas con suscripciones confirmadas, durante cinco minutos completos. La ejecución con preparación y drenaje duró 326.64 segundos. |
| Entregas | 236 cambios de disponibilidad y 59,000 de 59,000 entregas esperadas. Se comprobó cada destinatario y versión. |
| Pérdidas y duplicados | Cero pérdidas, entregas a destinatarios inesperados, duplicados, eventos ajenos y desconexiones inesperadas. |
| Latencia de evento | p95 de 270.91 ms y p99 de 347.10 ms. Cumplió el objetivo p95 inferior a 2 segundos. |
| Distribución de CPU | Cuatro procesos reales medidos. Relación entre el mayor y menor consumo medio: 1.0896, inferior al límite de 2. |
| Memoria de contenedores | Pico conjunto de 1,237.3 MiB, incluidos aplicación, PostgreSQL y gateway TLS. El consumo del generador no está incluido en ese pico. |
| Integridad y publicaciones | Inventario correcto, cero bloqueos mutuos y cero publicaciones pendientes. El escenario cambia disponibilidad y no crea pedidos. |
| TLS | Certificado y nombre del servidor verificados con una CA efímera confiada únicamente por el cliente. |
| Limpieza | El paso de retirada de contenedores, volúmenes y credenciales temporales terminó correctamente. |

Los nueve controles finales del informe pasaron. El runner tenía cuatro procesadores lógicos y 16,366,632 KiB de RAM; generador y servicios compartían esa máquina. Se midieron PostgreSQL 17.12, Redis 7.0.15 y Caddy 2.11.7. Estas versiones y recursos difieren de los de la laptop, por lo que los resultados se mantienen separados.

La evidencia proviene del job `132201987989` y artifact `14082620155`. SHA-256 del ZIP original: `6f537398394e36f522fee4774ac99a05b3946e97c7fd959168e5c18f7ea904df`. Los resultados permanecen en el repositorio aunque caduque la retención del artifact de GitHub.

## Corrección de la preparación en Linux

La [primera ejecución de GitHub](https://github.com/Gabino-RG/SnackUP-core/actions/runs/43515126430) construyó la imagen, pero se detuvo antes de crear las cuentas o empezar la carga. El listener de salud del Caddyfile de pruebas solo aceptaba `Host: 127.0.0.1`; el comprobador enviaba el nombre del origen HTTPS, `localhost:18443`. El contenedor no podía quedar saludable con esa combinación.

Se alineó ese listener con el del contenedor principal: acepta el nombre del origen y permanece enlazado exclusivamente a `127.0.0.1`. Se conservaron las comprobaciones de salud y TLS. La limpieza de la ejecución fallida pasó. Se añadieron diagnósticos acotados y redactados para que futuros fallos de preparación dejen evidencia útil.

El [segundo intento](https://github.com/Gabino-RG/SnackUP-core/actions/runs/43515939727) ya obtuvo aplicación y PostgreSQL saludables, pero Compose exigió un healthcheck para el gateway TLS adicional. Se incorporó una consulta real a `/health/ready` por HTTPS, con comprobación de certificado y nombre usando la CA interna. Ese intento también terminó antes de crear fixtures o medir carga, y retiró sus recursos temporales. Estos dos fallos de preparación se conservan como antecedentes de la configuración corregida.

En el [tercer intento](https://github.com/Gabino-RG/SnackUP-core/actions/runs/43516408115) los tres servicios quedaron saludables y el HTTPS interno pasó. La copia del certificado público no produjo el archivo esperado para el cliente y la comprobación se detuvo con `FileNotFoundError`, antes de crear las cuentas o medir carga. Se sustituyó esa copia por una lectura del certificado público desde el servicio en ejecución, con validación del PEM y del contexto SSL antes de guardarlo en el directorio privado del runner. La clave privada permanece dentro del contenedor y la CA se confía únicamente en el cliente de prueba.

## Verificación del contenedor y las aplicaciones

La [ejecución completa del 13 de noviembre](https://github.com/Gabino-RG/SnackUP-core/actions/runs/43516408560) pasó en el commit `6dee93f11fe379eec5c49b4909d462def88a9fd4`:

| Comprobación | Resultado |
|---|---|
| Backend con PostgreSQL | [319 pruebas aprobadas](https://github.com/Gabino-RG/SnackUP-core/actions/runs/43516408560/job/132199576129), un aviso de deprecación, 226.23 segundos. Incluye las doce pruebas nuevas de aislamiento del destino y validación TLS del generador. |
| Compilación y supervisión | [Ambas aplicaciones compiladas](https://github.com/Gabino-RG/SnackUP-core/actions/runs/43516408560/job/132199574943) y dos comprobaciones de supervisión aprobadas. |
| API y tiempo real básico | 28 comprobaciones HTTP/WebSocket iniciales y otras 28 después de detener Redis y recuperar el contenedor. |
| Navegadores | Cuatro comprobaciones aprobadas: Alumnos y Paneles en Chromium 151.0.7922.34 y WebKit 26.5, con respuesta 200 de las opciones de acceso. |
| Limpieza | Recursos temporales de la ejecución retirados correctamente. |

El commit `879412334a8b5a803713e7c3a272e7ae7033828b` solo modifica la transferencia del certificado en el workflow WSS. La aplicación, el backend, el despliegue y los tests son idénticos a los comprobados en `6dee93f`.

## Límites de la entrega

La ejecución Linux mide ese entorno de GitHub, no la laptop ni el servidor de la universidad. El generador comparte máquina con los servicios. Las pruebas de carga usan cuentas sintéticas exclusivamente en una base temporal separada de la demostración. No prueban 1,000 navegadores Flutter, renovación o reconexión de los 1,000 sockets, ni el envío de notificaciones del sistema operativo.

Para producción siguen pendientes los recursos de TI: servidor, dominio y HTTPS públicos, remitente SMTP y fuente académica autorizada. En ese entorno deben repetirse capacidad, recepción de correo y notificaciones, restauración de copias y alertas de operación. La ráfaga extrema de compras tampoco ha cumplido todavía el objetivo de latencia de 1.5 segundos.
