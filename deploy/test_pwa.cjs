// Behavioral checks of the worker's routing and registration, without Firebase.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const web = path.join(__dirname, '..', 'web');

async function workerChecks() {
  const listeners = {};
  const cached = new Map();
  let network = 0;
  let offline = false;
  const context = {
    URL, Request, Response, encodeURIComponent,
    self: {
      registration: {scope: 'https://snackup.test/'},
      location: {origin: 'https://snackup.test'},
      addEventListener: (name, fn) => { listeners[name] = fn; },
      skipWaiting: async () => {},
      clients: {claim: async () => {}},
    },
    caches: {
      open: async () => ({add: async (request) => { cached.set(request.url, new Response('offline')); }}),
      match: async (url) => cached.get(url),
      keys: async () => [],
      delete: async () => { throw new Error('Unexpected cache deletion'); },
    },
    fetch: async () => {
      network += 1;
      if (offline) throw new Error('Disconnected');
      return new Response('online');
    },
  };
  vm.runInNewContext(fs.readFileSync(path.join(web, 'snackup_service_worker.js'), 'utf8'), context);
  let installing;
  listeners.install({waitUntil: (promise) => { installing = promise; }});
  await installing;
  assert.deepEqual([...cached.keys()], ['https://snackup.test/offline.html']);
  function dispatch(url, options = {}) {
    let result;
    listeners.fetch({request: {
      url: new URL(url, 'https://snackup.test').href, method: 'GET', mode: 'navigate',
      headers: new Headers(), ...options,
    }, respondWith: (promise) => { result = promise; }});
    return result;
  }
  for (const url of ['/api', '/api/v1/users/me', '/api/legacy/v1/orders', '/socket.io/?EIO=4',
    '/media/private.webp', '/paneles', '/paneles/orders', '/%70aneles/orders',
    'https://firestore.googleapis.com/data']) {
    assert.equal(dispatch(url), undefined, url);
  }
  assert.equal(dispatch('/orders', {method: 'POST'}), undefined);
  assert.equal(dispatch('/orders', {headers: new Headers({Authorization: 'Bearer test'})}), undefined);
  assert.equal(dispatch('/orders', {mode: 'cors'}), undefined);
  assert.equal(network, 0);
  assert.equal(await (await dispatch('/')).text(), 'online');
  offline = true;
  assert.equal(await (await dispatch('/orders')).text(), 'offline');
  assert.deepEqual([...cached.keys()], ['https://snackup.test/offline.html']);
}

async function registrationChecks() {
  async function run(registrations) {
    let load;
    const registered = [];
    vm.runInNewContext(fs.readFileSync(path.join(web, 'pwa.js'), 'utf8'), {
      URL,
      window: {isSecureContext: true, addEventListener: (_, fn) => { load = fn; }},
      document: {baseURI: 'https://snackup.test/'},
      navigator: {serviceWorker: {
        getRegistrations: async () => registrations,
        register: async (url, options) => { registered.push({url: url.href, scope: options.scope}); },
      }},
    });
    await load();
    return registered;
  }
  assert.deepEqual(await run([]), [{url: 'https://snackup.test/snackup_service_worker.js', scope: '/'}]);
  assert.equal((await run([{scope: 'https://snackup.test/',
    active: {scriptURL: 'https://snackup.test/flutter_service_worker.js'}}])).length, 1);
  assert.deepEqual(await run([{scope: 'https://snackup.test/',
    active: {scriptURL: 'https://snackup.test/firebase-messaging-sw.js'}}]), []);
}

(async () => {
  await workerChecks();
  await registrationChecks();
  process.stdout.write('PWA routing, data exclusion and single registration checks passed.\n');
})().catch((error) => { process.stderr.write(error.stack + '\n'); process.exitCode = 1; });
