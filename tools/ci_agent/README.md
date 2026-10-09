# SnackUP · Agente gráfico de Integración Continua

Aplicación para visualizar el pipeline de SnackUP, identificar la etapa activa, inspeccionar registros y explicar por qué una ejecución se aprueba o se detiene. Incluye evidencia descargada de GitHub Actions y un video corto de esa evidencia. SnackUP es una aplicación de pedidos para la cafetería universitaria de UTSJR, desarrollada con Flutter/Dart Web.

## Abrir en Windows

1. Descomprime todo el paquete en una carpeta.
2. Instala Python 3.10 o posterior si todavía no está instalado; activa la opción para agregar Python al PATH.
3. Haz doble clic en `INICIAR_WINDOWS.bat` y conserva abierta la ventana del servidor mientras usas el agente. Se abrirá `http://127.0.0.1:8765/`.
4. En el panel, selecciona **CI aprobado real** y pulsa **Reproducir evidencia real**. También puedes seleccionar **CI fallido real** para revisar la aplicación del principio fail fast.

El agente utiliza la biblioteca estándar de Python y no requiere instalar paquetes con pip. Para consultar GitHub se necesita conexión a Internet; para reproducir la evidencia incluida, no. Si solo deseas revisar la evidencia sin iniciar Python, abre `web/index.html`: esa opción sirve únicamente para la reproducción; GitHub, la demostración y el CI local requieren el iniciador.

También puedes iniciar desde una terminal ubicada en la carpeta del paquete con `python server.py`. En Linux/macOS, ejecuta `bash iniciar.sh`. Si el puerto está ocupado, utiliza `python server.py --port 8766`. La opción `--no-browser` permite iniciar el servidor sin abrir una ventana.

## Cuatro modos, cuatro alcances

| Modo | Qué hace | Qué demuestra |
|---|---|---|
| Evidencia registrada | Reproduce cronológicamente resultados reales descargados de GitHub Actions; permite acelerar el avance. | Lo ocurrido en la ejecución identificada por su URL y SHA. No inicia un nuevo CI. |
| GitHub | Consulta ejecuciones y estados de un repositorio público mediante la API de GitHub. | El estado reportado por GitHub en el momento de la consulta. El monitor observa; las reglas del workflow remoto detienen el CI. |
| CI local | Ejecuta comandos definidos del pipeline en una copia local de SnackUP y presenta su salida. | Los resultados de esa ejecución local, con los requisitos disponibles en la computadora. |
| Demo: falla rápido | Ejecuta comandos Python sobre un ejemplo aislado; requiere el servidor local. | El funcionamiento didáctico de las reglas. No acredita pruebas de SnackUP. |

Una reproducción no se etiqueta como ejecución en vivo. Una compilación aprobada no se presenta como despliegue a producción. El video incluido muestra una reproducción de registros reales, con rótulos que identifican su origen.

En modo GitHub, la API proporciona estados de jobs y pasos; el log completo se consulta mediante el enlace a GitHub. Los registros descargados sí están incluidos en la evidencia histórica. La variable de entorno opcional `GITHUB_TOKEN`, con acceso de lectura, permite consultar repositorios autorizados o ampliar el límite de peticiones; no se entrega al navegador.

## Cómo funciona el agente

Es un **agente basado en reglas**, con decisiones explicables. No utiliza un modelo de lenguaje ni requiere una API de inteligencia artificial.

- **Percibe:** estados de etapas, horas de inicio y término, códigos de salida, registros, rama, SHA y artefactos.
- **Representa:** una secuencia con estados pendientes, en ejecución, aprobados, fallidos y omitidos o bloqueados.
- **Decide:** identifica la primera etapa fallida y relaciona mensajes reconocibles del registro con recomendaciones. Si falla su CI local, deja de ejecutar las siguientes etapas.
- **Actúa:** actualiza la gráfica y los registros, muestra el diagnóstico y propone una revisión concreta. En modo GitHub, informa la decisión del workflow; no modifica código, no cancela ejecuciones remotas y no despliega.

