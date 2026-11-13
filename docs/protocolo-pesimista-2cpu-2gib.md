# Prueba pesimista: 2 vCPU y 2 GiB

Solicitada el 13 de noviembre de 2026 para anticipar una asignación de TI menor a la prevista. El resultado debe describir los límites encontrados, aunque haya fallos; no acredita por sí solo la capacidad de un servidor aún desconocido.

## Entorno y aislamiento

Se ejecuta en Linux mediante `.github/workflows/pessimistic-load.yml`, exclusivamente desde `codex/integracion-local-completa`. Usa la imagen unificada real: aplicaciones compiladas de Alumnos y Paneles, API, Caddy, Redis y scheduler. PostgreSQL y el terminador TLS de prueba son servicios separados del mismo proyecto Compose desechable.

| Servicio | Memoria máxima | CPU permitidas |
|---|---:|---|
| Aplicación, API, Redis, Caddy y scheduler | 1,152 MiB | 0–1 |
| PostgreSQL | 768 MiB | 0–1 |
| Terminador TLS | 128 MiB | 0–1 |
| **Total servicios** | **2,048 MiB (2 GiB)** | **Las mismas dos CPU lógicas** |

Cada contenedor tiene `MemorySwap == Memory`: no se amplía su presupuesto mediante swap. Se verifican los límites efectivos y se registran reinicios y señales de OOM. La API utiliza un worker, una mutación simultánea, dos verificaciones Argon2 simultáneas y pool SQL 10 + 5. Se conservan los parámetros criptográficos; no se abaratan para mejorar el resultado.

El generador, los monitores y las comprobaciones de navegador usan las CPU 2–3 del runner. El sistema operativo, Docker y el generador quedan **fuera** de los 2 GiB asignados a los contenedores. Esta medición no equivale a una máquina virtual completa de 2 GiB, que también tendría que alojar esos componentes. Las dos CPU lógicas del runner tampoco garantizan equivalencia con dos núcleos físicos de otro procesador.

La base `snackup_loadtest` es temporal y separada. Contiene 1,000 cuentas ficticias de alumnos, cuatro locales, cuatro operadores, un administrador y un producto por local. Las cuentas son datos de carga autorizados, no usuarios institucionales. Las operaciones se realizan por HTTP y WebSocket reales, con autenticación y persistencia SQL; no se simulan respuestas del servidor. No se utiliza ni altera la base de demostración de la laptop.

El cliente HTTP y WSS verifica el certificado y el nombre del servidor usando únicamente la CA efímera de esta ejecución. El navegador de comprobación puede aceptar ese certificado de laboratorio; se informa por separado. No se instala una CA en el sistema ni se publica el entorno en Internet.

## Secuencia de medición

Las etapas se ejecutan secuencialmente sobre el mismo entorno limitado. Las pruebas de carga reinician únicamente los pedidos y datos asociados de la base desechable. Fallar un umbral de rendimiento no debe ocultar las etapas posteriores.

| Etapa | Carga | Qué debe observarse |
|---|---|---|
| Integridad | Crear/repetir/cancelar; 200 compradores con stock 50; 50 claves repetidas diez veces | Idempotencia, stock exacto, ausencia de pedidos duplicados |
| Acceso | Tres olas de 200 inicios de sesión | Éxitos, rechazos, latencias y memoria de Argon2 |
| Lecturas | 50, 100, 300, 500 y 1,000 alumnos; 15 s de rampa y 90 s estables por escalón | Catálogo, menú y pedidos; rampa separada del cálculo del objetivo |
| Compras y cancelaciones | 1, 2, 4 y 8 compras/s durante 90 s por escalón | Llegadas programadas, compras efectivas, cancelación, saturación y latencias |
| Ráfaga | 1,000 cuentas compran simultáneamente | Primer intento; un reintento automático de 503 con la misma clave; recuperación posterior separada |
| Tiempo real | 1,000 conexiones WSS durante cinco minutos | Eventos esperados y recibidos, duplicados, latencia y desconexiones |
| Operación combinada | 1,000 lectores y 1,000 WSS, cuatro cocinas con dos tabletas, consultas administrativas y 1.5 compras/s durante diez minutos | Ciclo completo de pedido, aceptación, preparación y entrega, con hasta cinco minutos de drenaje |
| Colaboración durante la operación | Hasta 20 pedidos muestreados, uno de cada 31 creados | Mensaje alumno → cocina → alumno, calificación detallada del pedido entregado y misma opinión/promedio en Administración |

Las consultas periódicas de cada alumno están espaciadas entre cinco y diez segundos; 1,000 alumnos conectados no significa 1,000 peticiones por segundo. Los tiempos de preparación y caminata son reales, de 20–60 s y 5–30 s respectivamente. Los conflictos de versión entre dos tabletas son esperados y se distinguen de errores internos.

Los dos frontends compilados se comprueban en Chromium y WebKit antes y después de la secuencia. Esa comprobación verifica carga y acceso básico; no significa que 1,000 navegadores rendericen simultáneamente todas las pantallas ni que cada botón se haya probado bajo carga.

## Evaluación

- Lecturas: p95 < 750 ms, p99 < 2 s; separar tasa de error y CPU de la fase estable.
- Compras: p95 < 1.5 s; indicar rechazos 503 y latencia total con reintento, además de primeros intentos.
- Acceso por olas: al menos 99% exitoso y p95 < 3 s.
- Tiempo real: entrega completa, sin duplicados ni desconexiones inesperadas; p95 < 2 s para 1,000 sockets.
- Cocina: al menos 99% de los pedidos creados entregados tras el drenaje, aceptación p95 < 10 s y creación p95 < 1.5 s.
- Integridad: cero stock negativo, diferencias de inventario, claves/números/códigos duplicados, deadlocks y publicaciones pendientes después del drenaje.
- Recursos: límites efectivos de memoria y CPU, consumo medido, reinicios y OOM. Con un solo worker no se presenta un cociente de balance entre workers como evidencia.

Cada etapa conserva sus resultados y fallos. Se debe informar el mayor escalón medido que cumple los objetivos y también los superiores que fallen. Un error de instrumentación se identifica y corrige antes de sacar conclusiones de capacidad; no se presenta como defecto de la aplicación ni se borra su ejecución histórica.

Se conservan los JSON de métricas y diagnósticos. No se incluyen cuentas, contraseñas, sesiones, cuerpos de mensajes, claves privadas ni archivos de la base en los artifacts. Al terminar se eliminan contenedores, volúmenes y archivos privados de la prueba.

Quedan fuera de esta medición el correo SMTP, el Push externo, el padrón de la universidad, una base histórica grande, la red del campus y la resistencia durante horas o días. Ninguno se declara aprobado por este ensayo.
