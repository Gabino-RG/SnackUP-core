// Real, loopback-only browser regression using the existing public demo accounts.
// No route interception, mocks, database writes, seeds, orders or external origins.
// Opt in: ALLOW_LOCAL_PORTAL_CHECK=YES node tools/check_portal_browser_isolation.cjs
// Reports omit passwords, tokens, cookie values, user IDs and response bodies.
'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
assert.equal(process.env.ALLOW_LOCAL_PORTAL_CHECK, 'YES', 'Explicit local check opt-in required');
const { chromium, webkit } = require(process.env.SNACKUP_PLAYWRIGHT || 'playwright');

const portals = [
  { key: 'kitchen', audience: 'cocina', origin: 'http://cocina.localhost:18080',
    heading: 'Acceso a Cocina', account: 'operator@staff.example.edu', role: 'business',
    marker: 'Actualizar tablero', mismatch: 'Este acceso es exclusivo para las cuentas de Cocina.' },
  { key: 'administration', audience: 'administracion', origin: 'http://administracion.localhost:18080',
    heading: 'Acceso a Administración', account: 'master@staff.example.edu', role: 'admin',
    marker: 'Actualizar datos', mismatch: 'Este acceso es exclusivo para las cuentas de Administración.' },
];
// These credentials are already public in tools/seed_integrated.py. This checker
// neither creates these accounts nor changes a password when one no longer works.
const demoPassword = 'SnackUP-Prueba-V32!';
const studentOrigin = 'http://localhost:18080';
for (const origin of [...portals.map(portal => portal.origin), studentOrigin]) {
  const url = new URL(origin);
  assert.equal(url.protocol, 'http:');
  assert.equal(url.port, '18080');
  assert.ok(['cocina.localhost', 'administracion.localhost', 'localhost'].includes(url.hostname));
  assert.equal(url.username + url.password + url.search + url.hash, '');
}
const output = path.resolve(__dirname, '../backend/reports/portal-isolation',
  new Date().toISOString().replace(/[:.]/g, '-'));
fs.mkdirSync(output, { recursive: true });
const report = {
  success: false, startedAt: new Date().toISOString(), outputDirectory: output,
  origins: portals.map(portal => portal.origin), localOnly: true,
  mutationScope: 'Existing demo-account login, refresh and logout only; no business data changes',
  browserContext: 'The two staff portals share one new browser context per engine',
  screenshotsContainAccountViews: true, screenshotsPublished: false,
  limits: ['Local HTTP is accepted only on the exact localhost test origins; production requires HTTPS.',
    'Screenshots stay in the ignored local reports directory and may contain visible demo history.',
    'This checks browser separation and sign-in, not all features or load capacity.'],
  results: [],
};
const reportPath = path.join(output, 'report.json');
const pageResults = new WeakMap();
function save() {
  fs.writeFileSync(reportPath, JSON.stringify(report, null, 2) + '\n');
}

function text(page, label) {
  // Flutter merges adjacent static text into one multiline semantic label.
  // Match the complete line, not a substring of a different portal's heading.
  const escaped = label.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  return page.getByText(label, { exact: true })
    .or(page.getByLabel(new RegExp('(?:^|\\n)' + escaped + '(?:\\n|$)'))).first();
}

function detail(page, step) {
  const result = pageResults.get(page);
  if (result) {
    result.detail = step;
    save();
  }
}

async function semantics(page) {
  detail(page, 'wait_flutter_view');
  await page.locator('flutter-view').waitFor({ state: 'attached', timeout: 60000 });
  const enable = page.getByRole('button', { name: 'Enable accessibility', exact: true });
  if (await enable.count()) await enable.dispatchEvent('click');
}

function responseAt(page, portal, route, method = 'GET') {
  return page.waitForResponse(response => {
    const url = new URL(response.url());
    return url.origin === portal.origin && url.pathname === route && response.request().method() === method;
  }, { timeout: 60000 });
}

