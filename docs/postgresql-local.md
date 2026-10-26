# SnackUP con PostgreSQL local

## Iniciar

Abre `INICIAR-SNACKUP-POSTGRESQL.cmd` y entra a http://localhost:8080. El acceso de alumno se guarda en `.local/snackup-demo/ACCESO-LOCAL.txt`. Si tenías una sesión de la anterior base SQLite, vuelve a iniciar sesión.

Se requieren Git, Python 3.11 o posterior, Node 20 o posterior, Flutter y PostgreSQL 16, 17 o 18 instalado. El preparador busca sus ejecutables en `C:\Program Files\PostgreSQL`; en esta computadora utiliza PostgreSQL 18. Prepara un entorno Python propio y el conector `psycopg` fijado en `tools/requirements-postgresql-local.txt`.

## Base e instancia propias

| Campo | Valor |
| --- | --- |
| Servidor | `127.0.0.1` |
| Puerto | `55432` |
| Base | `snackup_local` |
| Usuario | `snackup_local` |
| Contraseña | Generada, guardada únicamente en `.local/snackup-demo/postgresql.json` |

Puedes registrar estos datos en pgAdmin. No compartas el archivo de credenciales. La instancia escucha solo en esta computadora y usa autenticación SCRAM. El usuario administra únicamente esta instancia de demostración, no la instancia PostgreSQL que ya tenías funcionando.

Los archivos persistentes están en `.local/snackup-demo/postgres-data`, con registro en `.local/snackup-demo/postgres.log`. No se reutilizan ni alteran los datos de otras instalaciones. La carpeta `.local/` está excluida de Git. El archivo SQLite anterior se conserva aparte, sin importación automática. Firebase queda intacto.

`DETENER-SNACKUP-LOCAL.cmd` detiene la app y la API. Si también quieres apagar exclusivamente la instancia PostgreSQL de SnackUP, ejecuta `.local\snackup-demo\venv\Scripts\python.exe tools\postgresql_demo.py --stop`. El iniciador vuelve a encenderla y conserva los datos. No borres `postgres-data` ni su archivo de credenciales.

`ENTREGAR-PEDIDO-DE-PRUEBA.cmd` simula la entrega del último pedido de demostración; después puedes valorarlo desde la app. La base incluye una cafetería, dos cuentas ficticias y seis productos, uno agotado para comprobar su ocultación. Los pedidos y reseñas se guardan al usar la aplicación.

## Qué usa la API de Gabino

Se consultaron las ramas remotas. No existe una rama llamada `api/backend` en ese listado; la rama de API encontrada es `codex/backend-api-v3-fastapi`, commit `1c3459bfd58a083acf4a1638c5013db93873f057`.

- [backend/snackup/config.py](https://github.com/Gabino-RG/SnackUP-core/blob/1c3459bfd58a083acf4a1638c5013db93873f057/backend/snackup/config.py) configura SQLite como valor predeterminado de desarrollo y exige `postgresql+psycopg://` para producción.
- [backend/compose.yaml](https://github.com/Gabino-RG/SnackUP-core/blob/1c3459bfd58a083acf4a1638c5013db93873f057/backend/compose.yaml) utiliza la imagen `postgres:17-alpine` y una conexión PostgreSQL. No usa SQL Server.

Esta rama conecta el cliente a una copia fijada de esa API con PostgreSQL 18 local. Usa los modelos originales, sin aplicar la adaptación de SQL Server. Mantiene el modo de pruebas del backend para preparar el esquema y datos ficticios; no configura SMTP, Redis ni notificaciones externas. Los preparadores anteriores de SQL Server se conservan como alternativa histórica y no se ejecutan en el flujo PostgreSQL.

## Comprobación real

Pasaron 21 comprobaciones contra PostgreSQL: instancia exclusiva, 23 tablas, inicio de sesión, menú, exclusión del producto agotado, creación y repetición segura de pedido, descuento único del inventario, preparación y entrega, estrellas y comentarios del local y comida, rechazo de reseña duplicada, historial y persistencia SQL.

La evidencia sin credenciales está en `docs/evidence/api-client/postgresql-local.json`. Para repetir la prueba con los servicios encendidos: `.local\snackup-demo\venv\Scripts\python.exe tools\check_postgresql_demo.py`. Crea y entrega un pedido de prueba adicional y descuenta una unidad de chilaquiles; no utiliza cuentas reales. No prueba la interacción visual del navegador ni concurrencia de varios servidores.
