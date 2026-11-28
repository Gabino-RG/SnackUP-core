import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';

// Local emulator only: never sends test writes to the project's live database.
const host = process.env.FIRESTORE_EMULATOR_HOST ?? '127.0.0.1:8080';
assert.match(host, /^(127\.0\.0\.1|localhost):\d+$/);
const root = 'projects/demo-snackup-sprint9/databases/(default)/documents';
const base = 'http://' + host + '/v1/' + root;
const suffix = randomUUID();
const student = 'photo-student-' + suffix;
const manager = 'photo-manager-' + suffix;
const otherManager = 'photo-other-manager-' + suffix;
const business = 'photo-business-' + suffix;
const otherBusiness = 'photo-other-business-' + suffix;
const product = 'photo-product-' + suffix;
const maxBytes = 150 * 1024;

function token(uid) {
  const encode = (value) => Buffer.from(JSON.stringify(value)).toString('base64url');
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
  if (Buffer.isBuffer(value) || value instanceof Uint8Array) {
    return { bytesValue: Buffer.from(value).toString('base64') };
  }
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
const stamp = (fieldPath) => ({ fieldPath, setToServerValue: 'REQUEST_TIME' });
const write = (path, data, timestamp, patch = false) => ({
  update: { name: root + '/' + path, fields: fields(data) },
  ...(patch ? { updateMask: { fieldPaths: Object.keys(data) } } : {}),
  ...(timestamp ? { updateTransforms: [stamp(timestamp)] } : {}),
});
const remove = (path) => ({ delete: root + '/' + path });
const commit = (uid, ...writes) => request(uid, ':commit', { writes });
async function request(uid, path, data) {
  return fetch(base + path, {
    method: data ? 'POST' : 'GET',
    headers: {
      ...(uid ? { Authorization: 'Bearer ' + (uid === 'owner' ? uid : token(uid)) } : {}),
      'Content-Type': 'application/json',
    },
    body: data ? JSON.stringify(data) : undefined,
  });
}
async function expect(label, promise, status = 200) {
  const response = await promise;
  const body = await response.text();
  assert.equal(response.status, status, label + ' ' + body);
  console.log('OK ' + label);
  return body ? JSON.parse(body) : null;
}

const productData = {
  businessId: business, name: 'Agua', category: 'BEBIDAS', price: 24,
  stock: 4, isAvailable: true, isFeatured: false,
};
const jpeg = Buffer.from([0xff, 0xd8, 0xff, 0xd9]);
const photoData = { businessId: business, imageBytes: jpeg, contentType: 'image/jpeg' };
const photoWrite = (id, data = photoData, timestamp = 'updatedAt') =>
  write('productImages/' + id, data, timestamp);
const upload = (uid, id, data = photoData, timestamp = 'updatedAt') =>
  commit(uid, photoWrite(id, data, timestamp));
const read = (uid, id = product) => request(uid, '/productImages/' + id);
const deletePhoto = (uid, id = product) => commit(uid, remove('productImages/' + id));

await expect('preparar cuentas y negocios para fotos', commit('owner',
  write('users/' + student, { role: 'user', displayName: 'Estudiante', numeroDeControl: '1234' }),
  write('users/' + manager, { role: 'business' }),
  write('users/' + otherManager, { role: 'business' }),
  write('businesses/' + business, { ownerId: manager, isOpen: true }),
  write('businesses/' + otherBusiness, { ownerId: otherManager, isOpen: true })));

await expect('crear producto y foto en lote por su dueño', commit(manager,
  write('products/' + product, { ...productData, hasPhoto: true }), photoWrite(product)));
const stored = await expect('estudiante lee foto de producto disponible', read(student));
assert.equal(stored.fields.imageBytes.bytesValue, jpeg.toString('base64'));
await expect('dueño lee su foto', read(manager));
await expect('otro negocio lee foto del producto disponible', read(otherManager));
await expect('sin sesión no se leen fotos', read(null), 403);
await expect('estudiante no reemplaza fotos', upload(student, product), 403);
await expect('otro negocio no reemplaza fotos ajenas', upload(otherManager, product), 403);
await expect('sin sesión no se suben fotos', upload(null, product), 403);
await expect('no se permite enumerar toda la colección de fotos', request(student, ':runQuery', {
  structuredQuery: { from: [{ collectionId: 'productImages' }] },
}), 403);

await expect('dueño reemplaza una foto y conserva el mismo documento',
  upload(manager, product, { ...photoData, imageBytes: Buffer.from([0xff, 0xd8, 0x01, 0xff, 0xd9]) }));
await expect('se admite foto de exactamente 150 KiB',
  upload(manager, product, { ...photoData, imageBytes: Buffer.alloc(maxBytes, 1) }));
await expect('se rechaza foto mayor de 150 KiB',
  upload(manager, product, { ...photoData, imageBytes: Buffer.alloc(maxBytes + 1, 1) }), 403);
await expect('se rechaza imagen vacía',
  upload(manager, product, { ...photoData, imageBytes: Buffer.alloc(0) }), 403);
await expect('se rechaza texto en lugar de bytes',
  upload(manager, product, { ...photoData, imageBytes: jpeg.toString('base64') }), 403);
await expect('se rechaza tipo de contenido distinto de JPEG',
  upload(manager, product, { ...photoData, contentType: 'text/plain' }), 403);
await expect('se rechazan campos extra de foto',
  upload(manager, product, { ...photoData, unexpected: true }), 403);
const { contentType: ignored, ...missingMime } = photoData;
await expect('se rechaza foto sin tipo de contenido', upload(manager, product, missingMime), 403);
await expect('se rechaza foto sin fecha del servidor',
  upload(manager, product, photoData, null), 403);
await expect('se rechaza fecha escrita por cliente',
  upload(manager, product, { ...photoData, updatedAt: '2026-11-27' }, null), 403);
await expect('se rechaza cambio de negocio en una foto existente',
  upload(otherManager, product, { ...photoData, businessId: otherBusiness }), 403);
await expect('se rechaza foto sin producto asociado', upload(manager, 'missing-' + suffix), 403);

const otherProduct = 'other-product-' + suffix;
await expect('crear producto de otro negocio', commit(otherManager,
  write('products/' + otherProduct, { ...productData, businessId: otherBusiness })));
await expect('dueño no crea foto sobre un producto de otro negocio',
  upload(manager, otherProduct), 403);
await expect('dueño del otro negocio crea su foto',
  upload(otherManager, otherProduct, { ...photoData, businessId: otherBusiness }));

await expect('dueño oculta producto sin cambiar su foto', commit(manager,
  write('products/' + product, { isAvailable: false }, null, true)));
await expect('dueño lee foto de su producto oculto', read(manager));
await expect('estudiante no lee foto de producto oculto', read(student), 403);
await expect('otro negocio no lee foto de producto oculto', read(otherManager), 403);
await expect('otro negocio no elimina foto ajena', deletePhoto(otherManager), 403);
await expect('estudiante no elimina foto', deletePhoto(student), 403);
await expect('dueño elimina foto y marca producto sin foto en lote', commit(manager,
  write('products/' + product, { hasPhoto: false }, null, true),
  remove('productImages/' + product)));
await expect('foto eliminada ya no existe', read('owner'), 404);
await expect('dueño puede volver a crear la foto', upload(manager, product));
await expect('dueño elimina producto y foto en el mismo lote', commit(manager,
  remove('products/' + product), remove('productImages/' + product)));
await expect('producto eliminado ya no existe', request('owner', '/products/' + product), 404);
await expect('foto de producto eliminado tampoco existe', read('owner'), 404);

const legacy = 'legacy-product-' + suffix;
await expect('se conserva alta de producto anterior sin hasPhoto', commit(manager,
  write('products/' + legacy, { ...productData, imageUrl: 'https://example.com/old.jpg' })));
await expect('se conserva edición de producto anterior sin foto', commit(manager,
  write('products/' + legacy, { price: 25 }, null, true)));
await expect('se rechaza indicador hasPhoto de tipo incorrecto', commit(manager,
  write('products/invalid-photo-flag-' + suffix, { ...productData, hasPhoto: 'yes' })), 403);
await expect('se permite quitar foto inexistente de producto anterior', commit(manager,
  write('products/' + legacy, { hasPhoto: false, imageUrl: null }, null, true),
  remove('productImages/' + legacy)));
await expect('otro negocio no elimina foto inexistente de producto ajeno',
  deletePhoto(otherManager, legacy), 403);
await expect('se permite borrar producto anterior con foto inexistente', commit(manager,
  remove('products/' + legacy), remove('productImages/' + legacy)));

const orphan = 'orphan-photo-' + suffix;
await expect('preparar foto huérfana para limpieza', commit('owner', photoWrite(orphan)));
await expect('foto huérfana no es visible a estudiante', read(student, orphan), 403);
await expect('no se puede actualizar foto sin su producto', upload(manager, orphan), 403);
await expect('otro negocio no limpia foto huérfana ajena', deletePhoto(otherManager, orphan), 403);
await expect('su dueño puede limpiar foto huérfana', deletePhoto(manager, orphan));
