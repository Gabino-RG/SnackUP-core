import assert from 'node:assert/strict';

export const PROJECT = 'demo-snackup-qa';

export function assertDemoProject(value = PROJECT) {
  assert.equal(value, PROJECT, 'BLOQUEADO: solo se permite demo-snackup-qa');
  return value;
}

export function assertLocalEndpoint(value) {
  const url = new URL(value);
  assert.equal(url.protocol, 'http:', 'Solo HTTP local del emulador');
  assert.equal(url.hostname, '127.0.0.1', 'BLOQUEADO: destino no local');
  assert.ok(['8080', '9099'].includes(url.port), 'Puerto no autorizado');
  assert.equal(url.username, '', 'No se permiten credenciales en la URL');
  assert.equal(url.password, '', 'No se permiten credenciales en la URL');
  return url;
}

export function assertRulesReady(rules) {
  assert.equal(typeof rules, 'string');
  assert.ok(rules.trim().length > 0, 'BLOQUEADO: reglas vacias');
  assert.ok(!rules.includes('SNACKUP_RULES_PENDING'),
    'BLOQUEADO: falta la copia autorizada de las reglas de SnackUP');
  assert.ok(rules.includes('service cloud.firestore'),
    'BLOQUEADO: no es un archivo de reglas de Firestore');
  return true;
}
