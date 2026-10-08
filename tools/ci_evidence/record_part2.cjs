#!/usr/bin/env node
'use strict';

// Records the original SnackUP agent. Input must come from completed, real CI runs.
// No synthetic success states, missing-configuration fallbacks or webhook sends.
const fs = require('node:fs');
const path = require('node:path');
const http = require('node:http');
const crypto = require('node:crypto');
const { spawnSync } = require('node:child_process');

const USAGE = `Uso:
  node record_part2.cjs --success aprobado.json --failure fallido.json --outdir video
       [--agent-root tools/ci_agent] [--validate-only]

Cada JSON: {state: estadoNormalizado, sonar: {analysis_id, gate_status,
scan_executed}, notification: {status, provider, http_status, message_id?}}.
--validate-only valida evidencia sin instalar Playwright ni generar un video.`;
const clone = value => JSON.parse(JSON.stringify(value));
const instant = value => typeof value === 'string' ? Date.parse(value) : NaN;
const textOf = stage => [stage.id, stage.name, stage.original_name, stage.command].filter(Boolean).join(' ');
const indexes = (state, kind) => state.stages.reduce((found, stage, index) => {
  const text = textOf(stage);
  const gate = /quality[ _-]*gate|sonar[ _-]*gate|puerta de calidad/i.test(text);
  const configuration = /(?:verify|check).*(?:sonar|credential|secret)|(?:sonar.*config|config.*sonar)/i.test(text);
  const matches = kind === 'scan' ? /sonar/i.test(text) && !gate && !configuration
    : kind === 'gate' ? gate
    : /notif|webhook|discord|slack|correo/i.test(text);
  if (matches) found.push(index);
  return found;
}, []);
function assert(condition, message) { if (!condition) throw new Error(message); }