async function openLogin(page, portal) {
  detail(page, 'navigate_and_wait_auth_options');
  const [options] = await Promise.all([
    responseAt(page, portal, '/api/legacy/v1/auth/options'),
    page.goto(portal.origin + '/', { waitUntil: 'domcontentloaded' }),
  ]);
  assert.equal(options.status(), 200);
  assert.equal((await options.json()).passwordLogin, true);
  await semantics(page);
  detail(page, 'wait_login_heading_and_email');
  await text(page, portal.heading).waitFor();
  await page.getByRole('textbox', { name: 'Correo electrónico', exact: true }).waitFor();
  const other = portals.find(value => value !== portal);
  assert.equal(await text(page, other.heading).count(), 0);
  assert.equal(new URL(page.url()).origin, portal.origin);
}

async function signIn(page, portal, account, expectedStatus, onSession) {
  await page.bringToFront();
  detail(page, 'fill_login_form');
  // Use the editing lifecycle (focus, typing, blur). Setting the semantic
  // input's value with fill alone can outrun Flutter after a viewport change.
  for (const [name, value] of [['Correo electrónico', account], ['Contraseña', demoPassword]]) {
    const field = page.getByRole('textbox', { name, exact: true });
    await field.click();
    await field.press('ControlOrMeta+A');
    await field.pressSequentially(value);
    await field.press('Tab');
  }
  const result = pageResults.get(page);
  const attempt = { portal: portal.key, expectedStatus };
  (result.loginAttempts ??= []).push(attempt);
  const loginPromise = responseAt(page, portal, '/api/legacy/v1/auth/login', 'POST');
  const profilePromise = expectedStatus === 200
    ? responseAt(page, portal, '/api/legacy/v1/users/me').then(response => ({ response }), error => ({ error })) : null;
  detail(page, 'submit_login_and_wait_response');
  const [login] = await Promise.all([
    loginPromise,
    // Flutter's semantic overlay can move during focus/viewport updates.
    // Activate its exposed button, then require the real API response.
    page.getByRole('button', { name: 'Entrar', exact: true }).dispatchEvent('click'),
  ]);
  attempt.status = login.status();
  if (login.status() === 200) onSession();
  const submitted = login.request().postDataJSON();
  attempt.submittedAccountMatches = submitted.email === account;
  attempt.submittedPasswordMatches = submitted.password === demoPassword;
  assert.ok(attempt.submittedAccountMatches && attempt.submittedPasswordMatches,
    'The real form request must contain exactly the intended demo credentials');
  if (login.status() !== 200) {
    const code = (await login.json()).error?.code;
    attempt.errorCode = typeof code === 'string' && /^[A-Z_]+$/.test(code) ? code : 'UNRECOGNIZED';
  }
  save();
  assert.equal(login.status(), expectedStatus);
  if (expectedStatus !== 200) {
    assert.equal((await login.json()).error.code, 'PORTAL_ROLE_MISMATCH');
    detail(page, 'wait_role_mismatch_notice');
    await text(page, portal.mismatch).waitFor();
    assert.equal(await page.getByRole('button', { name: 'Cerrar sesión', exact: true }).count(), 0);
    return null;
  }
  detail(page, 'wait_authenticated_profile');
  const profileResult = await profilePromise;
  if (profileResult.error) throw profileResult.error;
  const profile = profileResult.response;
  assert.equal(profile.status(), 200);
  const identity = await profile.json();
  assert.equal(identity.role, portal.role);
  const cookies = (await login.headersArray()).filter(header => header.name.toLowerCase() === 'set-cookie');
  assert.ok(cookies.length > 0);
  assert.ok(cookies.every(header => !/;\s*domain\s*=/i.test(header.value)), 'Refresh cookies must be host-only');
  assert.ok(cookies.every(header => /;\s*httponly(?:;|$)/i.test(header.value)), 'Refresh cookies must be HttpOnly');
  assert.ok(cookies.every(header => /;\s*samesite\s*=\s*strict(?:;|$)/i.test(header.value)),
    'The server must send SameSite=Strict in every refresh Set-Cookie header');
  attempt.cookieHeaderAttributes = { hostOnly: true, httpOnly: true, sameSite: 'Strict', valuesOmitted: true };
  await waitPanel(page, portal);
  return identity.id;
}

