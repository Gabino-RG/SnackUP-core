// Compiled portal, actual FastAPI and disposable SQL state from live_backend.py.
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const { randomUUID } = require('node:crypto');
const engine = process.env.SNACKUP_BROWSER || 'chromium';
if (!['chromium', 'webkit'].includes(engine)) throw Error('Unsupported test browser');
const browserType = require(process.env.SNACKUP_PLAYWRIGHT || 'playwright')[engine];
const origin = process.env.SNACKUP_LIVE_ORIGIN;
const password = process.env.SNACKUP_LIVE_PASSWORD;
if (!origin || new URL(origin).hostname !== '127.0.0.1' || !password) throw Error('Run live_backend.py');
const output = 'build/live-backend';
fs.mkdirSync(output, {recursive: true});
for (const name of ['failure.txt', 'failure.png', 'browser-result.json']) {
  const previous = path.join(output, name);
  if (fs.existsSync(previous)) fs.unlinkSync(previous);
}
(async () => {
  const browser = await browserType.launch({headless: true, executablePath: engine === 'chromium' ? process.env.SNACKUP_CHROMIUM || undefined : undefined});
  const context = await browser.newContext({viewport: {width: 1440, height: 1050}});
  const page = await context.newPage();
  const studentContext = await browser.newContext();
  const errors = [], failures = [];
  const frames = [];
  page.on('websocket', socket => socket.on('framereceived', event => {
    try { frames.push(JSON.parse(event.payload)); } catch {}
  }));
  async function waitFrame(predicate) {
    const deadline = Date.now() + 15000;
    while (!frames.some(predicate)) {
      if (Date.now() > deadline) throw Error('Expected real-time notification was not received');
      await page.waitForTimeout(50);
    }
  }
  page.on('pageerror', e => {
    const detail = `${e.name}: ${e.message}\n${e.stack || '(no stack)'}`;
    errors.push(detail);
    console.error('Browser exception:', detail);
  });
  await page.addInitScript(() => {
    window.addEventListener('error', e => console.error('Window error detail',
      e.message, e.filename, e.lineno, e.colno, String(e.error), e.error?.stack));
    window.addEventListener('unhandledrejection', e => console.error('Unhandled rejection detail',
      String(e.reason), e.reason?.name, e.reason?.message, e.reason?.stack));
  });
  page.on('console', e => {
    if (e.type() === 'error') console.error('Browser console:', e.text());
  });
  page.on('response', r => {
    const p = new URL(r.url()).pathname;
    if (p.startsWith('/api/') && r.status() >= 400 && !(p.endsWith('/auth/refresh') && r.status() === 401)) {
      failures.push(`${r.status()} ${p}`);
    }
  });
  page.setDefaultTimeout(30000);
  async function enableSemantics() {
    await page.locator('flutter-view').waitFor({timeout: 60000});
    const placeholder = page.locator('flt-semantics-placeholder');
    if (await placeholder.count()) await placeholder.evaluate(node => node.click());
  }
  async function field(label, value) {
    await page.getByRole('textbox', {name: label, exact: true}).click();
    // Flutter activates its DOM text editor on the following frame.
    await page.waitForTimeout(100);
    await page.keyboard.press('Control+A');
    await page.keyboard.type(value, {delay: 15});
    await page.keyboard.press('Tab');
  }
  async function login(user) {
    await field('Correo electrónico', `${user}@staff.example.edu`);
    await field('Contraseña', password);
    await page.getByRole('button', {name: 'Entrar', exact: true}).click();
  }
  const text = value => page.getByText(value, {exact: false}).or(page.getByLabel(value, {exact: false})).first();
  try {
    await page.goto(origin + '/paneles/');
    await enableSemantics();
    await login('operator');
    await page.getByRole('switch', {name: 'Recibir pedidos', exact: true}).waitFor();
    assert.equal(await page.getByRole('button', {name: 'Gestionar locales y cuentas', exact: true}).count(), 0);
    await page.screenshot({path: path.join(output, 'cocina.png')});
    // Real browser refresh cookie must restore the Kitchen session on reload.
    await page.reload();
    await enableSemantics();
    await page.getByRole('switch', {name: 'Recibir pedidos', exact: true}).waitFor();
    await waitFrame(f => f.type === 'subscribed');
    const open = page.waitForResponse(r => r.url().endsWith('/business-1/status') && r.status() === 200);
    await page.getByRole('switch', {name: 'Recibir pedidos', exact: true}).click();
    await page.getByRole('button', {name: 'Confirmar', exact: true}).click();
    await open;
    const signedIn = await studentContext.request.post(origin + '/api/legacy/v1/auth/login', {
      headers: {Origin: origin}, data: {email: 'student@students.example.edu', password}
    });
    assert.equal(signedIn.status(), 200);
    const studentToken = (await signedIn.json()).tokens.accessToken;
    const purchase = await studentContext.request.post(origin + '/api/v1/orders', {
      headers: {Origin: origin, Authorization: 'Bearer ' + studentToken, 'Idempotency-Key': randomUUID()},
      data: {businessId: 'business-1', items: [{productId: 'product-1', quantity: 1}], paymentMethod: 'Efectivo', expectedTotal: 35.5}
    });
    assert.equal(purchase.status(), 201);
    const order = await purchase.json();
    await waitFrame(f => f.type === 'order.created' && f.data?.id === order.id);
    await page.getByRole('button', {name: 'Aceptar pedido', exact: true}).waitFor();
    await page.getByRole('button', {name: 'Aceptar pedido', exact: true}).click();
    await page.getByRole('button', {name: 'Iniciar preparación', exact: true}).waitFor();
    await page.screenshot({path: path.join(output, 'pedido-en-vivo.png')});
    await page.setViewportSize({width:390,height:844});
    await text('Preparando (1)').click();
    await page.screenshot({path: path.join(output, 'cocina-v32-movil.png')});
    const opened = page.waitForResponse(r => r.url().endsWith('/business-1/chats') && r.request().method() === 'POST' && r.status() === 200);
    await page.getByRole('button', {name: 'Chat del pedido', exact: true}).first().click();
    const chat = await (await opened).json();
    await field('Mensaje al alumno', 'Mensaje de Cocina desde navegador');
    const sent = page.waitForResponse(r => r.url().endsWith(`/chats/${chat.id}/messages`) && r.status() === 201);
    await page.getByRole('button', {name: 'Enviar mensaje', exact: true}).click();
    await sent;
    await page.screenshot({path: path.join(output, 'chat-v32-movil.png')});
    await page.getByRole('button', {name: /Back|Atrás|Volver/}).first().click();
    await page.setViewportSize({width:1440,height:1050});
    const reply = await studentContext.request.post(origin + `/api/v1/chats/${chat.id}/messages`, {
      headers: {Origin: origin, Authorization: 'Bearer ' + studentToken}, data: {text: 'Respuesta de prueba del alumno'}
    });
    assert.equal(reply.status(), 201);
    await page.getByRole('button', {name: 'Actividad en chats: revisar conversaciones', exact: true}).click();
    await text('Pedido ' + chat.orderId).click();
    await text('Respuesta de prueba del alumno').waitFor();
    await page.screenshot({path: path.join(output, 'chat-v32.png')});
    await page.getByRole('button', {name: 'Cerrar y borrar', exact: true}).click();
    await page.getByRole('button', {name: 'Confirmar', exact: true}).click();
    await text('No hay conversaciones activas.').waitFor();
    assert.equal(await page.getByText('Respuesta de prueba del alumno', {exact:true}).count(), 0);
    await page.getByRole('button', {name: /Back|Atrás|Volver/}).first().click();
    await text('Operación').click();
    await text('Horarios').click();
    await page.getByRole('textbox', {name: 'Hora de cierre (HH:mm)', exact: true}).waitFor();
    await field('Hora de cierre (HH:mm)', '23:50');
    const closing = page.waitForResponse(r => r.url().endsWith('/business-1/closing-schedule') && r.status() === 200);
    await page.getByRole('button', {name: 'Guardar horario', exact: true}).click();
    await closing;
    await text('Configuración guardada.').waitFor();
    await page.screenshot({path: path.join(output, 'horarios-v32.png')});
    await text('Estadísticas').click();
    await text('Productos más vendidos').waitFor();
    await page.screenshot({path: path.join(output, 'estadisticas-v32.png')});
    await page.getByRole('button', {name: /Historial/}).click();
    await text('Historial de pedidos').waitFor();
    await text('student').waitFor();
    await page.screenshot({path: path.join(output, 'historial.png')});
    await page.getByRole('button', {name: 'Cerrar sesión', exact: true}).click();
    await login('master');
    await page.getByRole('button', {name: 'Gestionar locales y cuentas', exact: true}).waitFor();
    await text('Opinión sintética para integración').waitFor();
    await page.screenshot({path: path.join(output, 'administracion.png')});
    await page.setViewportSize({width: 390, height: 844});
    await page.screenshot({path: path.join(output, 'administracion-movil.png')});
    await page.setViewportSize({width:1440,height:1050});
    await page.getByRole('button', {name:'Gestionar locales y cuentas',exact:true}).click();
    await page.getByRole('button', {name:'Consultar horario de Cafetería 1',exact:true}).click();
    await text('Horario del local · Consulta').waitFor();
    assert.equal(await page.getByRole('button', {name:'Guardar horario',exact:true}).count(), 0);
    await page.screenshot({path: path.join(output, 'horario-admin-v32.png')});
    await page.setViewportSize({width:390,height:844});
    await page.screenshot({path: path.join(output, 'horario-admin-v32-movil.png')});
    assert.deepEqual(errors, []);
    assert.deepEqual(failures, []);
    fs.writeFileSync(path.join(output, 'browser-result.json'), JSON.stringify({passed: true, engine, browserVersion: browser.version(),
      checks: ['Kitchen login', 'role isolation', 'HTTP-only cookie reload', 'WebSocket order.created and Kitchen accept', 'SQL order history',
        'chat send/reply/delete and activity outside chat', 'closing schedule', 'detailed statistics', 'read-only administrative schedule',
        'logout and admin login', 'zero-star review visible', 'desktop and mobile screenshots'], errors, failures}, null, 2));
    console.log('Real-backend browser smoke passed. Screenshots: ' + output);
  } catch (error) {
    await page.screenshot({path: path.join(output, 'failure.png')}).catch(() => {});
    fs.writeFileSync(path.join(output, 'failure.txt'), `${error.stack}\n${errors.join('\n')}\n${failures.join('\n')}`);
    throw error;
  } finally { await browser.close(); }
})().catch(error => {console.error(error); process.exitCode = 1;});
