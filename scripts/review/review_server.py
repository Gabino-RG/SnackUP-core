"""SnackUP review-only REST fixture. Loopback only; not a production backend."""
from __future__ import annotations
import argparse
import copy
import email.parser
import email.policy
import hashlib
import hmac
import http.cookies
import http.server
import json
import math
import mimetypes
import os
from pathlib import Path
import re
import secrets
import socket
import sqlite3
import sys
import threading
import time
import urllib.parse
import uuid
import webbrowser
from datetime import datetime, timedelta, timezone

PASSWORD = 'SnackUP-Prueba-2026'
ACTIVE = {'pending', 'accepted', 'preparing', 'ready'}
REASONS = {'product_unavailable', 'cannot_prepare', 'store_issue', 'store_closing', 'other'}
UTC = timezone.utc
CAMPUS = timezone(timedelta(hours=-6))

def now():
    return datetime.now(UTC).isoformat().replace('+00:00', 'Z')

def hash_password(password, salt=None):
    salt = salt or secrets.token_hex(16)
    return salt + ':' + hashlib.pbkdf2_hmac('sha256', password.encode(), bytes.fromhex(salt), 120_000).hex()

def check_password(password, hashed):
    return hmac.compare_digest(hash_password(password, hashed.split(':')[0]), hashed)

class Problem(Exception):
    def __init__(self, status, code, message='Revisa la solicitud.'):
        self.status, self.code, self.message = status, code, message

def require(condition, status=422, code='INVALID_INPUT', message='Revisa los datos del formulario.'):
    if not condition:
        raise Problem(status, code, message)

def text_field(data, key, maximum=120, required=True):
    value = data.get(key, '')
    require(isinstance(value, str))
    value = value.strip()
    require((bool(value) or not required) and len(value) <= maximum)
    return value

def new_id():
    return uuid.uuid4().hex

def public_user(user):
    return {k: v for k, v in user.items() if k != 'passwordHash'}

def public_order(order):
    return {k: v for k, v in order.items() if k not in {'pickupCode', 'customerNumeroDeControl'}}

