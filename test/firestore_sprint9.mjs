import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';

const host = process.env.FIRESTORE_EMULATOR_HOST ?? '127.0.0.1:8080';
assert.match(host, /^(127\.0\.0\.1|localhost):\d+$/);
const root = 'projects/demo-snackup-sprint9/databases/(default)/documents';
const base = 'http://' + host + '/v1/' + root;
const suffix = randomUUID();
const student = 'student-' + suffix;
const stranger = 'stranger-' + suffix;
const manager = 'manager-' + suffix;
const otherManager = 'other-' + suffix;
const cafe = 'cafes-' + suffix;
const soldOut = 'sold-out-' + suffix;
const product = 'product-' + suffix;
const order = 'order-' + suffix;

function token(uid) {
  const encode = (data) => Buffer.from(JSON.stringify(data)).toString('base64url');
  const now = Math.floor(Date.now() / 1000);
  return encode({ alg: 'none', typ: 'JWT' }) + '.' + encode({
    sub: uid, user_id: uid, iat: now, exp: now + 3600,
    aud: 'demo-snackup-sprint9',
    iss: 'https://securetoken.google.com/demo-snackup-sprint9',
    email: uid + '@utsjr.edu.mx',
    firebase: { sign_in_provider: 'password' },
  }) + '.';
}

function field(value) {
  if (value === null) return { nullValue: null };
  if (typeof value === 'string') return { stringValue: value };
  if (typeof value === 'boolean') return { booleanValue: value };
  if (typeof value === 'number') {
    return Number.isInteger(value) ? { integerValue: String(value) } : { doubleValue: value };
  }
  if (Array.isArray(value)) return { arrayValue: { values: value.map(field) } };
  return { mapValue: { fields: fields(value) } };
}
const fields = (data) => Object.fromEntries(
  Object.entries(data).map(([key, value]) => [key, field(value)]),
);
const requestTime = (fieldPath) => ({ fieldPath, setToServerValue: 'REQUEST_TIME' });
const write = (path, data, stamp, patch = false) => ({
  update: { name: root + '/' + path, fields: fields(data) },
  ...(patch ? { updateMask: { fieldPaths: Object.keys(data) } } : {}),
  ...(stamp ? { updateTransforms: [requestTime(stamp)] } : {}),
});
const commit = (uid, ...writes) => request(uid, ':commit', { writes });
async function request(uid, path, data) {
  return fetch(base + path, {
    method: data ? 'POST' : 'GET',
    headers: { Authorization: 'Bearer ' + (uid === 'owner' ? uid : token(uid)),
      'Content-Type': 'application/json' },
    body: data ? JSON.stringify(data) : undefined,
  });
}
async function expect(label, promise, status = 200) {
  const response = await promise;
  const body = await response.text();
  assert.equal(response.status, status, label + ' ' + body);
  console.log('OK ' + label);
}

const item = { productId: product, name: 'Agua', price: 24, quantity: 1, notes: '' };
const productData = { businessId: cafe, name: 'Agua', category: 'BEBIDAS',
  price: 24, stock: 4, isAvailable: true, isFeatured: false };
const profile = { role: 'user', displayName: 'Estudiante', numeroDeControl: '1234' };
await expect('preparar datos', commit('owner',
  write('users/' + stranger, profile),
  write('users/' + manager, { role: 'business' }),
  write('users/' + otherManager, { role: 'business' }),
  write('businesses/' + cafe, { ownerId: manager, isOpen: true }),
  write('products/' + soldOut, { ...productData, stock: 0, isAvailable: false })));
await expect('registro institucional', commit(student, write('users/' + student, profile)));
await expect('estudiante no cambia rol', commit(student,
  write('users/' + student, { role: 'business' }, null, true)), 403);
await expect('alta de producto por dueño', commit(manager, write('products/' + product, productData)));
await expect('rechazar producto inválido', commit(manager,
  write('products/invalid-' + suffix, { ...productData, price: -1 })), 403);
await expect('estudiante no crea productos', commit(student,
  write('products/invalid-' + suffix, productData)), 403);
await expect('estudiante no edita productos', commit(student,
  write('products/' + product, { price: 12 }, null, true)), 403);
const checkout = { businessId: cafe, userId: student, userDisplayName: 'Estudiante',
  userNumeroDeControl: '1234', status: 'pending', totalPrice: 24,
  paymentMethod: 'Efectivo', scheduledPickupTime: null, items: [item] };
await expect('compra de producto agotado rechazada', commit(student,
  write('orders/' + order, { ...checkout, items: [{ ...item, productId: soldOut }] }, 'createdAt')), 403);
await expect('total alterado rechazado', commit(student,
  write('orders/' + order, { ...checkout, totalPrice: 1 }, 'createdAt')), 403);
await expect('checkout válido', commit(student, write('orders/' + order, checkout, 'createdAt')));
await expect('estudiante lee su pedido', request(student, '/orders/' + order));
await expect('estudiante no lee pedido ajeno', request(stranger, '/orders/' + order), 403);
const change = (uid, values) => commit(uid, write('orders/' + order, values, 'statusUpdatedAt', true));
await expect('estudiante no cambia estado', change(student, { status: 'preparing' }), 403);
await expect('otro negocio no cancela', change(otherManager, { status: 'cancelled', cancellationReason: 'Sin insumos' }), 403);
await expect('impedir salto de estado', change(manager, { status: 'ready' }), 403);
await expect('negocio cambia a preparación', change(manager, { status: 'preparing' }));
await expect('motivo vacío rechazado', change(manager, { status: 'cancelled', cancellationReason: '   ' }), 403);
await expect('negocio no cambia total', change(manager, {
  status: 'cancelled', cancellationReason: 'Sin insumos', totalPrice: 0,
}), 403);
await expect('negocio cancela con motivo', change(manager, { status: 'cancelled', cancellationReason: 'Sin insumos' }));
await expect('pedido cancelado no se reabre', change(manager, { status: 'preparing' }), 403);

