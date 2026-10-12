import base64
import concurrent.futures
import http.cookiejar
import json
from pathlib import Path
import tempfile
import threading
import unittest
import urllib.error
import urllib.request
from review_server import ReviewServer, Store, PASSWORD

class Client:
    def __init__(self,url):
        self.url=url;self.token='';self.cookies=http.cookiejar.CookieJar();self.opener=urllib.request.build_opener(urllib.request.HTTPCookieProcessor(self.cookies))
    def call(self,method,path,data=None,headers=None,raw=None):
        req=urllib.request.Request(self.url+'/api/v1/'+path,data=raw if raw is not None else json.dumps(data or {}).encode() if method!='GET' else None,
            headers={'Content-Type':'application/json',**({'Authorization':'Bearer '+self.token} if self.token else {}),**(headers or {})},method=method)
        try:res=self.opener.open(req,timeout=10)
        except urllib.error.HTTPError as e:res=e
        body=res.read();return res.status,json.loads(body) if body else None
    def login(self,email='negocio@snackup.test',password=PASSWORD):
        status,body=self.call('POST','auth/login',{'email':email,'password':password});assert status==200,body;self.token=body['tokens']['accessToken'];return body

class ReviewTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.root=Path(self.temp.name);(self.root/'web').mkdir();(self.root/'web'/'index.html').write_text('ok')
        self.server=ReviewServer(('127.0.0.1',0),self.root/'web',self.root/'data');self.server.store.seed_test_fixtures();self.server.store.migrate_institution();self.thread=threading.Thread(target=self.server.serve_forever,daemon=True);self.thread.start()
        self.client=Client(f'http://127.0.0.1:{self.server.server_port}');self.client.login()
    def tearDown(self):
        self.server.shutdown();self.server.server_close();self.thread.join();self.server.store.db.close();self.temp.cleanup()
    def test_auth_scope_rotation_and_logout(self):
        self.assertEqual(self.client.call('GET','admin/users')[0],403)
        self.assertEqual(self.client.call('GET','businesses/antojitos/orders/active')[0],403)
        cookie=next(iter(self.client.cookies)).value
        status,result=self.client.call('POST','auth/refresh');self.assertEqual(status,200);self.assertNotEqual(next(iter(self.client.cookies)).value,cookie)
        self.client.token=result['tokens']['accessToken'];self.assertEqual(self.client.call('POST','auth/logout')[0],204)
        self.assertEqual(self.client.call('POST','auth/refresh')[0],401)
    def test_snapshot_stock_conflict_and_verified_workflow(self):
        _,products=self.client.call('GET','businesses/central/products');p=products['data'][0]
        _,ticket=self.client.call('POST','review/orders',{'businessId':'central'})
        _,active=self.client.call('GET','businesses/central/orders/active');order=next(o for o in active['data'] if o['orderNumber']==ticket['orderNumber'])
        self.assertNotIn('pickupCode',order);self.assertNotIn('customerNumeroDeControl',order)
        self.assertEqual(self.client.call('PATCH','products/'+p['id'],{**p,'price':99,'expectedVersion':p['version']})[0],409)
        _,fresh=self.client.call('GET','products/'+p['id']);self.assertEqual(fresh['stock'],p['stock']-1)
        self.assertEqual(self.client.call('PATCH','products/'+p['id'],{**fresh,'price':99,'expectedVersion':fresh['version']})[0],200)
        for action in ('accept','start','ready'):
            status,order=self.client.call('POST','orders/'+order['id']+'/'+action,{'expectedVersion':order['version']});self.assertEqual(status,200);self.assertEqual(order['total'],p['price'])
        self.assertEqual(self.client.call('POST','orders/'+order['id']+'/cancel',{'expectedVersion':order['version'],'reason':'store_closing'})[0],400)
        self.assertEqual(self.client.call('POST','orders/'+order['id']+'/complete',{'expectedVersion':order['version'],'method':'manual','code':'wrong'})[0],422)
        status,done=self.client.call('POST','orders/'+order['id']+'/complete',{'expectedVersion':order['version'],'method':'qr','code':ticket['pickupCode']});self.assertEqual(status,200);self.assertEqual(done['status'],'completed')
    def test_concurrent_accept_only_one_wins(self):
        _,rows=self.client.call('GET','businesses/central/orders/active');o=next(o for o in rows['data'] if o['status']=='pending')
        def accept(_):
            c=Client(self.client.url);c.token=self.client.token;return c.call('POST','orders/'+o['id']+'/accept',{'expectedVersion':o['version']})[0]
        with concurrent.futures.ThreadPoolExecutor(max_workers=2) as executor:codes=list(executor.map(accept,range(2)))
        self.assertEqual(sorted(codes),[200,409])
    def test_cancellation_refunds_stock_once_and_requires_other_note(self):
        _,ticket=self.client.call('POST','review/orders',{'businessId':'central'});_,rows=self.client.call('GET','businesses/central/orders/active');o=next(r for r in rows['data'] if r['orderNumber']==ticket['orderNumber'])
        pid=o['items'][0]['productId'];_,p=self.client.call('GET','products/'+pid)
        self.assertEqual(self.client.call('POST','orders/'+o['id']+'/cancel',{'expectedVersion':o['version'],'reason':'other'})[0],422)
        self.assertEqual(self.client.call('POST','orders/'+o['id']+'/cancel',{'expectedVersion':o['version'],'reason':'other','notes':'Prueba de cancelación'})[0],200)
        self.assertEqual(self.client.call('POST','orders/'+o['id']+'/cancel',{'expectedVersion':o['version'],'reason':'other','notes':'Prueba'})[0],409)
        _,after=self.client.call('GET','products/'+pid);self.assertEqual(after['stock'],p['stock']+1)
    def test_admin_creation_followup_and_account_revocation(self):
        admin=Client(self.client.url);admin.login('admin@snackup.test')
        _,b=admin.call('POST','admin/businesses',{'name':'Local nuevo','category':'Comida','description':'Nuevo','isActive':True})
        status,u=admin.call('POST','admin/users',{'displayName':'Nuevo operador','email':'nuevo@test.example','role':'business','businessId':b['id'],'password':'Clave-Prueba-123','isActive':True});self.assertEqual(status,201);self.assertNotIn('passwordHash',u)
        _,users=admin.call('GET','admin/users');owner=next(r for r in users['data'] if r['id']=='owner')
        self.assertEqual(admin.call('PATCH','admin/users/owner',{**owner,'isActive':False,'expectedVersion':owner['version']})[0],200)
        self.assertEqual(self.client.call('GET','users/me')[0],403)
        _,reviews=admin.call('GET','admin/reviews');r=reviews['data'][0]
        self.assertEqual(admin.call('GET','admin/reviews/'+r['id']+'/followup')[0],404)
        _,case=admin.call('PUT','admin/reviews/'+r['id']+'/followup',{'expectedVersion':0,'status':'in_review','assignee':'Juan','note':'Revisar con el local.'})
        self.assertEqual(case['version'],1)
        _,history=admin.call('GET','admin/reviews/'+r['id']+'/followup/history');self.assertEqual(len(history['data']),1)
    def test_persistence_images_and_origin_rejection(self):
        _,products=self.client.call('GET','businesses/central/products');p=products['data'][0]
        self.assertEqual(self.client.call('PATCH','products/'+p['id'],{**p,'price':93.5,'expectedVersion':p['version']})[0],200)
        other=Store(self.root/'data'/'revision.sqlite3');self.assertEqual(other.get('products',p['id'])['price'],93.5);other.db.close()
        image=base64.b64decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jGZkAAAAASUVORK5CYII=')
        raw=b'--TEST\r\nContent-Disposition: form-data; name="file"; filename="test.png"\r\nContent-Type: image/png\r\n\r\n'+image+b'\r\n--TEST--\r\n'
        status,media=self.client.call('POST','media',headers={'Content-Type':'multipart/form-data; boundary=TEST'},raw=raw)
        self.assertEqual(status,201);self.assertEqual(urllib.request.urlopen(media['url']).read(),image)
        self.assertEqual(self.client.call('POST','review/orders',{'businessId':'central'},headers={'Origin':'https://external.example'})[0],403)
        self.assertEqual(self.client.call('GET','users/me',headers={'Host':'external.example'})[0],403)
    def test_master_and_four_independent_local_accounts(self):
        master=Client(self.client.url);master.login('admin@snackup.test')
        _,profile=master.call('GET','users/me');self.assertTrue(profile['isMaster'])
        _,institution=master.call('GET','institution')
        _,locales=master.call('GET','admin/businesses')
        self.assertEqual(len(locales['data']),4)
        self.assertEqual({b['cafeteriaId'] for b in locales['data']},{institution['cafeteria']['id']})
        for email,bid in [('negocio','central'),('antojitos','antojitos'),('verde','verde'),('dulce','dulce')]:
            operator=Client(self.client.url);operator.login(email+'@snackup.test')
            _,profile=operator.call('GET','users/me');self.assertFalse(profile['isMaster'])
            self.assertEqual(profile['businessId'],bid)
            self.assertEqual(operator.call('GET','businesses/'+bid+'/orders/active')[0],200)
            other='central' if bid!='central' else 'verde'
            self.assertEqual(operator.call('GET','businesses/'+other+'/orders/active')[0],403)

    def test_master_enforces_institutional_email_and_cannot_be_promoted_or_disabled(self):
        master=Client(self.client.url);master.login('admin@snackup.test')
        payload={'displayName':'Administración académica','email':'persona@gmail.com','role':'admin','isActive':True,'password':'Clave-Prueba-123'}
        for email in ('persona@gmail.com','persona@utsjr.edu.mx.evil.example'):
            status,body=master.call('POST','admin/users',{**payload,'email':email})
            self.assertEqual((status,body['error']['code']),(422,'INSTITUTIONAL_EMAIL_REQUIRED'))
        self.assertEqual(master.call('POST','admin/users',{**payload,'email':'persona@utsjr.edu.mx','isMaster':True})[0],403)
        status,user=master.call('POST','admin/users',{**payload,'email':'persona@utsjr.edu.mx'})
        self.assertEqual(status,201);self.assertFalse(user['isMaster'])
        admin=Client(self.client.url);admin.login('persona@utsjr.edu.mx','Clave-Prueba-123')
        for path in ('admin/businesses','admin/reviews','admin/academic-catalog'):
            self.assertEqual(admin.call('GET',path)[0],200)
        self.assertEqual(admin.call('GET','admin/users')[0],403)
        self.assertEqual(admin.call('POST','admin/users',payload)[0],403)
        self.assertEqual(admin.call('PATCH','admin/users/'+user['id'],{**user,'isMaster':True,'expectedVersion':user['version']})[0],403)
        _,owner=master.call('GET','users/me')
        for changes in ({'isActive':False},{'role':'user'},{'isMaster':False}):
            self.assertEqual(master.call('PATCH','admin/users/admin',{**owner,**changes,'expectedVersion':owner['version']})[0],403)

    def test_academic_catalog_is_paged_and_independent_from_opinions(self):
        admin=Client(self.client.url);admin.login('admin@snackup.test')
        self.assertEqual(self.client.call('GET','admin/academic-catalog')[0],403)
        _,page=admin.call('GET','admin/academic-catalog?limit=4&page=1');entries=page['data']
        for number in range(2,page['pagination']['totalPages']+1):
            _,page=admin.call('GET',f'admin/academic-catalog?limit=4&page={number}');entries+=page['data']
        self.assertEqual(len(entries),21)
        self.assertEqual(len({e['id'] for e in entries}),21)
        self.assertIn('software-6',{e['id'] for e in entries if e.get('careerId')=='software'})
        _,reviews=admin.call('GET','admin/reviews')
        self.assertNotIn('software-6',{r['groupId'] for r in reviews['data']})
        with self.server.store.lock,self.server.store.db:
            self.server.store.put('academic_catalog',{'id':'software-100','kind':'group','name':'DSM-100','careerId':'software'})
        _,updated=admin.call('GET','admin/academic-catalog')
        self.assertIn('software-100',{e['id'] for e in updated['data']})

    def test_additive_migration_preserves_user_work_and_is_idempotent(self):
        store=self.server.store
        with store.lock,store.db:
            store.db.execute("DELETE FROM records WHERE kind='migrations'")
            business=store.get('businesses','central');store.put('businesses',{**business,'name':'Mi local editado'})
            product=store.get('products','central-p1');store.put('products',{**product,'price':123.45})
            password=store.get('users','admin')['passwordHash']
        store.migrate_institution()
        versions={u['id']:u['version'] for u in store.rows('users')}
        store.migrate_institution()
        self.assertEqual(versions,{u['id']:u['version'] for u in store.rows('users')})
        self.assertEqual(store.get('businesses','central')['name'],'Mi local editado')
        self.assertEqual(store.get('products','central-p1')['price'],123.45)
        self.assertEqual(store.get('users','admin')['passwordHash'],password)
        self.assertEqual(len(store.rows('users')),5)

class AccessFlowTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.root=Path(self.temp.name);(self.root/'web').mkdir();(self.root/'web'/'index.html').write_text('ok')
        self.server=ReviewServer(('127.0.0.1',0),self.root/'web',self.root/'data');self.thread=threading.Thread(target=self.server.serve_forever,daemon=True);self.thread.start()
        self.client=Client(f'http://127.0.0.1:{self.server.server_port}')
        self.master=Client(self.client.url);self.master.login('admin@snackup.test')
    tearDown=ReviewTests.tearDown
    def request(self,email='operador@example.test',**extra):
        return self.client.call('POST','auth/register',{'displayName':'Operador solicitado','email':email,'password':'Clave-Solicitada-123',
            'requestedRole':'business','context':'Trabajaré en el local que nos asigne la universidad.',**extra})
    def pending(self):
        return self.master.call('GET','admin/access-requests')[1]['data'][0]
    def local(self):
        return self.master.call('POST','admin/businesses',{'name':'Local creado por el equipo','category':'Comida','isActive':True})[1]
    def test_fresh_install_has_only_master_and_no_invented_records(self):
        store=self.server.store
        self.assertEqual([u['id'] for u in store.rows('users')],['admin'])
        for kind in ('businesses','products','orders','reviews','academic_catalog'):
            self.assertEqual(store.rows(kind),[],kind)
        _,options=self.client.call('GET','auth/options');self.assertEqual(options,{'passwordLogin':True,'selfRegistration':True,'googleEnabled':False})
        self.assertEqual(self.client.call('GET','auth/google/start')[0],503)
    def test_pending_and_rejected_requests_never_get_a_session(self):
        self.assertEqual(self.request()[0],202)
        status,result=self.client.call('POST','auth/login',{'email':'operador@example.test','password':'Clave-Solicitada-123'})
        self.assertEqual((status,result['error']['code']),(403,'ACCESS_PENDING'));self.assertEqual(len(self.client.cookies),0)
        self.assertNotIn('tokens',result);self.assertEqual(self.client.call('GET','admin/access-requests')[0],401)
        request=self.pending();self.assertNotIn('passwordHash',request)
        self.assertEqual(self.client.call('POST','admin/access-requests/'+request['id']+'/decision',{'decision':'approve'})[0],401)
        status,denied=self.master.call('POST','admin/access-requests/'+request['id']+'/decision',{'decision':'reject','expectedVersion':request['version']})
        self.assertEqual(status,200);self.assertFalse(denied['isActive'])
        status,result=self.client.call('POST','auth/login',{'email':'operador@example.test','password':'Clave-Solicitada-123'})
        self.assertEqual((status,result['error']['code']),(403,'ACCESS_REJECTED'))
        self.assertEqual(self.request(password='Otra-Contrasena-123')[0],202)
        status,result=self.client.call('POST','auth/login',{'email':'operador@example.test','password':'Otra-Contrasena-123'})
        self.assertEqual(status,401)
    def operator(self,business,email='operador@example.test'):
        status,user=self.master.call('POST','admin/users',{'displayName':'Operador','email':email,'role':'business','businessId':business['id'],'isActive':True,'password':'Clave-Prueba-123'})
        self.assertEqual(status,201)
        owner=Client(self.client.url);owner.login(email,'Clave-Prueba-123')
        return owner,user
    def test_master_and_admin_cannot_read_or_operate_kitchen_resources(self):
        b=self.local();bid=b['id'];owner,_=self.operator(b)
        self.master.call('POST','admin/users',{'displayName':'Admin','email':'admin2@utsjr.edu.mx','role':'admin','isActive':True,'password':'Clave-Prueba-123'})
        admin=Client(self.client.url);admin.login('admin2@utsjr.edu.mx','Clave-Prueba-123')
        status,p=owner.call('POST','businesses/'+bid+'/products',{'name':'Producto propio','category':'Comida','price':40,'isAvailable':True,'isFeatured':False})
        self.assertEqual(status,201)
        self.assertEqual(owner.call('PATCH','businesses/'+bid+'/status',{'isOpen':True,'expectedVersion':b['version']})[0],200)
        self.assertEqual(owner.call('POST','review/orders',{'businessId':bid})[0],201)
        _,active=owner.call('GET','businesses/'+bid+'/orders/active');order=active['data'][0]
        reads=['businesses/'+bid,'businesses/'+bid+'/products','businesses/'+bid+'/orders/active',
            'businesses/'+bid+'/orders/history?date=2026-10-12','businesses/'+bid+'/stats?from=2026-10-01&to=2026-10-31',
            'products/'+p['id'],'orders/'+order['id']]
        actions=[('GET',path,None) for path in reads]+[
            ('PATCH','businesses/'+bid,{**b,'name':'Cambio no autorizado','expectedVersion':2}),
            ('PATCH','businesses/'+bid+'/status',{'isOpen':False,'expectedVersion':2}),
            ('POST','businesses/'+bid+'/products',p),
            ('PATCH','products/'+p['id'],{**p,'price':99,'expectedVersion':p['version']}),
            ('DELETE','products/'+p['id'],{'expectedVersion':p['version']}),
            ('POST','review/orders',{'businessId':bid}),('POST','media',{})]
        actions += [('POST','orders/'+order['id']+'/'+action,{'expectedVersion':order['version']}) for action in ('accept','start','ready','complete','cancel')]
        before={kind:self.server.store.rows(kind) for kind in ('businesses','products','orders')}
        for account in (self.master,admin):
            for method,path,data in actions:
                with self.subTest(account=account is self.master,method=method,path=path):
                    status,body=account.call(method,path,data)
                    self.assertEqual((status,body['error']['code']),(403,'FORBIDDEN'))
            for path in ('admin/businesses','admin/reviews','admin/academic-catalog'):
                self.assertEqual(account.call('GET',path)[0],200)
        self.assertEqual(before,{kind:self.server.store.rows(kind) for kind in before})
        self.assertEqual(owner.call('POST','orders/'+order['id']+'/accept',{'expectedVersion':order['version']})[0],200)
        _,profile=self.master.call('GET','users/me')
        self.assertEqual((profile['role'],profile['businessId']),('admin',None))
    def test_operator_cannot_enter_administration_or_another_local(self):
        b=self.local();owner,user=self.operator(b)
        other=self.local();other_owner,_=self.operator(other,'otro@example.test')
        status,p=other_owner.call('POST','businesses/'+other['id']+'/products',{'name':'Producto de otro local','category':'Comida','price':40,'isAvailable':True,'isFeatured':False})
        self.assertEqual(status,201)
        paths=['admin/businesses','admin/users','admin/access-requests','admin/reviews','admin/followups','admin/academic-catalog',
            'businesses/'+other['id'],'businesses/'+other['id']+'/products','businesses/'+other['id']+'/orders/active','products/'+p['id']]
        actions=[('GET',path,None) for path in paths]+[
            ('POST','admin/businesses',{'name':'No permitido'}),
            ('PATCH','admin/businesses/'+b['id'],{**b,'expectedVersion':b['version']}),
            ('POST','admin/users',{}),('PATCH','admin/users/'+user['id'],{**user,'role':'admin','isMaster':True,'expectedVersion':user['version']}),
            ('POST','admin/access-requests/arbitrary/decision',{'decision':'approve'}),
            ('PUT','admin/reviews/arbitrary/followup',{}),
            ('PATCH','products/'+p['id'],{**p,'price':99,'expectedVersion':p['version']}),
            ('POST','review/orders',{'businessId':other['id']})]
        before={kind:self.server.store.rows(kind) for kind in ('businesses','products','users')}
        for method,path,data in actions:
            with self.subTest(method=method,path=path):
                status,body=owner.call(method,path,data)
                self.assertEqual((status,body['error']['code']),(403,'FORBIDDEN'))
        self.assertEqual(before,{kind:self.server.store.rows(kind) for kind in before})
        self.assertEqual(owner.call('GET','businesses/'+b['id']+'/orders/active')[0],200)
        self.assertEqual(self.master.call('PATCH','admin/businesses/'+b['id'],{**b,'isActive':False,'expectedVersion':b['version']})[0],200)
        self.assertEqual(owner.call('GET','businesses/'+b['id'])[0],403)
    def test_master_confirms_identity_and_assignment_before_activation(self):
        self.request();request=self.pending();local=self.local()
        path='admin/access-requests/'+request['id']+'/decision'
        payload={'decision':'approve','role':'business','businessId':local['id'],'expectedVersion':request['version']}
        self.assertEqual(self.master.call('POST',path,payload)[0],422)
        self.assertEqual(self.pending()['approvalStatus'],'pending')
        status,user=self.master.call('POST',path,{**payload,'identityConfirmed':True});self.assertEqual(status,200)
        self.assertEqual(user['businessId'],local['id']);self.assertFalse(user['isMaster'])
        self.assertEqual(self.master.call('POST',path,{**payload,'identityConfirmed':True})[0],409)
        self.client.login('operador@example.test','Clave-Solicitada-123')
        self.assertEqual(self.client.call('GET','businesses/'+local['id']+'/orders/active')[0],200)
        self.assertEqual(self.client.call('GET','admin/access-requests')[0],403)
        self.assertEqual(self.server.store.rows('access_audit')[0]['actorId'],'admin')
    def test_request_cannot_grant_own_role_or_master_or_overwrite_credentials(self):
        for extra in ({'role':'admin'},{'isMaster':True},{'isActive':True},{'businessId':'arbitrary'}):
            self.assertEqual(self.request(**extra)[0],400)
        self.assertEqual(self.request(email='a@utsjr.edu.mx.evil.example',requestedRole='admin')[0],422)
        before=self.server.store.get('users','admin')['passwordHash']
        self.assertEqual(self.request(email='admin@snackup.test')[0],202)
        self.assertEqual(self.server.store.get('users','admin')['passwordHash'],before)
        self.assertEqual(self.master.call('GET','admin/access-requests')[1]['data'],[])
    def test_ordinary_admin_cannot_review_requests(self):
        self.request(email='administracion@utsjr.edu.mx',requestedRole='admin')
        req=self.pending()
        status,user=self.master.call('POST','admin/access-requests/'+req['id']+'/decision',{'decision':'approve','role':'admin','identityConfirmed':True,'expectedVersion':req['version']})
        self.assertEqual(status,200);self.assertFalse(user['isMaster'])
        self.client.login('administracion@utsjr.edu.mx','Clave-Solicitada-123')
        self.assertEqual(self.client.call('GET','admin/access-requests')[0],403)
        self.assertEqual(self.client.call('POST','admin/users',{})[0],403)
    def test_upgrade_retires_only_known_example_accounts_and_preserves_work(self):
        s=self.server.store;s.seed_test_fixtures();s.migrate_institution()
        with s.db:
            s.put('users',{'id':'user-created','email':'propio@example.test','displayName':'Propio','role':'business','isActive':True,'businessId':'central','isMaster':False,'version':1,'passwordHash':'preserved'})
            p=s.get('products','central-p1');s.put('products',{**p,'price':321.5})
            s.db.execute("DELETE FROM records WHERE kind='migrations' AND id='owner-managed-v3'")
        s.migrate_clean_start();s.migrate_clean_start()
        self.assertEqual({u['id'] for u in s.rows('users')},{'admin','user-created'})
        self.assertEqual(len(s.rows('retired_example_accounts')),4)
        self.assertEqual(s.get('products','central-p1')['price'],321.5)
        self.assertEqual(s.get('users','user-created')['passwordHash'],'preserved')

if __name__=='__main__':unittest.main()
