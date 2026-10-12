/**
 * Candidate-only authorization contract. NOT wired into CI or production.
 * No emulator is started and no Firebase endpoint is contacted by default.
 * Run only after the local-emulator workflow has independent authorization:
 * SNACKUP_ADMIN_RULES_LOCAL=1 node --test --test-concurrency=1 admin-monitoring.test.mjs
 * Requires an already running Firestore emulator at 127.0.0.1:8080.
 * This suite is source-reviewed only until an emulator run is explicitly recorded.
 */
import {after, before, describe, test} from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {initializeTestEnvironment, assertFails, assertSucceeds} from '@firebase/rules-unit-testing';
import {
  collection, deleteDoc, doc, getDoc, getDocs, orderBy, query,
  serverTimestamp, setDoc, Timestamp, where, writeBatch,
} from 'firebase/firestore';
import {assertDemoProject, assertLocalEndpoint, assertRulesReady} from './guard.mjs';

const enabled = process.env.SNACKUP_ADMIN_RULES_LOCAL === '1';
const projectId = 'demo-snackup-qa';
const prefix = `admin-contract-${randomUUID()}`;
const paths = new Set();
let env;
let student;
let otherStudent;
let admin;
let profileAdmin;
let stringClaimAdmin;
let anonymous;
let sequence = 0;

function remember(path) { paths.add(path); return path; }
async function seed(path, data) {
  remember(path);
  await env.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), path), data);
  });
}

async function fixture({status = 'completed', userId = `${prefix}-student`} = {}) {
  const orderId = `${prefix}-${++sequence}`;
  await seed(`orders/${orderId}`, {userId, businessId: `${prefix}-business`, status});
  remember(`reviews/${orderId}`);
  const payload = {
    businessId: `${prefix}-business`, userId, orderId,
    rating: 3, serviceRating: 2, foodRating: 4,
    career: 'Tecnologías de la Información', group: 'DS02SV-26',
    comment: 'Comentario sintético de contrato', createdAt: serverTimestamp(), schemaVersion: 2,
  };
  return {orderId, payload, ref: doc(student, `reviews/${orderId}`)};
}

async function seededReview() {
  const f = await fixture();
  await seed(`reviews/${f.orderId}`, {...f.payload, createdAt: Timestamp.now()});
  return f;
}

function followup(f) {
  return {
    reviewId: f.orderId, businessId: f.payload.businessId, status: 'in_review',
    assignee: 'Responsable de prueba', note: 'Revisar tiempo de atención',
    updatedAt: serverTimestamp(), updatedBy: `${prefix}-admin`,
  };
}

