/**
 * SnackUP — pruebas HTTP reales contra Firestore Emulator.
 * NO es un backend nuevo ni un simulador de respuestas de éxito.
 * Arrange y oráculo persistido: Security Rules Unit Testing (bypass SOLO local).
 * Act: fetch REST con ID token de Firebase Auth Emulator (sin bypass).
 * Assert: HTTP + contenido + persistencia. Cada caso prepara/limpia sus datos.
 * Instalar dependencias y copiar reglas reales según README antes de ejecutar.
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

function fields(value) {
  return Object.fromEntries(Object.entries(value).map(([key, v]) => [key, encode(v)]));
}
function encode(value) {
  if (value === null) return {nullValue: null};
  if (value instanceof Date) return {timestampValue: value.toISOString()};
  if (typeof value === 'boolean') return {booleanValue: value};
  if (typeof value === 'string') return {stringValue: value};
  if (typeof value === 'number') {
    assert.ok(Number.isFinite(value), 'Valor numérico finito requerido');
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
  const res = await fetch(url, {
    method, headers, redirect: 'error',
    body: body === undefined ? undefined : JSON.stringify(body),
    signal: AbortSignal.timeout(10000),
  });
  const text = await res.text();
  let json;
  try { json = text ? JSON.parse(text) : null; }
  catch { throw new Error(`Respuesta HTTP ${res.status} no JSON`); }
  return {status: res.status, json};
}
async function seed(path, data) {
  paths.add(path);
  return env.withSecurityRulesDisabled(async ctx => setDoc(doc(ctx.firestore(), path), data));
}
async function stored(path) {
  return env.withSecurityRulesDisabled(async ctx => {
    const snap = await getDoc(doc(ctx.firestore(), path));
    return snap.exists() ? snap.data() : undefined;
  });
}
async function cleanup(selected) {
  if (!env) return;
  await env.withSecurityRulesDisabled(async ctx => {
    for (const path of selected) {
      await deleteDoc(doc(ctx.firestore(), path));
      paths.delete(path);
    }
  });
}
async function createActor(label, role) {
  const email = `${label}-${randomUUID()}@example.test`;
  const res = await request('POST', `${AUTH}/accounts:signUp?key=fake-api-key`, null, {
    email, password: `Qa!${randomUUID()}`, returnSecureToken: true,
  });
  assert.equal(res.status, 200, `Auth Emulator no pudo crear ${label}`);
  assert.equal(typeof res.json.idToken, 'string');
  const actor = {uid: res.json.localId, idToken: res.json.idToken, email};
  if (role === 'business') actor.businessId = `qa-business-${randomUUID()}`;
  actors[label] = actor;
  await seed(`users/${actor.uid}`, {
    role, displayName: `QA ${label}`, email, numeroDeControl: 'QA0001',
  });
  if (role === 'business') {
    await seed(`businesses/${actor.businessId}`, {ownerId: actor.uid, name: `QA ${label}`});
  }
  return actor;
}
before(async () => {
  const configured = process.env.GCLOUD_PROJECT || PROJECT;
  assertDemoProject(configured);
  const rules = await readFile(new URL('./firestore.rules', import.meta.url), 'utf8');
  assertRulesReady(rules);
  env = await initializeTestEnvironment({
    projectId: PROJECT,
    firestore: {host: '127.0.0.1', port: 8080, rules},
  });
  await createActor('U1', 'user');
  await createActor('U2', 'user');
  await createActor('B1', 'business');
  await createActor('B2', 'business');
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
  if (errors.length) throw new AggregateError(errors, 'Fallos de limpieza del entorno de pruebas');
});
async function fixture(state = 'pending') {
  const prefix = `qa-${randomUUID()}`;
  const f = {
    product: `products/${prefix}-p1`, product2: `products/${prefix}-p2`,
    order: `orders/${prefix}-o1`, order2: `orders/${prefix}-o2`,
    cart: `users/${actors.U1.uid}/cart/${prefix}-c1`, created: `orders/${prefix}-new`,
  };
  f.productData = {
    businessId: actors.B1.businessId, name: 'Café QA', description: 'Producto sintético',
    price: 35, stock: 10, isAvailable: true, isFeatured: false,
    category: 'Bebidas', imageUrl: '',
  };
  const item = {
    productId: f.product.split('/').at(-1), name: 'Café QA',
    quantity: 2, price: 35, notes: 'Sin azúcar (QA)',
  };
  f.orderData = {
    businessId: actors.B1.businessId, userId: actors.U1.uid, userDisplayName: 'QA U1',
    userNumeroDeControl: 'QA0001', status: state, totalPrice: 70,
    paymentMethod: 'Efectivo', createdAt: Timestamp.fromDate(new Date('2026-09-29T12:00:00Z')),
    scheduledPickupTime: null, items: [item],
  };
  await seed(f.product, f.productData);
  await seed(f.product2, {...f.productData, businessId: actors.B2.businessId, name: 'Café B2 QA'});
  await seed(f.order, f.orderData);
  await seed(f.order2, {...f.orderData, businessId: actors.B2.businessId, userId: actors.U2.uid});
  await seed(f.cart, {...item, businessId: actors.B1.businessId});
  paths.add(f.created);
  return f;
}
async function withFixture(state, fn) {
  const f = await fixture(state);
  try { await fn(f); }
  finally { await cleanup([f.product, f.product2, f.order, f.order2, f.cart, f.created]); }
}
function equalFilter(fieldPath, value) {
  return {fieldFilter: {field: {fieldPath}, op: 'EQUAL', value: encode(value)}};
}
function query(collectionId, filters) {
  return {structuredQuery: {
    from: [{collectionId}],
    where: {compositeFilter: {op: 'AND', filters}},
    limit: 20,
  }};
}
function documents(result) {
  assert.equal(result.status, 200);
  assert.ok(Array.isArray(result.json), 'runQuery debe devolver una matriz JSON');
  return result.json.filter(row => row.document).map(row => row.document);
}
function assertDenied(result) {
  assert.equal(result.status, 403);
  assert.equal(result.json?.error?.status, 'PERMISSION_DENIED');
}
function patchUrl(path, keys) {
  const url = new URL(`${DOCS}/${path}`);
  for (const key of keys) url.searchParams.append('updateMask.fieldPaths', key);
  url.searchParams.set('currentDocument.exists', 'true');
  return url.toString();
}
async function patch(path, actor, changes) {
  return request('PATCH', patchUrl(path, Object.keys(changes)), actor, {fields: fields(changes)});
}
function immutable(original, actual) {
  for (const key of ['userId','businessId','totalPrice','items','createdAt','paymentMethod']) {
    assert.deepEqual(actual[key], original[key], `Cambió el campo protegido ${key}`);
  }
}

test('API-01 | Menú: consulta solo productos disponibles del negocio solicitado', async () => {
  // Arrange
  await withFixture('pending', async f => {
    const body = query('products', [equalFilter('businessId', actors.B1.businessId), equalFilter('isAvailable', true)]);
    // Act
    const result = await request('POST', `${DOCS}:runQuery`, actors.U1, body);
    // Assert
    const rows = documents(result);
    assert.equal(rows.length, 1);
    assert.equal(rows[0].name, `${ROOT}/${f.product}`);
    assert.equal(rows[0].fields.isAvailable.booleanValue, true);
    assert.deepEqual(await stored(f.product), f.productData);
  });
});
test('API-02 | Cocina: cola pending del propio negocio sin pedidos ajenos', async () => {
  // Arrange
  await withFixture('pending', async f => {
    const body = query('orders', [equalFilter('businessId', actors.B1.businessId), equalFilter('status', 'pending')]);
    // Act
    const result = await request('POST', `${DOCS}:runQuery`, actors.B1, body);
    // Assert
    const rows = documents(result);
    assert.equal(rows.length, 1);
    assert.equal(rows[0].name, `${ROOT}/${f.order}`);
    assert.equal(rows[0].fields.businessId.stringValue, actors.B1.businessId);
    assert.equal(rows[0].fields.status.stringValue, 'pending');
  });
});
test('API-03 | Usuario: creación atómica de pedido y vaciado del ítem del carrito', async () => {
  // Arrange
  await withFixture('pending', async f => {
    const {createdAt, ...order} = f.orderData;
    const body = {writes: [
      {update: {name: `${ROOT}/${f.created}`, fields: fields(order)},
       updateTransforms: [{fieldPath: 'createdAt', setToServerValue: 'REQUEST_TIME'}],
       currentDocument: {exists: false}},
      {delete: `${ROOT}/${f.cart}`, currentDocument: {exists: true}},
    ]};
    // Act
    const result = await request('POST', `${DOCS}:commit`, actors.U1, body);
    // Assert
    assert.equal(result.status, 200);
    assert.equal(result.json.writeResults.length, 2);
    assert.equal(typeof result.json.commitTime, 'string');
    const saved = await stored(f.created);
    assert.equal(saved.status, 'pending');
    assert.equal(saved.userId, actors.U1.uid);
    assert.equal(saved.businessId, actors.B1.businessId);
    assert.equal(saved.totalPrice, 70);
    assert.deepEqual(saved.items, order.items);
    assert.ok(saved.createdAt instanceof Timestamp);
    assert.equal(await stored(f.cart), undefined);
  });
});
test('API-04 | Privacidad: lectura anónima del pedido denegada', async () => {
  // Arrange
  await withFixture('pending', async f => {
    const before = await stored(f.order);
    // Act
    const result = await request('GET', `${DOCS}/${f.order}`, null);
    // Assert
    assertDenied(result);
    assert.equal(result.json.fields, undefined);
    assert.deepEqual(await stored(f.order), before);
  });
});
test('API-05 | Aislamiento: negocio B2 no puede leer un pedido de B1', async () => {
  // Arrange
  await withFixture('pending', async f => {
    // Act
    const result = await request('GET', `${DOCS}/${f.order}`, actors.B2);
    // Assert
    assertDenied(result);
    assert.equal(result.json.fields, undefined);
    assert.deepEqual(await stored(f.order), f.orderData);
  });
});
test('API-06 | Cocina: pending a preparing sin alterar importe ni propietario', async () => {
  // Arrange
  await withFixture('pending', async f => {
    // Act
    const result = await patch(f.order, actors.B1, {status: 'preparing'});
    // Assert
    assert.equal(result.status, 200);
    assert.equal(result.json.fields.status.stringValue, 'preparing');
    const saved = await stored(f.order);
    assert.equal(saved.status, 'preparing');
    immutable(f.orderData, saved);
  });
});
test('API-07 | Autorización: un usuario no puede ejecutar acciones de cocina', async () => {
  // Arrange
  await withFixture('pending', async f => {
    const before = await stored(f.order);
    // Act
    const result = await patch(f.order, actors.U1, {status: 'preparing'});
    // Assert
    assertDenied(result);
    assert.deepEqual(await stored(f.order), before);
  });
});
test('API-08 | Estado terminal: completed no regresa a preparing', async () => {
  // Arrange
  await withFixture('completed', async f => {
    const before = await stored(f.order);
    // Act
    const result = await patch(f.order, actors.B1, {status: 'preparing'});
    // Assert
    assertDenied(result);
    assert.deepEqual(await stored(f.order), before);
  });
});
test('API-09 | Disponibilidad: negocio marca su producto como no disponible', async () => {
  // Arrange
  await withFixture('pending', async f => {
    // Act
    const result = await patch(f.product, actors.B1, {isAvailable: false});
    // Assert
    assert.equal(result.status, 200);
    assert.equal(result.json.fields.isAvailable.booleanValue, false);
    assert.deepEqual(await stored(f.product), {...f.productData, isAvailable: false});
    // La propagación a la pantalla del usuario se comprueba en MOV-04, no aquí.
  });
});
test('API-10 | Cancelación: negocio cancela desde preparing', async () => {
  // Arrange
  await withFixture('preparing', async f => {
    // Act
    const result = await patch(f.order, actors.B1, {status: 'cancelled'});
    // Assert
    assert.equal(result.status, 200);
    assert.equal(result.json.fields.status.stringValue, 'cancelled');
    const saved = await stored(f.order);
    assert.equal(saved.status, 'cancelled');
    immutable(f.orderData, saved);
  });
});
test('API-11 | Cancelación: no se cancela un pedido que ya está ready', async () => {
  // Arrange
  await withFixture('ready', async f => {
    const before = await stored(f.order);
    // Act
    const result = await patch(f.order, actors.B1, {status: 'cancelled'});
    // Assert
    assertDenied(result);
    assert.deepEqual(await stored(f.order), before);
  });
});
test('API-12 | Integridad: cambiar estado no permite modificar totalPrice', async () => {
  // Arrange
  await withFixture('pending', async f => {
    const before = await stored(f.order);
    // Act
    const result = await patch(f.order, actors.B1, {status: 'preparing', totalPrice: 1});
    // Assert
    assertDenied(result);
    assert.deepEqual(await stored(f.order), before);
  });
});
