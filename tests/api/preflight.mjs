import {readFile, mkdir, writeFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {assertDemoProject, assertLocalEndpoint, assertRulesReady, PROJECT} from './guard.mjs';

const directory = new URL('./reports/', import.meta.url);
const report = {timestamp: new Date().toISOString(), scope: 'preflight-no-functional-test',
  project: PROJECT, commit: process.env.GITHUB_SHA || null, node: process.version,
  status: 'BLOCKED', reason: null, rulesSha256: null, restCasesExecuted: 0};
try {
  assertDemoProject(process.env.GCLOUD_PROJECT || PROJECT);
  assertLocalEndpoint('http://127.0.0.1:8080');
  assertLocalEndpoint('http://127.0.0.1:9099');
  const rules = await readFile(new URL('./firestore.rules', import.meta.url), 'utf8');
  assertRulesReady(rules);
  report.rulesSha256 = createHash('sha256').update(rules).digest('hex');
  report.status = 'READY';
  report.reason = 'Precondiciones verificadas; todavia no se ha ejecutado REST.';
} catch (error) {
  report.reason = error.message;
  process.exitCode = 1;
}
await mkdir(directory, {recursive: true});
await writeFile(new URL('preflight.json', directory), JSON.stringify(report, null, 2) + '\n');
console.log(JSON.stringify(report, null, 2));
