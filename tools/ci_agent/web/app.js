/* SnackUP CI Agent: rendering and transparent replay of recorded execution data. */
(() => {
  'use strict';
  const $ = id => document.getElementById(id);
  const statusLabels = {pending:'Pendiente',running:'En curso',success:'Aprobada',failure:'Fallida',skipped:'Sin ejecutar',blocked:'Bloqueada',cancelled:'Cancelada',completed:'Finalizada'};
  const modeLabels = {replay:'Reproducción de ejecución real',live:'En vivo · GitHub',demo:'Demostración aislada',local:'CI local'};
  let state = null, evidence = null, selected = 0, manuallySelected = false;
  let timer = null, replay = null, pollToken = 0;
  const clone = value => JSON.parse(JSON.stringify(value));
  const timestamp = value => value ? Date.parse(value) : NaN;
  const isTerminal = value => ['success','failure','skipped','blocked','cancelled'].includes(value);
  const speedLabel = value => `${Math.round(Number(value) * 100) / 100}×`;

  function durationLabel(seconds) {
    if (!Number.isFinite(seconds) || seconds < 0) return '—';
    if (seconds < 60) return `${Math.round(seconds)} s`;
    return `${Math.floor(seconds / 60)} min ${Math.round(seconds % 60)} s`;
  }

  function stageDuration(stage) {
    const start = timestamp(stage.started_at), end = timestamp(stage.completed_at);
    if (!Number.isFinite(start)) return '—';
    if (stage.status === 'running' && replay) return durationLabel(Math.max(0, replay.elapsed - ((start - replay.start) / 1000)));
    if (Number.isFinite(end)) return durationLabel((end - start) / 1000);
    if (stage.status === 'running') return durationLabel((Date.now() - start) / 1000);
    return '—';
  }

  function notice(message, error = false) {
    $('notice').textContent = message;
    $('notice').className = `notice${error ? ' error' : ''}`;
    $('notice').hidden = !message;
  }

  async function api(path, options) {
    if (location.protocol === 'file:') throw new Error('Esta función necesita el iniciador local. Abre INICIAR_WINDOWS.bat o el iniciador correspondiente y usa la dirección que muestra. La evidencia incluida puede reproducirse sin conexión.');
    const response = await fetch(path, {cache:'no-store',...options});
    const body = await response.json();
    if (!response.ok) throw new Error(body.error || `No se pudo consultar el servidor (${response.status}).`);
    return body;
  }

  function normalize(input) {
    const value = clone(input);
    value.stages = Array.isArray(value.stages) ? value.stages : [];
    value.decisions = Array.isArray(value.decisions) ? value.decisions : [];
    value.artifacts = Array.isArray(value.artifacts) ? value.artifacts : [];
    value.source_notes = Array.isArray(value.source_notes) ? value.source_notes : typeof value.source_notes === 'string' && value.source_notes ? [value.source_notes] : [];
    value.stages.forEach((stage, index) => {stage.id ??= `stage-${index}`;stage.logs = Array.isArray(stage.logs) ? stage.logs : [];stage.status ||= 'pending';});
    return value;
  }

  function safeLink(anchor, url) {
    let valid = false;
    try { const parsed = new URL(url); valid = ['http:','https:'].includes(parsed.protocol); } catch (_) { /* no external link */ }
    anchor.hidden = !valid;
    if (valid) anchor.href = url;
    else anchor.removeAttribute('href');
  }

  function runOutcome() {
    if (!state) return 'pending';
    if (state.conclusion && state.status === 'completed') return state.conclusion;
    return state.status === 'running' ? 'running' : 'pending';
  }

  function currentDecisions() {
    if (!state) return [];
    const failed = state.stages.find(stage => stage.status === 'failure');
    if (failed) {
      if (state.decisions.length) return state.decisions;
      return [{level:'failure',title:`Fallo en ${failed.name}`,detail:'La ejecución devolvió un resultado fallido. El agente identifica la primera etapa que bloquea la integración.',recommendation:'Consulta el registro, corrige el error y vuelve a ejecutar el pipeline.'},{level:'info',title:'Etapas posteriores detenidas',detail:'Fail fast evita continuar con un resultado que todavía no ha sido validado.'}];
    }
    if (state.status === 'completed' && state.decisions.length) return state.decisions;
    if (state.status === 'completed' && state.conclusion === 'success') return [{level:'success',title:'Validación completada',detail:`Las ${state.stages.filter(s => s.status === 'success').length} etapas aprobadas quedan respaldadas por la ejecución registrada.`},{level:'info',title:'CI concluido',detail:state.artifacts.length ? 'El artefacto puede revisarse en la ejecución de origen. El despliegue pertenece a CD.' : 'Consulta la ejecución de origen para comprobar sus salidas.'}];
    const active = state.stages.find(stage => stage.status === 'running');
    if (active) return [{level:'info',title:`Observando: ${active.name}`,detail:active.description || 'La siguiente etapa solo se habilita si esta termina correctamente.',recommendation:'El agente compara el estado de cada etapa y detecta la primera condición de fallo.'},{level:'info',title:'Avance verificable',detail:state.mode === 'replay' ? 'Los estados se reconstruyen a partir de las marcas de tiempo del registro real. Los resultados se revelan al concluir cada etapa.' : 'El monitor consulta el estado de la ejecución. Los registros permiten revisar la causa de cualquier fallo.'}];
    return [{level:'info',title:'Listo para observar',detail:'Reproduce una ejecución real o conecta el monitor a GitHub. Selecciona una etapa para inspeccionar sus registros.'},{level:'info',title:'Reglas transparentes',detail:'El agente identifica ejecución, aprobación, fallo y etapas omitidas. Sus decisiones se basan en esos estados.'}];
  }

  function renderDecisions() {
    $('agentDecisions').replaceChildren();
    for (const decision of currentDecisions().slice(0,3)) {
      const card = document.createElement('div'); card.className = `decision ${decision.level || 'info'}`;
      const label = document.createElement('div'); label.className = 'decision-label';
      label.textContent = ['failure','error'].includes(decision.level) ? 'DIAGNÓSTICO' : decision.level === 'success' ? 'VALIDACIÓN' : 'OBSERVACIÓN';
      const title = document.createElement('strong'); title.textContent = decision.title || 'Estado del pipeline';
      card.append(label,title);
      if (decision.detail) {const detail = document.createElement('p');detail.textContent = decision.detail;card.append(detail);}
      if (decision.recommendation) {const rec = document.createElement('p');rec.className = 'recommendation';rec.textContent = decision.recommendation;card.append(rec);}
      $('agentDecisions').append(card);
    }
  }

  function renderStages() {
    const container = $('stageList');
    const scroll = container.scrollTop;
    container.replaceChildren();
    state.stages.forEach((stage,index) => {
      const button = document.createElement('button'); button.className = `stage ${stage.status}${selected === index ? ' selected' : ''}`;
      button.setAttribute('aria-label',`${index+1}. ${stage.name}, ${statusLabels[stage.status] || stage.status}`);
      button.setAttribute('aria-pressed',String(selected === index));
      const icon = document.createElement('span');icon.className = 'stage-icon';
      icon.textContent = stage.status === 'success' ? '✓' : stage.status === 'failure' ? '×' : ['blocked','skipped','cancelled'].includes(stage.status) ? '−' : stage.status === 'running' ? '' : String(index+1).padStart(2,'0');
      const copy = document.createElement('div');copy.className = 'stage-copy';
      const name = document.createElement('strong');name.textContent = stage.name;
      const desc = document.createElement('small');
      desc.textContent = `${statusLabels[stage.status] || stage.status}${stage.command ? ` · ${stage.command}` : ''}`;
      copy.append(name,desc);
      const duration = document.createElement('span');duration.className = 'stage-duration';duration.textContent = stageDuration(stage);
      button.append(icon,copy,duration);
      button.addEventListener('click',() => selectStage(index));
      container.append(button);
    });
    container.scrollTop = scroll;
  }

  function renderDetail() {
    const stage = state.stages[selected];
    if (!stage) return;
    $('detailTitle').textContent = stage.name;
    $('detailNumber').textContent = `${String(selected+1).padStart(2,'0')} / ${String(state.stages.length).padStart(2,'0')}`;
    $('detailStatus').textContent = statusLabels[stage.status] || stage.status;
    $('detailStatus').className = `status-pill ${stage.status}`;
    $('detailDuration').textContent = stageDuration(stage);
    $('detailDescription').textContent = stage.description || (stage.status === 'skipped' ? 'Esta etapa no se ejecutó. Revisa las etapas anteriores.' : 'Información de la etapa seleccionada en el pipeline.');
    const lines = [];
    if (stage.command) lines.push(`$ ${stage.command}`,'');
    if (stage.status === 'pending') lines.push('La etapa todavía no ha comenzado.','Espera a que se validen las etapas anteriores.');
    else if (stage.status === 'running' && state.mode === 'replay') {
      lines.push(`Inicio registrado: ${stage.started_at || 'consultar fuente'}`,'','Reconstruyendo el avance de una ejecución real.','Los registros completos se muestran al terminar esta etapa.');
    } else if (stage.logs.length) lines.push(...stage.logs);
    else if (['skipped','blocked'].includes(stage.status)) lines.push('Etapa sin ejecutar.','El pipeline se detuvo antes de llegar a este paso.');
    else if (stage.status === 'running') lines.push('Comando en ejecución. Esperando registros del monitor…');
    else lines.push(`Estado registrado: ${statusLabels[stage.status] || stage.status}.`,'Consulta el enlace de origen para ver el registro completo.');
    $('logPanel').textContent = lines.join('\n');
    $('logSource').textContent = state.mode === 'demo' ? 'Proceso local' : state.mode === 'local' ? 'Flutter local' : 'GitHub Actions';
  }

  function render() {
    if (!state) return;
    const outcome = runOutcome();
    $('modeLabel').textContent = modeLabels[state.mode] || 'Evidencia de GitHub Actions';
    const dates = state.stages.map(s => timestamp(s.started_at)).filter(Number.isFinite);
    const recorded = dates.length ? new Date(Math.min(...dates)).toLocaleString('es-MX',{dateStyle:'short',timeStyle:'short'}) : '';
    $('modeDescription').textContent = state.mode === 'replay' ? `${replay ? `${speedLabel(replay.speed)} · ` : ''}Registrada ${recorded || 'en GitHub Actions'}${replay?.paused ? ' · pausada' : ''}` : state.mode === 'demo' ? 'Comandos inocuos reales · entorno separado' : state.mode === 'local' ? 'Comandos Flutter del proyecto seleccionado' : 'Consulta del estado real en GitHub Actions';
    $('modeIndicator').style.background = outcome === 'failure' ? 'var(--red)' : outcome === 'running' ? 'var(--purple)' : 'var(--green)';
    $('modeIndicator').style.boxShadow = `0 0 0 5px ${outcome === 'failure' ? 'var(--red-light)' : outcome === 'running' ? 'var(--purple-light)' : 'var(--green-light)'}`;
    $('modeType').textContent = state.mode === 'demo' ? 'DEMO' : 'CI';
    const runTitle = `${state.title || state.repository || 'SnackUP'}${state.run_id ? ` #${state.run_id}` : ''}`;
    $('runTitle').textContent = runTitle;
    $('runTitle').title = runTitle;
    $('branchLabel').textContent = state.branch || '—';
    $('shaLabel').textContent = state.sha ? state.sha.slice(0,8) : '—';
    $('shaLabel').title = state.sha || '';
    $('runStatus').textContent = outcome === 'success' ? 'CI aprobado' : outcome === 'failure' ? 'CI fallido' : outcome === 'cancelled' ? 'Cancelado' : outcome === 'running' ? 'En ejecución' : 'En espera';
    $('runStatus').className = `status-pill ${outcome}`;
    safeLink($('sourceLink'),state.url);
    const terminal = state.stages.filter(s => isTerminal(s.status)).length;
    const success = state.stages.filter(s => s.status === 'success').length;
    const running = state.stages.find(s => s.status === 'running');
    $('progressCount').textContent = `${terminal} / ${state.stages.length} etapas`;
    $('progressHeadline').textContent = outcome === 'success' ? 'Pipeline completado · validaciones aprobadas' : outcome === 'failure' ? 'Pipeline detenido · fallo detectado' : running ? `En ejecución: ${running.name}` : 'Listo para observar el pipeline';
    $('progressFill').style.width = `${state.stages.length ? terminal / state.stages.length * 100 : 0}%`;
    $('progressFill').className = outcome;
    $('elapsedLabel').textContent = replay ? `${replay.paused ? 'Pausa' : outcome === 'pending' ? 'Evidencia real' : 'Reproducción'} · ${durationLabel(replay.elapsed)} de ${durationLabel(replay.duration)} registrados · velocidad ${speedLabel(replay.speed)}` : state.mode === 'demo' ? 'Demostración aislada: evidencia de comandos locales, sin modificar SnackUP.' : state.mode === 'local' ? 'Ejecución local del CI. Revisa los registros de cada comando.' : `${success} etapas aprobadas · consulta periódica del estado real.`;
    for (const option of Array.from($('speedSelect').options || [])) option.textContent = speedLabel(option.value);
    $('flowBadge').textContent = outcome === 'running' ? 'EN CURSO' : outcome === 'success' ? 'APROBADO' : outcome === 'failure' ? 'DETENIDO' : 'CI';
    $('flowBadge').className = `live-dot ${outcome}`;
    const artifact = state.artifacts[0];
    $('artifactName').textContent = artifact?.name || (outcome === 'failure' ? 'Sin artefacto validado' : outcome === 'success' ? 'Consulta los artefactos de la ejecución' : 'Artefacto pendiente');
    $('artifactSummary').textContent = artifact ? 'Artefacto disponible' : outcome === 'failure' ? 'Empaquetado sin completar' : 'Salida de CI · sin despliegue';
    $('artifactNote').textContent = artifact ? 'Paquete identificable en la ejecución de origen.' : 'Validar y empaquetar. El despliegue pertenece a CD.';
    safeLink($('artifactLink'),artifact?.url);
    $('sourceNotes').replaceChildren();
    for (const note of state.source_notes) {const item = document.createElement('li');item.textContent = note;$('sourceNotes').append(item);}
    renderStages();renderDetail();renderDecisions();
  }

  function setState(input) {
    state = normalize(input);
    if (selected >= state.stages.length) selected = Math.max(0,state.stages.length-1);
    if (!manuallySelected) {
      const active = state.stages.findIndex(stage => stage.status === 'running');
      const failed = state.stages.findIndex(stage => stage.status === 'failure');
      selected = active >= 0 ? active : failed >= 0 ? failed : state.status === 'completed' ? Math.max(0,state.stages.length-1) : 0;
    }
    render();
    return clone(state);
  }

  function selectStage(index) {
    if (!state || index < 0 || index >= state.stages.length) return;
    selected = index;manuallySelected = true;render();
  }

  function stop() {
    if (timer) clearInterval(timer);
    timer = null;pollToken += 1;
    if (replay) replay.paused = true;
    $('pauseButton').disabled = true;
    $('pauseButton').textContent = 'Ⅱ';
  }

  async function loadEvidence(which = $('evidenceCase').value) {
    stop();notice('');replay = null;manuallySelected = false;
    $('evidenceCase').value = which;
    const bundled = which === 'failure' ? window.SNACKUP_EVIDENCE_FAILURE : window.SNACKUP_EVIDENCE;
    try {evidence = normalize(await api(`/api/evidence${which === 'failure' ? '?case=failure' : ''}`));}
    catch (error) {if (!bundled) {notice(error.message,true);throw error;}evidence = normalize(bundled);}
    evidence.mode = 'replay';
    setState(evidence);
    return clone(evidence);
  }

  function replayTimeline(source) {
    const starts = source.stages.map(stage => timestamp(stage.started_at)).filter(Number.isFinite);
    const ends = source.stages.map(stage => timestamp(stage.completed_at)).filter(Number.isFinite);
    const start = starts.length ? Math.min(...starts) : Date.now();
    const duration = starts.length && ends.length ? Math.max(1,(Math.max(...ends)-start)/1000) : Math.max(1,source.stages.length*4);
    const timings = source.stages.map((stage,index) => {
      const a = timestamp(stage.started_at), b = timestamp(stage.completed_at);
      return {start:Number.isFinite(a) ? (a-start)/1000 : index*duration/Math.max(1,source.stages.length),end:Number.isFinite(b) ? (b-start)/1000 : (index+1)*duration/Math.max(1,source.stages.length)};
    });
    const failIndex = source.stages.findIndex(stage => stage.status === 'failure');
    const failAt = failIndex >= 0 ? timings[failIndex].end : Infinity;
    return {start,duration,timings,failAt};
  }

  function projectReplay(seconds) {
    if (!replay) return;
    replay.elapsed = Math.max(0,Math.min(seconds,replay.duration));
    const projected = clone(replay.source);
    const final = replay.elapsed >= replay.duration;
    const failed = replay.elapsed >= replay.failAt;
    projected.status = final || failed ? 'completed' : 'running';
    projected.conclusion = final || failed ? replay.source.conclusion : null;
    projected.mode = 'replay';
    projected.stages.forEach((stage,index) => {
      const time = replay.timings[index];
      if (['skipped','blocked','cancelled'].includes(stage.status)) stage.status = final || failed ? stage.status : 'pending';
      else if (replay.elapsed >= time.end) stage.status = stage.status;
      else if (replay.elapsed >= time.start) {stage.status = 'running';stage.completed_at = null;stage.logs = [];}
      else {stage.status = 'pending';stage.completed_at = null;stage.started_at = null;stage.logs = [];}
    });
    if (!final && !failed) {projected.artifacts = [];projected.decisions = [];}
    setState(projected);
    if (final && timer) {clearInterval(timer);timer = null;$('pauseButton').disabled = true;}
    return clone(state);
  }

  function resumeReplay() {
    if (!replay || replay.elapsed >= replay.duration) return;
    replay.paused = false;replay.anchor = performance.now();replay.anchorElapsed = replay.elapsed;
    $('pauseButton').disabled = false;$('pauseButton').textContent = 'Ⅱ';$('pauseButton').title = 'Pausar reproducción';$('pauseButton').setAttribute('aria-label','Pausar reproducción');
    timer = setInterval(() => projectReplay(replay.anchorElapsed + (performance.now()-replay.anchor)/1000*replay.speed),200);
    render();
  }

  async function startReplay(speed = Number($('speedSelect').value) || 3) {
    stop();notice('');manuallySelected = false;
    if (!evidence) await loadEvidence();
    const timeline = replayTimeline(evidence);
    replay = {...timeline,source:clone(evidence),speed:Number(speed) || 3,elapsed:0,paused:true};
    projectReplay(0);resumeReplay();
    return {duration:replay.duration,speed:replay.speed};
  }

  function seekReplay(seconds) {
    if (!replay && evidence) {replay = {...replayTimeline(evidence),source:clone(evidence),speed:Number($('speedSelect').value)||3,elapsed:0,paused:true};}
    if (!replay) return null;
    const wasPlaying = !replay.paused;
    if (timer) {clearInterval(timer);timer = null;}
    projectReplay(Number(seconds) || 0);
    if (wasPlaying && replay.elapsed < replay.duration) resumeReplay();
    return clone(state);
  }

  function pauseReplay() {
    if (!replay) return;
    if (replay.paused) return resumeReplay();
    if (timer) clearInterval(timer);timer = null;replay.paused = true;
    $('pauseButton').textContent = '▶';$('pauseButton').title = 'Continuar reproducción';$('pauseButton').setAttribute('aria-label','Continuar reproducción');render();
  }

  async function monitor(path,initial) {
    stop();replay = null;manuallySelected = false;notice('');
    const token = pollToken;
    if (initial) setState(initial);
    async function tick() {
      try {
        const next = await api(path);
        if (token !== pollToken) return;
        setState(next);
        if (next.status !== 'completed') setTimeout(tick,path.startsWith('/api/run?') ? 15000 : 650);
      } catch (error) {if (token === pollToken) notice(error.message,true);}
    }
    if (!initial || initial.status !== 'completed') tick();
  }

  async function fetchRuns() {
    const repo = $('repoInput').value.trim();
    if (!/^[\w.-]+\/[\w.-]+$/.test(repo)) throw new Error('Escribe el repositorio como propietario/repositorio.');
    $('runsButton').disabled = true;
    try {
      const response = await api(`/api/runs?repo=${encodeURIComponent(repo)}`);
      $('runSelect').replaceChildren();
      for (const run of response.runs || []) {
        const option = document.createElement('option');option.value = run.id;
        option.textContent = `#${run.id} · ${run.head_branch} · ${run.conclusion || run.status} · ${(run.head_sha || '').slice(0,7)}`;
        $('runSelect').append(option);
      }
      notice(response.runs?.length ? `${response.runs.length} ejecuciones encontradas. Elige una y pulsa Monitorear.` : 'No se encontraron ejecuciones de Actions para este repositorio.');
    } finally {$('runsButton').disabled = false;}
  }

  const guarded = fn => async () => {try {await fn();} catch (error) {notice(error.message || String(error),true);}};
  $('replayButton').addEventListener('click',guarded(() => startReplay()));
  $('pauseButton').addEventListener('click',pauseReplay);
  $('evidenceCase').addEventListener('change',guarded(() => loadEvidence()));
  $('speedSelect').addEventListener('change',() => {if (!replay) return;const wasPlaying = !replay.paused;if (timer) clearInterval(timer);timer = null;replay.speed = Number($('speedSelect').value);if (wasPlaying) resumeReplay();else render();});
  $('githubToggle').addEventListener('click',() => {$('githubPanel').hidden = !$('githubPanel').hidden;$('localPanel').hidden = true;});
  $('localToggle').addEventListener('click',() => {$('localPanel').hidden = !$('localPanel').hidden;$('githubPanel').hidden = true;});
  $('runsButton').addEventListener('click',guarded(fetchRuns));
  $('liveButton').addEventListener('click',guarded(async () => {
    const repo = $('repoInput').value.trim(), id = $('runSelect').value;
    if (!id) throw new Error('Busca y selecciona una ejecución antes de iniciar el monitor.');
    await monitor(`/api/run?repo=${encodeURIComponent(repo)}&id=${encodeURIComponent(id)}`);
  }));
  $('demoButton').addEventListener('click',guarded(async () => {
    const initial = await api('/api/demo',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({fail_at:'unit'})});
    await monitor('/api/demo',initial);
  }));
  $('localButton').addEventListener('click',guarded(async () => {
    const repo_path = $('localPath').value.trim();
    if (!repo_path) throw new Error('Indica la carpeta local del proyecto Flutter de SnackUP.');
    const initial = await api('/api/local',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({repo_path})});
    await monitor('/api/local',initial);
  }));

  window.SnackupAgent = {loadEvidence,startReplay,stop,getState:() => state ? clone(state) : null,setState,selectStage,seekReplay,pauseReplay,resumeReplay,getReplayDuration:() => replay?.duration || (evidence ? replayTimeline(evidence).duration : 0)};
  loadEvidence().catch(() => {});
})();
