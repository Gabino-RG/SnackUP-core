// Real compiled frontend + persistent local REST fixture. CI only.
const fs = require('node:fs');
const path = require('node:path');
const { chromium } = require(process.env.SNACKUP_PLAYWRIGHT || 'playwright');
const output = process.env.SNACKUP_SCREENSHOTS || 'build/review-screenshots';
const productionBuild = process.env.SNACKUP_PRODUCTION_BUILD === '1';
const reviewUrl = process.env.SNACKUP_REVIEW_URL || 'http://localhost:8791/';
// This test creates disposable fixtures. Never point it at a deployed backend.
if (!['localhost', '127.0.0.1', '[::1]'].includes(new URL(reviewUrl).hostname)) {
  throw new Error('Browser fixture test requires a loopback server');
}
fs.mkdirSync(output, { recursive: true });
(async () => {
  const browser = await chromium.launch({headless:true,executablePath:process.env.SNACKUP_CHROMIUM||undefined,args:['--no-sandbox']});
  const context = await browser.newContext({viewport:{width:1440,height:1050}});
  const page = await context.newPage();
  const errors=[];
  const apiFailures=[];
  const traces=[];
  const traceJobs=[];
  function redact(value) {
    if (Array.isArray(value)) return value.map(redact);
    if (value && typeof value === 'object') return Object.fromEntries(Object.entries(value).map(([key,v])=>[key,/^(password|newPassword|accessToken|refreshToken|token)$/i.test(key)?'REDACTED-SECRET':redact(v)]));
    return value;
  }
  page.on('response', response => {
    const url = new URL(response.url());
    if (!url.pathname.startsWith('/api/v1/')) return;
    const req = response.request();
    traceJobs.push((async()=>{
      let body=null, requestBody=null;
      try {body=await response.json();} catch {}
      try {requestBody=req.postDataJSON();} catch {}
      traces.push(redact({method:req.method(),path:url.pathname.slice('/api/v1/'.length)+url.search,status:response.status(),body,requestBody}));
    })());
  });
  page.on('response',r=>{if(r.url().includes('/api/v1/') && r.status()>=400 && !r.url().includes('/auth/refresh'))apiFailures.push(r.status()+' '+new URL(r.url()).pathname);});
  async function typeField(label,value){
    const field=page.getByRole('textbox',{name:label,exact:true});
    await field.click();
    await page.waitForTimeout(100);
    await page.keyboard.press('Control+A');
    await page.keyboard.type(value,{delay:15});
    await page.keyboard.press('Tab');
  }
  function label(text){
    return page.getByText(text,{exact:true}).or(page.getByLabel(text,{exact:true})).first();
  }
  function contents(text){
    // Flutter merges non-interactive card text into one accessibility node.
    return page.getByText(text,{exact:false}).or(page.getByLabel(text,{exact:false})).first();
  }
  page.on('pageerror',e=>errors.push(e.message));
  page.setDefaultTimeout(20000);
  try {
    await page.goto(reviewUrl);
    await page.locator('flutter-view').waitFor({timeout:60000});
    const accessibility=page.locator('flt-semantics-placeholder');
    if(await accessibility.count()) await accessibility.evaluate(node=>node.click());
    async function login(email,password='SnackUP-Prueba-2026'){
      await typeField('Correo electrónico',email);
      await typeField('Contraseña',password);
      await page.getByRole('button',{name:'Entrar',exact:true}).click();
    }
    async function loginLocal() {
      if (productionBuild) {
        if (await page.getByRole('button',{name:'Entrar al local de prueba',exact:true}).count()) throw new Error('Review shortcut leaked into delivery');
        await login('negocio@snackup.test');
      } else {
        await page.getByRole('button',{name:'Entrar al local de prueba',exact:true}).click();
      }
    }
    await page.getByRole('button',{name:'Entrar',exact:true}).waitFor();
    // The review package has one ready local and a separate master account.
    // Fictional history feeds the actual API charts; active orders remain opt-in.
    await page.screenshot({path:path.join(output,'00-acceso-desktop.png')});
    for(const [width,height,name] of [[360,800,'00-acceso-movil.png'],[768,1024,'00-acceso-tablet.png']]) {
      await page.setViewportSize({width,height});
      await page.screenshot({path:path.join(output,name)});
    }
    await page.setViewportSize({width:1440,height:1050});
    await loginLocal();
    await page.getByText(/^Local de prueba\s+Cafetería universitaria$/).waitFor();
    await page.getByRole('switch',{name:'Recibir pedidos',exact:true}).waitFor();
    if(await page.getByRole('button',{name:'Gestionar locales y cuentas',exact:true}).count()) throw new Error('Ready local must not access administration');
    await page.screenshot({path:path.join(output,'00-local-listo-sin-configurar.png')});
    const salesResponse=page.waitForResponse(r=>new URL(r.url()).pathname.endsWith('/review-local/stats')&&r.status()===200);
    await page.getByRole('button',{name:/Resumen/}).click();
    const sales=await (await salesResponse).json();
    if(sales.totalSold<=0||sales.completed<=0||sales.cancelled<=0) throw new Error('Demo sales and cancellations must be populated');
    await label('Resumen de ventas').waitFor();
    await contents('$'+sales.totalSold.toFixed(2)+'\nVentas entregadas').waitFor();
    await page.screenshot({path:path.join(output,'00-resumen-con-datos.png')});
    const historyResponse=page.waitForResponse(r=>new URL(r.url()).pathname.endsWith('/review-local/orders/history')&&r.status()===200);
    await page.getByRole('button',{name:/Historial/}).click();
    const history=await (await historyResponse).json();
    if(!history.data.length||history.summary.completed<=0) throw new Error('Today must have example history');
    await label('Historial de pedidos').waitFor();
    await page.getByText(/Cliente de ejemplo/).or(page.getByLabel(/Cliente de ejemplo/)).first().waitFor();
    await page.screenshot({path:path.join(output,'00-historial-con-datos.png')});
    await page.getByRole('button',{name:'Cerrar sesión',exact:true}).click();
    await page.getByRole('button',{name:'Crea tu cuenta',exact:true}).click();
    await typeField('Nombre completo','Operador solicitado UI');
    await typeField('Correo electrónico','solicitado-ui@snackup.test');
    await typeField('Local o área y motivo de acceso','Operaré el local creado por el equipo.');
    await typeField('Contraseña','Clave-Solicitada-123');
    await typeField('Confirmar contraseña','Clave-Solicitada-123');
    await page.getByRole('button',{name:'Solicitar acceso',exact:true}).click();
    await page.getByRole('button',{name:'Volver al acceso',exact:true}).click();
    await login('solicitado-ui@snackup.test','Clave-Solicitada-123');
    await page.getByText(/Tu solicitud está pendiente de autorización por la cuenta maestra/).or(page.getByLabel(/Tu solicitud está pendiente de autorización por la cuenta maestra/)).first().waitFor();
    await page.screenshot({path:path.join(output,'01-solicitud-pendiente.png')});
    const reviewsResponse=page.waitForResponse(r=>new URL(r.url()).pathname.endsWith('/admin/reviews')&&r.status()===200);
    await login('admin@snackup.test');
    const reviews=(await (await reviewsResponse).json()).data;
    await page.getByRole('button',{name:'Gestionar locales y cuentas',exact:true}).waitFor();
    if(await page.getByRole('button',{name:'Entrar al panel del local',exact:true}).count()) throw new Error('Master must not enter the business panel');
    if(await page.getByRole('switch',{name:'Recibir pedidos',exact:true}).count()) throw new Error('Kitchen controls leaked into administration');
    await label('Local de prueba').waitFor();
    await contents('Promedio de '+reviews.length+' valoraciones').waitFor();
    await page.screenshot({path:path.join(output,'02-maestro-separado.png')});
    const negatives=reviews.filter(r=>r.rating<=2);
    await label('Solo 1–2 estrellas').click();
    await contents('Promedio de '+negatives.length+' valoraciones').waitFor();
    await label('Limpiar filtros').click();
    await page.getByRole('button',{name:/Carrera: Todas las carreras/}).click();
    await page.getByText('Desarrollo de Software',{exact:true}).or(page.getByLabel('Desarrollo de Software',{exact:true})).last().click();
    const software=reviews.filter(r=>r.career==='Desarrollo de Software');
    await contents('Promedio de '+software.length+' valoraciones').waitFor();
    await page.getByRole('button',{name:/Grupo: Todos los grupos/}).click();
    await label('DSM-1').click();
    await contents('Promedio de '+software.filter(r=>r.group==='DSM-1').length+' valoraciones').waitFor();
    await label('Limpiar filtros').click();
    await page.getByRole('button',{name:/Últimos 30 días/}).or(label('Últimos 30 días')).first().click();
    await page.getByText('Últimos 7 días',{exact:true}).or(page.getByLabel('Últimos 7 días',{exact:true})).last().click();
    await contents('Promedio de 21 valoraciones').waitFor();
    await label('Limpiar filtros').click();
    await page.mouse.move(1120,830);
    await page.mouse.wheel(0,750);
    await contents('Evolución de la experiencia').waitFor();
    await page.screenshot({path:path.join(output,'02-graficas-con-datos.png')});
    await page.mouse.wheel(0,-1800);
    await page.getByRole('button',{name:'Gestionar locales y cuentas',exact:true}).click();
    await page.getByRole('button',{name:'Agregar local',exact:true}).click();
    await typeField('Nombre del local','Local del equipo');
    await typeField('Categoría','Cafetería');
    await page.getByRole('button',{name:'Guardar',exact:true}).click();
    await page.getByRole('button',{name:'Editar Local del equipo',exact:true}).waitFor();
    if(await page.getByRole('button',{name:'Entrar a Local del equipo',exact:true}).count()) throw new Error('Business management must not open kitchen');
    await page.reload();
    await page.locator('flutter-view').waitFor();
    const enableAgain=page.locator('flt-semantics-placeholder');
    if(await enableAgain.count())await enableAgain.evaluate(n=>n.click());
    await page.getByRole('button',{name:'Solicitudes de acceso',exact:true}).click();
    await page.getByRole('button',{name:'Revisar Operador solicitado UI',exact:true}).click();
    await page.getByRole('button',{name:/Sin local/}).or(page.getByRole('combobox',{name:/Local asignado/})).or(label('Sin local')).first().click();
    await page.getByText('Local del equipo',{exact:true}).or(page.getByLabel('Local del equipo',{exact:true})).last().click();
    await page.getByRole('button',{name:/Pendiente de verificar/}).or(label('Pendiente de verificar')).first().click();
    await page.getByText('Sí, verifiqué su identidad',{exact:true}).or(page.getByLabel('Sí, verifiqué su identidad',{exact:true})).last().click();
    await page.screenshot({path:path.join(output,'03-autorizacion-maestra.png')});
    await page.getByRole('button',{name:'Guardar',exact:true}).click();
    await label('No hay solicitudes pendientes.').waitFor();
    await page.reload();
    await page.locator('flutter-view').waitFor();
    const enableThird=page.locator('flt-semantics-placeholder');
    if(await enableThird.count())await enableThird.evaluate(n=>n.click());
    await page.getByRole('button',{name:'Cerrar sesión',exact:true}).click();
    await login('solicitado-ui@snackup.test','Clave-Solicitada-123');
    await page.getByText(/^Local del equipo\s+Cafetería universitaria$/).waitFor();
    for(const name of ['Volver a Administración','Gestionar locales y cuentas','Crear cuenta','Solicitudes de acceso']) {
      if(await page.getByRole('button',{name,exact:true}).count()) throw new Error('Administrative control leaked into business panel: '+name);
    }
    // Exercise the actual ready-to-use login through the complete local workflow.
    await page.getByRole('button',{name:'Cerrar sesión',exact:true}).click();
    await loginLocal();
    await page.getByText(/^Local de prueba\s+Cafetería universitaria$/).waitFor();
    await page.getByRole('button',{name:/Productos/}).click();
    await page.getByRole('button',{name:'Agregar',exact:true}).click();
    await typeField('Nombre del producto','Producto creado por el equipo');
    await typeField('Categoría','Comida');
    await typeField('Precio (MXN)','49.50');
    await page.getByRole('button',{name:'Guardar producto',exact:true}).click();
    await page.getByRole('switch',{name:/Producto creado por el equipo/}).waitFor();
    await page.getByRole('button',{name:'Cambiar precio de Producto creado por el equipo',exact:true}).click();
    await typeField('Nuevo precio (MXN)','54.00');
    await page.getByRole('button',{name:'Guardar precio',exact:true}).click();
    await page.getByRole('switch',{name:/Producto creado por el equipo.*\$54\.00/s}).waitFor();
    await page.getByRole('button',{name:/Cocina/}).click();
    await page.getByRole('switch',{name:'Recibir pedidos',exact:true}).click();
    await page.getByRole('button',{name:'Confirmar',exact:true}).click();
    await label('Recibiendo pedidos').waitFor();
    let ticket;
    if (productionBuild) {
      if (await page.getByRole('button',{name:'Recibir pedido de prueba',exact:true}).count()) throw new Error('Review order generator leaked into delivery');
      // Fixture setup is outside the compiled frontend and uses its own session.
      const loginResponse=await fetch(new URL('/api/v1/auth/login',reviewUrl),{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({email:'negocio@snackup.test',password:'SnackUP-Prueba-2026'})});
      if (!loginResponse.ok) throw new Error('Fixture login failed');
      const token=(await loginResponse.json()).tokens.accessToken;
      const headers={'Content-Type':'application/json','Authorization':'Bearer '+token};
      const me=await fetch(new URL('/api/v1/users/me',reviewUrl),{headers});
      if (!me.ok) throw new Error('Fixture profile failed');
      const businessId=(await me.json()).businessId;
      const response=await fetch(new URL('/api/v1/review/orders',reviewUrl),{method:'POST',headers,body:JSON.stringify({businessId})});
      if (!response.ok) throw new Error('Fixture order creation failed');
      ticket=await response.json();
    } else {
      const ticketResponse=page.waitForResponse(r=>r.url().endsWith('/api/v1/review/orders')&&r.request().method()==='POST');
      await page.getByRole('button',{name:'Recibir pedido de prueba',exact:true}).click();
      ticket=await (await ticketResponse).json();
      await page.getByRole('button',{name:'Ir a cocina',exact:true}).click();
    }
    await page.getByRole('button',{name:'Aceptar pedido',exact:true}).waitFor();
    await page.screenshot({path:path.join(output,'04-cocina-desktop.png')});
    await page.getByRole('button',{name:'Aceptar pedido',exact:true}).click();
    await page.setViewportSize({width:768,height:1024});
    await label('Preparando (1)').click();
    await page.getByRole('button',{name:'Iniciar preparación',exact:true}).waitFor();
    await page.screenshot({path:path.join(output,'05-cocina-tablet.png')});
    await page.getByRole('button',{name:'Iniciar preparación',exact:true}).click();
    await page.getByRole('button',{name:'Marcar listo',exact:true}).click();
    await page.setViewportSize({width:360,height:800});
    await label('Listos (1)').click();
    await page.getByRole('button',{name:'Verificar entrega',exact:true}).waitFor();
    await page.screenshot({path:path.join(output,'06-cocina-movil.png')});
    await page.getByRole('button',{name:'Verificar entrega',exact:true}).click();
    await typeField('Código del cliente',ticket.pickupCode);
    await page.getByRole('button',{name:'Confirmar entrega',exact:true}).click();
    await label('Listos (0)').waitFor();
    if(errors.length) throw new Error('Browser errors: '+errors.join('\n'));
    await Promise.all(traceJobs);
    fs.writeFileSync(path.join(output,'contract-trace.json'),JSON.stringify(traces,null,2));
    fs.writeFileSync(path.join(output,'result.json'),JSON.stringify({passed:true,productionFrontend:productionBuild,productionBackend:false,demo:{reviews:reviews.length,sales,history:history.summary},flows:['local login before administration','populated sales and history through API','charts filtered by rating, career, group and period','master restricted to administration','local access request','pending denied login','master approval','business created by user','operator restricted to business panel','catalog create','price edit','explicit accept','prepare','ready','verified delivery','mobile 360','tablet 768','desktop 1440'],errors},null,2));
    console.log('Integrated browser review passed');
  } catch(error) {
    await page.screenshot({path:path.join(output,'failure.png')}).catch(()=>{});
    fs.writeFileSync(path.join(output,'failure.txt'),String(error)+'\nAPI: '+apiFailures.join(', ')+'\n'+await page.locator('body').innerText()+'\nSEMANTICS: '+await page.locator('[role]').evaluateAll(nodes=>JSON.stringify(nodes.map(n=>({role:n.getAttribute('role'),label:n.getAttribute('aria-label'),text:n.textContent})),null,2)));
    console.error(error.message);
    process.exitCode=1;
  } finally { await browser.close(); }
})();
