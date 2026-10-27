# SnackUP: guía de Cocina y Administración

Entrega web adaptable a móvil, tablet y PC. Se abre en el navegador desde la
dirección HTTPS proporcionada por la institución, normalmente `/paneles/`.
No es un APK ni una aplicación publicada en las tiendas. Las cuentas definitivas
las autoriza Administración; el paquete no incluye contraseñas de producción.

## Cocina: comenzar el turno

1. Iniciar sesión y comprobar el nombre del local.
2. Revisar conexión, productos disponibles y horario de cierre.
3. Activar **Recibir pedidos** cuando el local esté preparado.
4. Mantener el panel visible. El sonido de pedidos se activa desde el icono de
   volumen; el navegador puede requerir esa interacción para permitir audio.

En PC las secciones aparecen en el lateral; en móvil, en la barra inferior.
En pantallas pequeñas o con teclado abierto algunas áreas necesitan desplazarse.
Si el dispositivo usa letra ampliada, los controles siguen disponibles mediante
desplazamiento; no es necesario reducir el tamaño del texto del sistema.

## Atender pedidos

**Aceptar → Iniciar preparación → Marcar listo → Verificar entrega.**
La entrega requiere el código del cliente o un QR válido. Para usar la cámara,
el sitio necesita HTTPS y permiso de cámara. Si no está disponible, introducir
el código manualmente. No entregar con el código de otro pedido.

Si otro equipo ya cambió el pedido, revisar el tablero actualizado antes de
actuar. Si se pierde la conexión, los datos visibles pueden ser antiguos y se
bloquean los cambios hasta recuperar la consulta. Una entrega sin respuesta
puede haberse guardado: volver al tablero y actualizar, sin repetirla a ciegas.

## Chat

Abrir **Chat del pedido**, **Operación → Chat** o el icono superior. El punto
del icono indica actividad de conversaciones, no un contador de mensajes sin
leer. También puede incluir mensajes propios y conversaciones existentes.

Dentro del chat se consulta cada 10 segundos; el indicador general, cada 15
segundos mientras la aplicación está visible. No hay avisos del sistema con
el navegador cerrado. Conservar el panel visible durante el turno.

Los mensajes admiten hasta 1,000 caracteres. Si un envío falla, comprobar la
conversación antes de repetirlo. **Cerrar y borrar** elimina la conversación
para ambos participantes; requiere confirmación. Expira tras 24 horas sin
actividad. No usar el chat como archivo permanente de incidencias.

## Horarios, vales y resumen

- **Operación → Horarios:** guardar hora local HH:mm, activar cierre automático,
  posponer el cierre de hoy y configurar espera de recogida. Posponer usa la
  zona del campus, no la hora del teléfono. El cierre impide pedidos nuevos;
  permite terminar los existentes. La reapertura es manual.
- **Pedidos y vales:** cancelar como no recogido solo después del plazo. No se
  repone inventario. Liberar un vale de pedido cancelado requiere confirmar que
  realmente no fue canjeado; un vale consumido no se puede liberar.
- **Estadísticas:** consultar periodos y ventas entregadas. El medio de pago
  registrado no demuestra que el cobro haya sido conciliado.

## Administración

Revisar opiniones y seguimientos, gestionar locales y autorizar cuentas según
los permisos asignados. Comprobar identidad y local antes de habilitar Cocina.
El reloj junto al local permite consultar su horario. Administración no puede
leer chats ni modificar cierres o pedidos desde esa vista.

Al suspender una cuenta, su sesión deja de poder operar. Usar una cuenta propia
por responsable autorizado; no compartir contraseñas entre roles. Cerrar sesión
al terminar el turno, especialmente en equipos compartidos.

## Cuando algo falla

| Situación | Acción |
| --- | --- |
| Datos desactualizados o sin conexión | Recuperar red y actualizar el tablero antes de operar |
| Resultado de entrega o envío incierto | Consultar su estado; no asumir que falló ni repetir automáticamente |
| Otro dispositivo cambió el registro | Recargar y revisar el cambio antes de guardar |
| Sesión terminada o acceso retirado | Iniciar sesión de nuevo o consultar al administrador |
| Cierre automático no ejecutado | Avisar al responsable técnico; cerrar recepción manualmente si corresponde |
| QR no disponible | Introducir el código manualmente; verificar permisos y HTTPS |

Para soporte, anotar hora, local, número de pedido, acción y mensaje de error.
No enviar contraseñas, tokens ni capturas con conversaciones privadas.

## Antes de usar con datos reales

Completar la aceptación institucional descrita en
[preparación para producción](PREPARACION_PRODUCCION_PANELES.md): servidor,
HTTPS, correo, respaldos restaurables, monitoreo, carga y validación del personal.
Los ensayos de navegador y tamaños de pantalla no sustituyen la prueba en los
teléfonos y PC concretos del campus, incluida cámara, teclado y permisos.
