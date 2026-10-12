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
  page.on('pageerror',e=>errors.push(e.message));
  page.setDefaultTimeout(20000);
  try {
    await page.goto('http://localhost:8791/');
    await page.locator('flutter-view').waitFor({timeout:60000});
    const accessibility=page.locator('flt-semantics-placeholder');
    if(await accessibility.count()) await accessibility.evaluate(node=>node.click());
    async function login(email){
      await typeField('Correo electrónico',email);
      await typeField('Contraseña','SnackUP-Prueba-2026');
      await page.getByRole('button',{name:'Entrar',exact:true}).click();
    }
    await login('negocio@snackup.test');
    await page.getByText('Cafetería Central',{exact:true}).first().waitFor();
    await page.getByRole('button',{name:'Aceptar pedido',exact:true}).first().waitFor();
    await page.screenshot({path:path.join(output,'01-cocina-desktop.png')});
    await page.getByRole('button',{name:'Recibir pedido de prueba',exact:true}).click();
    await page.getByText(/Pedido de prueba #/).waitFor();
    await page.screenshot({path:path.join(output,'02-comprobante-prueba.png')});
    await page.getByRole('button',{name:'Ir a cocina',exact:true}).click();
    await page.getByText(/^Productos Tab/).first().click();
    await page.getByRole('button',{name:'Agregar',exact:true}).click();
    await typeField('Nombre del producto','Producto de revisión UI');
    await typeField('Categoría','Comida');
    await typeField('Precio (MXN)','49.50');
    await page.getByRole('button',{name:'Guardar producto',exact:true}).click();
    await typeField('Buscar por nombre o categoría','Producto de revisión UI');
    await page.getByText('Producto de revisión UI',{exact:true}).waitFor();
    await page.getByRole('button',{name:'Cambiar precio de Producto de revisión UI',exact:true}).click();
    await typeField('Nuevo precio (MXN)','54.00');
    await page.getByRole('button',{name:'Guardar precio',exact:true}).click();
    await page.getByText('$54.00',{exact:true}).waitFor();
    await page.screenshot({path:path.join(output,'03-productos-desktop.png')});
    await page.setViewportSize({width:390,height:844});
    await page.getByText(/Cocina Tab/).first().click();
    await page.getByText('Nuevos (3)',{exact:true}).waitFor();
    await page.screenshot({path:path.join(output,'04-cocina-movil.png')});
    await page.getByRole('button',{name:'Cerrar sesión',exact:true}).click();
    await login('admin@snackup.test');
    await page.getByText('Gestionar locales y cuentas',{exact:true}).waitFor();
    await page.setViewportSize({width:1440,height:1050});
    await page.screenshot({path:path.join(output,'05-administracion-desktop.png')});
    await page.getByRole('button',{name:'Gestionar locales y cuentas',exact:true}).click();
    await page.getByRole('button',{name:'Agregar local',exact:true}).click();
    await typeField('Nombre del local','Local de revisión UI');
    await typeField('Categoría','Cafetería');
    await page.getByRole('button',{name:'Guardar',exact:true}).click();
    await page.getByText('Local de revisión UI',{exact:true}).waitFor();
    await page.screenshot({path:path.join(output,'06-gestion-locales.png')});
    await page.getByText('Cuentas',{exact:true}).click();
    await page.getByRole('button',{name:'Crear cuenta',exact:true}).click();
    await typeField('Nombre','Operador de revisión UI');
    await typeField('Correo electrónico','operador-ui@snackup.test');
    await typeField('Contraseña inicial','Clave-Prueba-123');
    await page.getByText('Sin local',{exact:true}).click();
    await page.getByText('Local de revisión UI',{exact:true}).last().click();
    await page.getByRole('button',{name:'Guardar',exact:true}).click();
    await page.getByText('Operador de revisión UI',{exact:true}).waitFor();
    await page.setViewportSize({width:390,height:844});
    await page.screenshot({path:path.join(output,'07-cuentas-movil.png')});
    if(errors.length) throw new Error('Browser errors: '+errors.join('\n'));
    fs.writeFileSync(path.join(output,'result.json'),JSON.stringify({passed:true,flows:['login','kitchen','review order','catalog create','price edit','mobile kitchen','admin login','business create','account create'],errors},null,2));
    console.log('Integrated browser review passed');
  } catch(error) {
    await page.screenshot({path:path.join(output,'failure.png')}).catch(()=>{});
    fs.writeFileSync(path.join(output,'failure.txt'),String(error)+'\nAPI: '+apiFailures.join(', ')+'\n'+await page.locator('body').innerText()+'\nSEMANTICS: '+await page.locator('[role]').evaluateAll(nodes=>nodes.map(n=>n.getAttribute('role')+':'+n.getAttribute('aria-label')).join('\n')));
    console.error(error.message);
    process.exitCode=1;
  } finally { await browser.close(); }
})();
