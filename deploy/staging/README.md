# SnackUP: instalación del piloto de Cocina y Administración

Este paquete prepara un servidor nuevo de pruebas. No despliega automáticamente,
no trae cuentas, padrón ni contraseñas y no certifica capacidad para mil alumnos.
Backend: `81c76c5`; paneles: `0287cbf`. `versions.json` contiene los SHA completos.
El frontend de alumnos incluido por el backend todavía usa Firebase: no utilizar
este piloto como lanzamiento general ni dar por terminada su integración SQL.

## Datos que debe entregar la universidad

- Servidor Linux amd64 y acceso administrativo para instalar Docker Engine,
  Compose 2.24.4 o posterior y Python 3. Se solicitaron 6–8 vCPU, 16 GB RAM,
  SSD de 100–200 GB y red de 100 Mbps o más; la capacidad real se debe medir.
- Subdominio de pruebas apuntando a ese servidor, puertos 80/443 disponibles y
  correo del responsable de certificados. Confirmar antes si ya existe un proxy.
- Dominios institucionales autorizados, responsable de la cuenta maestra y
  datos de institución/cafetería. El dominio de correo no concede un rol de Cocina.
- SMTP y mecanismo autorizado para consultar/importar el padrón, con carrera y
  grupo. Mientras falten, probar con cuentas y padrón sintéticos; no inventar
  las carreras a partir del correo.
- Ubicación y responsable de respaldos externos, retención y recuperación.

## Preparar el paquete desde el repositorio de paneles

```sh
git fetch origin
python deploy/staging/prepare.py --output build/SnackUP-Piloto
```

Se generan una carpeta y `build/SnackUP-Piloto.zip`, sin `.env`. No se sobrescribe
un destino existente. El backend se exporta de su commit, sin cambiar sus ramas.
Los contextos de ambos frontends quedan fijados a SHA, no a puntas de ramas.

## Instalar en el servidor nuevo

Descomprimir el ZIP en una carpeta privada del piloto. Desde esa carpeta:

```sh
sha256sum -c SHA256SUMS
cd backend
python3 configure.py init
# Editar .env en el servidor: completar dominio, correo de certificados,
# institución, cafetería y dominios autorizados. Configurar SMTP cuando exista.
python3 configure.py check
docker compose --env-file .env -f compose.unified.yaml -p snackup-piloto config --quiet
docker compose --env-file .env -f compose.unified.yaml -p snackup-piloto up -d --build --wait --wait-timeout 180
docker compose --env-file .env -f compose.unified.yaml -p snackup-piloto ps
```

Se conserva el Compose original del backend: un contenedor de aplicación con
API, PWAs, Caddy, Redis y tareas; otro de PostgreSQL sin puerto público. El build
requiere acceso a GitHub y a los registros de dependencias. El primer arranque
aplica las migraciones a la base del piloto. No ejecutar sobre una base existente
sin revisar respaldos y migraciones. El proyecto `snackup-piloto` separa volúmenes,
pero sus puertos 80/443 deben estar libres.

`configure.py init` genera tres secretos distintos solamente en ese servidor y
se niega a sobrescribir `.env`. Mantener el archivo privado; no subirlo al repo
ni enviarlo por chat. En Linux se crea con permisos 0600. `check` revisa campos
básicos; Compose comprueba el resto de la configuración sin imprimirla.

La cuenta maestra se crea interactivamente, cambiando el correo del ejemplo por
el autorizado en `.env`:

```sh
docker compose --env-file .env -f compose.unified.yaml -p snackup-piloto exec app python -m snackup.cli create-master --email RESPONSABLE@DOMINIO --name "Responsable del piloto"
```

El CLI pide la contraseña sin mostrarla. Desde Administración se crean los
locales y se autorizan las cuentas de Cocina. Para importar padrón autorizado,
consultar `backend/README.md` y ejecutar primero `import-roster --dry-run`.
No hay usuario ni contraseña por defecto.

## Aceptación antes de ampliar el piloto

1. Abrir `https://DOMINIO/paneles/`, comprobar HTTPS, acceso y cierre de sesión.
2. Autorizar un operador y verificar que solo puede gestionar su local.
3. Crear/editar un producto; recibir un pedido de prueba de la API de alumnos,
   verlo sin recargar, prepararlo y entregarlo con su código. Comprobar que un
   código incorrecto no lo entrega y que aparecen historial y totales.
4. Registrar una opinión de prueba, comprobar carrera/grupo y seguimiento
   administrativo. Una opinión de cero estrellas debe contar como negativa.
5. Comprobar recuperación por correo con SMTP real y recarga de sesión.
6. Reiniciar el piloto y verificar persistencia; realizar respaldo y restauración
   en otro entorno. El volumen de Docker por sí solo no constituye un respaldo.
7. Validar por separado la app de alumnos contra SQL y medir la carga prevista.

Guardar resultados, versiones, navegador/dispositivo y errores de cada caso.
Las pruebas locales del frontend están documentadas en la rama de paneles en
`docs/integracion/VALIDACION_BACKEND_V32.md`. El paquete no confirma acceso al
servidor, envío SMTP, certificado real ni la integración completa de alumnos.

## Detener y diagnosticar

```sh
docker compose --env-file .env -f compose.unified.yaml -p snackup-piloto logs --tail 100 app
docker compose --env-file .env -f compose.unified.yaml -p snackup-piloto stop
```

`stop` conserva datos. No usar `down --volumes` para una instalación con datos.
No compartir `.env`, tokens, códigos de recogida ni datos del padrón en reportes.
Para volver a una versión anterior con cambios de esquema, seguir el procedimiento
de restauración probado del backend; no basta con cambiar la imagen.
