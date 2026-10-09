# Guía de Contribución - SnackUP

## Flujo de trabajo

SnackUP utiliza un flujo de trabajo basado en ramas para mantener un desarrollo organizado, estable y fácil de revisar.

Las ramas principales del proyecto son:

- `main`: contiene las versiones estables del proyecto.
- `develop`: integra los cambios realizados durante el desarrollo.

Las nuevas funcionalidades, correcciones y cambios de documentación deben realizarse en ramas independientes creadas a partir de `develop`.

## Convención de ramas

### Nuevas funcionalidades

Formato:

`feature/nombre-funcionalidad`

Ejemplo:

`feature/login-validation`

### Correcciones

Formato:

`fix/descripcion-error`

Ejemplo:

`fix/login-error`

### Documentación

Formato:

`docs/descripcion`

Ejemplo:

`docs/contributing-guide`

### Integración continua

Formato:

`ci/descripcion`

Ejemplo:

`ci/update-flutter-workflow`

---

## Procedimiento de contribución

1. Actualizar la rama `develop`.
2. Crear una nueva rama a partir de `develop`.
3. Realizar los cambios necesarios.
4. Ejecutar las validaciones de Flutter.
5. Realizar commits siguiendo la convención Conventional Commits.
6. Subir la rama al repositorio remoto.
7. Crear un Pull Request hacia `develop`.
8. Esperar la ejecución del pipeline de CI.
9. Solicitar la revisión de al menos un integrante del equipo.
10. Realizar el merge únicamente cuando las validaciones sean correctas.

---

## Conventional Commits

SnackUP utiliza Conventional Commits para mantener un historial de cambios claro y organizado.

Prefijos principales:

- `feat:` nueva funcionalidad.
- `fix:` corrección de errores.
- `docs:` cambios de documentación.
- `test:` incorporación o modificación de pruebas.
- `refactor:` cambios internos del código sin modificar la funcionalidad.
- `chore:` tareas de mantenimiento.
- `ci:` modificaciones relacionadas con integración continua.

## Ejemplos

`feat: add login validation`

`fix: correct Firebase authentication error`

`test: add email validator unit tests`

`docs: add contribution guidelines`

`ci: update Flutter validation workflow`

---

## Pull Requests

Todo cambio debe integrarse mediante un Pull Request.

Antes del merge se deberá verificar:

- Que el código pase `flutter analyze`.
- Que las pruebas pasen con `flutter test`.
- Que el pipeline de GitHub Actions finalice correctamente.
- Que no se introduzcan errores críticos.
- Que el cambio sea revisado por al menos un integrante del equipo cuando sea posible.
- Que la documentación se actualice cuando el cambio lo requiera.

---

## Validaciones locales

Antes de crear un Pull Request se recomienda ejecutar los siguientes comandos desde la carpeta `app`:

```bash
flutter pub get
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
flutter build apk --debug