class Store:
    def __init__(self, path):
        self.path = Path(path)
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self.lock = threading.RLock()
        self.db = sqlite3.connect(self.path, check_same_thread=False)
        self.db.execute('PRAGMA journal_mode=WAL')
        self.db.execute('CREATE TABLE IF NOT EXISTS records(kind TEXT,id TEXT,payload TEXT,PRIMARY KEY(kind,id))')
        self.db.execute('CREATE TABLE IF NOT EXISTS refresh(hash TEXT PRIMARY KEY,user_id TEXT,version INTEGER,expires REAL)')
        self.tokens = {}
        self.login_attempts = {}
        if not self.rows('users'):
            self.seed()
        self.migrate_institution()
    def rows(self, kind):
        return [json.loads(r[0]) for r in self.db.execute('SELECT payload FROM records WHERE kind=? ORDER BY id', (kind,))]
    def get(self, kind, id):
        row = self.db.execute('SELECT payload FROM records WHERE kind=? AND id=?', (kind,id)).fetchone()
        if row is None:
            raise Problem(404, 'NOT_FOUND')
        return json.loads(row[0])
    def put(self, kind, item, id=None):
        self.db.execute('INSERT OR REPLACE INTO records VALUES(?,?,?)',(kind,id or item['id'],json.dumps(item,ensure_ascii=False)))
        return item
    def bump(self, kind, old, changes):
        return self.put(kind,{**old,**changes,'version':old['version']+1,'updatedAt':now()})
    def version(self, body, record):
        require(type(body.get('expectedVersion')) is int and body['expectedVersion']==record['version'],409,'VERSION_CONFLICT')
    def configuration(self):
        return self.get('configuration','institution')
    def migrate_institution(self):
        # Additive and idempotent: never reset passwords, products or reviewed data.
        if any(r['id']=='institution-v2' for r in self.rows('migrations')):return
        with self.db:
            if not any(r['id']=='institution' for r in self.rows('configuration')):
                self.put('configuration',{'id':'institution','university':{'id':'utsjr','name':'Universidad Tecnológica de San Juan del Río'},
                    'cafeteria':{'id':'cafeteria-utsjr','name':'Cafetería universitaria'},'adminEmailDomains':['utsjr.edu.mx']})
            config=self.configuration();cafeteria=config['cafeteria']
            replacements={'central':('Cafetería Central','Local 1 · Central'),'antojitos':('Antojitos del Campus','Local 2 · Antojitos'),
                'verde':('Rincón Verde','Local 3 · Rincón Verde'),'dulce':('Pausa Dulce','Local 4 · Pausa Dulce')}
            for b in self.rows('businesses'):
                changes={'cafeteriaId':cafeteria['id'],'cafeteriaName':cafeteria['name']}
                if b['id'] in replacements and b['name']==replacements[b['id']][0]:changes['name']=replacements[b['id']][1]
                if b.get('description')=='Preparado al momento para la comunidad del campus.':changes['description']='Local de la cafetería de la universidad.'
                self.bump('businesses',b,changes)
            for u in self.rows('users'):
                master=u['id']=='admin' and u['role']=='admin'
                changes={'isMaster':master}
                if master and u['displayName']=='Administración SnackUP':changes['displayName']='Cuenta maestra SnackUP'
                self.bump('users',u,changes)
            for uid,email,bid,name in [('owner3','verde@snackup.test','verde','Operador Local 3'),('owner4','dulce@snackup.test','dulce','Operador Local 4')]:
                users=self.rows('users')
                if not any(u.get('businessId')==bid and u['role']=='business' and u['isActive'] for u in users) and not any(u['email']==email or u['id']==uid for u in users):
                    self.put('users',{'id':uid,'email':email,'displayName':name,'role':'business','businessId':bid,'isActive':True,'isMaster':False,
                        'version':1,'passwordHash':hash_password(PASSWORD),'createdAt':now(),'updatedAt':now()})
            careers=[('software','Desarrollo de Software','DSM'),('administracion','Administración','ADM'),('mecatronica','Mecatrónica','MEC')]
            if not self.rows('academic_catalog'):
                for cid,name,prefix in careers:
                    self.put('academic_catalog',{'id':cid,'name':name,'kind':'career'})
                    for number in range(1,7):
                        self.put('academic_catalog',{'id':f'{cid}-{number}','name':f'{prefix}-{number}','kind':'group','careerId':cid})
            # Existing opinions retain their wording. Add IDs only for known examples.
            for r in self.rows('reviews'):
                for cid,name,prefix in careers:
                    if r.get('career')==name and re.fullmatch(prefix+r'-[1-6]',r.get('group','')):
                        self.put('reviews',{**r,'careerId':cid,'groupId':f'{cid}-{r["group"].split("-")[-1]}'})
            self.put('migrations',{'id':'institution-v2','appliedAt':now()})
    def seed(self):
        with self.db:
            for i,(id,name,category) in enumerate([('central','Cafetería Central','Cafetería'),('antojitos','Antojitos del Campus','Comida mexicana'),('verde','Rincón Verde','Saludable'),('dulce','Pausa Dulce','Postres')]):
                self.put('businesses',{'id':id,'name':name,'category':category,'description':'Preparado al momento para la comunidad del campus.','timezone':'America/Mexico_City','isOpen':True,'isActive':True,'version':1,'createdAt':now(),'updatedAt':now()})
                for n,(name,price,cat) in enumerate([('Hamburguesa especial',85,'Comida'),('Torta de pollo',55,'Comida'),('Agua de limón',25,'Bebidas'),('Café americano',30,'Bebidas'),('Ensalada fresca',65,'Comida'),('Galleta de avena',20,'Postres')]):
                    self.put('products',{'id':f'{id}-p{n+1}','businessId':id,'name':name,'price':price,'category':cat,'description':'Producto de ejemplo. Puedes editarlo y subir tu propia imagen.','stock':40 if n<3 else None,'isAvailable':True,'isFeatured':n==0,'imageUrl':None,'version':1,'createdAt':now(),'updatedAt':now()})
                for n in range(8 if i==0 else 2):
                    self.new_order(id, status=['pending','pending','accepted','preparing','ready','completed','cancelled','completed'][n],code='4821')
            for id,email,name,role,bid in [('admin','admin@snackup.test','Administración SnackUP','admin',None),('owner','negocio@snackup.test','Operador Central','business','central'),('owner2','antojitos@snackup.test','Operador Antojitos','business','antojitos')]:
                self.put('users',{'id':id,'email':email,'displayName':name,'role':role,'businessId':bid,'isActive':True,'version':1,'passwordHash':hash_password(PASSWORD),'createdAt':now(),'updatedAt':now()})
            comments=['Buena atención y comida caliente.','Se tardaron demasiado en entregar mi pedido.','Me gustó el menú y el precio.','Mi bebida llegó equivocada.','Todo estuvo excelente.','Faltan opciones sin azúcar.']
            for i in range(36):
                bid=['central','antojitos','verde','dulce'][i%4]
                self.put('reviews',{'id':f'review-{i:03}','businessId':bid,'rating':[5,2,4,1,5,3][i%6],'foodRating':[5,3,4,2,5,3][i%6],'serviceRating':[5,1,4,2,5,3][i%6],
                    'career':['Desarrollo de Software','Administración','Mecatrónica'][i%3],'group':['DSM-1','ADM-2','MEC-3'][i%3],'comment':comments[i%6],'createdAt':(datetime.now(UTC)-timedelta(hours=i*5)).isoformat()})
    def new_order(self, business_id, status='pending', code=None):
        business=self.get('businesses',business_id)
        require(business['isActive'] and business['isOpen'],409,'BUSINESS_CLOSED')
        products=[p for p in self.rows('products') if p['businessId']==business_id and p['isAvailable'] and (p['stock'] is None or p['stock']>0)]
        require(products,422,'PRODUCT_UNAVAILABLE')
        p=products[0]
        previous=[o for o in self.rows('orders') if o['businessId']==business_id]
        number=max([o['orderNumber'] for o in previous],default=1000)+1
        date=now()
        item={'id':new_id(),'productId':p['id'],'name':p['name'],'price':p['price'],'quantity':1,'notes':'Sin cebolla' if number%2 else ''}
        order={'id':new_id(),'orderNumber':number,'businessId':business_id,'userId':'review-student','customerName':['Ana López','Luis Hernández','María García','Diego Pérez'][number%4],
            'customerNumeroDeControl':'20260001','items':[item],'subtotal':p['price'],'total':p['price'],'paymentMethod':'Efectivo','status':status,'createdAt':date,'updatedAt':date,'version':1,
            'pickupCode':code or str(secrets.randbelow(9000)+1000),'scheduledPickupTime':None,'cancelReason':'cannot_prepare' if status=='cancelled' else None,'cancelNotes':None,'cancelledBy':'business' if status=='cancelled' else None,'verification':None}
        for field in ['acceptedAt','preparingAt','readyAt','completedAt','cancelledAt']:
            order[field]=date if (field=='completedAt' and status=='completed') or (field=='cancelledAt' and status=='cancelled') else None
        if p['stock'] is not None and status!='cancelled':
            remaining=p['stock']-1
            self.bump('products',p,{'stock':remaining,'isAvailable':remaining>0})
        self.put('orders',order)
        return order
    def issue(self,user):
        access=secrets.token_urlsafe(32)
        refresh=secrets.token_urlsafe(40)
        self.tokens[access]=(user['id'],user['version'],time.time()+900)
        self.db.execute('DELETE FROM refresh WHERE expires<?',(time.time(),))
        self.db.execute('INSERT INTO refresh VALUES(?,?,?,?)',(hashlib.sha256(refresh.encode()).hexdigest(),user['id'],user['version'],time.time()+86400))
        # Prune only expired tokens, never log credentials or bearer values.
        self.tokens={k:v for k,v in self.tokens.items() if v[2]>time.time()}
        return {'accessToken':access,'accessTokenExpiresAt':(datetime.now(UTC)+timedelta(minutes=15)).isoformat()},refresh
    def authenticate(self,header):
        value=self.tokens.get(header.removeprefix('Bearer ')) if header.startswith('Bearer ') else None
        require(value is not None,401,'UNAUTHENTICATED')
        uid,version,expires=value
        require(expires>time.time(),401,'TOKEN_EXPIRED')
        user=self.get('users',uid)
        require(user['isActive'] and user['version']==version,403,'ACCESS_REVOKED')
        return user