function redactString(value) {
  return value
    .replace(/https:\/\/hooks\.slack\.com\/services\/[^\s"'<>]+/gi, '[WEBHOOK REDACTADO]')
    .replace(/https:\/\/(?:(?:canary|ptb)\.)?discord(?:app)?\.com\/api(?:\/v\d+)?\/webhooks\/[^\s"'<>]+/gi, '[WEBHOOK REDACTADO]')
    .replace(/\b(?:squ|sqp|sqa)_[A-Za-z0-9_]+\b/g, '[TOKEN REDACTADO]')
    .replace(/(Authorization\s*[:=]\s*(?:Bearer|Basic)\s+)[^\s"']+/gi, '$1[REDACTADO]')
    .replace(/(-Dsonar\.(?:token|login)=)[^\s"']+/gi, '$1[REDACTADO]')
    .replace(/((?:SONAR_TOKEN|CI_FAILURE_WEBHOOK|SLACK_WEBHOOK_URL|DISCORD_WEBHOOK_URL)\s*[:=]\s*)[^\s"']+/gi, '$1[REDACTADO]');
}
function redact(value) {
  if (typeof value === 'string') return redactString(value);
  if (Array.isArray(value)) return value.map(redact);
  if (value && typeof value === 'object') return Object.fromEntries(Object.entries(value).map(([key, item]) => [key, /^(?:token|secret|webhook_url|authorization)$/i.test(key) ? '[REDACTADO]' : redact(item)]));
  return value;
}

function validateEvidence(bundle, kind) {
  const label = kind === 'success' ? 'aprobado' : 'fallido';
  const state = bundle?.state;
  assert(state && Array.isArray(state.stages) && state.stages.length >= 5, `Caso ${label}: falta el estado normalizado del pipeline.`);
  assert(state.status === 'completed', `Caso ${label}: la ejecución debe haber terminado.`);
  assert(state.conclusion === (kind === 'success' ? 'success' : 'failure'), `Caso ${label}: la conclusión real no coincide.`);
  assert(Number.isSafeInteger(Number(state.run_id)) && Number(state.run_id) > 0, `Caso ${label}: falta run_id.`);
  assert(/^[a-f0-9]{40}$/i.test(state.sha || ''), `Caso ${label}: falta el SHA completo del commit.`);
  assert(/^[\w.-]+\/[\w.-]+$/.test(state.repository || ''), `Caso ${label}: falta el repositorio de origen.`);
  assert(state.url === `https://github.com/${state.repository}/actions/runs/${state.run_id}`, `Caso ${label}: URL de ejecución incoherente.`);
  const validStatuses = ['success', 'failure', 'skipped', 'blocked', 'cancelled'];
  for (const stage of state.stages) {
    assert(validStatuses.includes(stage.status), `Caso ${label}: etapa ${stage.name} sin conclusión verificable.`);
    assert(stage.name && stage.id && Array.isArray(stage.logs), `Caso ${label}: etapa incompleta.`);
    if (['success', 'failure'].includes(stage.status)) {
      const start = instant(stage.started_at), end = instant(stage.completed_at);
      assert(Number.isFinite(start) && Number.isFinite(end) && end >= start, `Caso ${label}: ${stage.name} carece de marcas de tiempo reales.`);
    }
  }
  const scanIndexes = indexes(state, 'scan'), gateIndexes = indexes(state, 'gate'), notificationIndexes = indexes(state, 'notification');
  assert(scanIndexes.length, `Caso ${label}: no hay etapa SonarQube.`);
  assert(gateIndexes.length, `Caso ${label}: no hay etapa Quality Gate.`);
  assert(bundle.sonar && typeof bundle.sonar.scan_executed === 'boolean', `Caso ${label}: falta constancia de ejecución del scanner.`);
  if (kind === 'success' || bundle.sonar.scan_executed) {
    assert(bundle.sonar.scan_executed === true, 'Caso aprobado: configurar SonarQube no demuestra ejecutar el análisis.');
    assert(typeof bundle.sonar.analysis_id === 'string' && bundle.sonar.analysis_id.trim().length >= 8, `Caso ${label}: falta analysis_id obtenido de SonarQube.`);
    assert(scanIndexes.some(index => state.stages[index].status === 'success'), `Caso ${label}: el análisis Sonar no terminó correctamente.`);
  }
  if (kind === 'success') {
    assert(bundle.sonar.gate_status === 'OK', 'Caso aprobado: el Quality Gate real debe devolver OK.');
    assert(gateIndexes.some(index => state.stages[index].status === 'success'), 'Caso aprobado: no existe etapa Quality Gate aprobada.');
    assert(!state.stages.some(stage => ['failure', 'blocked', 'cancelled'].includes(stage.status)), 'Caso aprobado: contiene una etapa fallida, bloqueada o cancelada.');
  } else {
    assert(state.stages.some(stage => stage.status === 'failure'), 'Caso fallido: no existe una etapa realmente fallida.');
    const receipt = bundle.notification;
    assert(receipt?.status === 'DELIVERED', 'Caso fallido: falta recibo DELIVERED de la notificación real.');
    assert(['slack', 'discord', 'email', 'correo'].includes(String(receipt.provider || '').toLowerCase()), 'Caso fallido: proveedor de notificación no reconocido.');
    assert(Number.isInteger(receipt.http_status) && receipt.http_status >= 200 && receipt.http_status < 300, 'Caso fallido: el proveedor no confirmó la entrega con HTTP 2xx.');
    if (String(receipt.provider).toLowerCase() === 'slack') assert(receipt.http_status === 200 && receipt.acknowledgement === 'slack_ok', 'Caso fallido: falta la confirmación HTTP 200 / ok de Slack.');
    if (String(receipt.provider).toLowerCase() === 'discord') assert(receipt.acknowledgement === 'discord_created_message' && /^\d{15,22}$/.test(String(receipt.message_id || '')), 'Caso fallido: falta el mensaje real creado por Discord (webhook wait=true).');
    if (receipt.run_id !== undefined) assert(String(receipt.run_id) === String(state.run_id), 'Caso fallido: el recibo pertenece a otra ejecución.');
    if (receipt.repository !== undefined) assert(receipt.repository === state.repository, 'Caso fallido: el recibo pertenece a otro repositorio.');
    if (receipt.commit !== undefined || receipt.sha !== undefined) assert((receipt.commit || receipt.sha) === state.sha, 'Caso fallido: el recibo pertenece a otro commit.');
    assert(notificationIndexes.some(index => state.stages[index].status === 'success'), 'Caso fallido: la etapa de notificación no se ejecutó correctamente.');
    const failureAt = Math.min(...state.stages.filter(stage => stage.status === 'failure').map(stage => instant(stage.completed_at)));
    assert(notificationIndexes.some(index => state.stages[index].status === 'success' && instant(state.stages[index].started_at) >= failureAt), 'Caso fallido: la notificación precede al fallo.');
  }
  return {scanIndexes, gateIndexes, notificationIndexes};
}

function timeline(state) {
  const executed = state.stages.filter(stage => ['success', 'failure'].includes(stage.status));
  const start = Math.min(...executed.map(stage => instant(stage.started_at)));
  const end = Math.max(...executed.map(stage => instant(stage.completed_at)));
  assert(Number.isFinite(start) && Number.isFinite(end) && end > start, 'No hay una cronología reproducible.');
  const failures = executed.filter(stage => stage.status === 'failure');
  return {start, end, duration: (end - start) / 1000, failureAt: failures.length ? Math.min(...failures.map(stage => instant(stage.completed_at))) : Infinity};
}

// Every projected status comes from the recorded stage's actual start/end time.
// Pending/running frames hide future logs, artifacts and final decisions.
function projectState(source, elapsedSeconds) {
  const times = timeline(source), elapsed = Math.max(0, Math.min(elapsedSeconds, times.duration));
  const now = times.start + elapsed * 1000, final = now >= times.end;
  const projected = clone(source);
  projected.mode = 'replay';
  projected.status = final ? 'completed' : 'running';
  projected.conclusion = final ? source.conclusion : null;
  projected.completed_at = final ? source.completed_at : null;
  projected.decisions = final ? (source.decisions || []) : [];
  projected.artifacts = final ? (source.artifacts || []) : [];
  projected.stages = source.stages.map(original => {
    const stage = clone(original), start = instant(original.started_at), end = instant(original.completed_at);
    if (['skipped', 'blocked', 'cancelled'].includes(stage.status)) {
      const revealAt = Number.isFinite(end) ? end : times.failureAt;
      if (!final && now < revealAt) {stage.status = 'pending'; stage.started_at = null; stage.completed_at = null; stage.logs = [];}
    } else if (now >= end) {
      // Keep the actual conclusion, never turn a skipped step into a success.
    } else if (now >= start) {stage.status = 'running'; stage.completed_at = null; stage.logs = [];}
    else {stage.status = 'pending'; stage.started_at = null; stage.completed_at = null; stage.logs = [];}
    return stage;
  });
  // Source notes may include outcomes; disclose them only after the run ends.
  projected.source_notes = final ? (source.source_notes || []) : ['Reproducción acelerada de una ejecución real; los resultados se revelan según sus marcas de tiempo.'];
  return {state: projected, times, elapsed, final};
}

function argumentsFrom(argv) {
  const args = {};
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    if (['--help', '-h'].includes(arg)) return {help: true};
    if (arg === '--validate-only') {args.validateOnly = true; continue;}
    assert(['--success', '--failure', '--outdir', '--agent-root'].includes(arg), `Argumento desconocido: ${arg}`);
    assert(argv[i + 1] && !argv[i + 1].startsWith('--'), `Falta valor de ${arg}.`);
    args[arg.slice(2)] = path.resolve(argv[++i]);
  }
  assert(args.success && args.failure && (args.outdir || args.validateOnly), USAGE);
  return args;
}

async function staticServer(agentRoot, bundles) {
  const webRoot = path.join(agentRoot, 'web');
  assert(fs.existsSync(path.join(webRoot, 'index.html')), 'No se encontró la interfaz original. Usa --agent-root.');
  const files = {'/':'index.html', '/index.html':'index.html', '/styles.css':'styles.css', '/app.js':'app.js'};
  const server = http.createServer((req, res) => {
    const url = new URL(req.url, 'http://127.0.0.1');
    if (url.pathname === '/api/evidence') {
      res.writeHead(200, {'Content-Type':'application/json', 'Cache-Control':'no-store'});
      res.end(JSON.stringify(bundles[url.searchParams.get('case') === 'failure' ? 'failure' : 'success'].state));
      return;
    }
    if (url.pathname === '/evidence-data.js') {
      res.writeHead(200, {'Content-Type':'application/javascript', 'Cache-Control':'no-store'});
      res.end(`window.SNACKUP_EVIDENCE=${JSON.stringify(bundles.success.state)};window.SNACKUP_EVIDENCE_FAILURE=${JSON.stringify(bundles.failure.state)};`);
      return;
    }
    const file = files[url.pathname];
    if (!file) {res.writeHead(404); res.end(); return;}
    res.writeHead(200, {'Content-Type':file.endsWith('.html') ? 'text/html' : file.endsWith('.css') ? 'text/css' : 'application/javascript', 'Cache-Control':'no-store'});
    fs.createReadStream(path.join(webRoot, file)).pipe(res);
  });
  await new Promise((resolve, reject) => {server.once('error', reject); server.listen(0, '127.0.0.1', resolve);});
  return {url:`http://127.0.0.1:${server.address().port}/`, close:() => new Promise(resolve => server.close(resolve))};
}

function scene(time, bundles) {
  if (time < 4) return {key:'failure', elapsed:0, caption:'SnackUP · Segunda parte CI | SonarQube + notificación de fallos | Ejecuciones reales'};
  if (time < 24) return {key:'failure', elapsed:(time - 4) / 20 * timeline(bundles.failure.state).duration, caption:'Caso de fallo: reconstrucción acelerada de los pasos y de la notificación posterior'};
  if (time < 34) return {key:'failure', elapsed:Infinity, focus:'notification', caption:'Fallo detectado → aviso real al equipo | El servidor del proveedor aceptó el mensaje'};
  if (time < 66) return {key:'success', elapsed:(time - 34) / 32 * timeline(bundles.success.state).duration, caption:'Caso aprobado: pasos reales de SnackUP, análisis SonarQube, Quality Gate y artefacto'};
  if (time < 72) return {key:'success', elapsed:Infinity, focus:'scan', caption:'SonarQube ejecutado: análisis del código y resultados identificables en el servidor'};
  if (time < 77) return {key:'success', elapsed:Infinity, focus:'gate', caption:'Quality Gate real: OK | La validación de calidad forma parte del pipeline'};
  return {key:'success', elapsed:Infinity, focus:'artifact', caption:'Evidencia final: CI aprobado + aviso de fallo entregado | Repositorio y ejecuciones verificables'};
}

async function record(args, bundles, checks) {
  // Require optional authoring dependencies only after the authentic-evidence guard.
  const { chromium } = require('playwright');
  const sibling = path.resolve(__dirname, '..', 'ci_agent');
  const agentRoot = args['agent-root'] || (fs.existsSync(path.join(sibling, 'web')) ? sibling : path.resolve(__dirname, '../../..', 'SnackUP-CI-Agent'));
  const out = args.outdir, frames = path.join(out, 'frames');
  fs.mkdirSync(frames, {recursive:true});
  const server = await staticServer(agentRoot, bundles);
  let browser;
  const errors = [], sizes = {};
  try {
    browser = await chromium.launch({headless:true, args:['--no-sandbox']});
    const page = await browser.newPage({viewport:{width:1600, height:1000}, deviceScaleFactor:1});
    page.on('pageerror', error => errors.push(String(error)));
    await page.goto(server.url, {waitUntil:'networkidle'});
    await page.waitForFunction(() => window.SnackupAgent?.getState()?.stages?.length > 0);
    await page.addStyleTag({content:`
      .topbar{height:60px}.nav-active:after{bottom:-20px}.hero{padding:16px 0}h1{font-size:29px}
      .toolbar{margin-bottom:12px}.run-strip{padding:11px 16px}.progress-overview{margin:14px 0}
      .panel-heading{min-height:61px;padding:12px 16px}.stage-list{padding:7px 9px}
      .stage{padding:4px 7px;margin-bottom:1px;gap:8px;height:var(--ci-stage-row-height,40px)}
      .stage-copy strong{font-size:12px;line-height:1.25}.stage-copy small{font-size:9px;line-height:1.2;margin-top:2px}
      .stage-icon{width:23px;height:23px}.stage:not(:last-child) .stage-icon:after{top:24px;height:16px}
      .panel-footer{padding:9px 5px}.terminal pre{height:256px;font-size:11px}.detail-summary p{min-height:26px}
      .decisions{height:145px;max-height:145px;min-height:145px}.failfast-card{margin-top:10px}.page-footer{padding:11px 0}
      #ci2-proof{margin:0 16px 12px;padding:10px 11px;border:1px solid #e3d9eb;border-radius:8px;background:#f5effa;font:11px/1.65 system-ui;overflow-wrap:anywhere}
      #ci2-proof strong{display:block;font-size:12px;color:#76528e}#ci2-proof .verified{color:#458976;font-weight:650}
      #video-caption{position:fixed;left:30px;right:30px;bottom:15px;padding:13px 20px;background:#292238;color:#fff;border-radius:12px;font:600 19px/1.4 system-ui;z-index:9999;text-align:center;box-shadow:0 3px 20px #0002;pointer-events:none}
    `});
    await page.evaluate(() => {
      window.SnackupAgent.stop();
      const caption = document.createElement('div'); caption.id = 'video-caption'; document.body.append(caption);
      const proof = document.createElement('div'); proof.id = 'ci2-proof';
      document.querySelector('.agent-panel').insertBefore(proof, document.querySelector('.failfast-card'));
      document.querySelector('.hero h1').textContent = 'CI con calidad y alertas.';
      document.querySelector('.hero p').textContent = 'SonarQube · Quality Gate · Notificación cuando el pipeline falla';
      document.querySelector('.additional-controls').hidden = true;
    });
    const fps = 4, seconds = 80;
    let activeKey = '';
    for (let frame = 0; frame < fps * seconds; frame++) {
      const time = frame / fps, current = scene(time, bundles), bundle = bundles[current.key];
      const projection = projectState(bundle.state, current.elapsed);
      let selected = projection.state.stages.findIndex(stage => stage.status === 'running');
      if (current.focus === 'notification') selected = checks[current.key].notificationIndexes.find(index => bundle.state.stages[index].status === 'success');
      else if (current.focus === 'scan') selected = checks[current.key].scanIndexes.find(index => bundle.state.stages[index].status === 'success');
      else if (current.focus === 'gate') selected = checks[current.key].gateIndexes.find(index => bundle.state.stages[index].status === 'success');
      else if (current.focus === 'artifact') selected = projection.state.stages.findIndex(stage => /artifact|artefact|empaqueta|upload/i.test(textOf(stage)) && stage.status === 'success');
      if (selected === undefined || selected < 0) selected = projection.state.stages.findIndex(stage => stage.status === 'failure');
      if (selected < 0) selected = Math.max(0, projection.state.stages.length - 1);
      await page.evaluate(({state, selected, caption, elapsed, duration, bundle, checks}) => {
        window.SnackupAgent.setState(state); window.SnackupAgent.selectStage(selected);
        document.getElementById('video-caption').textContent = caption;
        document.getElementById('evidenceCase').value = state.conclusion === 'success' || state.run_id === window.SNACKUP_EVIDENCE.run_id ? 'success' : 'failure';
        document.getElementById('modeDescription').textContent = `Reproducción acelerada · registrada ${new Date(state.started_at || state.stages.find(s => s.started_at)?.started_at).toLocaleString('es-MX')}`;
        document.getElementById('elapsedLabel').textContent = `${Math.round(elapsed)} s de ${Math.round(duration)} s registrados · se usan marcas de tiempo originales`;
        const proof = document.getElementById('ci2-proof'); proof.replaceChildren();
        const add = (label, value, passed = false) => {const line = document.createElement('div'); line.textContent = `${label}: ${value}`; if (passed) line.className = 'verified'; proof.append(line);};
        const title = document.createElement('strong'); title.textContent = 'Evidencia de la segunda parte'; proof.append(title);
        const scanDone = checks.scanIndexes.some(index => state.stages[index].status === 'success');
        const gateDone = checks.gateIndexes.some(index => state.stages[index].status === 'success');
        const notifyDone = checks.notificationIndexes.some(index => state.stages[index].status === 'success');
        add('SonarQube', scanDone ? 'Análisis ejecutado' : 'Pendiente / en curso', scanDone);
        if (scanDone && bundle.sonar.analysis_id) add('Análisis', bundle.sonar.analysis_id);
        add('Quality Gate', gateDone ? bundle.sonar.gate_status : 'Sin conclusión todavía', gateDone && bundle.sonar.gate_status === 'OK');
        if (notifyDone && bundle.notification.status === 'DELIVERED') {
          add('Aviso', `DELIVERED · ${bundle.notification.provider} · HTTP ${bundle.notification.http_status}`, true);
          if (bundle.notification.message_id) add('Mensaje', bundle.notification.message_id);
          add('Alcance', 'Aceptación del servidor; no lectura humana');
        } else add('Aviso por fallo', state.conclusion === 'success' ? 'No aplica: ejecución aprobada' : 'No entregado todavía');
        const list = document.getElementById('stageList'), footer = list.parentElement.querySelector('.panel-footer');
        const available = document.getElementById('video-caption').getBoundingClientRect().top - list.getBoundingClientRect().top - footer.getBoundingClientRect().height - 12;
        const rowHeight = Math.max(36, Math.min(48, Math.floor((available - 14) / state.stages.length) - 1));
        list.style.height = `${Math.min(available, state.stages.length * (rowHeight + 1) + 14)}px`;
        list.style.setProperty('--ci-stage-row-height', `${rowHeight}px`);
        const activeRow = list.children[selected];
        if (activeRow) list.scrollTop = Math.max(0, activeRow.offsetTop - list.offsetTop - list.clientHeight / 2 + activeRow.clientHeight / 2);
        document.getElementById('logPanel').scrollTop = currentFocusBottom(state.stages[selected]);
        function currentFocusBottom(stage) {return /notif|sonar|quality[ _-]*gate/i.test([stage.id, stage.name].join(' ')) ? document.getElementById('logPanel').scrollHeight : 0;}
      }, {state:projection.state, selected, caption:current.caption, elapsed:projection.elapsed, duration:projection.times.duration, bundle, checks:checks[current.key]});
      if (activeKey !== current.key) {
        activeKey = current.key;
        sizes[current.key] = await page.evaluate(() => {const list = document.getElementById('stageList'); return {height:list.clientHeight, content:list.scrollHeight, rows:list.children.length};});
        sizes[current.key].all_fit = sizes[current.key].content <= sizes[current.key].height + 2;
        sizes[current.key].scroll_follows_actual_stage = !sizes[current.key].all_fit;
      }
      if (frame === 127) await page.screenshot({path:path.join(out, 'ci2-fallo-notificacion.png')});
      if (frame === 283) await page.screenshot({path:path.join(out, 'ci2-sonarqube.png')});
      if (frame === 303) await page.screenshot({path:path.join(out, 'ci2-quality-gate.png')});
      await page.screenshot({path:path.join(frames, `${String(frame).padStart(5, '0')}.png`)});
    }
    assert(!errors.length, `Errores de la interfaz: ${errors.join('\n')}`);
    await page.screenshot({path:path.join(out, 'ci2-aprobado-final.png')});
    const rendered = spawnSync('ffmpeg', ['-y', '-framerate', String(fps), '-i', path.join(frames, '%05d.png'), '-vf', 'fps=30', '-c:v', 'libx264', '-preset', 'fast', '-crf', '21', '-pix_fmt', 'yuv420p', '-movflags', '+faststart', path.join(out, 'SnackUP_Pipeline_CI_Parte2.mp4')], {encoding:'utf8', maxBuffer:4 * 1024 * 1024});
    if (rendered.error) throw rendered.error;
    assert(rendered.status === 0, rendered.stderr || 'FFmpeg no pudo codificar el video.');
    fs.rmSync(frames, {recursive:true, force:true});
    const manifest = {duration_seconds:seconds, resolution:'1600x1000', type:'Reproducción acelerada de ejecuciones reales', successful_run:bundles.success.state.url, failed_run:bundles.failure.state.url, sonar_analysis_id:bundles.success.sonar.analysis_id, quality_gate:bundles.success.sonar.gate_status, notification:bundles.failure.notification, browser_errors:errors, all_stages_fit:sizes};
    manifest.input_sha256 = Object.fromEntries(['success', 'failure'].map(key => [key, crypto.createHash('sha256').update(fs.readFileSync(args[key])).digest('hex')]));
    manifest.video_sha256 = crypto.createHash('sha256').update(fs.readFileSync(path.join(out, 'SnackUP_Pipeline_CI_Parte2.mp4'))).digest('hex');
    fs.writeFileSync(path.join(out, 'verificacion-video-parte2.json'), JSON.stringify(redact(manifest), null, 2) + '\n');
    console.log(`Video real de 80 segundos generado: ${path.join(out, 'SnackUP_Pipeline_CI_Parte2.mp4')}`);
  } finally {
    if (browser) await browser.close();
    await server.close();
  }
}

async function main(argv = process.argv.slice(2)) {
  const args = argumentsFrom(argv);
  if (args.help) {console.log(USAGE); return;}
  const bundles = Object.fromEntries(['success', 'failure'].map(key => [key, redact(JSON.parse(fs.readFileSync(args[key], 'utf8')))]));
  const checks = {success:validateEvidence(bundles.success, 'success'), failure:validateEvidence(bundles.failure, 'failure')};
  assert(bundles.success.state.repository === bundles.failure.state.repository, 'Los casos deben pertenecer al mismo repositorio.');
  assert(String(bundles.success.state.run_id) !== String(bundles.failure.state.run_id), 'Los casos aprobado y fallido requieren dos ejecuciones distintas.');
  if (args.validateOnly) {console.log('Evidencia válida: SonarQube ejecutado, Quality Gate OK y aviso real DELIVERED. No se generó un video.'); return;}
  await record(args, bundles, checks);
}
module.exports = {argumentsFrom, indexes, validateEvidence, timeline, projectState, redact, scene, main};
if (require.main === module) main().catch(error => {console.error(`No se generó evidencia final: ${error.message}`); process.exitCode = 1;});
