import {test} from 'node:test';
import assert from 'node:assert/strict';
import {assertDemoProject, assertLocalEndpoint, assertRulesReady} from './guard.mjs';

// Estas pruebas validan el aislamiento del kit, NO los 12 casos REST.
for (const port of [8080, 9099]) {
  test(`GUARD permite emulador local ${port}`, () => {
    const url = `http://127.0.0.1:${port}/v1/example`;
    const parsed = assertLocalEndpoint(url);
    assert.equal(parsed.port, String(port));
  });
}
for (const url of [
  'https://firestore.googleapis.com/v1/projects/production',
  'http://example.com:8080/test',
  'http://127.0.0.1:8000/test',
  'https://127.0.0.1:8080/test',
  'http://user:password@127.0.0.1:8080/test',
  'http://127.0.0.1.example.com:8080/test',
  'http://localhost:8080/test',
]) {
  test(`GUARD rechaza ${url}`, () => assert.throws(() => assertLocalEndpoint(url)));
}
test('GUARD permite proyecto demo exacto', () => {
  assert.equal(assertDemoProject('demo-snackup-qa'), 'demo-snackup-qa');
});
test('GUARD rechaza proyecto real', () => {
  assert.throws(() => assertDemoProject('snackup-8fe96'));
});
test('GUARD rechaza marcador de reglas pendientes', () => {
  assert.throws(() => assertRulesReady('// SNACKUP_RULES_PENDING'));
});
test('GUARD rechaza archivo vacio', () => assert.throws(() => assertRulesReady('')));
test('GUARD rechaza archivo ajeno a Firestore', () => {
  assert.throws(() => assertRulesReady('not a rules file'));
});
test('GUARD acepta estructura minima, sin acreditar permisos', () => {
  const candidate = 'service cloud.firestore { match /databases/{db}/documents { match /{d=**} { allow read, write: if false; } } }';
  assert.equal(assertRulesReady(candidate), true);
});
