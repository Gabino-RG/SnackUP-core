/** SnackUP: 12 AAA REST + 6 regresiones adicionales. Solo emuladores.
 * Arrange/oraculo: bypass local. Act: HTTP con token del actor, sin bypass.
 * Cada caso comprueba siembra, respuesta y persistencia y limpia sus datos.
 */
import {test, before, after} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {randomUUID} from 'node:crypto';
import {assertLocalEndpoint, assertDemoProject, assertRulesReady} from './guard.mjs';
import {initializeTestEnvironment} from '@firebase/rules-unit-testing';
import {doc, setDoc, getDoc, deleteDoc, Timestamp} from 'firebase/firestore';

const PROJECT = 'demo-snackup-qa';
const ROOT = `projects/${PROJECT}/databases/(default)/documents`;
const DOCS = `http://127.0.0.1:8080/v1/${ROOT}`;
const AUTH = 'http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1';
let env;
const actors = {};
const paths = new Set();
const fields = value => Object.fromEntries(Object.entries(value).map(([k,v]) => [k, encode(v)]));
function encode(value) {
  if (value === null) return {nullValue: null};
  if (value instanceof Date) return {timestampValue: value.toISOString()};
  if (typeof value === 'boolean') return {booleanValue: value};
  if (typeof value === 'string') return {stringValue: value};
  if (typeof value === 'number') {
    assert.ok(Number.isFinite(value));
    return Number.isInteger(value) ? {integerValue: String(value)} : {doubleValue: value};
  }
  if (Array.isArray(value)) return {arrayValue: {values: value.map(encode)}};
  if (typeof value === 'object') return {mapValue: {fields: fields(value)}};
  throw new TypeError(`Tipo no compatible: ${typeof value}`);
}
async function request(method, url, actor, body) {
  assertLocalEndpoint(url);
  const headers = {'Content-Type': 'application/json'};
  if (actor) headers.Authorization = `Bearer ${actor.idToken}`;
  const response = await fetch(url, {method, headers, redirect: 'error',
    body: body === undefined ? undefined : JSON.stringify(body), signal: AbortSignal.timeout(10000)});
  const text = await response.text();
  let json;
  try { json = text ? JSON.parse(text) : null; }
  catch { throw new Error(`Respuesta HTTP ${response.status} no JSON`); }
  return {status: response.status, json};
}
async function seed(path, data) {
  paths.add(path);
  await env.withSecurityRulesDisabled(async ctx => { await setDoc(doc(ctx.firestore(), path), data); });
}
async function stored(path) {
  // withSecurityRulesDisabled devuelve Promise<void>, NO el valor del callback.
  let value;
  await env.withSecurityRulesDisabled(async ctx => {
    const snapshot = await getDoc(doc(ctx.firestore(), path));
    value = snapshot.exists() ? snapshot.data() : undefined;
  });
  return value;
}
async function cleanup(selected) {
  if (!env) return;
  await env.withSecurityRulesDisabled(async ctx => {
    for (const path of selected) { await deleteDoc(doc(ctx.firestore(), path)); paths.delete(path); }
  });
}
async function createActor(label, role) {
  const email = `${label}-${randomUUID()}@example.test`;
  const result = await request('POST', `${AUTH}/accounts:signUp?key=fake-api-key`, null,
    {email, password: `Qa!${randomUUID()}`, returnSecureToken: true});
  assert.equal(result.status, 200, `Auth Emulator no pudo crear ${label}`);
  assert.equal(typeof result.json.idToken, 'string');
  const actor = {uid: result.json.localId, idToken: result.json.idToken, email};
  if (role === 'business') actor.businessId = `qa-business-${randomUUID()}`;
  actors[label] = actor;
  await seed(`users/${actor.uid}`, {role, displayName: `QA ${label}`, email, numeroDeControl: 'QA0001'});
  if (role === 'business') await seed(`businesses/${actor.businessId}`, {ownerId: actor.uid, name: `QA ${label}`});
}
before(async () => {
  assertDemoProject(process.env.GCLOUD_PROJECT || PROJECT);
  const rules = await readFile(new URL('./firestore.rules', import.meta.url), 'utf8');
  assertRulesReady(rules);
  env = await initializeTestEnvironment({projectId: PROJECT, firestore: {host: '127.0.0.1', port: 8080, rules}});
  for (const [label, role] of [['U1','user'],['U2','user'],['B1','business'],['B2','business']]) await createActor(label, role);
});
after(async () => {
  const errors = [];
  try { await cleanup([...paths]); } catch (error) { errors.push(error); }
  for (const actor of Object.values(actors)) {
    try {
      const result = await request('POST', `${AUTH}/accounts:delete?key=fake-api-key`, null, {idToken: actor.idToken});
      assert.equal(result.status, 200, 'No se pudo limpiar una cuenta sintetica');
    } catch (error) { errors.push(error); }
  }
  try { if (env) await env.cleanup(); } catch (error) { errors.push(error); }
  if (errors.length) throw new AggregateError(errors, 'Fallos de limpieza');
});
async function fixture(state) {
  const prefix = `qa-${randomUUID()}`;
  const f = {product: `products/${prefix}-p1`, product2: `products/${prefix}-p2`,
    order: `orders/${prefix}-o1`, order2: `orders/${prefix}-o2`,
    cart: `users/${actors.U1.uid}/cart/${prefix}-c1`, created: `orders/${prefix}-new`};
  f.productData = {businessId: actors.B1.businessId, name: 'Cafe QA', description: 'Producto sintetico',
    price: 35, stock: 10, isAvailable: true, isFeatured: false, category: 'Bebidas', imageUrl: ''};
  const item = {productId: f.product.split('/').at(-1), name: 'Cafe QA', quantity: 2, price: 35, notes: 'Sin azucar (QA)'};
  f.orderData = {businessId: actors.B1.businessId, userId: actors.U1.uid, userDisplayName: 'QA U1',
    userNumeroDeControl: 'QA0001', status: state, totalPrice: 70, paymentMethod: 'Efectivo',
    createdAt: Timestamp.fromDate(new Date('2026-09-29T12:00:00Z')), scheduledPickupTime: null, items: [item]};
  await seed(f.product, f.productData);
  await seed(f.product2, {...f.productData, businessId: actors.B2.businessId});
  await seed(f.order, f.orderData);
  await seed(f.order2, {...f.orderData, businessId: actors.B2.businessId, userId: actors.U2.uid});
  await seed(f.cart, {...item, businessId: actors.B1.businessId});
  paths.add(f.created);
  return f;
}
async function withFixture(state, fn) {
  const f = await fixture(state);
  try {
    // Verifica Arrange y el oraculo para evitar comparaciones undefined === undefined.
    assert.deepEqual(await stored(f.product), f.productData, 'La siembra/oraculo del producto debe funcionar');
    assert.deepEqual(await stored(f.order), f.orderData, 'La siembra/oraculo del pedido debe funcionar');
    assert.ok(await stored(f.cart), 'El carrito debe existir antes de Act');
    await fn(f);
  } finally { await cleanup([f.product, f.product2, f.order, f.order2, f.cart, f.created]); }
}
function equalFilter(fieldPath, value) { return {fieldFilter: {field: {fieldPath}, op: 'EQUAL', value: encode(value)}}; }
function query(collectionId, filters) {
  return {structuredQuery: {from: [{collectionId}], where: {compositeFilter: {op: 'AND', filters}}, limit: 20}};
}
function documents(result) {
  assert.equal(result.status, 200);
  assert.ok(Array.isArray(result.json));
  return result.json.filter(row => row.document).map(row => row.document);
}
function denied(result) { assert.equal(result.status, 403); assert.equal(result.json?.error?.status, 'PERMISSION_DENIED'); }
async function patch(path, actor, changes) {
  const url = new URL(`${DOCS}/${path}`);
  for (const key of Object.keys(changes)) url.searchParams.append('updateMask.fieldPaths', key);
  url.searchParams.set('currentDocument.exists', 'true');
  return request('PATCH', url.toString(), actor, {fields: fields(changes)});
}
function immutable(original, actual) {
  for (const key of ['userId','businessId','totalPrice','items','createdAt','paymentMethod']) assert.deepEqual(actual[key], original[key], key);
}
function commitBody(f, overrides = {}) {
  const {createdAt, ...order} = f.orderData;
  return {writes: [
    {update: {name: `${ROOT}/${f.created}`, fields: fields({...order, ...overrides})},
      updateTransforms: [{fieldPath: 'createdAt', setToServerValue: 'REQUEST_TIME'}], currentDocument: {exists: false}},
    {delete: `${ROOT}/${f.cart}`, currentDocument: {exists: true}},
  ]};
}

