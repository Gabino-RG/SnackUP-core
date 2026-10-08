'use strict';
// Artificial fixtures exercise refusal and timeline rules only. Never video evidence.
const test = require('node:test');
const assert = require('node:assert/strict');
const {validateEvidence, projectState, redact, scene} = require('./record_part2.cjs');

function fixture(failure = false) {
  const stages = ['checkout', 'analyze', 'unit', 'sonar-scan', 'quality-gate', failure ? 'controlled-failure' : 'artifact', 'notification'].map((id, index) => ({
    id, name:id, status:failure && index === 5 ? 'failure' : !failure && index === 6 ? 'skipped' : 'success',
    started_at:new Date(Date.UTC(2026, 9, 8, 12, 0, index * 10)).toISOString(),
    completed_at:new Date(Date.UTC(2026, 9, 8, 12, 0, index * 10 + 9)).toISOString(), logs:[`TEST FIXTURE ONLY ${id}`]
  }));
  const run_id = failure ? 102 : 101;
  return {state:{repository:'fixture/never-publish', run_id, sha:'a'.repeat(40), url:`https://github.com/fixture/never-publish/actions/runs/${run_id}`, status:'completed', conclusion:failure ? 'failure' : 'success', stages, artifacts:[], decisions:[]}, sonar:{analysis_id:'FIXTURE-ONLY-ANALYSIS', gate_status:'OK', scan_executed:true}, notification:failure ? {status:'DELIVERED', provider:'discord', acknowledgement:'discord_created_message', http_status:200, message_id:'1234567890123456789', run_id, repository:'fixture/never-publish', commit:'a'.repeat(40)} : {status:'SKIPPED'}};
}

test('completed fixtures satisfy the expected metadata schema', () => {
  assert.equal(validateEvidence(fixture(), 'success').gateIndexes[0], 4);
  assert.equal(validateEvidence(fixture(true), 'failure').notificationIndexes[0], 6);
});
test('configuration-only and skipped scans cannot count as successful Sonar evidence', () => {
  const bundle = fixture(); bundle.sonar.scan_executed = false;
  assert.throws(() => validateEvidence(bundle, 'success'), /no demuestra ejecutar/);
  bundle.sonar.scan_executed = true; bundle.state.stages[3].name = 'Check Sonar credentials'; bundle.state.stages[3].id = 'config';
  assert.throws(() => validateEvidence(bundle, 'success'), /no hay etapa SonarQube/);
});
test('a non-OK real Quality Gate blocks approved evidence', () => {
  const bundle = fixture(); bundle.sonar.gate_status = 'ERROR';
  assert.throws(() => validateEvidence(bundle, 'success'), /debe devolver OK/);
});
test('a successful process without provider acknowledgement cannot prove a notification', () => {
  const bundle = fixture(true); bundle.notification.status = 'FAILED';
  assert.throws(() => validateEvidence(bundle, 'failure'), /DELIVERED/);
  bundle.notification.status = 'DELIVERED'; bundle.notification.http_status = 500;
  assert.throws(() => validateEvidence(bundle, 'failure'), /HTTP 2xx/);
});
test('Discord needs the actual created message and receipt must match the run', () => {
  const bundle = fixture(true); delete bundle.notification.message_id;
  assert.throws(() => validateEvidence(bundle, 'failure'), /mensaje real creado/);
  bundle.notification.message_id = '1234567890123456789'; bundle.notification.run_id = 999;
  assert.throws(() => validateEvidence(bundle, 'failure'), /otra ejecución/);
});
test('Slack HTTP success must also acknowledge the expected provider body', () => {
  const bundle = fixture(true); bundle.notification.provider = 'slack'; bundle.notification.acknowledgement = 'unverified';
  assert.throws(() => validateEvidence(bundle, 'failure'), /confirmación HTTP 200/);
  bundle.notification.acknowledgement = 'slack_ok';
  assert.equal(validateEvidence(bundle, 'failure').notificationIndexes[0], 6);
});
test('notification before the failure is not failure-triggered evidence', () => {
  const bundle = fixture(true); bundle.state.stages[6].started_at = bundle.state.stages[1].started_at;
  assert.throws(() => validateEvidence(bundle, 'failure'), /precede al fallo/);
});
test('timeline never reveals future logs or results and continues observing notification', () => {
  const source = fixture(true).state;
  let projected = projectState(source, 45).state;
  assert.equal(projected.stages[4].status, 'running');
  assert.deepEqual(projected.stages[4].logs, []);
  assert.equal(projected.stages[6].status, 'pending');
  assert.equal(projected.conclusion, null);
  projected = projectState(source, 65).state;
  assert.equal(projected.stages[5].status, 'failure');
  assert.equal(projected.stages[6].status, 'running');
  assert.equal(projected.status, 'running');
  assert.equal(projectState(source, Infinity).state.conclusion, 'failure');
});
test('skipped stages stay skipped at the end and closing scene uses approved run', () => {
  const success = fixture();
  assert.equal(projectState(success.state, Infinity).state.stages[6].status, 'skipped');
  assert.equal(scene(79, {success, failure:fixture(true)}).key, 'success');
});
test('webhook URLs and Sonar credentials cannot enter screenshots or output manifest', () => {
  const sanitized = redact({token:'never-print', logs:['https://hooks.slack.com/services/T/B/secret', 'https://discord.com/api/webhooks/123/secret?wait=true', '-Dsonar.token=squ_123abc', 'Authorization: Bearer confidential']});
  assert(!JSON.stringify(sanitized).includes('never-print'));
  assert(!JSON.stringify(sanitized).includes('confidential'));
  assert(!JSON.stringify(sanitized).includes('https://hooks.slack.com'));
  assert(!JSON.stringify(sanitized).includes('https://discord.com'));
  assert(!JSON.stringify(sanitized).includes('squ_123abc'));
});
