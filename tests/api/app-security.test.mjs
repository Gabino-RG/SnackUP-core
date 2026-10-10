/**
 * Integrated app rules contract, SOURCE ONLY until an approved emulator run.
 * Never starts emulators. Skipped unless SNACKUP_APP_RULES_LOCAL=1.
 * Not wired into CI; no Firebase runtime verification is claimed for this change.
 */
import {after, before, describe, test} from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {initializeTestEnvironment, assertFails, assertSucceeds} from '@firebase/rules-unit-testing';
import {doc, setDoc, updateDoc, deleteDoc, getDoc, serverTimestamp, Timestamp, writeBatch} from 'firebase/firestore';
import {assertDemoProject, assertLocalEndpoint, assertRulesReady} from './guard.mjs';

const projectId='demo-snackup-qa', prefix='app-contract-'+randomUUID();
const uid=prefix+'-student', ownerId=prefix+'-owner', adminId=prefix+'-admin';
let env, student, owner, outsider, admin;
const paths=new Set();
let seq=0;
async function seed(path,data) {
  paths.add(path);
  await env.withSecurityRulesDisabled(async ctx=>{await setDoc(doc(ctx.firestore(),path),data);});
}
async function fixture(count=1,{open=true}={}) {
  const key=prefix+'-'+(++seq), businessId=key+'-business', orderId=key+'-order';
  await seed('businesses/'+businessId,{ownerId,name:'Local sintético',isOpen:open});
  const items=[];
  for(let i=0;i<count;i++){
    const productId=key+'-product-'+i;
    const product={businessId,name:'Producto '+i,name_searchable:'producto '+i,description:'QA',category:'TEST',
      priceCents:3517,price:35.17,stock:10,isAvailable:true,isFeatured:false,imageUrl:null};
    await seed('products/'+productId,product);
    items.push({productId,name:product.name,quantity:2,price:35.17,unitPriceCents:3517,notes:''});
  }
  const totalCents=items.reduce((sum,item)=>sum+item.unitPriceCents*item.quantity,0);
  const data={businessId,userId:uid,userDisplayName:'Alumno de prueba',userNumeroDeControl:'0000000000',
    status:'pending',schemaVersion:2,items,totalCents,totalPrice:totalCents/100,paymentMethod:'Efectivo',
    pickupCode:'0123456789abcdef0123456789abcdef',scheduledPickupTime:null,createdAt:serverTimestamp()};
  paths.add('orders/'+orderId);
  return {businessId,orderId,data,ref:doc(student,'orders/'+orderId)};
}
async function persistedOrder(f,status='pending'){
  await seed('orders/'+f.orderId,{...f.data,status,createdAt:Timestamp.now(),...(status==='pending'?{}:{stockReserved:true})});
}
async function reviewFixture(){
  const f=await fixture(); await persistedOrder(f,'completed');
  await seed('reviews/'+f.orderId,{businessId:f.businessId,userId:uid,orderId:f.orderId,rating:1,serviceRating:1,
    foodRating:2,career:'',group:'',comment:'Reseña sintética',schemaVersion:2,createdAt:Timestamp.now()});
  return f;
}
function followup(f,eventId){
  return {reviewId:f.orderId,businessId:f.businessId,status:'in_review',assignee:'Responsable QA',note:'Acuerdo QA',
    eventId,updatedBy:adminId,updatedAt:serverTimestamp()};
}
function auditBatch(f,eventId,values=followup(f,eventId)){
  const parent='admin_followups/'+f.orderId, event=parent+'/history/'+eventId;
  paths.add(parent); paths.add(event);
  const batch=writeBatch(admin); batch.set(doc(admin,parent),values); batch.set(doc(admin,event),values); return batch;
}