describe('Administrative monitoring candidate — local emulator only', {skip: !enabled, concurrency: false}, () => {
  before(async () => {
    assertDemoProject(projectId);
    assertDemoProject(process.env.GCLOUD_PROJECT || projectId);
    assertLocalEndpoint('http://127.0.0.1:8080');
    assert.ok(!process.env.FIRESTORE_EMULATOR_HOST || process.env.FIRESTORE_EMULATOR_HOST === '127.0.0.1:8080', 'Unexpected emulator host');
    const rules = await readFile(new URL('./candidates/admin-monitoring.rules', import.meta.url), 'utf8');
    assertRulesReady(rules);
    env = await initializeTestEnvironment({projectId, firestore: {host: '127.0.0.1', port: 8080, rules}});
    student = env.authenticatedContext(`${prefix}-student`).firestore();
    otherStudent = env.authenticatedContext(`${prefix}-other`).firestore();
    admin = env.authenticatedContext(`${prefix}-admin`, {admin: true}).firestore();
    profileAdmin = env.authenticatedContext(`${prefix}-profile-admin`).firestore();
    stringClaimAdmin = env.authenticatedContext(`${prefix}-string-admin`, {admin: 'true'}).firestore();
    anonymous = env.unauthenticatedContext().firestore();
    await seed(`users/${prefix}-profile-admin`, {role: 'admin'});
  });

  after(async () => {
    if (!env) return;
    try {
      await env.withSecurityRulesDisabled(async (context) => {
        for (const path of [...paths].reverse()) await deleteDoc(doc(context.firestore(), path));
      });
    } finally { await env.cleanup(); }
  });

  test('owner can read an empty deterministic slot and create a completed-order review', async () => {
    // Arrange
    const f = await fixture();
    // Act / Assert
    assert.equal((await assertSucceeds(getDoc(f.ref))).exists(), false);
    await assertSucceeds(setDoc(f.ref, f.payload));
    assert.equal((await getDoc(f.ref)).data().orderId, f.orderId);
  });

  test('duplicate update is denied even for the same owner', async () => {
    const f = await seededReview();
    await assertFails(setDoc(f.ref, {...f.payload, rating: 1}));
    assert.equal((await getDoc(f.ref)).data().rating, 3);
  });

  test('a different student cannot create or read another student review', async () => {
    const f = await fixture();
    await assertFails(setDoc(doc(otherStudent, `reviews/${f.orderId}`), {...f.payload, userId: `${prefix}-other`}));
    await assertFails(getDoc(doc(otherStudent, `reviews/${f.orderId}`)));
  });

  test('forging an order with a legacy review ID cannot disclose another student review', async () => {
    // Arrange: a historical random-ID review with a different order ID/owner.
    const f = await fixture({userId: `${prefix}-other`});
    const legacyId = `${f.orderId}-legacy`;
    await seed(`reviews/${legacyId}`, {...f.payload, createdAt: Timestamp.now()});
    remember(`orders/${legacyId}`);
    // Act: legacy order rules allow a client-chosen new ID. It must not confer
    // ownership of an existing review document at that coinciding ID.
    await assertSucceeds(setDoc(doc(student, `orders/${legacyId}`), {
      userId: `${prefix}-student`, businessId: f.payload.businessId, status: 'pending',
    }));
    // Assert: the existing review owner, not the forged order owner, controls read.
    await assertFails(getDoc(doc(student, `reviews/${legacyId}`)));
    await assertSucceeds(getDoc(doc(otherStudent, `reviews/${legacyId}`)));
  });

  for (const status of ['pending', 'preparing', 'ready', 'cancelled']) {
    test(`review requires completed order, not ${status}`, async () => {
      const f = await fixture({status});
      await assertFails(setDoc(f.ref, f.payload));
    });
  }

  test('student cannot substitute business or deterministic order ID', async () => {
    const f = await fixture();
    await assertFails(setDoc(f.ref, {...f.payload, businessId: 'another-business'}));
    await assertFails(setDoc(f.ref, {...f.payload, orderId: 'another-order'}));
  });

  for (const [field, value] of [
    ['rating', 0], ['serviceRating', 6], ['foodRating', 3.5], ['rating', '5'],
    ['schemaVersion', 1], ['career', 'x'.repeat(121)], ['group', 'x'.repeat(41)],
    ['comment', 'x'.repeat(1501)], ['createdAt', Timestamp.fromMillis(0)],
  ]) {
    test(`invalid ${field} is rejected`, async () => {
      const f = await fixture();
      await assertFails(setDoc(f.ref, {...f.payload, [field]: value}));
    });
  }

  test('new reviews reject unnecessary identifying fields', async () => {
    const f = await fixture();
    await assertFails(setDoc(f.ref, {...f.payload, userName: 'Synthetic student'}));
    await assertFails(setDoc(f.ref, {...f.payload, email: 'synthetic@example.test'}));
  });

  test('only boolean admin claim can list reviews across the campus', async () => {
    await seededReview();
    await assertSucceeds(getDocs(query(collection(admin, 'reviews'), orderBy('__name__'))));
    for (const db of [student, profileAdmin, stringClaimAdmin, anonymous]) {
      await assertFails(getDocs(collection(db, 'reviews')));
    }
  });

  test('student can query own review history but cannot query another owner', async () => {
    await seededReview();
    await assertSucceeds(getDocs(query(collection(student, 'reviews'), where('userId', '==', `${prefix}-student`))));
    await assertFails(getDocs(query(collection(student, 'reviews'), where('userId', '==', `${prefix}-other`))));
  });

  test('legacy duplicate preflight can query own owner plus order fields', async () => {
    const f = await fixture();
    const legacyPath = `reviews/${f.orderId}-legacy-random-id`;
    await seed(legacyPath, {...f.payload, createdAt: Timestamp.now()});
    const result = await assertSucceeds(getDocs(query(collection(student, 'reviews'),
      where('userId', '==', `${prefix}-student`), where('orderId', '==', f.orderId))));
    assert.equal(result.size, 1);
    assert.equal(result.docs[0].id, `${f.orderId}-legacy-random-id`);
  });

  test('admin saves follow-up and matching immutable history atomically', async () => {
    const f = await seededReview();
    const parentPath = remember(`admin_followups/${f.orderId}`);
    const historyPath = remember(`${parentPath}/history/first`);
    const values = followup(f);
    const batch = writeBatch(admin);
    batch.set(doc(admin, parentPath), values);
    batch.set(doc(admin, historyPath), values);
    await assertSucceeds(batch.commit());
    assert.equal((await getDoc(doc(admin, historyPath))).data().status, 'in_review');
    await assertFails(setDoc(doc(admin, historyPath), {...values, note: 'Altered'}));
    await assertFails(deleteDoc(doc(admin, historyPath)));
    await assertFails(getDoc(doc(student, parentPath)));
    await assertFails(getDoc(doc(student, historyPath)));
  });

  test('profile admin and ordinary student cannot create follow-ups', async () => {
    const f = await seededReview();
    const path = remember(`admin_followups/${f.orderId}`);
    for (const db of [profileAdmin, student]) await assertFails(setDoc(doc(db, path), followup(f)));
  });

  test('follow-up rejects mismatched business, actor and unsupported status', async () => {
    const f = await seededReview();
    const path = remember(`admin_followups/${f.orderId}`);
    const ref = doc(admin, path);
    const values = followup(f);
    await assertFails(setDoc(ref, {...values, businessId: 'other-business'}));
    await assertFails(setDoc(ref, {...values, updatedBy: 'forged-admin'}));
    await assertFails(setDoc(ref, {...values, status: 'erased'}));
  });

  test('history rejects a different event payload from the current follow-up', async () => {
    const f = await seededReview();
    const parentPath = remember(`admin_followups/${f.orderId}`);
    const historyPath = remember(`${parentPath}/history/mismatch`);
    const values = followup(f);
    const batch = writeBatch(admin);
    batch.set(doc(admin, parentPath), values);
    batch.set(doc(admin, historyPath), {...values, note: 'Different note'});
    await assertFails(batch.commit());
    assert.equal((await getDoc(doc(admin, parentPath))).exists(), false);
  });
});
