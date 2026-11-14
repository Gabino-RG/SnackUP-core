// Check the compiled sign-in screens against the running API. No accounts or test data are needed.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { chromium, webkit } = require(process.env.SNACKUP_PLAYWRIGHT || 'playwright');

const origin = process.env.SNACKUP_BROWSER_ORIGIN || 'https://snackup.example.test';
assert.ok(['https://snackup.example.test', 'https://localhost:18443', 'http://localhost:18080'].includes(origin));
const reportPath = process.argv[2] || 'reports/unified/browsers.json';
const staffOrigin = portal => {
  const url = new URL(origin);
  url.hostname = `${portal}.${url.hostname}`;
  return url.origin;
};
const screens = [
  { portal: 'alumnos', origin, path: '/', options: '/api/v1/auth/options', email: 'Correo institucional', submit: 'Iniciar sesión' },
  { portal: 'cocina', origin: staffOrigin('cocina'), path: '/', options: '/api/legacy/v1/auth/options', email: 'Correo electrónico', submit: 'Entrar', heading: 'Acceso a Cocina' },
  { portal: 'administracion', origin: staffOrigin('administracion'), path: '/', options: '/api/legacy/v1/auth/options', email: 'Correo electrónico', submit: 'Entrar', heading: 'Acceso a Administración' },
];

function semanticLine(page, label) {
  // Flutter may merge static text into one multiline aria-label.
  const escaped = label.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  return page.getByText(label, { exact: true })
    .or(page.getByLabel(new RegExp('(?:^|\\n)' + escaped + '(?:\\n|$)'))).first();
}

async function checkScreen(browser, screen, result) {
  const context = await browser.newContext({ locale: 'es-MX', ignoreHTTPSErrors: origin.startsWith('https:') });
  try {
    const page = await context.newPage();
    page.setDefaultTimeout(30000);
    const pageErrors = [];
    page.on('pageerror', error => pageErrors.push(error.name));
    result.phase = 'options';
    const [response] = await Promise.all([
      page.waitForResponse(r => {
        const url = new URL(r.url());
        return url.origin === screen.origin && url.pathname === screen.options && r.request().method() === 'GET';
      }, { timeout: 60000 }),
      page.goto(screen.origin + screen.path, { waitUntil: 'domcontentloaded' }),
    ]);
    result.optionsStatus = response.status();
    assert.equal(result.optionsStatus, 200);
    assert.equal((await response.json()).passwordLogin, true);
    result.phase = 'form';
    await page.locator('flutter-view').waitFor({ state: 'attached' });
    // Flutter's accessibility control enables the same semantic form exposed to assistive technology.
    const email = page.getByRole('textbox', { name: screen.email, exact: true });
    if (!await email.count()) {
      await page.getByRole('button', { name: 'Enable accessibility' }).dispatchEvent('click');
    }
    await email.waitFor();
    if (screen.heading) await semanticLine(page, screen.heading).waitFor();
    await page.getByRole('textbox', { name: 'Contraseña', exact: true }).waitFor();
    result.phase = 'validation';
    await page.getByRole('button', { name: screen.submit, exact: true }).click();
    const errorText = 'Escribe tu contraseña.';
    await page.getByText(errorText).or(page.getByLabel(errorText)).first().waitFor();
    assert.equal(pageErrors.length, 0);
    result.phase = 'complete';
    result.ok = true;
  } finally {
    await context.close();
  }
}

async function main() {
  const results = [];
  for (const [name, engine] of Object.entries({ chromium, webkit })) {
    let browser;
    try {
      browser = await engine.launch();
      for (const screen of screens) {
        const result = { browser: name, version: browser.version(), portal: screen.portal, origin: screen.origin, path: screen.path, ok: false,
          ignoreHTTPSErrors: origin.startsWith('https:') };
        results.push(result);
        try {
          await checkScreen(browser, screen, result);
        } catch (error) {
          result.errorType = error.name;
        }
        console.log(JSON.stringify(result));
      }
    } catch (error) {
      results.push({ browser: name, phase: 'launch', errorType: error.name, ok: false });
    } finally {
      if (browser) await browser.close();
    }
  }
  // Restrict artifacts to known paths, status codes and phases. Never collect cookies, frames or response bodies.
  fs.mkdirSync(path.dirname(reportPath), { recursive: true });
  fs.writeFileSync(reportPath, JSON.stringify(results, null, 2) + '\n');
  if (results.some(result => !result.ok)) process.exitCode = 1;
}
main().catch(error => { console.error(error.name); process.exitCode = 1; });