describe('Integrated app security — opt-in loopback only',{skip:process.env.SNACKUP_APP_RULES_LOCAL!=='1',concurrency:false},()=>{
  before(async()=>{
    assertDemoProject(projectId); assertDemoProject(process.env.GCLOUD_PROJECT||projectId);
    assertLocalEndpoint('http://127.0.0.1:8080');
    assert.ok(!process.env.FIRESTORE_EMULATOR_HOST||process.env.FIRESTORE_EMULATOR_HOST==='127.0.0.1:8080');
    const rules=await readFile(new URL('../../app/firestore.rules',import.meta.url),'utf8');
    assertRulesReady(rules);
    env=await initializeTestEnvironment({projectId,firestore:{host:'127.0.0.1',port:8080,rules}});
    student=env.authenticatedContext(uid,{email:'student@utsjr.edu.mx'}).firestore();
    owner=env.authenticatedContext(ownerId).firestore();
    outsider=env.authenticatedContext(prefix+'-outsider').firestore();
    admin=env.authenticatedContext(adminId,{admin:true}).firestore();
  });
  after(async()=>{
    if(!env)return;
    try{await env.withSecurityRulesDisabled(async ctx=>{
      for(const path of [...paths].reverse())await deleteDoc(doc(ctx.firestore(),path));
    });}finally{await env.cleanup();}
  });

  for(const count of [1,8]){
    test('accepts exact catalog prices for '+count+' unique lines within rule lookup budget',async()=>{
      const f=await fixture(count);
      await assertSucceeds(setDoc(f.ref,f.data));
      assert.equal((await getDoc(f.ref)).data().totalCents,7034*count);
    });
  }
  test('rejects nine lines',async()=>{
    const f=await fixture(9); await assertFails(setDoc(f.ref,f.data));
  });
  test('rejects tampered total even when both submitted totals agree',async()=>{
    const f=await fixture();
    await assertFails(setDoc(f.ref,{...f.data,totalCents:1,totalPrice:.01}));
  });
  test('rejects tampered line price even with internally matching totals',async()=>{
    const f=await fixture(); const items=[{...f.data.items[0],unitPriceCents:1,price:.01}];
    await assertFails(setDoc(f.ref,{...f.data,items,totalCents:2,totalPrice:.02}));
  });
  test('rejects duplicate products, fractional quantities and excess stock',async()=>{
    const f=await fixture();
    await assertFails(setDoc(f.ref,{...f.data,items:[...f.data.items,...f.data.items],totalCents:14068,totalPrice:140.68}));
    await assertFails(setDoc(f.ref,{...f.data,items:[{...f.data.items[0],quantity:1.5}]}));
    await assertFails(setDoc(f.ref,{...f.data,items:[{...f.data.items[0],quantity:11}],totalCents:38687,totalPrice:386.87}));
  });
  test('rejects closed business and unavailable product',async()=>{
    const f=await fixture(1,{open:false}); await assertFails(setDoc(f.ref,f.data));
    const g=await fixture(); await seed('products/'+g.data.items[0].productId,{
      businessId:g.businessId,name:g.data.items[0].name,price:35.17,priceCents:3517,stock:10,isAvailable:false});
    await assertFails(setDoc(g.ref,g.data));
  });
  test('rejects foreign business product or spoofed display name',async()=>{
    const f=await fixture(),g=await fixture();
    await assertFails(setDoc(f.ref,{...f.data,items:g.data.items}));
    await assertFails(setDoc(f.ref,{...f.data,items:[{...f.data.items[0],name:'Falso'}]}));
  });
  test('valid legacy two-decimal price works without cents; inconsistent cents do not',async()=>{
    const f=await fixture(),item=f.data.items[0];
    await seed('products/'+item.productId,{businessId:f.businessId,name:item.name,price:35.17,stock:10,isAvailable:true});
    await assertSucceeds(setDoc(f.ref,f.data));
    const g=await fixture(),other=g.data.items[0];
    await seed('products/'+other.productId,{businessId:g.businessId,name:other.name,price:35.17,priceCents:1,stock:10,isAvailable:true});
    await assertFails(setDoc(g.ref,{...g.data,items:[{...other,unitPriceCents:1,price:.01}],totalCents:2,totalPrice:.02}));
  });
  test('rejects past schedule and invalid pickup code',async()=>{
    const f=await fixture();
    await assertFails(setDoc(f.ref,{...f.data,scheduledPickupTime:Timestamp.fromMillis(0)}));
    await assertFails(setDoc(f.ref,{...f.data,pickupCode:'matricula'}));
  });
  test('student cannot alter order status or stock',async()=>{
    const f=await fixture(); await persistedOrder(f);
    await assertFails(updateDoc(f.ref,{status:'preparing',stockReserved:true,updatedAt:serverTimestamp()}));
    await assertFails(updateDoc(doc(student,'products/'+f.data.items[0].productId),{stock:8,updatedAt:serverTimestamp()}));
  });
  test('only owner accepts order and reserves its own product stock atomically',async()=>{
    const f=await fixture(); await persistedOrder(f);
    const batch=writeBatch(owner);
    batch.update(doc(owner,'products/'+f.data.items[0].productId),{stock:8,updatedAt:serverTimestamp()});
    batch.update(doc(owner,'orders/'+f.orderId),{status:'preparing',stockReserved:true,updatedAt:serverTimestamp()});
    await assertSucceeds(batch.commit());
    await assertFails(updateDoc(doc(outsider,'orders/'+f.orderId),{status:'ready',updatedAt:serverTimestamp()}));
    await assertSucceeds(updateDoc(doc(owner,'orders/'+f.orderId),{status:'ready',updatedAt:serverTimestamp()}));
    await assertSucceeds(updateDoc(doc(owner,'orders/'+f.orderId),{status:'completed',updatedAt:serverTimestamp(),completedAt:serverTimestamp()}));
    await assertFails(updateDoc(doc(owner,'orders/'+f.orderId),{status:'pending',updatedAt:serverTimestamp()}));
  });
  test('owner cannot change price or customer while changing an order status',async()=>{
    const f=await fixture(); await persistedOrder(f);
    await assertFails(updateDoc(doc(owner,'orders/'+f.orderId),{status:'preparing',stockReserved:true,updatedAt:serverTimestamp(),totalPrice:1}));
    await assertFails(updateDoc(doc(owner,'orders/'+f.orderId),{status:'preparing',stockReserved:true,updatedAt:serverTimestamp(),userId:ownerId}));
  });
  test('public profile creation accepts only student role and never mutable admin',async()=>{
    const ref=doc(student,'users/'+uid); paths.add('users/'+uid);
    const data={role:'user',email:'student@utsjr.edu.mx',displayName:'Alumno QA',numeroDeControl:'0000000000',
      createdAt:serverTimestamp(),privacyAcceptedAt:serverTimestamp(),privacyVersion:'2'};
    await assertFails(setDoc(ref,{...data,role:'business'}));
    await assertFails(setDoc(ref,{...data,role:'admin'}));
    await assertFails(setDoc(ref,{...data,admin:true}));
    await assertSucceeds(setDoc(ref,data));
    await assertFails(updateDoc(ref,{role:'business'}));
    await assertFails(updateDoc(ref,{admin:true}));
  });
  test('parent follow-up cannot be written without matching new history',async()=>{
    const f=await reviewFixture(); const parent='admin_followups/'+f.orderId; paths.add(parent);
    await assertFails(setDoc(doc(admin,parent),followup(f,'event-one')));
    await assertSucceeds(auditBatch(f,'event-one').commit());
    await assertFails(setDoc(doc(admin,parent),{...followup(f,'event-one'),note:'Sin nuevo evento'}));
    await assertSucceeds(auditBatch(f,'event-two',{...followup(f,'event-two'),status:'resolved'}).commit());
    await assertFails(getDoc(doc(student,parent)));
  });
  test('history cannot be forged alone, edited or deleted',async()=>{
    const f=await reviewFixture(); const path='admin_followups/'+f.orderId+'/history/first';paths.add(path);
    await assertFails(setDoc(doc(admin,path),followup(f,'first')));
    await assertSucceeds(auditBatch(f,'first').commit());
    await assertFails(updateDoc(doc(admin,path),{note:'Alterado'}));
    await assertFails(deleteDoc(doc(admin,path)));
  });
  test('forged order ID never confers access to an existing foreign review',async()=>{
    const f=await fixture();
    // A valid order is owned by the student, while an imported historical
    // random-ID review at the same document ID belongs to someone else.
    await seed('reviews/'+f.orderId,{userId:prefix+'-other',businessId:f.businessId,orderId:'historical-order'});
    await assertSucceeds(setDoc(f.ref,f.data));
    await assertFails(getDoc(doc(student,'reviews/'+f.orderId)));
  });
  test('student cannot take over a business, create catalog products or read arbitrary chats',async()=>{
    const f=await fixture();
    await assertFails(updateDoc(doc(student,'businesses/'+f.businessId),{ownerId:uid}));
    await assertFails(setDoc(doc(student,'products/'+prefix+'-forged'),{businessId:f.businessId}));
    await assertFails(getDoc(doc(student,'chats/any-chat')));
  });
});

