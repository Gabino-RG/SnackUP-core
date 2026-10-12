// Real compiled frontend + persistent local REST fixture. CI only.
const fs = require('node:fs');
const path = require('node:path');
const { chromium } = require(process.env.SNACKUP_PLAYWRIGHT || 'playwright');
const output = process.env.SNACKUP_SCREENSHOTS || 'build/review-screenshots';
fs.mkdirSync(output, { recursive: true });
(async () => {
  const browser = await chromium.launch({headless:true,args:['--no-sandbox']});
  const context = await browser.newContext({viewport:{width:1440,height:1050}});
  const page = await context.newPage();
  const errors=[];
  const apiFailures=[];
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
  page.on('pageerror',e=>errors.push(e.message));
  page.setDefaultTimeout(20000);
  try {
    await page.goto('http://localhost:8791/');
    await page.locator('flutter-view').waitFor({timeout:60000});
    const accessibility=page.locator('flt-semantics-placeholder');
    if(await accessibility.count()) await accessibility.evaluate(node=>node.click());
    async function login(email,password='SnackUP-Prueba-2026'){
      await typeField('Correo electrónico',email);
      await typeField('Contraseña',password);
      await page.getByRole('button',{name:'Entrar',exact:true}).click();
    }
    // A fresh install contains only the master. All operational records below
    // are created by this isolated CI test through the UI, never by the package.
    await page.screenshot({path:path.join(output,'00-acceso-desktop.png')});
    for(const [width,height,name] of [[360,800,'00-acceso-movil.png'],[768,1024,'00-acceso-tablet.png']]) {
      await page.setViewportSize({width,height});
      await page.screenshot({path:path.join(output,name)});
    }
    await page.setViewportSize({width:1440,height:1050});
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
    await login('admin@snackup.test');
    await page.getByRole('button',{name:'Gestionar locales y cuentas',exact:true}).waitFor();
    await label('Todavía no hay locales registrados.').waitFor();
    await page.screenshot({path:path.join(output,'02-maestro-sin-datos.png')});
    await page.getByRole('button',{name:'Gestionar locales y cuentas',exact:true}).click();
    await page.getByRole('button',{name:'Agregar local',exact:true}).click();
    await typeField('Nombre del local','Local del equipo');
    await typeField('Categoría','Cafetería');
    await page.getByRole('button',{name:'Guardar',exact:true}).click();
    await page.getByRole('button',{name:'Editar Local del equipo',exact:true}).waitFor();
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
    await page.getByRole('switch').click();
    await label('Recibiendo pedidos').waitFor();
    const ticketResponse=page.waitForResponse(r=>r.url().endsWith('/api/v1/review/orders')&&r.request().method()==='POST');
    await page.getByRole('button',{name:'Recibir pedido de prueba',exact:true}).click();
    const ticket=await (await ticketResponse).json();
    await page.getByRole('button',{name:'Ir a cocina',exact:true}).click();
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
    fs.writeFileSync(path.join(output,'result.json'),JSON.stringify({passed:true,flows:['master-only start','local access request','pending denied login','master approval','business created by user','catalog create','price edit','explicit accept','prepare','ready','verified delivery','mobile 360','tablet 768','desktop 1440'],errors},null,2));
    console.log('Integrated browser review passed');
  } catch(error) {
    await page.screenshot({path:path.join(output,'failure.png')}).catch(()=>{});
    fs.writeFileSync(path.join(output,'failure.txt'),String(error)+'\nAPI: '+apiFailures.join(', ')+'\n'+await page.locator('body').innerText()+'\nSEMANTICS: '+await page.locator('[role]').evaluateAll(nodes=>JSON.stringify(nodes.map(n=>({role:n.getAttribute('role'),label:n.getAttribute('aria-label'),text:n.textContent})),null,2)));
    console.error(error.message);
    process.exitCode=1;
  } finally { await browser.close(); }
})();
