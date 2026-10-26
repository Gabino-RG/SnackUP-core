# Base de datos local

Desde la carpeta del proyecto, abre `INICIAR-SNACKUP-LOCAL.cmd`. Luego entra a http://localhost:8080. La primera ejecución prepara Python, las dependencias del backend y el cliente web; requiere Git, Python 3.11 o posterior, Node 20 o posterior y Flutter disponibles.

El correo y la contraseña de prueba se guardan en `.local/snackup-demo/ACCESO-LOCAL.txt`. Son cuentas locales; las cuentas de Firebase no sirven para esta demostración.

La base SQLite está en `.local/snackup-demo/demo.db`. Conserva usuarios, cafetería, productos, existencias, pedidos, estados y valoraciones al reiniciar. Empieza con una cafetería, un alumno, una cuenta interna de cocina y seis productos ficticios, incluido uno agotado para comprobar que no aparezca en el menú. Los pedidos y las reseñas se crean al usar la app.

Después de crear un pedido, abre `ENTREGAR-PEDIDO-DE-PRUEBA.cmd` para simular su preparación y entrega mediante la API. Después podrás valorar la comida y el local desde la aplicación. Para cerrar los servicios usa `DETENER-SNACKUP-LOCAL.cmd`; los datos se conservan.

La copia del backend corresponde al commit `1c3459bfd58a083acf4a1638c5013db93873f057`. Usa su modelo SQL y su configuración de pruebas para crear el esquema SQLite, sin Redis, correo ni notificaciones externas. Solo escucha en esta computadora. No es una instalación de producción ni importa o modifica Firebase.

La carpeta `.local/` está excluida de Git: no subas la base, credenciales ni registros. Los cambios de esta preparación pertenecen a `codex/cliente-campus`, sin modificar `main`.