class ReviewHandler(http.server.SimpleHTTPRequestHandler):
    extensions_map={**http.server.SimpleHTTPRequestHandler.extensions_map,'.wasm':'application/wasm','.js':'application/javascript','.json':'application/json'}
    def __init__(self,*args,**kwargs):
        super().__init__(*args,directory=str(args[2].web_root),**kwargs)
    def log_message(self,*args):
        pass
    def end_headers(self):
        self.send_header('Cache-Control','no-store')
        self.send_header('X-Content-Type-Options','nosniff')
        self.send_header('Referrer-Policy','no-referrer')
        super().end_headers()
    def list_directory(self,path):
        self.send_error(404)
    def reply(self,data=None,status=200,cookie=None):
        if getattr(self,'_deferring',False):
            self._response=(data,status,cookie);return
        raw=b'' if data is None else json.dumps(data,ensure_ascii=False).encode()
        self.send_response(status)
        self.send_header('Content-Type','application/json; charset=utf-8')
        self.send_header('Content-Length',str(len(raw)))
        if cookie is not None:
            self.send_header('Set-Cookie',f'snackup_review_refresh={cookie}; HttpOnly; SameSite=Strict; Path=/api/v1/auth; Max-Age={86400 if cookie else 0}')
        self.end_headers()
        if raw:self.wfile.write(raw)
    def refresh_cookie(self):
        jar=http.cookies.SimpleCookie()
        try:jar.load(self.headers.get('Cookie',''))
        except http.cookies.CookieError:return ''
        return jar['snackup_review_refresh'].value if 'snackup_review_refresh' in jar else ''
    def check_origin(self):
        host=self.headers.get('Host','')
        allowed={f'localhost:{self.server.server_port}',f'127.0.0.1:{self.server.server_port}'}
        require(host in allowed,403,'BAD_ORIGIN')
        origin=self.headers.get('Origin')
        require(origin is None or origin==f'http://{host}',403,'BAD_ORIGIN')
    def body(self):
        try:length=int(self.headers.get('Content-Length','0'))
        except ValueError:raise Problem(400,'INVALID_INPUT')
        require(0<=length<=6*1024*1024,413,'TOO_LARGE')
        raw=self.rfile.read(length)
        if self.path.split('?')[0].endswith('/media'):return raw
        require(self.headers.get('Content-Type','').split(';')[0]=='application/json',415,'JSON_REQUIRED')
        try:data=json.loads(raw or '{}')
        except (ValueError,UnicodeError):raise Problem(400,'INVALID_JSON')
        require(isinstance(data,dict),400,'INVALID_JSON')
        return data
    def do_GET(self):self.dispatch('GET')
    def do_HEAD(self):
        try:
            self.check_origin()
            if self.path.startswith('/api/') or self.path.startswith('/media/'):
                self.send_error(405);return
            super().do_HEAD()
        except Problem:self.send_error(403)
    def do_POST(self):self.dispatch('POST')
    def do_PATCH(self):self.dispatch('PATCH')
    def do_PUT(self):self.dispatch('PUT')
    def do_DELETE(self):self.dispatch('DELETE')
    def dispatch(self,method):
        try:
            self.check_origin()
            parsed=urllib.parse.urlsplit(self.path)
            path=urllib.parse.unquote(parsed.path)
            if not path.startswith('/api/v1/'):
                require(method=='GET',405,'METHOD_NOT_ALLOWED')
                if path.startswith('/media/'):
                    name=path[7:]
                    require(bool(re.fullmatch(r'[a-f0-9]{32}\.(png|jpg|webp)',name)),404,'NOT_FOUND')
                    file=self.server.data_dir/'media'/name
                    require(file.is_file(),404,'NOT_FOUND')
                    raw=file.read_bytes();self.send_response(200);self.send_header('Content-Type',mimetypes.guess_type(name)[0]);self.send_header('Content-Length',str(len(raw)));self.end_headers();self.wfile.write(raw);return
                return super().do_GET()
            query=urllib.parse.parse_qs(parsed.query)
            data={} if method=='GET' else self.body()
            parts=path[len('/api/v1/'):].strip('/').split('/')
            self._deferring=True
            try:
                with self.server.store.lock, self.server.store.db:
                    self.route(method,parts,query,data)
            finally:self._deferring=False
            self.reply(*self._response)
        except Problem as e:self.reply({'error':{'code':e.code,'message':e.message}},e.status)
        except (ValueError,TypeError,KeyError):self.reply({'error':{'code':'INVALID_INPUT','message':'Revisa los datos de la solicitud.'}},400)
        except (BrokenPipeError,ConnectionResetError):pass
        except Exception as e:
            print('Error del servidor de revisión:',type(e).__name__,flush=True)
            self.reply({'error':{'code':'SERVER_ERROR','message':'No se pudo completar la operación.'}},500)
    def page(self,rows,q):
        number=int(q.get('page',['1'])[0]);limit=int(q.get('limit',['20'])[0])
        require(number>=1 and 1<=limit<=200,400)
        return {'data':rows[(number-1)*limit:number*limit],'pagination':{'page':number,'limit':limit,'total':len(rows),'totalPages':math.ceil(len(rows)/limit)}}
    def admin(self,user):require(user['role']=='admin',403,'FORBIDDEN')
    def master(self,user):
        self.admin(user);require(user.get('isMaster') is True,403,'MASTER_REQUIRED','Solo la cuenta maestra puede administrar accesos.')
    def business_access(self,user,bid):
        require(user['role']=='business' and user.get('businessId')==bid,403,'FORBIDDEN')
        require(self.server.store.get('businesses',bid)['isActive'],403,'ACCESS_REVOKED')
    def route(self,m,p,q,d):
        s=self.server.store
        if p==['realtime']:raise Problem(503,'POLLING_MODE')
        if p==['auth','login'] and m=='POST':
            email=text_field(d,'email',160).lower();password=d.get('password','');require(isinstance(password,str))
            failures=[t for t in s.login_attempts.get(email,[]) if t>time.time()-60]
            require(len(failures)<12,429,'RATE_LIMITED')
            user=next((u for u in s.rows('users') if u['email']==email),None)
            if user is None or not user['isActive'] or not check_password(password,user['passwordHash']):
                s.login_attempts[email]=failures+[time.time()];raise Problem(401,'INVALID_CREDENTIALS')
            if user['role']=='business':require(s.get('businesses',user['businessId'])['isActive'],403,'ACCESS_REVOKED')
            old=self.refresh_cookie()
            if old:s.db.execute('DELETE FROM refresh WHERE hash=?',(hashlib.sha256(old.encode()).hexdigest(),))
            tokens,cookie=s.issue(user);self.reply({'user':public_user(user),'tokens':tokens},cookie=cookie);return
        if p==['auth','refresh'] and m=='POST':
            hashed=hashlib.sha256(self.refresh_cookie().encode()).hexdigest()
            row=s.db.execute('SELECT user_id,version,expires FROM refresh WHERE hash=?',(hashed,)).fetchone()
            require(row is not None and row[2]>time.time(),401,'UNAUTHENTICATED')
            user=s.get('users',row[0]);require(user['isActive'] and user['version']==row[1],401,'UNAUTHENTICATED')
            if user['role']=='business':require(s.get('businesses',user['businessId'])['isActive'],401,'UNAUTHENTICATED')
            s.db.execute('DELETE FROM refresh WHERE hash=?',(hashed,));tokens,cookie=s.issue(user);self.reply({'tokens':tokens},cookie=cookie);return
        if p==['auth','logout'] and m=='POST':
            hashed=hashlib.sha256(self.refresh_cookie().encode()).hexdigest();s.db.execute('DELETE FROM refresh WHERE hash=?',(hashed,))
            s.tokens.pop(self.headers.get('Authorization','').removeprefix('Bearer '),None);self.reply(status=204,cookie='');return
        if p==['auth','forgot-password'] and m=='POST':
            text_field(d,'email',160);self.reply(status=204);return
        if p==['auth','reset-password'] and m=='POST':raise Problem(422,'RESET_TOKEN_INVALID','La recuperación real requiere el servicio de correo del backend.')
        user=s.authenticate(self.headers.get('Authorization',''))
        if p==['users','me'] and m=='GET':self.reply(public_user(user));return
        if p==['institution'] and m=='GET':self.reply(s.configuration());return
        if p==['review','orders'] and m=='POST':
            bid=text_field(d,'businessId');self.business_access(user,bid);order=s.new_order(bid)
            self.reply({'orderNumber':order['orderNumber'],'pickupCode':order['pickupCode']},201);return
        if p==['media'] and m=='POST':
            require(user['role']=='business',403,'FORBIDDEN');self.business_access(user,user['businessId']);self.upload(d);return
        if p and p[0]=='businesses':
            require(len(p)>=2,404,'NOT_FOUND');bid=p[1];self.business_access(user,bid);business=s.get('businesses',bid)
            if len(p)==2 and m=='GET':self.reply(business);return
            if (len(p)==2 or p[2:]==['status']) and m=='PATCH':
                s.version(d,business)
                if p[2:]==['status']:
                    require(type(d.get('isOpen')) is bool);changes={'isOpen':d['isOpen']}
                else:changes={'name':text_field(d,'name',100),'category':text_field(d,'category',60),'description':text_field(d,'description',600,False)}
                self.reply(s.bump('businesses',business,changes));return
            if p[2:]==['products']:
                if m=='GET':
                    rows=[r for r in s.rows('products') if r['businessId']==bid]
                    query=q.get('q',[''])[0].casefold();rows=[r for r in rows if query in (r['name']+' '+r['category']).casefold()]
                    if 'isAvailable'in q:rows=[r for r in rows if r['isAvailable']==(q['isAvailable'][0]=='true')]
                    self.reply(self.page(rows,q));return
                if m=='POST':
                    product=self.product(d,bid);self.reply(s.put('products',product),201);return
            if p[2:]==['orders','active'] and m=='GET':
                rows=sorted([public_order(r) for r in s.rows('orders') if r['businessId']==bid and r['status']in ACTIVE],key=lambda r:r['createdAt'])
                self.reply(self.page(rows,q));return
            if p[2:]==['orders','history'] and m=='GET':
                date=q.get('date',[''])[0];datetime.strptime(date,'%Y-%m-%d')
                rows=self.period_orders(bid,date,date);result=self.page([public_order(r) for r in rows],q);result['summary']=self.summary(rows);self.reply(result);return
            if p[2:]==['stats'] and m=='GET':
                start=q.get('from',[''])[0];end=q.get('to',[''])[0];datetime.strptime(start,'%Y-%m-%d');datetime.strptime(end,'%Y-%m-%d');require(start<=end)
                self.reply(self.summary(self.period_orders(bid,start,end)));return
        if len(p)==2 and p[0]=='products':
            old=s.get('products',p[1]);self.business_access(user,old['businessId'])
            if m=='GET':self.reply(old);return
            if m=='PATCH':s.version(d,old);self.reply(s.bump('products',old,self.product({**old,**d},old['businessId'],old=old)));return
            if m=='DELETE':s.version(d,old);s.db.execute('DELETE FROM records WHERE kind=? AND id=?',('products',old['id']));self.reply(status=204);return
        if p and p[0]=='orders' and len(p)>=2:
            order=s.get('orders',p[1]);self.business_access(user,order['businessId'])
            if len(p)==2 and m=='GET':self.reply(public_order(order));return
            if len(p)==3 and m=='POST':self.transition(order,p[2],d,user);return
        if p and p[0]=='admin':
            self.admin(user)
            if p[1:]==['academic-catalog'] and m=='GET':self.reply(self.page(s.rows('academic_catalog'),q));return
            if p[1:]==['businesses']:
                if m=='GET':
                    query=q.get('q',[''])[0].casefold();self.reply(self.page([b for b in s.rows('businesses') if query in (b['name']+' '+b['category']).casefold()],q));return
                if m=='POST':
                    b={'id':new_id(),'name':text_field(d,'name',100),'category':text_field(d,'category',60),'description':text_field(d,'description',600,False),'isOpen':False,'isActive':d.get('isActive',True),'timezone':'America/Mexico_City','version':1,'createdAt':now(),'updatedAt':now()}
                    cafeteria=s.configuration()['cafeteria'];require(d.get('cafeteriaId',cafeteria['id'])==cafeteria['id'])
                    b.update({'cafeteriaId':cafeteria['id'],'cafeteriaName':cafeteria['name']})
                    require(type(b['isActive']) is bool);self.reply(s.put('businesses',b),201);return
            if len(p)==3 and p[1]=='businesses' and m=='PATCH':
                b=s.get('businesses',p[2]);s.version(d,b);active=d.get('isActive');require(type(active) is bool)
                if not active:require(not any(o['businessId']==b['id'] and o['status']in ACTIVE for o in s.rows('orders')),409,'BUSINESS_HAS_ACTIVE_ORDERS')
                changes={'name':text_field(d,'name',100),'category':text_field(d,'category',60),'description':text_field(d,'description',600,False),'isActive':active}
                if not active:changes['isOpen']=False
                self.reply(s.bump('businesses',b,changes));return
            if p[1:]==['users'] and m=='GET':
                self.master(user)
                query=q.get('q',[''])[0].casefold();self.reply(self.page([public_user(u) for u in s.rows('users') if query in (u['displayName']+' '+u['email']).casefold()],q));return
            if (p[1:]==['users'] and m=='POST') or (len(p)==3 and p[1]=='users' and m=='PATCH'):
                self.master(user)
                self.save_user(d,user,None if m=='POST' else s.get('users',p[2]));return
            if p[1:]==['reviews'] and m=='GET':self.reply(self.page(s.rows('reviews'),q));return
            if p[1:]==['followups'] and m=='GET':self.reply(self.page(s.rows('followups'),q));return
            if len(p)>=4 and p[1]=='reviews' and p[3]=='followup':
                review=s.get('reviews',p[2]);rid=review['id']
                if len(p)==5 and p[4]=='history' and m=='GET':
                    rows=sorted([r for r in s.rows('followup_history') if r['reviewId']==rid],key=lambda r:r['updatedAt'],reverse=True);self.reply(self.page(rows,q));return
                if len(p)==4:
                    existing=next((r for r in s.rows('followups') if r['reviewId']==rid),None)
                    if m=='GET':
                        require(existing is not None,404,'FOLLOWUP_NOT_FOUND');self.reply(existing);return
                    if m=='PUT':
                        s.version(d,existing or {'version':0});require(d.get('status')in {'pending','in_review','resolved'})
                        record={'reviewId':rid,'businessId':review['businessId'],'status':d['status'],'assignee':text_field(d,'assignee',120),'note':text_field(d,'note',2000),'version':(existing or {'version':0})['version']+1,'updatedAt':now()}
                        s.put('followups',record,rid);s.put('followup_history',record,new_id());self.reply(record);return
        raise Problem(404,'NOT_FOUND')
    def product(self,d,bid,old=None):
        price=d.get('price');stock=d.get('stock')
        require(type(price)in (int,float) and math.isfinite(price) and 0<price<=10000)
        require(stock is None or (type(stock)is int and 0<=stock<=1000000))
        require(type(d.get('isAvailable')) is bool and type(d.get('isFeatured')) is bool)
        image=d.get('imageUrl');require(image is None or (isinstance(image,str) and (image.startswith('/media/') or image.startswith('http://localhost:') or image.startswith('http://127.0.0.1:'))))
        return {'id':old['id'] if old else new_id(),'businessId':bid,'name':text_field(d,'name',160),'description':text_field(d,'description',2000,False),'category':text_field(d,'category',120),'price':round(price,2),'stock':stock,'isAvailable':d['isAvailable'] and stock!=0,'isFeatured':d['isFeatured'],'imageUrl':image,
            'version':old['version'] if old else 1,'createdAt':old['createdAt'] if old else now(),'updatedAt':now()}
    def transition(self,o,action,d,user):
        s=self.server.store;s.version(d,o)
        transitions={'accept':('pending','accepted','acceptedAt'),'start':('accepted','preparing','preparingAt'),'ready':('preparing','ready','readyAt'),'complete':('ready','completed','completedAt')}
        changes={}
        if action=='cancel':
            require(o['status']in {'pending','accepted','preparing'},400,'INVALID_STATUS_TRANSITION')
            require(d.get('reason') in REASONS,422,'INVALID_CANCEL_REASON');notes=text_field(d,'notes',500,d['reason']=='other')
            changes={'status':'cancelled','cancelReason':d['reason'],'cancelNotes':notes,'cancelledBy':'business','cancelledAt':now()}
            for item in o['items']:
                try:p=s.get('products',item['productId'])
                except Problem:continue
                if p['stock'] is not None:
                    s.bump('products',p,{'stock':p['stock']+item['quantity'],'isAvailable':p['isAvailable'] or p['stock']==0})
        else:
            require(action in transitions,404,'NOT_FOUND');before,after,field=transitions[action]
            require(o['status']==before,400,'INVALID_STATUS_TRANSITION')
            if action=='complete':
                require(d.get('method') in {'qr','manual'},422,'VERIFICATION_FAILED')
                accepted={o['pickupCode']}
                if d['method']=='manual':accepted.add(o['customerNumeroDeControl'])
                require(d.get('code')in accepted,422,'VERIFICATION_FAILED')
                changes['verification']={'method':d['method'],'verifiedAt':now(),'verifiedBy':user['id']}
            changes.update({'status':after,field:now()})
        self.reply(public_order(s.bump('orders',o,changes)))
    def period_orders(self,bid,start,end):
        rows=[]
        for o in self.server.store.rows('orders'):
            if o['businessId']!=bid or o['status']in ACTIVE:continue
            date=datetime.fromisoformat(o.get('completedAt') or o.get('cancelledAt') or o['createdAt']).astimezone(CAMPUS).date().isoformat()
            if start<=date<=end:rows.append(o)
        return sorted(rows,key=lambda r:r['updatedAt'],reverse=True)
    def summary(self,rows):
        done=[r for r in rows if r['status']=='completed']
        return {'completed':len(done),'cancelled':sum(r['status']=='cancelled' for r in rows),'totalSold':round(sum(r['total'] for r in done),2)}
    def save_user(self,d,actor,old):
        s=self.server.store
        require('isMaster' not in d or d['isMaster']==bool(old and old.get('isMaster')),403,'MASTER_PROTECTED')
        if old:s.version(d,old)
        role=d.get('role');active=d.get('isActive');bid=d.get('businessId');email=text_field(d,'email',160).lower()
        require(role in {'admin','business','user'} and type(active)is bool and re.fullmatch(r'[^\s@]+@[^\s@]+\.[^\s@]+',email))
        require(not any(u['email']==email and (old is None or u['id']!=old['id']) for u in s.rows('users')),409,'EMAIL_EXISTS')
        if old and old.get('isMaster'):
            require(role=='admin' and active,403,'MASTER_PROTECTED','La cuenta maestra debe permanecer activa.')
        if role=='admin' and not (old and old.get('isMaster') and email==old['email']):
            require(email.rsplit('@',1)[-1] in s.configuration()['adminEmailDomains'],422,'INSTITUTIONAL_EMAIL_REQUIRED','Utiliza un correo institucional autorizado.')
        if role=='business':
            require(isinstance(bid,str) and bid,422,'BUSINESS_REQUIRED');b=s.get('businesses',bid);require(b['isActive'] or not active)
            require(not active or not any(u['role']=='business' and u['isActive'] and u.get('businessId')==bid and (old is None or u['id']!=old['id']) for u in s.rows('users')),409,'BUSINESS_ALREADY_ASSIGNED')
        else:bid=None
        if old and old['id']==actor['id']:require(role==actor['role'] and active,403,'SELF_ACCESS_CHANGE')
        if old and old['role']=='admin' and (role!='admin' or not active):require(any(u['id']!=old['id'] and u['role']=='admin' and u['isActive'] for u in s.rows('users')),409,'LAST_ADMIN')
        changes={'displayName':text_field(d,'displayName',100),'email':email,'role':role,'businessId':bid,'isActive':active}
        if old:
            changed=s.bump('users',old,changes);s.db.execute('DELETE FROM refresh WHERE user_id=?',(old['id'],))
        else:
            password=d.get('password');require(isinstance(password,str) and 12<=len(password)<=128)
            changed=s.put('users',{'id':new_id(),**changes,'isMaster':False,'passwordHash':hash_password(password),'version':1,'createdAt':now(),'updatedAt':now()})
        self.reply(public_user(changed),200 if old else 201)
    def upload(self,raw):
        content_type=self.headers.get('Content-Type','')
        require(content_type.startswith('multipart/form-data;'))
        message=email.parser.BytesParser(policy=email.policy.default).parsebytes(('Content-Type: '+content_type+'\r\nMIME-Version: 1.0\r\n\r\n').encode()+raw)
        images=[part for part in message.iter_parts() if part.get_param('name',header='content-disposition')=='file']
        require(len(images)==1);part=images[0];content=part.get_payload(decode=True)
        require(isinstance(content,bytes) and 0<len(content)<=5*1024*1024,413,'TOO_LARGE')
        kind=part.get_content_type()
        valid=(kind=='image/png' and content.startswith(b'\x89PNG\r\n\x1a\n'))or(kind=='image/jpeg' and content.startswith(b'\xff\xd8\xff'))or(kind=='image/webp' and content[:4]==b'RIFF' and content[8:12]==b'WEBP')
        require(valid,422,'INVALID_IMAGE')
        extension={'image/png':'png','image/jpeg':'jpg','image/webp':'webp'}[kind];name=new_id()+'.'+extension
        folder=self.server.data_dir/'media';folder.mkdir(exist_ok=True);(folder/name).write_bytes(content)
        self.reply({'url':f'http://{self.headers["Host"]}/media/{name}'},201)

