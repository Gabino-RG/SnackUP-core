# SnackUP completo en Windows

El paquete `SnackUP-PC.zip` compila **`app/lib/main.dart`**, el mismo punto de entrada de la aplicación conectada a Firebase. Incluye el acceso de alumnos, negocios y administración según la cuenta autenticada. No usa el punto de entrada `main_admin_demo.dart` ni sus datos ficticios.

La compilación local y un iniciador funcionando no certifican por sí solos la operación completa del servicio. La activación de Firebase y la comprobación del iniciador directamente en Windows siguen pendientes; consulta [la activación administrativa](admin/README.md#activación-pendiente-en-un-entorno-aprobado-por-ti) y [la evidencia de validación](admin/VALIDACION.md).

## Abrir el paquete

1. En Windows 10/11 de 64 bits, descarga el ZIP y elige **Extraer todo**.
2. Abre `SnackUP-PC/INICIAR_SNACKUP.cmd`. Incluye Python embedded: no requiere instalar Python, Flutter, Git ni ejecutar como administrador.
3. El navegador abre `http://localhost:8790/`. Mantén la consola abierta.
4. Inicia sesión con una cuenta de SnackUP. El acceso administrativo requiere el custom claim booleano `admin: true`; un campo editable en el perfil no lo concede.
5. Al terminar, cierra sesión si compartes el equipo. Detén el servidor con `Ctrl+C` o cerrando la consola.

La aplicación requiere Internet y acceso al proyecto Firebase configurado en el código. Las operaciones autorizadas se guardan en ese servicio: los pedidos, reseñas y seguimientos **no se borran al recargar**. No se incluyen cuentas ni contraseñas. No se han creado usuarios, asignado privilegios ni desplegado reglas como parte del empaquetado.

El iniciador escucha únicamente en `127.0.0.1`; sólo publica los archivos de `web/`. No sirve el código fuente, el runtime ni el resto del equipo. El origen estable `http://localhost:8790` permite reutilizar los datos del navegador entre inicios; cambiar navegador, perfil, hostname o puerto, o borrar su almacenamiento, puede exigir volver a iniciar sesión.

## Activación de Firebase

El personal responsable del proyecto debe verificar la configuración de la aplicación web, proveedores de autenticación, dominios autorizados aplicables (incluido `localhost` para el uso local), reglas e índices de Firestore y permisos de Storage. El paquete usa la configuración pública de FlutterFire existente; no incorpora un SDK de administración ni claves privadas.

Los permisos y reglas del entorno conectado determinan qué operaciones funcionan. El flujo de administración y seguimiento requiere completar la [revisión de reglas y claims](admin/README.md). El ZIP no concede permisos por sí mismo ni sustituye esa activación. Antes de utilizarlo operativamente deben validarse los flujos alumno → pedido → negocio → entrega → reseña → revisión administrativa con cuentas autorizadas y datos de prueba acordados. Las condiciones y límites constatados se documentan en [VALIDACION.md](admin/VALIDACION.md).

## Si algo falla

- **Puerto 8790 ocupado:** cierra la instancia anterior de SnackUP. El iniciador termina con un error y no abre el navegador ni elige otro puerto, para evitar mostrar por accidente otro servicio.
- **No se abre el navegador:** con la consola aún abierta, escribe `http://localhost:8790/` manualmente.
- **Falta `runtime/python.exe` o `web/index.html`:** extrae todo el ZIP; no ejecutes desde la vista del archivo comprimido.
- **Error de conexión:** comprueba Internet y la disponibilidad/configuración del proyecto. La aplicación completa necesita Firebase incluso aunque sus archivos estén en la PC.
- **Permiso denegado o no aparece administración:** revisa las reglas y permisos de la cuenta con el responsable del proyecto. Reinicia la sesión después de un cambio de claims. Volver a descargar el paquete no concede privilegios.

## Generar el paquete desde la rama

Requisitos del equipo de desarrollo: Python 3.10 o posterior, Git, Flutter y sus dependencias resueltas, más el ZIP oficial de Python embedded para Windows x64 descargado previamente. El script no descarga un runtime ni despliega servicios. Se ha preparado para Flutter 3.32.0 y el runtime `python-3.14.8-embed-amd64.zip` utilizado en el paquete anterior.

Primero confirma los cambios en **nuestra rama**, nunca en `main`. El script exige un checkout limpio y comprueba de nuevo que el commit y los archivos versionados no cambiaron durante el build. Esto mantiene consistente el código fuente incluido con la compilación distribuida.

Desde la raíz del repositorio:

```bash
python3 scripts/pc/build_pc_package.py \
  --runtime /ruta/python-3.14.8-embed-amd64.zip \
  --flutter /ruta/flutter/bin/flutter \
  --output /ruta/fuera-del-repo/SnackUP-PC.zip \
  --no-pub
```

Omite `--no-pub` si necesitas que Flutter resuelva dependencias durante el build. El comando interno de compilación es:

```bash
flutter build web --release --no-web-resources-cdn \
  -t lib/main.dart -o build/pc-release
```

`--no-web-resources-cdn` incluye los recursos del motor Flutter localmente. **No convierte Firebase en un servicio sin conexión**: la aplicación conectada todavía necesita Internet.

El ZIP contiene `web/`, el runtime completo con su licencia, el iniciador, instrucciones, documentos administrativos y `codigo_fuente.zip` obtenido mediante `git archive` del commit exacto. También incluye `INTEGRACION.md`, `VALIDACION_INTEGRADA.md` y la carpeta `security/` cuando existen en la documentación del commit. `VERSION.json` registra rama, commit, versiones y hash del runtime; `SHA256SUMS.txt` permite comprobar los archivos distribuidos. Sólo se archivan archivos versionados y el script rechaza nombres comunes de credenciales o claves privadas detectables. No incluye el SDK de Flutter, cachés, `.git`, ni credenciales locales.

El empaquetado ordena los archivos y fija las fechas del ZIP al commit. Para repetir una compilación se necesitan también las mismas versiones del compilador, dependencias y runtime; no se promete igualdad binaria entre versiones de herramientas. El script comprueba el ZIP y rechaza un resultado de 50 MiB o más.

## Comprobación del iniciador

El servidor usa únicamente la biblioteca estándar de Python. Para QA, desde el paquete extraído se puede ejecutar:

```bash
python3 start_snackup.py --no-browser --port 0
```

`--port 0` solicita un puerto disponible e imprime la URL. Es útil para comprobar archivos y tipos MIME sin abrir el navegador; el uso normal conserva el puerto 8790. La validación HTTP en Linux no equivale a probar `INICIAR_SNACKUP.cmd` ni `python.exe` en Windows. Esa prueba nativa continúa pendiente hasta ejecutarlos en el equipo de destino.
