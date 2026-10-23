// Opt-in load only against an explicitly confirmed, disposable test environment.
import http from 'k6/http';
import { check, sleep } from 'k6';
import exec from 'k6/execution';
import { SharedArray } from 'k6/data';
import { Rate } from 'k6/metrics';

const base = (__ENV.BASE_URL || '').replace(/\/$/, '');
const target = Number(__ENV.TARGET_VUS || '1000');
const mode = __ENV.MODE || 'read';
if (__ENV.ALLOW_LOAD !== 'YES' || __ENV.TARGET_ENV !== 'isolated-loadtest') {
  throw new Error('Set ALLOW_LOAD=YES and TARGET_ENV=isolated-loadtest only for an authorized disposable deployment.');
}
if (!/^https?:\/\/[^/?#]+$/.test(base) || base.split('://')[1] !== __ENV.CONFIRM_HOST) {
  throw new Error('BASE_URL must be an origin and CONFIRM_HOST must match its host:port exactly.');
}
if (!Number.isInteger(target) || target < 1 || target > 1000 || !['read', 'orders'].includes(mode)) {
  throw new Error('TARGET_VUS must be 1..1000; MODE must be read or orders.');
}
if (mode === 'orders' && __ENV.ALLOW_WRITES !== 'YES') {
  throw new Error('MODE=orders reserves stock, creates and cancels orders. Explicit ALLOW_WRITES=YES is required.');
}
if (!__ENV.CREDENTIALS_FILE) throw new Error('CREDENTIALS_FILE must refer to a private external fixture file.');
const accounts = new SharedArray('private-student-credentials', () => {
  const students = JSON.parse(open(__ENV.CREDENTIALS_FILE)).students;
  if (!Array.isArray(students) || students.length < target) throw new Error('Provide one test account per virtual user.');
  const uniqueEmails = new Set();
  for (let index = 0; index < target; index += 1) {
    const account = students[index];
    if (!account.email || !account.password || !account.businessId || !account.productId) throw new Error('A fixture account is incomplete.');
    uniqueEmails.add(String(account.email).toLowerCase());
  }
  if (uniqueEmails.size !== target) throw new Error('Do not reuse a student account across virtual users.');
  return students;
});

const idempotency = new Rate('idempotent_retries_match');
const cancellation = new Rate('reservations_cancelled');
export const options = {
  noCookiesReset: true,
  scenarios: {
    students: {
      executor: 'ramping-vus', startVUs: 0, gracefulRampDown: '30s',
      stages: [
        { duration: '2m', target: Math.min(100, target) },
        { duration: '2m', target: Math.min(300, target) },
        { duration: '2m', target }, { duration: '30m', target },
        { duration: '2m', target: 0 },
      ],
    },
  },
  thresholds: {
    http_req_failed: [{ threshold: 'rate<0.01', abortOnFail: true, delayAbortEval: '1m' }],
    http_req_duration: ['p(95)<750', 'p(99)<2000'],
    checks: ['rate>0.99'],
    ...(mode === 'orders' ? {
      idempotent_retries_match: ['rate==1'], reservations_cancelled: ['rate==1'],
      'http_req_duration{name:create_order}': ['p(95)<1500'],
    } : {}),
  },
};

let accessToken;
let expiresAt = 0;
function json(response) { try { return response.json(); } catch (_) { return {}; } }
function params(name, extra = {}) {
  return { tags: { name }, headers: { 'Content-Type': 'application/json', Origin: base,
    ...(accessToken ? { Authorization: `Bearer ${accessToken}` } : {}), ...extra } };
}
function login(account) {
  let response;
  if (accessToken) response = http.post(`${base}/api/v1/auth/refresh`, '{}', params('refresh'));
  if (!response || response.status !== 200) {
    accessToken = undefined;
    response = http.post(`${base}/api/v1/auth/login`, JSON.stringify({ email: account.email, password: account.password }), params('login'));
  }
  const payload = json(response);
  if (!check(response, { authenticated: (r) => r.status === 200 && Boolean(payload.tokens?.accessToken) })) return false;
  accessToken = payload.tokens.accessToken;
  expiresAt = Date.parse(payload.tokens.accessTokenExpiresAt);
  return true;
}

export function setup() {
  const response = http.get(`${base}/health/ready`, { tags: { name: 'readiness' } });
  if (response.status !== 200) throw new Error('The isolated target is not ready.');
}

export default function () {
  const account = accounts[exec.vu.idInTest - 1];
  if (!accessToken || Date.now() + 60000 >= expiresAt) {
    if (!login(account)) { sleep(10); return; }
  }
  const businesses = http.get(`${base}/api/v1/student/businesses?limit=20`, params('list_businesses'));
  check(businesses, { 'businesses readable': (r) => r.status === 200 });
  const products = http.get(`${base}/api/v1/student/businesses/${account.businessId}/products?limit=20`, params('list_products'));
  check(products, { 'products readable': (r) => r.status === 200 });
  const history = http.get(`${base}/api/v1/student/orders?limit=20`, params('own_orders'));
  check(history, { 'own orders readable': (r) => r.status === 200 });

  if (mode === 'orders') {
    const key = `load-${exec.vu.idInTest}-${exec.vu.iterationInScenario}-${Date.now()}`;
    const payload = JSON.stringify({ businessId: account.businessId,
      items: [{ productId: account.productId, quantity: 1, notes: '[CARGA AISLADA]' }], paymentMethod: 'cash' });
    const response = http.post(`${base}/api/v1/student/orders`, payload, params('create_order', { 'Idempotency-Key': key }));
    const created = json(response);
    if (check(response, { 'order created': (r) => r.status === 201 && Boolean(created.id) })) {
      const retry = http.post(`${base}/api/v1/student/orders`, payload, params('retry_order', { 'Idempotency-Key': key }));
      idempotency.add(retry.status === 201 && json(retry).id === created.id);
      sleep(0.5);
      const cancelled = http.post(`${base}/api/v1/student/orders/${created.id}/cancel`,
        JSON.stringify({ expectedVersion: created.version }), params('cancel_order'));
      cancellation.add(cancelled.status === 200 && json(cancelled).status === 'cancelled');
    }
  }
  sleep(5 + Math.random() * 5);
}