async function waitPanel(page, portal) {
  await semantics(page);
  detail(page, 'wait_authenticated_panel_controls');
  await page.getByRole('button', { name: 'Cerrar sesión', exact: true }).first().waitFor();
  // Both panels disable refresh until their actual initial data load ends.
  // Presence alone would capture placeholders and zero-valued loading cards.
  await page.getByRole('button', { name: portal.marker, exact: true, disabled: false }).first().waitFor();
  assert.equal(await text(page, 'No se pudieron cargar los datos').count(), 0);
  assert.equal(await text(page, portal.heading).count(), 0);
  assert.equal(new URL(page.url()).origin, portal.origin);
}

async function restoredIdentity(page, portal, expectedIdentity) {
  await page.bringToFront();
  detail(page, 'reload_and_wait_refresh_profile');
  const [refresh, profile] = await Promise.all([
    responseAt(page, portal, '/api/legacy/v1/auth/refresh', 'POST'),
    responseAt(page, portal, '/api/legacy/v1/users/me'),
    page.reload({ waitUntil: 'domcontentloaded' }),
  ]);
  assert.equal(refresh.status(), 200);
  assert.equal(profile.status(), 200);
  const identity = await profile.json();
  assert.equal(identity.role, portal.role);
  assert.equal(identity.id, expectedIdentity);
  await waitPanel(page, portal);
}

async function signOut(page, portal) {
  await page.bringToFront();
  detail(page, 'logout_and_wait_response');
  const [response] = await Promise.all([
    responseAt(page, portal, '/api/legacy/v1/auth/logout', 'POST'),
    page.getByRole('button', { name: 'Cerrar sesión', exact: true }).first().dispatchEvent('click'),
  ]);
  assert.ok([200, 204].includes(response.status()));
  detail(page, 'wait_login_after_logout');
  await text(page, portal.heading).waitFor();
}

async function waitForPaint(page, size) {
  await page.waitForFunction(({ width, height }) => {
    const view = document.querySelector('flutter-view');
    const bounds = view?.getBoundingClientRect();
    return window.innerWidth === width && window.innerHeight === height && bounds &&
      Math.round(bounds.width) === width && Math.round(bounds.height) === height;
  }, size);
  // Include real image/font fetches, which can finish after semantic controls.
  await page.waitForLoadState('networkidle', { timeout: 15000 });
  await page.evaluate(async () => {
    await document.fonts.ready;
    await new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(() => requestAnimationFrame(resolve))));
  });
}

async function imageContent(page, png) {
  // Inspect the produced PNG, not Flutter's semantic tree: after resize WebKit
  // can expose the new controls while its compositor still returns white.
  return page.evaluate(async data => {
    const image = new Image();
    image.src = 'data:image/png;base64,' + data;
    await image.decode();
    const canvas = document.createElement('canvas');
    canvas.width = image.width;
    canvas.height = image.height;
    const context = canvas.getContext('2d', { willReadFrequently: true });
    context.drawImage(image, 0, 0);
    const rgba = context.getImageData(0, 0, image.width, image.height).data;
    const colors = new Set();
    let samples = 0, nonWhite = 0;
    for (let y = 0; y < image.height; y += 4) {
      for (let x = 0; x < image.width; x += 4) {
        const offset = (y * image.width + x) * 4;
        const r = rgba[offset], g = rgba[offset + 1], b = rgba[offset + 2];
        colors.add((r >> 4) * 256 + (g >> 4) * 16 + (b >> 4));
        if (Math.min(r, g, b) < 235) nonWhite++;
        samples++;
      }
    }
    const nonWhiteRatio = nonWhite / samples;
    return { width: image.width, height: image.height, sampledPixels: samples,
      nonWhiteRatio: Number(nonWhiteRatio.toFixed(4)), colorBins: colors.size,
      nonBlank: nonWhiteRatio > 0.01 && colors.size >= 8 };
  }, png.toString('base64'));
}

