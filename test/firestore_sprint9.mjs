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

const customerOrder = 'customer-cancellation-' + suffix;
const readyOrder = 'ready-order-' + suffix;
const cancellation = {
  status: 'cancelled',
  cancellationReason: 'Cancelado por el cliente',
  cancelledBy: 'customer',
};
const cancel = (uid, id, data = cancellation) => commit(uid,
  write('orders/' + id, data, 'statusUpdatedAt', true));
await expect('crear pedido para cancelación', commit(student,
  write('orders/' + customerOrder, checkout, 'createdAt')));
await expect('otro estudiante no cancela', cancel(stranger, customerOrder), 403);
await expect('cliente no modifica el importe al cancelar',
  cancel(student, customerOrder, { ...cancellation, totalPrice: 0 }), 403);
await expect('cliente cancela su pedido', cancel(student, customerOrder));
await expect('la cafetería puede leer el pedido cancelado',
  request(manager, '/orders/' + customerOrder));
await expect('cliente no vuelve a cancelar el mismo pedido',
  cancel(student, customerOrder), 403);
await expect('crear pedido listo para verificar transición', commit('owner',
  write('orders/' + readyOrder, { ...checkout, status: 'ready' }, 'createdAt')));
await expect('cliente no cancela un pedido listo', cancel(student, readyOrder), 403);

// La eliminación debe respetar el propietario y conservar pedidos históricos.
const removableProduct = 'removable-product-' + suffix;
const removeProduct = (uid) => commit(uid, { delete: root + '/products/' + removableProduct });
await expect('crear producto para eliminación', commit(manager,
  write('products/' + removableProduct, productData)));
const historicalOrder = 'historical-order-' + suffix;
await expect('crear pedido antes de eliminar producto', commit(student,
  write('orders/' + historicalOrder, {
    ...checkout, items: [{ ...item, productId: removableProduct }],
  }, 'createdAt')));
await expect('estudiante no elimina producto', removeProduct(student), 403);
await expect('otro negocio no elimina producto', removeProduct(otherManager), 403);
await expect('negocio propietario elimina producto', removeProduct(manager));
await expect('producto eliminado no existe', request('owner', '/products/' + removableProduct), 404);
await expect('pedido previo permanece después de eliminar producto', request(student, '/orders/' + historicalOrder));

// Regresión: concatenar IDs con List.concat, sin permitir productos repetidos.
const boundaryProducts = Array.from({ length: 9 }, (_, i) => 'boundary-' + i + '-' + suffix);
await expect('preparar productos para límites de checkout', commit('owner',
  ...boundaryProducts.map((id) => write('products/' + id, productData))));
const boundaryItems = boundaryProducts.map((id) => ({ ...item, productId: id }));
const boundaryCheckout = (id, items) => commit(student, write('orders/' + id + '-' + suffix,
  { ...checkout, items, totalPrice: items.reduce((total, line) => total + line.price * line.quantity, 0) }, 'createdAt'));
await expect('ocho productos distintos permitidos', boundaryCheckout('eight', boundaryItems.slice(0, 8)));
await expect('nueve productos distintos rechazados', boundaryCheckout('nine', boundaryItems), 403);
await expect('productos repetidos con notas distintas rechazados', boundaryCheckout('duplicate',
  [item, { ...item, notes: 'Otra nota' }]), 403);
await expect('cantidad cero rechazada', boundaryCheckout('zero', [{ ...item, quantity: 0 }]), 403);
