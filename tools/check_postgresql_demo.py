"""Exercise only this repository's synthetic PostgreSQL demo, never production."""
import json
from pathlib import Path
from uuid import uuid4
import httpx
from sqlalchemy import create_engine, text
from postgresql_demo import PRIVATE, ROOT, load, url

config = load()
settings = json.loads((PRIVATE / 'database.json').read_text(encoding='utf-8-sig'))
assert settings['engine'] == 'postgresql'
credentials = json.loads((PRIVATE / 'credentials.json').read_text(encoding='utf-8'))
checks = []
def check(condition, name):
    if not condition:
        raise AssertionError(name)
    checks.append(name)

engine = create_engine(url(config))
with engine.connect() as connection:
    check(connection.scalar(text('SELECT current_database()')) == 'snackup_local', 'real-postgresql-database')
    check(Path(connection.scalar(text('SHOW data_directory'))).resolve() == (PRIVATE / 'postgres-data').resolve(), 'exclusive-snackup-cluster')
    check(connection.scalar(text("SELECT count(*) FROM information_schema.tables WHERE table_schema='public'")) == 23, '23-backend-tables')
    before = connection.scalar(text("SELECT stock FROM products WHERE id='demo-product-1'"))
sessions = []
with httpx.Client(base_url='http://localhost:8080', timeout=20, trust_env=False) as client:
    def login(email):
        reply = client.post('/api/v1/auth/login', json={'email': email, 'password': credentials['password']})
        check(reply.status_code == 200, 'login-' + ('student' if email == credentials['student_email'] else 'kitchen'))
        tokens = reply.json()['tokens']
        sessions.append(tokens)
        return {'Authorization': 'Bearer ' + tokens['accessToken']}
    try:
        student = login(credentials['student_email'])
        reply = client.get('/api/v1/businesses?page=1&limit=100', headers=student)
        check(reply.status_code == 200 and any(b['id'] == 'demo-cafe' for b in reply.json()['data']), 'business-catalog')
        reply = client.get('/api/v1/businesses/demo-cafe/products?isAvailable=true&page=1&limit=100', headers=student)
        check(reply.status_code == 200 and all(p['id'] != 'demo-product-6' for p in reply.json()['data']), 'sold-out-product-hidden')
        key = str(uuid4())
        body = {'businessId':'demo-cafe','items':[{'productId':'demo-product-1','quantity':1,'notes':'Prueba de conexion PostgreSQL'}],
                'paymentMethod':'Efectivo','expectedTotal':55.0}
        reply = client.post('/api/v1/orders', json=body, headers={**student,'Idempotency-Key':key})
        check(reply.status_code == 201, 'create-order')
        order = reply.json()
        repeated = client.post('/api/v1/orders', json=body, headers={**student,'Idempotency-Key':key})
        check(repeated.status_code == 201 and repeated.json()['id'] == order['id'], 'idempotent-order-retry')
        with engine.connect() as connection:
            check(connection.scalar(text("SELECT stock FROM products WHERE id='demo-product-1'")) == before - 1, 'single-inventory-reservation')
        kitchen = login(credentials['kitchen_email'])
        endpoint = '/api/v1/orders/' + order['id']
        for action in ['accept','start','ready']:
            reply = client.post(endpoint+'/'+action,json={'expectedVersion':order['version']},headers=kitchen)
            check(reply.status_code == 200, 'order-'+action)
            order = reply.json()
        own = client.get(endpoint,headers=student)
        check(own.status_code == 200 and own.json()['pickupCode'], 'pickup-code-when-ready')
        reply = client.post(endpoint+'/complete',json={'expectedVersion':order['version'],'method':'qr','code':own.json()['pickupCode']},headers=kitchen)
        check(reply.status_code == 200 and reply.json()['status'] == 'completed','order-delivered')
        reply = client.post(endpoint+'/rating',json={'rating':5,'comment':'Prueba local PostgreSQL: buena atencion.'},headers=student)
        check(reply.status_code == 201,'restaurant-stars-and-comment')
        reviews = {'reviews':[{'productId':'demo-product-1','rating':4,'comment':'Prueba local PostgreSQL: buen sabor.'}]}
        reply = client.post(endpoint+'/reviews',json=reviews,headers=student)
        check(reply.status_code == 201,'food-stars-and-comment')
        reply = client.post(endpoint+'/reviews',json=reviews,headers=student)
        check(reply.status_code == 409,'duplicate-food-review-rejected')
        reply = client.get(endpoint,headers=student)
        check(reply.status_code == 200 and reply.json()['status']=='completed' and reply.json()['isRated'], 'completed-and-rated-order')
        reply = client.get('/api/legacy/v1/student/orders?page=1&limit=100',headers=student)
        check(reply.status_code==200 and any(row['id']==order['id'] for row in reply.json()['data']),'order-history')
        with engine.connect() as connection:
            check(connection.scalar(text('SELECT count(*) FROM reviews WHERE order_id=:id'),{'id':order['id']})==1 and
                  connection.scalar(text('SELECT count(*) FROM product_reviews WHERE order_id=:id'),{'id':order['id']})==1,'reviews-persist-in-postgresql')
    finally:
        for tokens in sessions:
            client.post('/api/v1/auth/logout',json={'refreshToken':tokens.get('refreshToken')})
engine.dispose()
report = {'database':'PostgreSQL (isolated local synthetic demo)','checksPassed':len(checks),'checks':checks,
          'limitations':['Does not test browser interactions or multi-server concurrency.'],
          'backendRef':'1c3459bfd58a083acf4a1638c5013db93873f057'}
path = ROOT / 'docs/evidence/api-client/postgresql-local.json'
path.write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print('Comprobaciones PostgreSQL correctas:',len(checks))
