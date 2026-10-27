// Fault injection only against live_backend.py's disposable loopback database.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const engine = process.env.SNACKUP_BROWSER || 'chromium';
if (!['chromium', 'webkit'].includes(engine)) throw Error('Unsupported test browser');
const browserType = require(process.env.SNACKUP_PLAYWRIGHT || 'playwright')[engine];
const origin = process.env.SNACKUP_LIVE_ORIGIN;
const password = process.env.SNACKUP_LIVE_PASSWORD;
const fixtures = JSON.parse(process.env.SNACKUP_RESILIENCE_FIXTURES || '{}');
if (!origin || new URL(origin).hostname !== '127.0.0.1' || !fixtures.readyId) throw Error('Use disposable runner');
(async () => {
  const browser = await browserType.launch({headless: true});
  const context = await browser.newContext({viewport: {width:1440,height:1050}});
  const page = await context.newPage();
  page.setDefaultTimeout(30000);
  const checks = [], errors = [];
  page.on('pageerror', e => errors.push(e.message));
  const text = s => page.getByText(s,{exact:false}).or(page.getByLabel(s,{exact:false})).first();
  async function field(label, value) {
    await page.getByRole('textbox',{name:label,exact:true}).click();
    await page.waitForTimeout(100);
    await page.keyboard.press('Control+A');
    await page.keyboard.type(value,{delay:10});
    await page.keyboard.press('Tab');
  }
  async function until(fn) {
    const deadline=Date.now()+30000;
    while (!await fn()) {
      if(Date.now()>deadline) throw Error('Condition did not recover');
      await page.waitForTimeout(100);
    }
  }
  try {
    await page.goto(origin+'/paneles/');
    await page.locator('flutter-view').waitFor();
    const placeholder=page.locator('flt-semantics-placeholder');
    if(await placeholder.count()) await placeholder.evaluate(n=>n.click());
    await field('Correo electrónico','resilience@staff.example.edu');
    await field('Contraseña',password);
    await page.getByRole('button',{name:'Entrar',exact:true}).click();
    const accept=page.getByRole('button',{name:'Aceptar pedido',exact:true});
    await accept.waitFor();
    await context.setOffline(true);
    await page.getByRole('button',{name:'Actualizar tablero',exact:true}).click();
    await text('Los datos visibles pueden estar desactualizados.').waitFor();
    assert.equal(await accept.isDisabled(),true);
    await context.setOffline(false);
    await page.getByRole('button',{name:'Actualizar tablero',exact:true}).click();
    await until(async()=>await accept.isEnabled());
    checks.push('offline reads retain board, disable mutations and recover');

    let accepts=0;
    await page.route(`**/api/legacy/v1/orders/${fixtures.pendingId}/accept`, async route => {
      accepts++;
      const response=await route.fetch();
      assert.equal(response.status(),200);
      await route.abort('failed'); // Server committed, client did not receive it.
    });
    await accept.click();
    await until(async()=>await accept.count()===0);
    assert.equal(accepts,1);
    checks.push('lost accept response: board reconciles without replay');

    let deliveries=0;
    await page.route(`**/api/legacy/v1/orders/${fixtures.readyId}/complete`,async route=>{
      deliveries++;
      const response=await route.fetch();
      assert.equal(response.status(),200);
      await context.setOffline(true); // Reconciliation also fails.
      await route.abort('failed');
    });
    await page.getByRole('button',{name:'Verificar entrega',exact:true}).click();
    await field('Código del cliente',fixtures.readyCode);
    const confirm=page.getByRole('button',{name:'Confirmar entrega',exact:true});
    await confirm.click();
    await text('Revisa tu conexión.').waitFor();
    assert.equal(await confirm.isDisabled(),true,'Uncertain delivery must require closing and reloading, not another send');
    await context.setOffline(false);
    await page.getByRole('button',{name:'Volver y comprobar el pedido',exact:true}).click();
    await page.getByRole('button',{name:'Actualizar tablero',exact:true}).click();
    await until(async()=>await page.getByRole('button',{name:'Verificar entrega',exact:true}).count()===0);
    assert.equal(deliveries,1);
    checks.push('lost delivery response plus offline reconciliation: no second delivery');
    const adminContext = await browser.newContext();
    const signed = await adminContext.request.post(origin+'/api/legacy/v1/auth/login', {
      headers:{Origin:origin},data:{email:'master@staff.example.edu',password}
    });
    assert.equal(signed.status(),200);
    const adminToken=(await signed.json()).tokens.accessToken;
    const headers={Origin:origin,Authorization:'Bearer '+adminToken};
    const listed=await adminContext.request.get(origin+'/api/legacy/v1/admin/users?q=resilience',{headers});
    assert.equal(listed.status(),200);
    const user=(await listed.json()).data.find(u=>u.id==='resilience-operator');
    assert.ok(user);
    const revoked=await adminContext.request.patch(origin+'/api/legacy/v1/admin/users/'+user.id,{
      headers,data:{expectedVersion:user.version,displayName:user.displayName,email:user.email,
        role:user.role,businessId:user.businessId,isActive:false}
    });
    assert.equal(revoked.status(),200);
    await page.getByRole('button',{name:'Actualizar tablero',exact:true}).click();
    await page.getByRole('button',{name:'Entrar',exact:true}).waitFor();
    assert.equal(await page.getByRole('button',{name:'Iniciar preparación',exact:true}).count(),0);
    checks.push('administrative revocation removes the open Kitchen session and protected controls');
    await page.screenshot({path:'build/live-backend/resilience-recovered.png'});
    assert.deepEqual(errors,[]);
    fs.writeFileSync('build/live-backend/resilience-browser.json',JSON.stringify({passed:true,engine,checks,errors},null,2));
    console.log('Resilience browser passed');
  } catch(e) {
    await page.screenshot({path:'build/live-backend/resilience-failure.png'}).catch(()=>{});
    fs.writeFileSync('build/live-backend/resilience-failure.txt',String(e.stack));
    throw e;
  } finally {await browser.close();}
})().catch(e=>{console.error(e);process.exitCode=1;});
