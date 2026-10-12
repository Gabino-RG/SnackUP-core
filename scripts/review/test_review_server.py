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
    def login(self,email='negocio@snackup.test'):
        status,body=self.call('POST','auth/login',{'email':email,'password':PASSWORD});assert status==200,body;self.token=body['tokens']['accessToken'];return body

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
if __name__=='__main__':unittest.main()
