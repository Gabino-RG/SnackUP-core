# SnackUP: ejecucion de AAA REST y SonarQube

Esta rama agrega pruebas y automatizacion; no modifica las pantallas, el login, el workflow Flutter CI previo ni los servicios de produccion.

## Alcance y estado

- Se mantienen los 12 casos API-01 a API-12 del plan documental. Son peticiones HTTP a Firestore Emulator, no una API propia.
- Hay 15 pruebas GUARD del aislamiento del kit. No se cuentan como casos REST ni como pruebas del producto.
- El archivo `tests/api/firestore.rules` es un marcador que bloquea ejecucion. NO son las reglas actuales de SnackUP.
- El analisis Sonar corresponde al cliente Flutter/Dart, nunca al codigo interno de Firebase.
- La primera ejecucion debe conservar los reportes reales. Un bloqueo de configuracion NO es un Quality Gate evaluado y fallido por metricas.

## Integracion y seguridad

La suite usa exclusivamente `demo-snackup-qa`, `127.0.0.1:8080` y `127.0.0.1:9099`. La preparacion y el oraculo usan `withSecurityRulesDisabled` solamente en el emulador. La operacion Act utiliza el token del actor de prueba, no un token administrativo. Los negocios sinteticos tienen ID distinto al UID de su propietario y se siembra `businesses/{id}.ownerId`, consistente con el cliente revisado.

No ejecutar `firebase deploy`. No compartir tokens, contrasenas ni alumnos reales. No cambiar las reglas o asserts solo para obtener verde.

## Pendientes externos

1. Copia autorizada de las reglas actuales de Firestore; registrar origen, revision y fecha. Adaptar fixtures si las reglas exigen claims, verificacion de correo u otros campos.
2. Instancia/proyecto SonarQube con Dart y soporte del tipo de analisis. Configurar `SONAR_HOST_URL` y `SONAR_TOKEN` como secretos de GitHub; no ponerlos aqui. Crear/asociar el gate de `qa-config/quality-gate.spec.json` y definir New Code. El JSON no modifica el servidor.
3. Administrador: mantener `validate` y exigir los checks nuevos acordados. Comprobar bloqueo real del merge; no confundir check rojo con proteccion de rama.
4. Docente: confirmar que Firestore REST cumple el alcance de la consigna y cotejar Tema I. Las pruebas en dispositivos y la aceptacion humana no estan acreditadas por CI.

## Dependencias y ejecucion

Desde `tests/api`:

```sh
npm run check
npm run test:guard
npm run preflight
# Solo cuando las reglas y fixtures esten revisados:
npm install --save-dev --save-exact firebase @firebase/rules-unit-testing firebase-tools
# Versionar package.json y package-lock.json reales despues de instalarlos.
npm run test:ci
```

Node 22 y Java 21. Despues del primer lockfile usar `npm ci`. El workflow bloquea si falta el lock, prepara ambos manifiestos y los conserva como artefacto para revision. No se entrega un lockfile inventado. Un error de instalacion no es un caso REST fallido.

## Jobs nuevos

| Job | Evidencia y significado |
| --- | --- |
| qa-kit | Sintaxis y 15 verificaciones de aislamiento; no pruebas REST. |
| api-rest | Preflight con hash de reglas; luego 12 AAA y JUnit si las precondiciones estan completas. |
| flutter-coverage | Reejecuta las pruebas existentes y conserva LCOV; no supone cobertura global de 80%. |
| sonar | Verifica presencia de secretos, analiza Dart y espera el Quality Gate. |
| quality-gate | Solo aprueba si todos los jobs anteriores aprueban. |

El workflow previo `Flutter CI` y `validate` siguen intactos. No hay `continue-on-error` para convertir fallos en aprobaciones. Los artefactos se conservan 14 dias.

## Cierre

Guardar commit, run ID, reglas/hash, versiones, JUnit, LCOV y analisis Sonar. Corregir y repetir casos afectados. La demostracion pendiente incluye fallo por una condicion real de Sonar, bloqueo de integracion y correccion; no basta que falte un secreto. No fusionar este borrador como practica concluida.

Fuentes: plan SnackUP de 29/09/2026, `app/lib/features/home/business_home_screen.dart` del commit base y documentacion oficial:
- https://firebase.google.com/docs/emulator-suite/connect_firestore
- https://firebase.google.com/docs/rules/unit-tests
- https://docs.sonarsource.com/sonarqube-server/analyzing-source-code/languages/dart
- https://docs.sonarsource.com/sonarqube-server/analyzing-source-code/test-coverage/dart-test-coverage
