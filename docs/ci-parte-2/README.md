# SnackUP · CI, SonarQube y alertas de fallo

La segunda parte de la actividad exige **el enlace del repositorio y un video corto** que muestre los pasos del CI, el análisis SonarQube y la notificación cuando falla.

Esta implementación extiende `.github/workflows/flutter-ci.yml` del proyecto Flutter real. El video se obtiene de dos ejecuciones terminadas: una aprobada y otra con fallo controlado después del Quality Gate, seguida de una alerta confirmada por Slack o Discord.

**Estado inicial:** implementación disponible; la acreditación de SonarQube y de la alerta depende de configurar los servicios y ejecutar el pipeline. Los tests locales usan respuestas simuladas para probar el código: no son evidencia de un escaneo ni de un mensaje enviado.

### Comprobación remota del 8 de octubre de 2026

- [Verificación de la implementación](https://github.com/Gabino-RG/SnackUP-core/actions/runs/37867100023): aprobada; 46 pruebas en el commit `f303fc9838b713bf79a3397362c90172d9b30178`. Las pruebas posteriores del contexto de pull request amplían la suite a 50.
- [Análisis real de la rama](https://github.com/Gabino-RG/SnackUP-core/actions/runs/37867098901): pruebas y compilación aprobadas; SonarQube analizó Dart e importó `coverage/lcov.info`. Su tarea terminó `SUCCESS`, Analysis ID `29e565a5-d8a7-4ca0-b272-e3c8df0af3ca`. La consulta del Quality Gate devolvió HTTP 403; el artefacto validado quedó bloqueado.
- Discord confirmó la alerta de esa ejecución: `DELIVERED`, HTTP 200. Esto acredita el envío real ante un fallo.
- [PR #24 en borrador hacia main](https://github.com/Gabino-RG/SnackUP-core/pull/24): permite usar el análisis de PR que admite el plan Free sin integrar cambios. [Su primera ejecución](https://github.com/Gabino-RG/SnackUP-core/actions/runs/37867434898) alcanzó SonarQube, pero el scanner respondió `Could not find the pullrequest with key '24'`. Falta revisar el vínculo del proyecto y el acceso de la app SonarQubeCloud a los PR de este repositorio.
- Las claves públicas verificadas son organización `jcoorp` y proyecto `JCoorp_SnackUP-core`. El token y webhook permanecen exclusivamente en GitHub Secrets.
- [PR #23](https://github.com/Gabino-RG/SnackUP-core/pull/23) conserva la revisión incremental de la segunda parte. La rama de entrega es [feature/ci-sonar-notifications](https://github.com/Gabino-RG/SnackUP-core/tree/feature/ci-sonar-notifications).

**La entrega definitiva sigue pendiente:** no existe todavía una ejecución con Quality Gate aprobado ni el video de la parte 2. `ESTADO_VERIFICADO.json` registra las comprobaciones reales y el bloqueo restante.

## 1. Qué hace el pipeline

| Paso | Control y evidencia |
| --- | --- |
| Descargar código | Checkout completo del commit identificable. |
| Configuración | Verifica nombres obligatorios y URL segura antes de gastar recursos. Nunca imprime secretos. |
| Flutter y dependencias | Flutter 3.32.0 estable y `flutter pub get`. |
| Análisis estático | Conserva el comando existente `flutter analyze --no-fatal-infos --no-fatal-warnings`: información y advertencias no bloquean; los errores sí. |
| Pruebas | `flutter test --coverage` y LCOV no vacío. Son pruebas unitarias y de widgets; no se presenta esta suite como integración. |
| Compilación | Construye la aplicación integrada mediante `lib/main.dart`. |
| SonarQube | Acción oficial fijada a la release v8.3.0; analiza Dart en SonarQube Cloud e importa LCOV. |
| Quality Gate | Espera a la tarea exacta del scanner y consulta su `analysisId`. Solo `OK` aprueba. El resultado de otro análisis no sirve. |
| Artefacto | Solo se empaqueta el build después de aprobar todos los controles. |
| Alerta | Job independiente `always()` + resultado `failure`. Funciona también cuando falla una etapa temprana. |

El principio Fail Fast detiene la validación al primer error. Los pasos de auditoría y notificación se ejecutan para conservar el diagnóstico. El despliegue pertenece a CD y está fuera de esta actividad.

## 2. Configuración única en GitHub

En el repositorio [Gabino-RG/SnackUP-core](https://github.com/Gabino-RG/SnackUP-core), abrir **Settings → Secrets and variables → Actions**.

| Tipo | Nombre exacto | Valor que debe guardar el equipo |
| --- | --- | --- |
| Repository secret | `SONAR_TOKEN` | Token real de SonarQube Cloud con permiso para analizar y consultar el proyecto. |
| Repository secret | `CI_FAILURE_WEBHOOK_URL` | Webhook real del canal Slack o Discord del equipo. |
| Repository variable, opcional | `SONAR_ORGANIZATION` | Por defecto `jcoorp`, verificada en el enlace de la organización. Permite configurar otra organización explícitamente. |
| Repository variable, opcional | `SONAR_PROJECT_KEY` | Por defecto `JCoorp_SnackUP-core`, verificada en el enlace del proyecto. Permite configurar otro proyecto explícitamente. |
| Repository variable, opcional | `SONAR_HOST_URL` | `https://sonarcloud.io` para EU; `https://sonarqube.us` para US. Por defecto usa EU. |

Los dos secretos deben guardarse directamente en GitHub. **No incluirlos en código, capturas, grabaciones, issues ni mensajes.** Las claves de organización y proyecto son identificadores públicos y pueden quedar en el workflow. El conector usado para este cambio no administra secretos de GitHub, por lo que un administrador del repositorio debe guardar los tokens y el webhook.

En SonarQube Cloud, importar el repositorio correcto, habilitar el análisis por CI y evitar el análisis automático simultáneo. El workflow analiza los pushes a `main`/`master` y los pull requests hacia esas ramas. Esta estrategia permite usar el plan Free cuando el destino coincide con la rama principal reconocida por SonarQube. El checkout y los comprobantes usan el SHA real de la rama fuente del PR; nunca se presenta la revisión de merge como si fuera ese commit. No sobrescribir `sonar.branch.name=main` para presentar una feature como principal.

Si aparece `Could not find the pullrequest with key '24'`, revisar en el proyecto **Administration → General Settings → Repository binding**: debe estar vinculado realmente a `Gabino-RG/SnackUP-core`. El botón View on GitHub puede ser un enlace manual y no sustituye esa comprobación. Después, en la organización **Administration → Organization Settings → Organization binding → Repository Access settings**, comprobar que la app actual **SonarQubeCloud** tiene acceso al repositorio. No confundirla con la app heredada SonarCloud. Si el repositorio pertenece a otra organización de GitHub y no se ofrece como destino, importar el repositorio en una organización Sonar correspondiente y actualizar las claves públicas; no borrar el proyecto existente.

Fuentes oficiales: [cambiar el vínculo](https://docs.sonarsource.com/sonarqube-cloud/managing-your-projects/administering-your-projects/changing-binding), [acceso de la app GitHub](https://docs.sonarsource.com/sonarqube-cloud/administering-sonarcloud/managing-organization/creating-organization/importing-github-organization) y [planes](https://docs.sonarsource.com/sonarqube-cloud/administering-sonarcloud/managing-subscription/subscription-plans).

Esta implementación utiliza SonarQube Cloud, que dispone de análisis Dart oficial. No sustituirlo por un contenedor Community Build y afirmar que analizó Flutter: Community Build no incluye ese analizador nativo. Un servidor SonarQube con Dart requeriría adaptar el host y comprobar edición/licencia.

No se afirma que las condiciones propuestas en `qa-config/quality-gate.spec.json` estén aplicadas en el servidor. El comprobante conserva las condiciones que el Quality Gate real devuelve. Un Gate rechazado se corrige; no se desactiva para obtener una pantalla verde.

## 3. Cómo se verifica la alerta

El notificador detecta el proveedor por el host del webhook. Solo admite HTTPS y hosts/rutas de Slack o Discord; rechaza redirecciones.

- Discord: añade `wait=true` y exige respuesta con ID del mensaje creado.
- Slack: exige HTTP 200 y respuesta literal `ok`.
- Un error HTTP, ausencia de webhook o respuesta inesperada produce un comprobante de fallo y salida distinta de cero.
- Un CI aprobado, cancelado u omitido no envía alerta.

El mensaje incluye SnackUP, rama, commit, etapa fallida, ID/intento de ejecución y enlace al log. No incluye el webhook ni tokens. `DELIVERED` acredita aceptación por el servidor del proveedor; no acredita que una persona leyó el mensaje.

Se conservan dos artefactos de auditoría:

| Artefacto | Contenido |
| --- | --- |
| `snackup-ci-audit` | Configuración pública, resultados por etapa, cobertura LCOV, metadatos de tarea Sonar, background task y resultado de Quality Gate. |
| `snackup-ci-notification` | Proveedor, estado, código HTTP, acuse e ID público del mensaje cuando Discord lo devuelve. |

## 4. Dos ejecuciones para la evidencia

Trabajar en **`feature/ci-sonar-notifications`**, sin mezclar estos cambios en `main` antes de revisión.

1. Guardar los dos secretos y verificar los identificadores públicos efectivos (variables o valores por defecto). Abrir un PR desde esta rama hacia la principal reconocida por SonarQube (PR #24 existente) y hacer un commit para activar `Flutter CI - SonarQube y alertas`. Mantener `docs/ci-parte-2/failure-test.json` con `"enabled": false`. Esperar a que SonarQube, Quality Gate y empaquetado aprueben. Conservar el ID de esta ejecución.
2. Para probar la alerta, cambiar exclusivamente `"enabled": true` en ese JSON y hacer un commit en la misma rama. Después de aprobar SonarQube, el step `Prueba controlada de fallo para evidencia` termina con código 1; el artefacto validado queda omitido y el job de notificación debe confirmar `DELIVERED`. Conservar el ID de esta segunda ejecución.
3. Restaurar `"enabled": false` mediante un commit. Esta restauración deja la rama lista para validación normal. El aviso indica explícitamente que el fallo fue controlado, solo si ese step realmente falló.

El marcador activa el fallo en el PR de esta rama de evidencia hacia main/master; no se activa en otras ramas ni destinos. La lógica conserva soporte para push propio, aunque el workflow completo se ejecuta mediante PR en este escenario Free. También existe el input manual `evidence_failure` cuando GitHub habilita `Run workflow`. Una configuración ausente, un Gate rechazado o un webhook fallido no equivalen a esta demostración aprobada.

Los reintentos deben ejecutar todos los jobs para que auditoría, tarea Sonar y recibo correspondan al mismo `run_attempt`. No mezclar comprobantes de commits o intentos distintos.

## 5. Generar el video corto

Para grabar desde la propia rama, crear **después de obtener ambos IDs reales** `docs/ci-parte-2/evidence-runs.json`:

```json
{
  "success_run": 123456789,
  "failure_run": 123456790
}
```

Los números anteriores son ejemplos: reemplazarlos por los IDs reales. Hacer commit del archivo activa `SnackUP CI parte 2 - video de evidencia real` sin necesitar cambios en `main`. Si el workflow ya está habilitado para ejecución manual, se pueden introducir los mismos IDs desde `Run workflow`.

El recolector descarga estados y artefactos de GitHub y exige concordancia de repositorio, commit, ID/intento, tarea Sonar y `analysisId`. El grabador rechaza una configuración pendiente, un análisis omitido, un Gate no aprobado o una notificación sin acuse.

Descargar el artefacto **`snackup-ci-part2-video`** de esa ejecución. Contendrá:

- `SnackUP_Pipeline_CI_Parte2.mp4`: 80 segundos, H.264, 1600 × 1000.
- Capturas de SonarQube, Quality Gate, fallo y notificación, y cierre aprobado.
- JSON de las dos ejecuciones y manifiesto con hashes de la evidencia/video.

El video reproduce de forma acelerada estados reales con sus marcas de tiempo; no es una ejecución en vivo. Primero muestra el caso de fallo y la alerta, y termina con el pipeline aprobado para evitar confundir la demostración de Fail Fast con el estado final del proyecto.

## 6. Entrega sugerida

> Repositorio: https://github.com/Gabino-RG/SnackUP-core/tree/feature/ci-sonar-notifications
>
> Video: adjuntar `SnackUP_Pipeline_CI_Parte2.mp4`.
>
> SnackUP incorpora análisis SonarQube de Flutter/Dart con cobertura y Quality Gate bloqueante. Ante un fallo, envía automáticamente una alerta al canal del equipo. El video muestra una ejecución real aprobada y un fallo controlado con acuse real de la notificación.

Usar el texto anterior **solo después de comprobar ambos requisitos reales**. Mientras falten credenciales o ejecuciones, la implementación está preparada pero la entrega todavía no está completa.

## 7. Archivos y verificación

| Archivo | Parte importante |
| --- | --- |
| `.github/workflows/flutter-ci.yml` | Secuencia CI, scanner oficial, gate y notificación independiente. |
| `app/sonar-project.properties` | Alcance `lib`/`test`, exclusiones y LCOV; ya existía y se conserva. |
| `tools/ci_sonar/preflight.py` | Rechazo temprano de configuración ausente/insegura. |
| `tools/ci_sonar/quality_gate.py` | Espera de la tarea exacta y bloqueo por Gate. |
| `tools/ci_notifications/notify_failure.py` | Envío HTTPS y validación del acuse, sin exponer secretos. |
| `tools/ci_evidence/collect_part2.py` | Procedencia de ejecuciones y comprobantes. |
| `tools/ci_evidence/record_part2.cjs` | Video gráfico con estados observados y guardas contra evidencia incompleta. |

```bash
python3 -m unittest discover -s tools/ci_notifications/tests -v
python3 -m unittest discover -s tools/ci_sonar/tests -v
python3 -m unittest discover -s tools/ci_evidence/tests -v
node --test tools/ci_evidence/test_record_part2.cjs
```

El workflow `SnackUP CI parte 2 - verificar implementación` ejecuta estas pruebas sin acceder a servicios de SonarQube ni enviar mensajes.

Fuentes oficiales: [Dart y preparación del análisis](https://docs.sonarsource.com/sonarqube-cloud/analyzing-source-code/languages/dart), [cobertura Dart](https://docs.sonarsource.com/sonarqube-cloud/analyzing-source-code/test-coverage/dart-test-coverage), [planes](https://docs.sonarsource.com/sonarqube-cloud/administering-sonarcloud/managing-subscription/subscription-plans), [acción v8.3.0](https://github.com/SonarSource/sonarqube-scan-action/releases/tag/v8.3.0), [webhooks Slack](https://docs.slack.dev/messaging/sending-messages-using-incoming-webhooks/) y [webhooks Discord](https://docs.discord.com/developers/resources/webhook#execute-webhook).