test('API-01 | Menu disponible del negocio solicitado', async () => {
  // Arrange
  await withFixture('pending', async f => {
    const body = query('products', [equalFilter('businessId', actors.B1.businessId), equalFilter('isAvailable', true)]);
    // Act
    const result = await request('POST', `${DOCS}:runQuery`, actors.U1, body);
    // Assert
    const rows = documents(result);
    assert.equal(rows.length, 1); assert.equal(rows[0].name, `${ROOT}/${f.product}`);
    assert.equal(rows[0].fields.isAvailable.booleanValue, true);
    assert.deepEqual(await stored(f.product), f.productData);
  });
});
test('API-02 | Cola de cocina aislada por negocio', async () => {
  // Arrange
  await withFixture('pending', async f => {
    const body = query('orders', [equalFilter('businessId', actors.B1.businessId), equalFilter('status', 'pending')]);
    // Act
    const result = await request('POST', `${DOCS}:runQuery`, actors.B1, body);
    // Assert
    const rows = documents(result);
    assert.equal(rows.length, 1); assert.equal(rows[0].name, `${ROOT}/${f.order}`);
    assert.equal(rows[0].fields.businessId.stringValue, actors.B1.businessId);
    assert.equal(rows[0].fields.status.stringValue, 'pending');
    assert.deepEqual(await stored(f.order), f.orderData);
  });
});
test('API-03 | Creacion atomica del pedido y vaciado de carrito', async () => {
  // Arrange
  await withFixture('pending', async f => {
    const body = commitBody(f);
    // Act
    const result = await request('POST', `${DOCS}:commit`, actors.U1, body);
    // Assert
    assert.equal(result.status, 200); assert.equal(result.json.writeResults.length, 2);
    assert.equal(typeof result.json.commitTime, 'string');
    const saved = await stored(f.created);
    assert.equal(saved.status, 'pending'); assert.equal(saved.userId, actors.U1.uid);
    assert.equal(saved.businessId, actors.B1.businessId); assert.equal(saved.totalPrice, 70);
    assert.deepEqual(saved.items, f.orderData.items); assert.ok(saved.createdAt instanceof Timestamp);
    assert.equal(await stored(f.cart), undefined);
  });
});
for (const [id, label, actorName] of [
  ['API-04','Lectura anonima denegada',null],
  ['API-05','Lectura de otro negocio denegada','B2'],
  ['REG-05','Lectura de otro usuario denegada','U2'],
]) {
  test(`${id} | ${label}`, async () => {
    // Arrange
    await withFixture('pending', async f => {
      const beforeValue = await stored(f.order);
      // Act
      const result = await request('GET', `${DOCS}/${f.order}`, actorName ? actors[actorName] : null);
      // Assert
      denied(result); assert.equal(result.json.fields, undefined);
      assert.deepEqual(await stored(f.order), beforeValue);
    });
  });
}
for (const [id, initial, target] of [
  ['API-06','pending','preparing'], ['API-10','preparing','cancelled'],
  ['REG-01','preparing','ready'], ['REG-02','ready','completed'],
]) {
  test(`${id} | Cocina permite ${initial} a ${target}`, async () => {
    // Arrange
    await withFixture(initial, async f => {
      // Act
      const result = await patch(f.order, actors.B1, {status: target});
      // Assert
      assert.equal(result.status, 200); assert.equal(result.json.fields.status.stringValue, target);
      const saved = await stored(f.order); assert.equal(saved.status, target); immutable(f.orderData, saved);
    });
  });
}
for (const [id, label, initial, actorName, changes] of [
  ['API-07','Usuario no ejecuta cocina','pending','U1',{status:'preparing'}],
  ['API-08','Estado terminal no retrocede','completed','B1',{status:'preparing'}],
  ['API-11','Pedido ready no se cancela','ready','B1',{status:'cancelled'}],
  ['API-12','Importe protegido al cambiar estado','pending','B1',{status:'preparing',totalPrice:1}],
  ['REG-03','No saltar directamente a ready','pending','B1',{status:'ready'}],
  ['REG-04','Otro negocio no modifica el pedido','pending','B2',{status:'preparing'}],
]) {
  test(`${id} | ${label}`, async () => {
    // Arrange
    await withFixture(initial, async f => {
      const beforeValue = await stored(f.order);
      // Act
      const result = await patch(f.order, actors[actorName], changes);
      // Assert
      denied(result); assert.deepEqual(await stored(f.order), beforeValue);
    });
  });
}
test('API-09 | Disponibilidad del producto propio', async () => {
  // Arrange
  await withFixture('pending', async f => {
    // Act
    const result = await patch(f.product, actors.B1, {isAvailable: false});
    // Assert
    assert.equal(result.status, 200); assert.equal(result.json.fields.isAvailable.booleanValue, false);
    assert.deepEqual(await stored(f.product), {...f.productData, isAvailable:false});
  });
});
test('REG-06 | Crear pedido de otro usuario se rechaza sin borrar carrito', async () => {
  // Arrange
  await withFixture('pending', async f => {
    const body = commitBody(f, {userId: actors.U2.uid});
    const cartBefore = await stored(f.cart);
    // Act
    const result = await request('POST', `${DOCS}:commit`, actors.U1, body);
    // Assert
    denied(result); assert.equal(await stored(f.created), undefined);
    assert.deepEqual(await stored(f.cart), cartBefore);
  });
});