Por ejemplo, ante el error histórico de compilación relacionado con `reloadApplication`, señala la etapa Web fallida, muestra el mensaje del compilador y explica que el artefacto no se generó. La recomendación acompaña la evidencia y no sustituye la revisión técnica.

## Evidencia real de SnackUP

Repositorio: [Gabino-RG/SnackUP-core](https://github.com/Gabino-RG/SnackUP-core).

La evidencia de la aplicación corresponde a la rama `test/api-aaa-sonarqube`. El proyecto Flutter de esa revisión está en `app/`.

| Evidencia | Resultado verificable | Enlace |
|---|---|---|
| Flutter CI aprobado · SHA `ddf0d461b07c407510bca28ef2cd5026aa4a624f` | 59 pruebas unitarias y de widgets aprobadas; compilación Web aprobada; artefacto conservado. | [Ejecución 37257224068](https://github.com/Gabino-RG/SnackUP-core/actions/runs/37257224068) |
| Pruebas REST del mismo SHA, en otro workflow | El job `api-rest` aprobó 18 pruebas. El workflow completo falló en Sonar y no se declara aprobado. | [Ejecución 37257224010](https://github.com/Gabino-RG/SnackUP-core/actions/runs/37257224010) |
| Flutter CI fallido · SHA `9b8cd9e53a12ed12083ced94cb43401b0d145956` | Las pruebas terminaron; falló la compilación por `reloadApplication`; el paso de artefacto quedó omitido. Una revisión posterior corrigió la falla y produjo el CI aprobado. | [Ejecución 37257039123](https://github.com/Gabino-RG/SnackUP-core/actions/runs/37257039123) |

Las ejecuciones anteriores son del 5 de octubre de 2026 en UTC. El Flutter CI aprobado utilizó Flutter 3.32.0 y `flutter analyze --no-fatal-infos --no-fatal-warnings`: reportó **124 avisos/informaciones tolerados**. Por ello, su resultado exitoso no significa ausencia de avisos ni aprobación del Quality Gate de SonarQube.

El artefacto histórico se llama `snackup-integrated-web` y tiene SHA-256 `ad9d0a0eb2be0aeaa736b35d07bd50e522915aa5a8f0605039971b121c739a23`. [Abrir artefacto en GitHub](https://github.com/Gabino-RG/SnackUP-core/actions/runs/37257224068/artifacts/11322847580). Su disponibilidad para descarga depende de la retención de GitHub; el paquete conserva los registros que documentan su creación.

El paquete descargable incluye los datos normalizados, los jobs y los registros originales en `evidence/`. La rama de código incluye los datos normalizados necesarios para reproducirlos. `web/evidence-data.js` permite reproducir los mismos datos sin conexión. Las 18 pruebas REST son evidencia adicional de otro workflow, no una etapa inventada dentro del Flutter CI histórico.

## Pipeline preparado para SnackUP

El archivo `.github/workflows/flutter_ci.yml` incluido dentro de este paquete es una configuración preparada para la revisión con Flutter en `app/` y pruebas REST en `tests/api/`. No está instalado automáticamente en la raíz de SnackUP y no debe presentarse como un nuevo pipeline ejecutado hasta contar con un run real de ese archivo. Fija Flutter 3.32.0, Node 22 y Java 21 para los emuladores.

| Orden | Etapa | Bloqueo y propósito |
|---|---|---|
| 1 | Commit / descarga | Identifica el código exacto por SHA y configura el entorno. |
| 2 | Dependencias y formato | Resuelve dependencias; un incumplimiento de formato produce salida fallida. |
| 3 | Análisis estático | Los errores bloquean. Los avisos e informaciones heredados se reportan con una política explícita de tolerancia. |
| 4 | Pruebas unitarias y de widgets | Comprueba lógica e interfaz antes de operaciones más costosas. |
| 5 | Compilación Web | Verifica que la aplicación integrada genera `build/web`. |
| 6 | Integración REST | Ejecuta las pruebas API con servicios de prueba de Firebase Emulator Suite. |
| 7 | Empaquetado | Conserva la salida Web identificada por commit y su comprobación SHA-256. |

Las unitarias se sitúan antes de la compilación para detectar pronto fallos baratos. Las etapas se ejecutan con gates: un comando fallido impide las operaciones posteriores. El análisis Dart no se denomina escaneo de seguridad completo; SonarQube y su Quality Gate deben configurarse y aprobarse por separado si son requisitos del proyecto.

El gate de formato es estricto y puede detener la primera ejecución si existe deuda previa de formato. El reporte de diagnósticos puede conservarse después de un fallo mediante `always()`; eso no permite continuar la compilación o generar un artefacto de aplicación aprobado.

## Ejecutar CI local real

Selecciona la carpeta raíz de tu copia de SnackUP en **Ejecutar CI local**. El agente detecta `app/pubspec.yaml` o `pubspec.yaml`. Necesitas Flutter/Dart en el PATH y, para la integración REST, Node/npm y los requisitos de Firebase de la suite, incluida Java para sus emuladores. Deben existir `tests/api/package.json`, un lockfile para `npm ci` y el script `test:ci`.

| Etapa local | Comando o acción |
|---|---|
| Dependencias | `flutter pub get` |
| Formato sin reescribir | `dart format --output=none --set-exit-if-changed lib test`, sobre los directorios existentes |
| Análisis | `flutter analyze --no-fatal-infos --no-fatal-warnings` |
| Pruebas | `flutter test --coverage` |
| Compilación | `flutter build web --release --no-web-resources-cdn` |
| Integración | `npm ci` y `npm run test:ci` en `tests/api/` |
| Artefacto | ZIP de la salida Web, manifiesto y SHA-256 en `.snackup-ci/` |

Si falta la suite REST o su script, la etapa de integración falla explícitamente y no se empaqueta un artefacto aprobado. Los comandos generan archivos de trabajo como `build/`, `coverage/` y `node_modules/`. No modifican el formato del código, no hacen push y no despliegan.

## Integrarlo al repositorio del equipo

1. Trabaja sobre una **rama propia** de la revisión de SnackUP que contiene `app/` y `tests/api/`.
2. Copia este agente a `tools/ci_agent/`.
3. Revisa y adapta el workflow preparado antes de copiarlo a `.github/workflows/flutter_ci.yml`: versión Flutter, rutas, configuración Firebase y alcance del análisis deben corresponder al código de esa rama.
4. Sube la rama y abre un Pull Request. Revisa una ejecución real y sus gates antes de integrarlo a la rama principal.

La estructura de `main` puede diferir de la revisión documentada. No sustituyas su workflow ni promociones otra rama sin revisar esas diferencias. El paquete permite comprobar el agente sin modificar `main`.

## CI y CD en esta entrega

CI valida cambios, ejecuta pruebas, compila y conserva un artefacto. CD se ocupa de preparar o realizar el despliegue. Este agente y el pipeline preparado terminan con el artefacto; Firebase Hosting no aparece como una etapa de despliegue de esta entrega.

## Equipo SnackUP

| Integrante | Rol |
|---|---|
| Francisco Arturo Munguía López | Project Manager |
| Juan Carlos Jaimes Meneses | Product Owner |
| Gabino Reyes García | QA |
| Sabina Pérez Olvera | Frontend |

Consulta `GUION_VIDEO.txt` para la secuencia breve de evidencia y `ENTREGA_CLASSROOM.txt` para el texto de entrega.

## Rama del agente

El código del agente está en [feature/ci-visual-agent](https://github.com/Gabino-RG/SnackUP-core/tree/feature/ci-visual-agent/tools/ci_agent), separado de `main`. El workflow `SnackUP CI Agent - validacion y video` prueba el motor y registra la interfaz en un navegador; no sustituye la evidencia de la compilación Flutter histórica ni ejecuta la plantilla Flutter nueva.