async function screenshots(page, portal, engine, phase, result, expectedIdentity) {
  await page.bringToFront();
  const reloadOnResize = process.platform === 'win32' && engine === 'webkit';
  if (reloadOnResize) {
    // Native Windows WebKit was observed to produce a persistently white
    // canvas after live resize. Fresh navigation at that size paints correctly.
    // This verifies each target viewport, not live resize or real Safari.
    result.visualLimitations = [{ code: 'LIVE_RESIZE_WHITE_RENDER', status: 'not_verified',
      observed: 'Native Windows WebKit rendered white after live viewport resize',
      workaround: 'Reload the same portal at each changed viewport and verify identity again',
      attribution: 'Undetermined; observed in this test runtime', realSafariVerified: false }];
  }
  async function resize(size) {
    const previous = page.viewportSize();
    const changed = previous.width !== size.width || previous.height !== size.height;
    await page.setViewportSize(size);
    if (reloadOnResize && changed) {
      if (phase === 'login') await openLogin(page, portal);
      else await restoredIdentity(page, portal, expectedIdentity);
    }
    return reloadOnResize && changed;
  }
  for (const [screen, size] of [['desktop', { width: 1440, height: 1000 }],
                              ['mobile', { width: 390, height: 844 }]]) {
    const viewportReloaded = await resize(size);
    await semantics(page);
    if (phase === 'login') await text(page, portal.heading).waitFor();
    else await waitPanel(page, portal);
    detail(page, 'capture_' + phase + '_' + screen);
    const file = `${engine}-${portal.key}-${phase}-${screen}.png`;
    const deadline = Date.now() + 15000;
    let png, pixels, attempts = 0;
    do {
      await waitForPaint(page, size);
      png = await page.screenshot({ animations: 'disabled' });
      pixels = await imageContent(page, png);
      attempts++;
    } while (!pixels.nonBlank && Date.now() < deadline);
    assert.ok(pixels.nonBlank, 'The rendered screenshot must contain painted application content');
    fs.writeFileSync(path.join(output, file), png);
    result.screenshots.push({ portal: portal.key, phase, viewport: size, file,
      dataLoadCompleted: phase === 'authenticated', viewportReloaded, captureAttempts: attempts, pixels });
  }
  await resize({ width: 1440, height: 1000 });
  await page.evaluate(() => new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve))));
}

async function cookieIsolation(context, result) {
  const cookies = await context.cookies();
  result.cookieMetadata = cookies.filter(cookie => cookie.name.startsWith('snackup_refresh'))
    .map(({ name, domain, path: cookiePath, httpOnly, sameSite, secure }) =>
      ({ name, domain, path: cookiePath, httpOnly, sameSite, secure, valueOmitted: true }));
  save();
  const selected = portals.map(portal => {
    const name = 'snackup_refresh_' + portal.audience;
    const row = cookies.find(cookie => cookie.name === name);
    assert.ok(row, 'Expected a refresh cookie for each staff portal');
    assert.equal(row.domain, new URL(portal.origin).hostname);
    assert.equal(row.path, '/api');
    assert.equal(row.httpOnly, true);
    if (process.platform === 'win32' && result.browser === 'webkit' && row.sameSite === 'None') {
      // Upstream marks this metadata check as an expected failure on native
      // Windows WebKit. HTTP header enforcement above is still mandatory.
      (result.unverifiedAttributes ??= []).push({ cookie: name, attribute: 'SameSite browser metadata',
        observed: row.sameSite, status: 'not_verified', reason: 'Native Windows WebKit cannot reliably report SameSite Strict/Lax',
        source: 'https://github.com/microsoft/playwright/blob/main/tests/library/browsercontext-cookies.spec.ts#L110-L131' });
    } else {
      assert.equal(row.sameSite, 'Strict');
    }
    return row;
  });
  assert.notEqual(selected[0].value, selected[1].value);
  for (const portal of portals) {
    const visible = await context.cookies(portal.origin + '/api/legacy/v1/auth/refresh');
    const refresh = visible.filter(cookie => cookie.name.startsWith('snackup_refresh'));
    assert.equal(refresh.length, 1);
    assert.equal(refresh[0].name, 'snackup_refresh_' + portal.audience);
  }
  result.cookies = selected.map(({ name, domain, path: cookiePath, httpOnly, sameSite, secure }) =>
    ({ name, domain, path: cookiePath, httpOnly, sameSite, secure, valueOmitted: true }));
}

