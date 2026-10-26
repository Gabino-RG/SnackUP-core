# SnackUP en Microsoft SQL Server

## Estado de esta computadora

Se instaló SQL Server Express LocalDB 2022, se registró la instancia exclusiva `SnackUP` y se preparó la adaptación del backend. La creación de la base y la prueba real de conexión están pendientes de reiniciar Windows.

El diagnóstico mostró sectores físicos de rendimiento de 16384 bytes y el motor falló al iniciar. Se aplicó el ajuste oficial `ForcedPhysicalSectorSizeInBytes`, tipo `REG_MULTI_SZ`, valor `* 4095`, en `HKLM\SYSTEM\CurrentControlSet\Services\stornvme\Parameters\Device`. El valor se verificó después de aplicarlo. Windows debe reiniciarse para activarlo; no se programó un reinicio automático.

El respaldo anterior está en `.local/snackup-demo/nvme-device-before.reg`. La documentación oficial de Microsoft explica [el problema, el ajuste y el reinicio necesario](https://learn.microsoft.com/troubleshoot/sql/database-engine/database-file-operations/troubleshoot-os-4kb-disk-sector-size). No se desactivó la protección de Windows.

## Después de reiniciar

1. Abre `INICIAR-SNACKUP-SQLSERVER.cmd` en la carpeta del proyecto. Prepara `SnackUP_Local`, los datos ficticios y la conexión del backend. Si falla, muestra el error y no cambia silenciosamente a SQLite.
2. Abre http://localhost:8080 e inicia sesión con el acceso guardado en `.local/snackup-demo/ACCESO-LOCAL.txt`. Si conservabas una sesión de SQLite, vuelve a iniciar sesión.

Para abrir la base en SQL Server Management Studio:

| Campo | Valor |
| --- | --- |
| Tipo de servidor | Motor de base de datos |
| Servidor | `(localdb)\SnackUP` |
| Autenticación | Autenticación de Windows |
| Base de datos | `SnackUP_Local` |

Si tu versión del cliente solicita confiar en el certificado para esta conexión local, habilita esa opción. No se crean credenciales SQL ni se cambia la contraseña de ninguna instancia existente.

`PREPARAR-SQLSERVER-LOCAL.cmd` prepara solamente la base y su configuración. `DETENER-SNACKUP-LOCAL.cmd` detiene la app y su API; conserva la base y no detiene otras instancias SQL Server. `ENTREGAR-PEDIDO-DE-PRUEBA.cmd` simula la entrega del último pedido de demostración para poder valorarlo.

## Datos y esquema

Se usan los 23 modelos del backend fijado en `1c3459b`: usuarios y sesiones, cafetería, productos e inventario, pedidos y artículos, transiciones, valoraciones del local y del producto, y tablas auxiliares. Los datos de demostración incluyen un alumno, una cuenta interna de cocina, una cafetería y seis productos, uno agotado. Los pedidos y comentarios se guardan al usar la app.

La configuración de conexión está en `.local/snackup-demo/database.json`. Los archivos de SQL Server pertenecen a la instancia LocalDB del usuario de Windows; no están en `demo.db`. La base SQLite anterior se conserva como archivo independiente y no se migra automáticamente. Firebase no se consulta, importa ni modifica.

El archivo `docs/api/sqlserver-schema.sql` contiene el T-SQL para una base nueva y vacía. **No lo ejecutes sobre tablas ya creadas por el preparador**: no es una migración de una base existente ni contiene las contraseñas/datos de demostración.

La adaptación local usa Unicode, claves con longitud válida, índices únicos filtrados, condiciones BIT, promedios decimales y bloqueos de escritura de SQL Server. Las relaciones usan `NO ACTION` para impedir rutas de cascada incompatibles; no se ofrece borrado físico de cuentas/dispositivos en esta demostración. La unicidad del código de recogida se aplica a todos los códigos nuevos. Esto prepara una prueba local; no certifica despliegue de producción ni concurrencia entre múltiples servidores.

## Validación pendiente y realizada

Pasaron cinco comprobaciones sin conexión: condiciones BIT/NULL, bloqueos de inventario, promedio fraccionario, compilación de las 23 tablas y unicidad filtrada. Se ejecutan con `.local\snackup-demo\venv\Scripts\python.exe tools\test_sqlserver_schema.py`.

Después del reinicio falta verificar en el motor real: creación de las tablas, inicio de sesión, catálogo, reserva de existencias, entrega y publicación de valoraciones. La app todavía puede estar sirviendo SQLite hasta ese momento; el inicio de sesión verificado anteriormente corresponde a SQLite, no a SQL Server.