class ReviewServer(http.server.ThreadingHTTPServer):
    allow_reuse_address=False
    daemon_threads=True
    def __init__(self,address,web_root,data_dir):
        self.web_root=Path(web_root).resolve();self.data_dir=Path(data_dir).resolve();self.store=Store(self.data_dir/'revision.sqlite3')
        super().__init__(address,ReviewHandler)
    def server_bind(self):
        if sys.platform=='win32' and hasattr(socket,'SO_EXCLUSIVEADDRUSE'):self.socket.setsockopt(socket.SOL_SOCKET,socket.SO_EXCLUSIVEADDRUSE,1)
        super().server_bind()

def main():
    parser=argparse.ArgumentParser(description='SnackUP: revisión local de los paneles')
    parser.add_argument('--port',type=int,default=8791);parser.add_argument('--no-browser',action='store_true')
    parser.add_argument('--web',type=Path,default=Path(__file__).resolve().parent/'web')
    parser.add_argument('--data',type=Path,default=Path(__file__).resolve().parent/'datos')
    args=parser.parse_args();require(0<=args.port<=65535)
    if not (args.web/'index.html').is_file():print('Extrae todo el ZIP antes de abrir INICIAR_SNACKUP.cmd.');return 1
    try:server=ReviewServer(('127.0.0.1',args.port),args.web,args.data)
    except OSError:print('No se pudo abrir el puerto. Cierra la otra instancia de SnackUP e intenta nuevamente.');return 1
    url=f'http://localhost:{server.server_port}/'
    print('\nSNACKUP | REVISION DE NEGOCIOS Y ADMINISTRACION\nDatos de prueba persistentes en esta PC.\nNo es el backend de producción.\n',flush=True)
    print(url+'\nNegocio: negocio@snackup.test\nAdministración: admin@snackup.test\nContraseña de prueba: '+PASSWORD+'\n\nMantén esta ventana abierta. Ctrl+C para terminar.\n',flush=True)
    if not args.no_browser:
        try:
            if sys.platform=='win32':os.startfile(url)
            else:webbrowser.open(url)
        except (OSError,webbrowser.Error):pass
    with server:
        try:server.serve_forever(poll_interval=.2)
        except KeyboardInterrupt:pass
        finally:server.store.db.close()
    return 0
if __name__=='__main__':raise SystemExit(main())