async function cannotReadOtherOrigin(page, other) {
  const outcome = await page.evaluate(async target => {
    try {
      const response = await fetch(target + '/api/legacy/v1/auth/options', { credentials: 'include' });
      await response.text();
      return { readable: true, status: response.status };
    } catch (error) {
      return { readable: false, errorType: error.name };
    }
  }, other.origin);
  assert.equal(outcome.readable, false, 'A staff page must not read the other portal through CORS');
  return outcome;
}

async function checkEngine(engineName, engine) {
  const result = { browser: engineName, success: false, phase: 'launch', checks: [], screenshots: [], cleanup: [] };
  report.results.push(result);
  let browser, context;
  const pages = new Map();
  const loggedIn = new Set();
  const identities = new Map();
  async function check(name, operation) {
    result.phase = name;
    await operation();
    result.checks.push({ name, ok: true });
    console.log(JSON.stringify({ browser: engineName, check: name, ok: true }));
    save();
  }
  try {
    browser = await engine.launch({ headless: true });
    result.version = browser.version();
    context = await browser.newContext({ locale: 'es-MX', viewport: { width: 1440, height: 1000 } });
    await check('students_options_read_only', async () => {
      const response = await context.request.get(studentOrigin + '/api/v1/auth/options', { maxRedirects: 0 });
      assert.equal(response.status(), 200);
      assert.equal((await response.json()).passwordLogin, true);
    });
    for (const portal of portals) {
      const page = await context.newPage();
      pages.set(portal.key, page);
      pageResults.set(page, result);
      page.setDefaultTimeout(30000);
      await check(portal.key + '_public_login', async () => {
        await openLogin(page, portal);
        await screenshots(page, portal, engineName, 'login', result);
      });
      await check(portal.key + '_rejects_other_role', async () => {
        const other = portals.find(value => value !== portal);
        await signIn(page, portal, other.account, 403, () => loggedIn.add(portal.key));
        assert.equal((await context.cookies()).filter(cookie => cookie.name.startsWith('snackup_refresh')).length, 0);
      });
    }
    for (const portal of portals) {
      const page = pages.get(portal.key);
      await check(portal.key + '_correct_role', async () => {
        // Reopen the real public entry after the deliberate rejection. The
        // two pages still share this context and its untouched cookie jar.
        await openLogin(page, portal);
        identities.set(portal.key, await signIn(page, portal, portal.account, 200, () => loggedIn.add(portal.key)));
        await screenshots(page, portal, engineName, 'authenticated', result, identities.get(portal.key));
      });
    }
    await check('host_only_http_only_cookies_are_independent', () => cookieIsolation(context, result));
    for (const portal of portals) {
      await check(portal.key + '_reload_retains_identity', () =>
        restoredIdentity(pages.get(portal.key), portal, identities.get(portal.key)));
      await check(portal.key + '_cannot_read_other_origin', async () => {
        const other = portals.find(value => value !== portal);
        result.crossOrigin ??= [];
        result.crossOrigin.push({ from: portal.key, to: other.key,
          ...await cannotReadOtherOrigin(pages.get(portal.key), other) });
      });
    }
    await check('kitchen_logout_preserves_administration', async () => {
      await signOut(pages.get('kitchen'), portals[0]);
      loggedIn.delete('kitchen');
      const cookies = await context.cookies();
      assert.equal(cookies.some(cookie => cookie.name === 'snackup_refresh_cocina'), false);
      assert.equal(cookies.some(cookie => cookie.name === 'snackup_refresh_administracion'), true);
      await restoredIdentity(pages.get('administration'), portals[1], identities.get('administration'));
      await openLogin(pages.get('kitchen'), portals[0]);
    });
    await check('administration_logout_clears_only_its_session', async () => {
      await signOut(pages.get('administration'), portals[1]);
      loggedIn.delete('administration');
      assert.equal((await context.cookies()).filter(cookie => cookie.name.startsWith('snackup_refresh')).length, 0);
    });
    result.phase = 'complete';
    result.success = true;
  } catch (error) {
    result.errorType = error.name;
    result.failureDetail = result.detail;
    result.checks.push({ name: result.phase, ok: false, errorType: error.name, detail: result.detail });
    result.failurePages = [];
    for (const portal of portals) {
      const page = pages.get(portal.key);
      if (!page || page.isClosed()) continue;
      try {
        const url = new URL(page.url());
        const file = `${engineName}-${portal.key}-failure.png`;
        // An interrupted sign-in can still contain the demo password. Never
        // expose field values through diagnostics or failure screenshots.
        await page.screenshot({ path: path.join(output, file), animations: 'disabled',
          mask: [page.locator('input,textarea')] });
        result.failurePages.push({ portal: portal.key, origin: url.origin, path: url.pathname,
          loginHeadingPresent: await text(page, portal.heading).count() > 0,
          emailValidationPresent: await text(page, 'Escribe un correo válido.').count() > 0,
          passwordValidationPresent: await text(page, 'Escribe tu contraseña.').count() > 0,
          emailFieldCount: await page.getByRole('textbox', { name: 'Correo electrónico', exact: true }).count(),
          logoutButtonCount: await page.getByRole('button', { name: 'Cerrar sesión', exact: true }).count(),
          screenshot: file });
      } catch (captureError) {
        result.failurePages.push({ portal: portal.key, captureErrorType: captureError.name });
      }
    }
    console.log(JSON.stringify({ browser: engineName, check: result.phase, ok: false,
      errorType: error.name, detail: result.failureDetail }));
  } finally {
    for (const portal of portals) {
      if (!loggedIn.has(portal.key)) continue;
      try {
        await signOut(pages.get(portal.key), portal);
        result.cleanup.push({ portal: portal.key, signedOut: true });
      } catch (error) {
        try {
          // Cleanup only: a broken rendered panel must not leave a demo auth
          // session alive. Cookie/origin are restricted to this same portal.
          const response = await context.request.post(portal.origin + '/api/legacy/v1/auth/logout', {
            headers: { Origin: portal.origin }, data: {}, maxRedirects: 0 });
          assert.equal(response.status(), 204);
          result.cleanup.push({ portal: portal.key, signedOut: true, method: 'same_origin_api_fallback',
            uiErrorType: error.name });
        } catch (cleanupError) {
          result.cleanup.push({ portal: portal.key, signedOut: false, errorType: cleanupError.name });
          result.success = false;
        }
      }
    }
    if (context) await context.close();
    if (browser) await browser.close();
    save();
  }
}

async function main() {
  save();
  for (const [name, engine] of Object.entries({ chromium, webkit })) await checkEngine(name, engine);
  report.finishedAt = new Date().toISOString();
  report.success = report.results.length === 2 && report.results.every(result => result.success);
  save();
  console.log(JSON.stringify({ success: report.success, report: reportPath }));
  if (!report.success) process.exitCode = 1;
}

main().catch(error => {
  report.success = false;
  report.errorType = error.name;
  save();
  console.error(JSON.stringify({ success: false, errorType: error.name, report: reportPath }));
  process.exitCode = 1;
});
