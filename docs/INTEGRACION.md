# SnackUP: aplicación integrada

La entrada de la aplicación es `app/lib/main.dart`. Alumno, negocio y administración comparten Firebase Authentication, Firestore, los pedidos y las reseñas del proyecto ya configurado `snackup-8fe96`. El paquete de PC se construye desde esa entrada; no abre `main_admin_demo.dart` ni inserta locales u opiniones ficticias.

El código se trabaja en `test/api-aaa-sonarqube`. No se ha publicado esta revisión en Firebase ni modificado `main`.

## Recorrido de la aplicación

| Paso | Comportamiento |
| --- | --- |
| Acceso | Inicio de sesión común; el servidor proporciona el rol. El alumno puede completar un registro cuyo perfil quedó pendiente. Una falla de red muestra reintento. |
| Alumno | Consulta el catálogo, añade productos a un carrito de un solo local y confirma la cotización actual. |
| Pedido | La transacción vuelve a leer carrito, catálogo y local; guarda el pedido y vacía sus renglones de carrito juntos. El precio se expresa en centavos enteros. |
| Negocio | Acepta y reserva existencias en una transacción; prepara, marca listo y confirma la entrega con un código específico del pedido. |
| Reseña | El alumno califica un pedido propio entregado. Se conservan general, servicio, alimentos, comentario y carrera/grupo opcionales. |
| Administración | La cuenta con claim booleano `admin: true` entra desde el mismo login. Consulta opiniones reales, filtra, compara locales y registra seguimientos persistentes con historial. |

El límite de un pedido es de 8 productos distintos y de 1 a 99 unidades por producto. Las reglas pueden verificar cada precio del catálogo y la suma del pedido dentro del límite de lecturas de Firestore. El inventario se reserva al **aceptar** el pedido, no al añadir al carrito; el negocio debe aceptar antes de preparar. La programación admite hasta las siguientes 24 horas. Los pedidos vencidos continúan visibles para el negocio.

Los pedidos anteriores siguen siendo legibles. Su QR de entrega usa el identificador del pedido si no existe un código nuevo; no usa la matrícula como contraseña. Las reseñas históricas sin servicio/alimentos no cuentan como cero en esos promedios. No se migran ni borran registros existentes automáticamente.

Antes de activar, hay que revisar los pedidos antiguos pendientes que excedan 8 renglones/99 unidades o carezcan de identificadores de producto: no cumplen el contrato de reserva y no se pueden aceptar con esta revisión. El negocio puede cancelarlos y acordar un pedido válido con el alumno. Los pedidos ya en preparación o listos conservan su recorrido de entrega y no reciben una reserva retroactiva; debe revisarse el inventario al activar.

## Configuración preparada en el repositorio

- `app/firebase.json` referencia reglas de Firestore, índices y Storage, además del hosting existente.
- `app/firestore.rules` valida perfiles, catálogo, pedidos, reseñas y seguimientos; las reglas candidatas anteriores de `tests/api/candidates/` se conservan como antecedentes.
- `app/firestore.indexes.json` describe los índices del conjunto integrado.
- `app/storage.rules` protege las imágenes de productos por propietario del negocio y limita tipos/tamaño.
- `tools/access/` contiene herramientas para provisionar accesos desde un entorno de confianza. Las credenciales administrativas nunca se incluyen en Flutter ni en el ZIP.
- `scripts/pc/` genera la descarga de Windows con la aplicación web compilada y un servidor local. Consulta [PC.md](./PC.md).
- CI compila `lib/main.dart` y conserva su artefacto web, además de ejecutar las pruebas de Flutter.

## Activación necesaria en Firebase

Una compilación correcta no prueba las reglas que actualmente tiene el servidor. Para habilitar esta revisión con datos reales, el responsable de Firebase debe:

1. Comparar las reglas e índices propuestos con la configuración vigente y revisar la compatibilidad de los registros existentes. No reemplazar reglas de colecciones ajenas sin conocerlas.
2. Ejecutar la suite de reglas en un entorno aislado autorizado y comprobar casos permitidos y denegados. La revisión estática no sustituye esa ejecución.
3. Confirmar las cuentas de negocio y la propiedad de sus locales; designar el correo/UID administrativo. Asignar claims desde Admin SDK preservando los claims existentes. Renovar la sesión después de asignarlos.
4. Activar las reglas e índices aprobados y la autorización Storage→Firestore necesaria para comprobar la propiedad de las imágenes. Esperar a que los índices terminen de construirse.
5. Probar con cuentas autorizadas: pedido → aceptación → preparación → entrega → reseña → consulta administrativa → seguimiento → recarga. Comprobar también que un alumno no acceda a datos ajenos ni a administración.
6. Publicar la compilación integrada en el destino aprobado cuando esa comprobación termine.

Esta revisión no ha cambiado permisos, cuentas ni datos del Firebase real. No existen credenciales de prueba productivas en el paquete. La anterior ejecución de emuladores fue bloqueada por revisión automática al intentar acceder a un endpoint remoto; no se reintentó esa operación ni se presenta la suite como ejecutada.

## Alcance operativo

- La aplicación conectada requiere internet y una cuenta válida. Los cambios aceptados por Firebase permanecen al recargar; no dependen de la memoria de una demo.
- Efectivo, tarjeta y vale indican la forma de pago **en el local**. No hay cobro electrónico integrado ni comprobación bancaria automática.
- Las alertas de pedidos funcionan con la aplicación abierta. No se declara entrega de notificaciones push en segundo plano.
- Carrera y grupo son autodeclarados. No existe integración con el padrón escolar.
- El monitor carga páginas de datos y muestra cuando el resultado es parcial. Actualizar vuelve a consultar el servidor; no se presenta como una suscripción continua.
- El aviso de privacidad debe ser revisado por la institución antes de uso real. No se afirma cumplimiento legal, capacidad de 2,500 usuarios ni disponibilidad garantizada por compilar la app.

Los resultados concretos de la verificación se registran en [VALIDACION_INTEGRADA.md](./VALIDACION_INTEGRADA.md).
