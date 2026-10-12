import {test} from 'node:test';
import assert from 'node:assert/strict';
import {accessPlan, adminClaims, executePlan} from './provision_access.mjs';
const base=['--project=snackup-8fe96','--uid=qa-user','--email=QA@example.test','--role=admin'];
test('dry-run is the default and normalizes expected email',()=> {
  const plan=accessPlan(base);
  assert.equal(plan.apply,false); assert.equal(plan.email,'qa@example.test');
});
test('apply requires matching explicit target confirmation',()=> {
  assert.throws(()=>accessPlan([...base,'--apply']));
  assert.throws(()=>accessPlan([...base,'--apply','--confirm-project=other']));
  assert.equal(accessPlan([...base,'--apply','--confirm-project=snackup-8fe96']).apply,true);
});
test('invalid uid/role/unknown args fail before SDK access',()=> {
  assert.throws(()=>accessPlan(base.map(x=>x.startsWith('--uid')?'--uid=bad/path':x)));
  assert.throws(()=>accessPlan(base.map(x=>x.startsWith('--role')?'--role=superuser':x)));
  assert.throws(()=>accessPlan([...base,'--credential=secret']));
});
test('business provisioning requires explicit nonempty business identity',()=> {
  const args=base.map(x=>x.startsWith('--role')?'--role=business':x);
  assert.throws(()=>accessPlan(args));
  assert.equal(accessPlan([...args,'--business-id=local-1','--name=Local real']).businessId,'local-1');
});
test('admin grant and revoke preserve unrelated custom claims',()=> {
  const old={subscription:'campus',staff:true};
  assert.deepEqual(adminClaims(old,true), {...old,admin:true});
  assert.deepEqual(adminClaims({...old,admin:true},false),old);
  assert.deepEqual(old,{subscription:'campus',staff:true});
});
test('dry-run cannot enter network execution boundary',async()=> {
  await assert.rejects(executePlan(accessPlan(base)),/requiere/);
});

