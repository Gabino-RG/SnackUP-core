# Funciones V3.2 de Cocina y Administración

Esta ampliación utiliza el backend `81c76c5eda9ba6315fbf1dcd1a69599f8906db5e`.
No modifica la app de alumnos ni sus ramas. Las respuestas del alumno en las
pruebas se generan mediante HTTP contra la API existente, con cuentas sintéticas.

## Cocina

En el menú **Operación** aparecen cuatro secciones:

- **Chat:** consultar conversaciones activas, enviar texto de hasta 1,000
  caracteres, leer respuestas y cerrar/borrar con confirmación. Para iniciar
  una conversación se usa **Chat del pedido** en una tarjeta de Cocina. El
  backend mantiene una conversación activa por alumno/local, hasta 1,000
  mensajes y caducidad tras 24 horas de inactividad. El panel consulta por HTTP
  cada 10 segundos únicamente con la vista abierta y la aplicación visible;
  también permite actualizar manualmente. La barra superior de Cocina muestra
  actividad de chats desde otras secciones mediante metadatos cada 15 segundos,
  con pausa en segundo plano y reintentos espaciados. No usa Socket.IO para chat
  ni notificaciones del sistema con el navegador cerrado. Los pedidos conservan
  su WebSocket nativo. No se guarda texto del chat en almacenamiento del navegador.
- **Horarios:** activar/desactivar cierre automático, configurar HH:mm, posponer
  el cierre de hoy y ajustar espera de recogida entre 5 y 180 minutos. Los cambios
  envían `expectedVersion`; un conflicto obliga a cargar la versión actual.
  Posponer usa la zona del campus America/Mexico_City, nunca la hora del equipo;
  se deshabilita para locales configurados en otra zona. El cierre no cancela
  pedidos ni reabre automáticamente. El proceso `snackup.jobs` del backend debe
  estar ejecutándose; el contenedor unificado ya lo inicia.
- **Pedidos y vales:** ver recogidas programadas; cancelar pedidos listos por
  no recogidos tras el plazo calculado desde la mayor fecha entre listo y
  recogida programada. La API vuelve a comprobar el plazo. No se reponen
  existencias. En el historial por fecha se puede confirmar que un vale de un
  pedido cancelado no fue canjeado y liberar su reserva. La cancelación no
  concede esa confirmación automáticamente. El servidor impide liberar un vale
  consumido y controla una reserva/consumo global por alumno y fecha del campus.
- **Estadísticas:** últimos 7 o 30 días, detalle diario, productos más vendidos
  y medios de pago de pedidos entregados. No equivale a conciliación de cobros.

## Administración

En **Gestionar locales y cuentas**, el reloj junto al local abre **Consultar
horario**: estado, zona, cierre automático, posposición y espera de recogida,
sin controles de modificación. La administración conserva las opiniones de
0–5 estrellas y sus seguimientos. Según el contrato, ADMIN no puede leer chats,
modificar cierres, cancelar pedidos ni liberar vales; no se amplían esos permisos
en el frontend.

## Contratos y sesiones

Las pantallas existentes conservan `/api/legacy/v1/`. Las funciones nuevas usan
un repositorio separado en `/api/v1/`, con la misma sesión y renovación de token.
El cliente autenticado canónico queda restringido al mismo origen y a ese prefijo;
no acepta otros destinos, medios ni rutas legacy. Al cambiar la sesión se invalidan
los clientes anteriores. El modo de revisión con simulador no habilita V3.2.

El contrato legacy no se sustituye por el canónico. Referencia de nuevas rutas:
`backend/contracts/v3.openapi.json` en la revisión del backend indicada arriba.

## Verificación

- Pruebas unitarias/widgets: límites de destino del token, paginación de mensajes,
  vista administrativa de solo lectura, validación de horario y borrado de texto
  y borrador al expirar una conversación.
- Clientes Flutter contra FastAPI/SQL temporales: guardar horario, posponer,
  ajustar espera, chat de ambos participantes, prohibición de acceso ADMIN,
  cierre del chat, cancelación de no recogido vencido sin reponer stock, rechazo
  antes del plazo y entre locales, liberación de vale cancelado y estadísticas.
- Navegador compilado: pedido por WebSocket, chat enviado/respondido/borrado,
  horario guardado, estadísticas y consulta administrativa sin botones de edición.

Ejecutar `flutter test` y el runner `scripts/integration/live_backend.py` descrito
en [validación del backend](VALIDACION_BACKEND_V32.md). Las capturas y el resultado
del navegador quedan en `build/live-backend/`. La prueba no certifica capacidad de
mil alumnos, SMTP, DNS ni despliegue productivo. No se invoca la UI de alumnos.

Preparación y pruebas pendientes del servidor: [producción de paneles](PREPARACION_PRODUCCION_PANELES.md).
