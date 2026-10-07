// Actual screenshots of the running graphical agent, replaying verified GitHub timestamps.
const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');
const { chromium } = require('playwright');

async function main() {
  const out = path.resolve(process.env.VIDEO_OUTPUT || 'video-output');
  fs.mkdirSync(out, { recursive: true });
  const frames = path.join(out, 'frames'); fs.mkdirSync(frames, { recursive: true });
  const browser = await chromium.launch({ headless: true, args: ['--no-sandbox'] });
  const page = await browser.newPage({ viewport: { width: 1600, height: 1000 }, deviceScaleFactor: 1 });
  const errors=[]; page.on('pageerror', e=>errors.push(String(e)));
  await page.goto('http://127.0.0.1:8765/', { waitUntil: 'networkidle' });
  await page.waitForFunction(()=>window.SnackupAgent && window.SnackupAgent.getState()?.stages?.length===7);
  await page.evaluate(()=>{
    const caption=document.createElement('div');caption.id='video-caption';
    caption.style.cssText='position:fixed;left:32px;right:32px;bottom:18px;padding:14px 24px;background:#292238;color:#fff;border-radius:14px;font:600 19px/1.5 system-ui;z-index:9999;text-align:center;box-shadow:0 3px 20px #0002;pointer-events:none';
    document.body.append(caption);
  });
  let lastCase='';
  const fps=4, seconds=65;
  for(let frame=0;frame<fps*seconds;frame++){
    const time=frame/fps;
    const which=time<40?'success':'failure';
    if(which!==lastCase){await page.evaluate(async key=>{await window.SnackupAgent.loadEvidence(key);window.SnackupAgent.stop();},which);lastCase=which;}
    const evidence=JSON.parse(fs.readFileSync(path.join(__dirname,'evidence',which==='success'?'evidence.json':'evidence-failure.json'),'utf8'));
    const start=Date.parse(evidence.stages[0].started_at), end=Date.parse(evidence.stages.at(-1).completed_at);
    const duration=(end-start)/1000;
    let elapsed,caption;
    if(time<4){elapsed=0;caption='SnackUP · Agente inteligente basado en reglas | Evidencia real de GitHub Actions';}
    else if(time<34){elapsed=(time-4)/30*duration;caption='Reproducción acelerada: commit → entorno → análisis → pruebas → compilación → artefacto';}
    else if(time<40){elapsed=duration+1;caption='CI aprobado: 59 pruebas y build Web. Los 124 avisos del análisis fueron tolerados.';}
    else if(time<58){elapsed=(time-40)/18*duration;caption='Segundo caso real: el pipeline observa una falla de compilación y omite el artefacto';}
    else {elapsed=duration+1;caption='Fail Fast: corregir el error antes de continuar. CI termina con un artefacto; desplegar pertenece a CD.';}
    await page.evaluate(({elapsed,caption})=>{window.SnackupAgent.seekReplay(elapsed);document.getElementById('video-caption').textContent=caption;},{elapsed,caption});
    if(time>=34&&time<37)await page.evaluate(()=>window.SnackupAgent.selectStage(4));
    if(time>=37&&time<40)await page.evaluate(()=>window.SnackupAgent.selectStage(6));
    if(time>=58)await page.evaluate(()=>window.SnackupAgent.selectStage(5));
    await page.screenshot({path:path.join(frames,String(frame).padStart(5,'0')+'.png')});
  }
  // Screenshots for human layout inspection at key outcomes.
  await page.evaluate(()=>document.getElementById('video-caption').remove());
  await page.screenshot({path:path.join(out,'ci-fallido.png')});
  await page.evaluate(async()=>{await window.SnackupAgent.loadEvidence('success');window.SnackupAgent.stop();window.SnackupAgent.seekReplay(1000);window.SnackupAgent.selectStage(4);});
  await page.screenshot({path:path.join(out,'ci-aprobado.png')});
  await page.setViewportSize({width:390,height:844});
  await page.screenshot({path:path.join(out,'ci-mobile.png'),fullPage:true});
  const overflow=await page.evaluate(()=>document.documentElement.scrollWidth>window.innerWidth);
  if(overflow)throw new Error('Horizontal overflow on mobile');
  if(errors.length)throw new Error('Browser errors: '+errors.join('\n'));
  await browser.close();
  const result=spawnSync('ffmpeg',['-y','-framerate',String(fps),'-i',path.join(frames,'%05d.png'),'-vf','fps=30','-c:v','libx264','-preset','fast','-crf','21','-pix_fmt','yuv420p','-movflags','+faststart',path.join(out,'SnackUP_Pipeline_CI.mp4')],{encoding:'utf8'});
  if(result.status!==0)throw new Error(result.stderr);
  fs.rmSync(frames,{recursive:true,force:true});
  fs.writeFileSync(path.join(out,'verificacion-video.json'),JSON.stringify({duration_seconds:seconds,resolution:'1600x1000',mode:'Reproducción gráfica de dos ejecuciones GitHub reales, acelerada',successful_run:37257224068,failed_run:37257039123,browser_errors:errors,mobile_horizontal_overflow:overflow},null,2));
  console.log('65-second video and QA screenshots produced.');
}
main().catch(e=>{console.error(e);process.exit(1)});
