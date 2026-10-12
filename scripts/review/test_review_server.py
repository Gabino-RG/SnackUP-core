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
        self.server=ReviewServer(('127.0.0.1',0),self.root/'web',self.root/'data');self.thread=threading.Thread(target=self.server.serve_forever,daemon=True);self.thread.start()
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

if __name__=='__main__':unittest.main()
