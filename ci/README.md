# Integración continua

El workflow `.github/workflows/flutter-ci.yml` se ejecuta en pushes a `develop`
y en pull requests hacia `main` o `develop`, con permiso de lectura del contenido.
Usa Flutter del canal estable con caché y ejecuta la instalación de dependencias,
la comprobación de formato, el análisis estático, las pruebas con cobertura y la
compilación del APK de depuración desde `app/`.

Al completar las validaciones y la compilación, publica el artefacto
`snackup-debug-apk` a partir de
`app/build/app/outputs/flutter-apk/app-debug.apk`.

## Comprobar cobertura

Requiere Bash y Python 3. Genera el informe desde la carpeta de la aplicación:

```bash
cd app
flutter test --coverage
```

Después, desde la raíz del repositorio:

```bash
bash ci/check_coverage.sh 70
```

El primer argumento es el porcentaje mínimo deseado, entre 0 y 100. `70` es un
ejemplo, no una política del proyecto. El segundo argumento opcional permite
seleccionar otro informe LCOV. La ruta predeterminada es
`app/coverage/lcov.info`, independientemente del directorio de ejecución.

El script devuelve un código distinto de cero si la cobertura no alcanza el
umbral, si falta el informe o si el archivo no contiene líneas de cobertura
válidas. El workflow genera cobertura, pero no impone un umbral automáticamente.
