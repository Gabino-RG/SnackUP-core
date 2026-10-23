# Aceptación de la conexión al backend

Estado de esta matriz: **aceptación en servidor institucional pendiente**.
La implementación SQL está en [`backend/`](../../backend/README.md), con pruebas
automáticas de API, permisos y concurrencia. Consultar su workflow para el commit
recibido. Las pruebas locales y el simulador no sustituyen la aceptación del despliegue.
Registrar para cada caso: commit frontend/backend, entorno, fecha, resultado y evidencia.
Usar cuentas autorizadas de prueba. No utilizar la base productiva para carga o fallos.

| Caso | Resultado exigido |
| --- | --- |
| Arranque REST | Sin Firebase ni accesos de demostración; consulta la API del entorno correcto. |
| Login | Credenciales válidas abren el panel por perfil; las inválidas no revelan existencia de cuentas. |
| Recarga y renovación | Cookie HttpOnly/Secure restaura acceso; expiraciones simultáneas no duplican efectos. |
| Logout y revocación | Logout borra cookie y revoca sesión; suspensión/cambio de rol cierra acceso y sockets. |
| Aislamiento | Admin/maestro reciben 403 al operar cocina. Business no accede a admin ni a otro local, incluso llamando HTTP directamente. |
| Solicitudes | Registro 202 sin sesión. Pendiente/rechazado no entra. Solo maestro aprueba; verifica identidad, dominio y local libre. |
| Gestión | Crear/editar locales y cuentas confirma versión. No eliminar último admin, promover maestro ni duplicar operador activo. |
| Referencias | Institución y padrón completo; grupos referencian carreras y no dependen de tener opiniones. |
| Productos | CRUD, imágenes y disponibilidad. Precio en MXN. Omitir stock lo conserva; null es distinto; conflicto no sobrescribe. |
| Imágenes | JPEG/PNG/WebP hasta 5 MiB; URL funciona en móvil y PC; rechazar formatos inválidos y archivos demasiado grandes. |
| Pedido del alumno | Aparece pending en cocina del local correcto; snapshots y reserva de stock al crear según v3. |
| Flujo | pending -> accepted -> preparing -> ready -> completed; no saltar estados ni repetir efectos. |
| Entrega | Código correcto entrega una vez. Código ajeno/incorrecto no entrega y no se expone en lecturas del operador. |
| Cancelación | Solo pending/accepted/preparing; motivo y nota para other; devuelve stock exactamente una vez. |
| Última unidad | Dos compras concurrentes: una aceptada y otra rechazada, sin stock negativo ni reserva parcial. |
| Dos cocinas | Dos tablets con misma versión: una transición válida y un conflicto; nunca doble entrega. |
| Historial y ventas | Totales de todo el periodo, solo entregados; cancelaciones separadas; corte de medianoche local correcto. |
| Opiniones | Pedido entregado y propio, sin duplicadas; ratings ausentes no se vuelven 0; el monitor no crea opiniones. |
| Seguimientos | Versión y evento atómicos; dos admins no se sobrescriben; 404 FOLLOWUP_NOT_FOUND solo si aún no existe seguimiento. |
| Paginación | Página pedida, orden estable, vacíos válidos y cifras completas; UI avisa de datos parciales. |
| Fallos de red | Timeout conserva contexto; no se reenvían mutaciones automáticamente ni se afirma un guardado incierto. |
| WSS | Temas autorizados, reconexión y revocación; al fallar, REST de respaldo sigue funcionando. |
| Contraseñas | Correo real, token de un uso/caducado y revocación al cambiar; respuesta genérica de recuperación. |
| Google, si se habilita | OIDC validado en servidor; nuevo usuario queda pendiente; nunca concede rol por correo o fragmento URL. |
| Dispositivos | Acceso, filtros, formularios y entrega revisados en escritorio, tablet y móvil; cámara en HTTPS con permiso. |
| Capacidad | Medir objetivo actualizado de 1,000 alumnos simultáneos más operadores, con hardware/datos/carga definidos, p95, errores, integridad y comportamiento sin WSS. |
| Operación | Certificados, respaldo/restauración SQL+medios, logs sin secretos, migraciones y procedimiento de maestro documentados. |

Implementado: FastAPI/PostgreSQL, entrega mediante código de pedido y efectivo al
recoger (sin afirmar cobro conciliado). Google está deshabilitado. Decisiones a
cerrar: dominio/HTTPS, acceso y formato de padrón institucional, correo, futura
pasarela de pagos si se requiere, conservación de datos y capacidad real.
No implementar silenciosamente múltiples operadores por local o rutas diferentes:
esos cambios afectan el contrato del frontend y requieren revisión conjunta.

La entrega frontend se acepta por compilación y pruebas propias. La integración
se acepta al completar esta matriz con el backend. La autorización de operación
productiva corresponde al equipo responsable después de verificar su entorno.
