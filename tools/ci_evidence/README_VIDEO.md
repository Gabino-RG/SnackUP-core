# Video de evidencia de CI — segunda parte

`record_part2.cjs` graba la interfaz original del agente SnackUP a partir de **dos ejecuciones CI reales terminadas**. No ejecuta el pipeline, no envía notificaciones y no convierte una configuración pendiente en evidencia.

Requisitos de autoría: Node.js 20 o posterior, Playwright con Chromium, FFmpeg con `libx264` y una copia de `tools/ci_agent/web` de la primera parte. El iniciador Python del agente no es necesario: el script sirve sus archivos en un puerto aleatorio de `127.0.0.1` y cierra el servidor al terminar.

```bash
npm install --no-save playwright
npx playwright install chromium
node tools/ci_evidence/record_part2.cjs \
  --success evidence/ci-part2/success.json \
  --failure evidence/ci-part2/failure.json \
  --agent-root tools/ci_agent \
  --outdir video-parte2
```

Argumentos:

| Argumento | Función |
| --- | --- |
| `--success archivo.json` | Estado de la ejecución aprobada y resultado real SonarQube / Quality Gate. |
| `--failure archivo.json` | Estado de la ejecución fallida y recibo real de notificación. |
| `--outdir carpeta` | Destino del MP4, capturas y manifiesto de verificación. |
| `--agent-root carpeta` | Directorio del agente original que contiene `web/`. Por defecto busca `tools/ci_agent` y, en este espacio de trabajo, `SnackUP-CI-Agent`. |
| `--validate-only` | Verifica los dos JSON sin cargar Playwright ni crear video. No requiere `--outdir`. |

El recolector debe producir este esquema con datos de GitHub Actions, la respuesta de SonarQube y el recibo del proveedor:

```text
{
  state: {repository, run_id, sha, url, status, conclusion, stages, ...},
  sonar: {analysis_id, gate_status, scan_executed, ...},
  notification: {status, provider, http_status, message_id?, ...},
  source: {...}
}
```

Cada etapa tiene `id`, `name`, `status`, `logs` como arreglo y, si se ejecutó, `started_at` / `completed_at` originales. El video usa los IDs acreditados `sonar.scan_stage_id`, `sonar.gate_stage_id` y `notification.notification_stage_id` del recolector; en datos sin esos campos, reconoce los nombres o comandos. Comprueba que el ID corresponda al paso correcto: descargar el código del notificador o guardar su comprobante no se interpreta como enviar el aviso. Tampoco interpreta una comprobación de credenciales como ejecución del scanner.

La ejecución aprobada debe incluir un análisis SonarQube ejecutado, `analysis_id`, `gate_status: "OK"` y pasos de análisis / gate aprobados. La ejecución fallida debe incluir un fallo y una notificación posterior aprobada, recibo `status: "DELIVERED"`, proveedor Slack/Discord/correo y HTTP 2xx. Discord requiere el ID numérico del mensaje creado mediante `wait=true` y `acknowledgement: "discord_created_message"`. Slack requiere HTTP 200 y `acknowledgement: "slack_ok"`, asignado sólo después de comprobar el cuerpo `ok`. Cuando el recibo conserva repositorio, run ID y commit, deben coincidir con la ejecución. Un HTTP 2xx aislado, una etapa omitida o un envío simulado no cumplen estas condiciones. `DELIVERED` acredita aceptación por el servidor del proveedor; no demuestra que una persona leyó el aviso.

El video dura **80 segundos**, resolución **1600 × 1000**, formato MP4 H.264. Reconstruye los estados a partir de los tiempos originales y oculta registros / resultados futuros. Si hay muchas etapas, la lista sigue con desplazamiento la etapa observada; no borra los pasos desconocidos. Primero muestra el caso de fallo y el recibo de aviso; termina con el CI aprobado y Quality Gate OK. Las leyendas aclaran que es una reproducción acelerada de ejecuciones reales.

Salidas:

- `SnackUP_Pipeline_CI_Parte2.mp4`
- `ci2-fallo-notificacion.png`
- `ci2-sonarqube.png`
- `ci2-quality-gate.png`
- `ci2-aprobado-final.png`
- `verificacion-video-parte2.json` con URLs de ejecuciones, analysis ID, recibo sanitizado y hashes SHA-256 de entradas / video.

El script oculta formatos comunes de tokens y URL de webhooks en textos y metadatos. El recolector debe entregar evidencia ya sanitizada; no introducir credenciales en los archivos JSON.

Validación de las reglas sin grabación:

```bash
node --test tools/ci_evidence/test_record_part2.cjs
node tools/ci_evidence/record_part2.cjs --success aprobado.json --failure fallido.json --validate-only
```

Las fixtures de prueba son artificiales y sólo verifican rechazo, concordancia, cronología y compatibilidad con `collect_part2.py`. La prueba de contrato consume en memoria sus fixtures existentes; no genera archivos de evidencia ni video. No se usan como evidencia de la actividad ni como entrada para un video final.
