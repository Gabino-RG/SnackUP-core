# Preparación para producción: Cocina y Administración

Alcance: paneles Flutter REST y herramientas de entrega. No modifica la app de
alumnos ni certifica el sistema completo. Backend fijado a `81c76c5`.
Estado: candidato a validación institucional; no autorizado aún para producción.

## Cambios preparados sin servidor

- Cocina muestra un acceso a conversaciones en la barra superior en todas sus
  secciones. El punto indica actividad, incluidas conversaciones existentes y
  mensajes propios; NO es un contador de mensajes sin leer. Abrirlo reconoce la
  actividad conocida. No se conserva texto ni historial de lectura en disco.
- Consulta solo la primera página de metadatos ordenada por actividad cada 15
  segundos. Se pausa al ocultar la aplicación y se actualiza al volver. Ante
  errores espera 30/60 segundos y muestra un aviso en el botón. Al cerrar sesión
  se destruye el monitor; respuestas tardías no restauran datos.
- Dentro de una conversación se conserva la actualización cada 10 segundos.
  Una lectura exitosa quita el error de conexión anterior. No se reenvía
  automáticamente un mensaje cuya entrega fue incierta.
- No hay notificaciones del sistema operativo con el navegador cerrado. El
  personal debe mantener el panel visible para recibir avisos de actividad.
- Administración conserva permisos de consulta de horarios; no obtiene acceso
  a chats ni permisos operativos de Cocina.

## Comprobación del servidor cuando esté disponible

Desde el paquete o repositorio, con Python 3 y el dominio real:

```sh
python check_panels_server.py --url https://DOMINIO --report comprobacion-paneles.json
```

En el repositorio el script está en `deploy/check_panels_server.py`. Solo realiza
lecturas públicas de salud, acceso y archivos de paneles, sin cuentas. Valida TLS
con el almacén de confianza de Python, no sigue redirecciones y comprueba formato,
rutas, caché y cabeceras. No imprime cuerpos de respuesta ni secretos. Un resultado
correcto no prueba permisos, correo, tareas programadas, carga o restauración.

## Evidencia obligatoria antes del lanzamiento

Registrar fecha, SHA de paneles/backend, navegador, responsable, resultado y
evidencia de cada caso. Pendiente significa pendiente, aunque las pruebas locales
hayan pasado. Usar cuentas y pedidos sintéticos separados de los reales.

| Prueba | Resultado exigido | Estado sin servidor |
| --- | --- | --- |
| HTTPS y rutas | Comprobación anterior aprobada; sin contenido mixto | Pendiente |
| Roles y sesión | Cocina solo su local; Admin sin chat; cerrar sesión y revocar cuenta impiden operar, también tras recarga | Pendiente institucional |
| Pedidos | Recibir, aceptar, preparar, entregar; código incorrecto rechazado; sin duplicados al perder conexión | Pendiente institucional |
| Chat | Aviso desde Productos/Cocina; leer/responder; desconectar y recuperar; borrar sin texto residual; dos locales aislados | Pendiente institucional |
| Cierre | Programar a unos minutos, esperar proceso real, comprobar local cerrado y pedidos existentes conservados; posponer y repetir | Pendiente institucional |
| Vales | Plazo no vencido rechazado; vencido cancelado sin reponer stock; vale consumido nunca liberado | Pendiente institucional |
| Administración | Opiniones 0–5, filtros y seguimiento; gestión de cuentas/locales; horarios de solo consulta | Pendiente institucional |
| Recuperación de acceso | Correo real, enlace válido una vez y vencimiento; ningún secreto en registros | Pendiente SMTP |
| Reinicio | Datos conservados; API, eventos y proceso de tareas recuperados | Pendiente servidor |
| Respaldo | Copia fuera del servidor, restauración en otra base/volumen vacíos; validar pedidos, totales e imágenes | Pendiente servidor |
| Carga | Mezcla acordada de lecturas, eventos y operaciones; medir latencias p95, errores, CPU/RAM y conexiones SQL | Pendiente infraestructura |
| Aceptación | Personal de Cocina y Administración completa su jornada de prueba y firma incidencias resueltas | Pendiente personal |

Para carga, aumentar progresivamente y acordar umbrales antes de ejecutar. Mil
alumnos conectados no equivalen a mil peticiones por segundo ni a mil cocineros.
Coordinar tráfico sintético de la API con el equipo responsable sin desarrollar
ni modificar la app de alumnos. No ejecutar carga sobre producción sin una ventana
autorizada. Las pruebas unitarias no acreditan capacidad concurrente.

## Respaldos y recuperación

El script original `deploy/backup.sh` del backend usa el servicio `api` del Compose
separado; el paquete unificado usa `app`. Para este paquete, desde `backend/`:

```sh
sh backup_unified.sh /RUTA/PRIVADA/RESPALDOS
```

Usa el proyecto `snackup-piloto`; si se cambió, establecer
`SNACKUP_COMPOSE_PROJECT` al nombre real. No incluye secretos. No detener servicios
ni cambiar datos automáticamente. Hacerlo en una ventana sin escrituras para
mantener coherencia entre SQL e imágenes. Archivos `.partial` indican fallo y no
son respaldos utilizables. Verificar `SHA256SUMS`, cifrar y copiar fuera del host.
El script se entrega preparado, sin afirmar que se haya ejecutado contra Docker
institucional. Probarlo junto con la restauración antes de habilitar producción.

Restaurar con `pg_restore --exit-on-error --single-transaction` en otra base vacía
y las imágenes en otro volumen. Ajustar propietarios/roles según el backend;
nunca usar la base real para ensayar. Acordar retención, pérdida máxima tolerable
de datos (RPO), tiempo de recuperación (RTO) y responsable.

Para volver a una entrega anterior conservar paquete, SHA e imagen previos.
Cambiar solo el contexto/imagen de paneles cuando el contrato siga siendo
compatible. No retroceder migraciones ni restaurar una base sobre la activa
como mecanismo automático de reversión. Ensayar primero en el entorno de pruebas.

## Monitoreo mínimo

Supervisar `/health/ready`, estado de contenedores, errores HTTP, espacio en disco,
antigüedad del último respaldo y proceso de tareas. Salud de la API por sí sola
no garantiza ejecución de cierres. Asignar un responsable y un destino de alertas
institucional; esto requiere acceso y no queda activado por generar el paquete.
