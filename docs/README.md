# Documentación de SnackUP

[![Flutter CI — develop](https://github.com/Gabino-RG/SnackUP-core/actions/workflows/flutter-ci.yml/badge.svg?branch=develop&event=push)](https://github.com/Gabino-RG/SnackUP-core/actions/workflows/flutter-ci.yml?query=branch%3Adevelop+event%3Apush)
[![Flutter CI — pull requests](https://github.com/Gabino-RG/SnackUP-core/actions/workflows/flutter-ci.yml/badge.svg?event=pull_request)](https://github.com/Gabino-RG/SnackUP-core/actions/workflows/flutter-ci.yml?query=event%3Apull_request)

## Descripción

SnackUP es una plataforma para la gestión digital de cafeterías escolares,
desarrollada con Flutter y Firebase. Permite gestionar menús, pedidos y acceso
de usuarios desde una aplicación multiplataforma.

La aplicación, sus recursos y la configuración de Firebase se encuentran en
`../app/`. El `README.md` del repositorio se conserva en la raíz.

## Seguimiento y plan

- [Board de Jira — backlog de SnackUP](https://snackup.atlassian.net/jira/software/projects/SNA/boards/104/backlog)
- [Plan DevOps — entrega final depurada](https://docs.google.com/document/d/16D6OpuM5h1bbJ5zieyC1zwShkQBwxK2OojRANM_XRCo/edit?tab=t.0)

## Requisitos

- Flutter del canal estable con Dart compatible con `^3.8.0`, según `pubspec.yaml`.
- Android SDK y un dispositivo o emulador para ejecutar la versión Android.
- Chrome para ejecutar la versión web.
- Acceso al proyecto Firebase si necesitas regenerar su configuración; para
  ello, instala Firebase CLI y FlutterFire CLI.

## Preparar y ejecutar

Desde la raíz del repositorio:

```bash
cd app
flutter pub get
flutter run
```

Para ejecutar en Chrome, desde `app/`:

```bash
flutter run -d chrome
```

Si necesitas regenerar la configuración de Firebase, ejecuta
`flutterfire configure` desde `app/` y selecciona el proyecto correspondiente.

## Construir

Todos los comandos siguientes se ejecutan desde `app/`.

APK de depuración para Android:

```bash
flutter build apk --debug
```

El archivo generado se encuentra en
`app/build/app/outputs/flutter-apk/app-debug.apk`, tomando la raíz del
repositorio como referencia.

Versión web:

```bash
flutter build web
```

El resultado queda en `app/build/web/`. Si tienes configurado Firebase Hosting,
ejecuta `firebase deploy --only hosting` desde `app/` para publicarlo.

## Validaciones y CI

Desde `app/`, ejecuta las mismas validaciones que usa el workflow:

```bash
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test --coverage
```

La comprobación de formato devuelve un error si encuentra archivos sin
formatear; para corregirlos, ejecuta `dart format .`.

El workflow `Flutter CI` se activa con pushes a `develop` y pull requests hacia
`main` o `develop`. Instala dependencias, verifica formato, analiza el código,
ejecuta pruebas con cobertura y compila el APK de depuración. Cuando todos los
pasos terminan correctamente, publica el artefacto `snackup-debug-apk` en la
ejecución de GitHub Actions. Los badges muestran el estado real de esas
ejecuciones.

Consulta [la guía de CI y cobertura](../ci/README.md) para comprobar el informe
LCOV. Abre `app/` en el editor para usar la configuración de `.vscode` trasladada.

## Archivos previstos

| Archivo | Estado |
| --- | --- |
| `Plan_DevOps_SnackUP.docx` | Copia local pendiente; el plan está enlazado arriba en Google Docs. |
| `mapa-devops.png` | Pendiente de incorporar; no estaba en el repositorio. |
| `arquitectura.png` | Pendiente de incorporar; no estaba en el repositorio. |
| `comunicacion.md` | Guía de comunicación por issues y pull requests. |

Las plantillas de GitHub están en `../.github/` y las instrucciones de cobertura
en `../ci/README.md`.
