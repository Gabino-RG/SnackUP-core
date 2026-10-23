# WebSocket de Cocina

Conectar a `/api/legacy/v1/realtime`, cambiando HTTPS por WSS. WebSocket nativo, no Socket.IO.
El upgrade no lleva Bearer en la URL. Validar Origin antes de aceptar y autorizar
mensajes en orden. No suscribir temas antes de validar el mensaje `auth`.

Cliente:
```json
{"action":"auth","token":"<accessToken>"}
{"action":"subscribe","topics":["business:local-1:orders","business:local-1"]}
```

Servidor, solo para el operador de ese local:
```json
{"type":"subscribed","topics":["business:local-1:orders","business:local-1"]}
{"id":"evento-1","type":"order.updated","topic":"business:local-1:orders","data":{"id":"pedido-1","version":4,"status":"ready"}}
```

Tipos reconocidos: `order.created`, `order.updated`, `business.updated`. IDs de
evento únicos; no enviar códigos de recogida o matrícula. Los avisos provocan una
lectura REST, no sustituyen la autorización ni modifican directamente el estado.
Publicar después del commit SQL; una outbox es una opción de implementación.

Heartbeat: servidor `{"type":"ping"}`, cliente `{"action":"pong"}`. El cliente
reenvía `auth` cada minuto. Revalidar cuenta, rol y local y cerrar suscripciones
revocadas. Errores `{"type":"unauthorized"}` o `{"type":"error"}` desconectan.
Administradores, incluido maestro, no pueden suscribirse a pedidos de cocina.

Si no hay confirmación en 10 segundos, el cliente usa REST cada 10 segundos.
Con suscripción, reconcilia cada 60 segundos. Reconecta tras 10 segundos; desde
tres fallos espera 60 segundos. Al ocultar el panel suspende conexiones y consultas.
Un servicio sin WebSocket puede responder 503 con error `POLLING_MODE`, como el
simulador; esto no acredita funcionamiento de WSS. La API REST debe seguir disponible.

El cliente no consume eventos de productos ni opiniones. No promete avisos con
la pestaña cerrada. Probar reconexión, cambio de sesión y revocación en el backend real.

## Convivencia con V3

Este documento describe el protocolo que ya consume el portal de compatibilidad.
Socket.IO V3 se conecta por `/socket.io/` y usa salas autorizadas; no es intercambiable
con este WebSocket. `OperationsRealtime` deriva `realtime` de la base REST, por lo que
la base `/api/legacy/v1/` mantiene su ruta correcta sin modificar el cliente.
