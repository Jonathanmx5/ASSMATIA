// Tests des règles Firestore (émulateur). Lancer : npm test
import { readFileSync } from 'node:fs';
import { after, before, beforeEach, test } from 'node:test';
import { assertFails, assertSucceeds, initializeTestEnvironment } from '@firebase/rules-unit-testing';
import { doc, getDoc, setDoc, deleteDoc, collection, query, where, getDocs } from 'firebase/firestore';

let env;
const NANNY = 'nanny1', OTHER = 'nanny2';
const PARENT_EMAIL = 'parent@example.com';

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-assmatia',
    firestore: { rules: readFileSync(new URL('../firestore.rules', import.meta.url), 'utf8') },
  });
});
after(() => env.cleanup());

beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, 'users', NANNY), { role: 'nanny' });
    await setDoc(doc(db, 'users', OTHER), { role: 'nanny' });
    await setDoc(doc(db, 'users', 'p1'), { role: 'parent' });
    await setDoc(doc(db, 'children', 'k1'), { nannyId: NANNY, firstName: 'Lina', parentEmails: [PARENT_EMAIL] });
    await setDoc(doc(db, 'contracts', 'c1'), { nannyId: NANNY, childId: 'k1' });
    await setDoc(doc(db, 'taxScales', '2026'), { nannyId: NANNY, year: 2026 });
    await setDoc(doc(db, 'sharedPlannings', 'k1'), { nannyId: NANNY, childId: 'k1', parentEmails: [PARENT_EMAIL] });
    await setDoc(doc(db, 'monthlySummaries', 'k1_2026-03'), { nannyId: NANNY, childId: 'k1', parentEmails: [PARENT_EMAIL] });
    await setDoc(doc(db, 'monthlySummaries', 'k2_2026-03'), { nannyId: NANNY, childId: 'k2', parentEmails: ['autre@example.com'] });
  });
});

const nanny = () => env.authenticatedContext(NANNY, { email: 'n@example.com', email_verified: true }).firestore();
const other = () => env.authenticatedContext(OTHER, { email: 'o@example.com', email_verified: true }).firestore();
const parent = (verified = true) =>
  env.authenticatedContext('p1', { email: PARENT_EMAIL, email_verified: verified }).firestore();

test('assmat : lit et écrit ses propres données', async () => {
  await assertSucceeds(getDoc(doc(nanny(), 'contracts', 'c1')));
  await assertSucceeds(setDoc(doc(nanny(), 'dailyLogs', 'x'), { nannyId: NANNY, childId: 'k1' }));
  await assertSucceeds(setDoc(doc(nanny(), 'leavePeriods', 'l'), { nannyId: NANNY }));
});

test('assmat : ne peut pas écrire au nom d\'une autre', async () => {
  await assertFails(setDoc(doc(nanny(), 'contracts', 'z'), { nannyId: OTHER }));
  await assertFails(setDoc(doc(other(), 'contracts', 'c1'), { nannyId: OTHER, childId: 'k1' }));
  await assertFails(getDoc(doc(other(), 'contracts', 'c1')));
});

test('parent vérifié : lit le planning et les récaps de son enfant', async () => {
  await assertSucceeds(getDoc(doc(parent(), 'sharedPlannings', 'k1')));
  const q = query(collection(parent(), 'monthlySummaries'), where('parentEmails', 'array-contains', PARENT_EMAIL));
  const s = await assertSucceeds(getDocs(q));
  if (s.size !== 1) throw new Error(`attendu 1 récap, reçu ${s.size}`);
});

test('parent : pas d\'accès aux autres enfants', async () => {
  await assertFails(getDoc(doc(parent(), 'monthlySummaries', 'k2_2026-03')));
  await assertFails(getDocs(collection(parent(), 'monthlySummaries')));
});

test('parent : aucune donnée privée ni fiscale', async () => {
  for (const [c, id] of [['children', 'k1'], ['contracts', 'c1'], ['taxScales', '2026']]) {
    await assertFails(getDoc(doc(parent(), c, id)));
  }
});

test('parent : aucune écriture', async () => {
  await assertFails(setDoc(doc(parent(), 'sharedPlannings', 'k1'), { nannyId: 'p1', parentEmails: [PARENT_EMAIL] }));
  await assertFails(setDoc(doc(parent(), 'monthlySummaries', 'new'), { nannyId: 'p1' }));
  await assertFails(deleteDoc(doc(parent(), 'monthlySummaries', 'k1_2026-03')));
  await assertFails(setDoc(doc(parent(), 'children', 'k1'), { nannyId: 'p1', parentEmails: [PARENT_EMAIL] }));
});

test('e-mail non vérifié : aucun accès', async () => {
  await assertFails(getDoc(doc(parent(false), 'sharedPlannings', 'k1')));
});

test('rôle : fixé à la création, non modifiable', async () => {
  await assertFails(setDoc(doc(parent(), 'users', 'p1'), { role: 'nanny' }));
  const fresh = env.authenticatedContext('new', { email: 'x@example.com', email_verified: true }).firestore();
  await assertSucceeds(setDoc(doc(fresh, 'users', 'new'), { role: 'parent' }));
  await assertFails(setDoc(doc(fresh, 'users', 'someoneElse'), { role: 'nanny' }));
});

test('suppression de compte : profil supprimable par son titulaire', async () => {
  await assertSucceeds(deleteDoc(doc(parent(), 'users', 'p1')));
});
