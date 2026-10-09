#!/usr/bin/env node
// Trusted operator utility. Dry-run performs no imports of Firebase and no network.
import {parseArgs} from 'node:util';
import {pathToFileURL} from 'node:url';

export function accessPlan(argv) {
  const {values} = parseArgs({args: argv, strict: true, options: {
    project: {type:'string'}, uid: {type:'string'}, email: {type:'string'},
    role: {type:'string'}, 'business-id': {type:'string'}, name: {type:'string'},
    apply: {type:'boolean', default:false}, 'confirm-project': {type:'string'},
    help: {type:'boolean', default:false},
  }});
  if (values.help) return {help:true};
  if (!/^[a-z][a-z0-9-]{4,28}[a-z0-9]$/.test(values.project ?? '')) throw new Error('Indica --project con el ID explícito del proyecto.');
  if (!/^[^/\s]{1,128}$/.test(values.uid ?? '')) throw new Error('Indica --uid de una cuenta existente.');
  const email = (values.email ?? '').trim().toLowerCase();
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) throw new Error('Indica --email para comprobar que el UID corresponde a la cuenta prevista.');
  if (!['admin','business','revoke-admin'].includes(values.role)) throw new Error('--role debe ser admin, business o revoke-admin.');
  const businessId = values['business-id'];
  const name = (values.name ?? '').trim();
  if (values.role === 'business' && (!/^[A-Za-z0-9_-]{1,128}$/.test(businessId ?? '') || !name || name.length > 160)) {
    throw new Error('Para negocio indica --business-id y --name (máximo 160 caracteres).');
  }
  if (values.role !== 'business' && (businessId || name)) throw new Error('Los datos de negocio solo corresponden a --role=business.');
  if (values.apply && values['confirm-project'] !== values.project) throw new Error('--apply requiere --confirm-project igual a --project.');
  return {project:values.project, uid:values.uid, email, role:values.role, businessId, name, apply:values.apply};
}

export function adminClaims(previous, enabled) {
  const next = {...(previous ?? {})};
  if (enabled) next.admin = true;
  else delete next.admin;
  return next;
}

export async function executePlan(plan) {
  // This explicit boundary is never entered by dry-run or by the offline tests.
  if (!plan.apply) throw new Error('La ejecución requiere un plan --apply validado.');
  if (process.env.FIREBASE_AUTH_EMULATOR_HOST || process.env.FIRESTORE_EMULATOR_HOST) {
    throw new Error('Este script de aprovisionamiento no acepta redirecciones a emuladores.');
  }
  const {initializeApp, applicationDefault, deleteApp} = await import('firebase-admin/app');
  const {getAuth} = await import('firebase-admin/auth');
  const app = initializeApp({projectId:plan.project, credential:applicationDefault()}, 'snackup-access-operator');
  try {
    const auth = getAuth(app);
    const user = await auth.getUser(plan.uid);
    if (user.disabled) throw new Error('La cuenta está deshabilitada.');
    if ((user.email ?? '').toLowerCase() !== plan.email) throw new Error('El correo del UID no coincide; no se aplicó ningún cambio.');
    if (plan.role === 'business') {
      const {getFirestore, FieldValue} = await import('firebase-admin/firestore');
      const db = getFirestore(app);
      const profileRef = db.collection('users').doc(plan.uid);
      const businessRef = db.collection('businesses').doc(plan.businessId);
      await db.runTransaction(async transaction => {
        const [profile, business] = await Promise.all([transaction.get(profileRef), transaction.get(businessRef)]);
        if (business.exists && business.data().ownerId !== plan.uid) {
          throw new Error('El negocio ya pertenece a otra cuenta; no se transfiere su propiedad.');
        }
        const timestamp = FieldValue.serverTimestamp();
        transaction.set(profileRef, {
          role:'business', email:plan.email,
          displayName:profile.data()?.displayName || user.displayName || plan.name,
          ...(profile.exists ? {} : {createdAt:timestamp}),
        }, {merge:true});
        // Re-running access provisioning must not close an existing operating shop.
        transaction.set(businessRef, {
          ownerId:plan.uid, name:plan.name,
          ...(business.exists ? {} : {isOpen:false, createdAt:timestamp}),
        }, {merge:true});
      });
    } else {
      await auth.setCustomUserClaims(plan.uid, adminClaims(user.customClaims, plan.role === 'admin'));
      if (plan.role === 'revoke-admin') await auth.revokeRefreshTokens(plan.uid);
    }
    return {applied:true, project:plan.project, uid:plan.uid, role:plan.role};
  } finally { await deleteApp(app); }
}

const help = `Aprovisionamiento SnackUP para TI (cuentas Auth existentes).
Por defecto: muestra un plan local, sin conexiones ni cambios.

node provision_access.mjs --project=snackup-8fe96 --uid=UID --email=cuenta@ejemplo.mx --role=admin
node provision_access.mjs --project=snackup-8fe96 --uid=UID --email=cuenta@ejemplo.mx --role=business --business-id=local-1 --name="Nombre real"
Roles: admin, business, revoke-admin.
Para aplicar un plan revisado: añade --apply --confirm-project=snackup-8fe96.
Requiere Firebase Admin SDK y credenciales ADC de TI. Nunca incluir claves en el repo.
`;

export async function main(argv=process.argv.slice(2)) {
  const plan=accessPlan(argv);
  if(plan.help) {console.log(help); return;}
  if(!plan.apply) {
    console.log(JSON.stringify({...plan, mode:'PLAN LOCAL · SIN CAMBIOS'}, null, 2));
    return;
  }
  console.log(JSON.stringify(await executePlan(plan), null, 2));
}
if(process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch(error => {console.error(error.message); process.exitCode=1;});
}

