"""Loopback-only demo backend with an isolated local database."""
import argparse
import json
from pathlib import Path
import secrets
import sys

ROOT = Path(__file__).resolve().parents[1]
PRIVATE = ROOT / '.local' / 'snackup-demo'
BACKEND = PRIVATE / 'source' / 'backend'
sys.path.insert(0, str(BACKEND))

def config():
    PRIVATE.mkdir(parents=True, exist_ok=True)
    path = PRIVATE / 'credentials.json'
    if not path.exists():
        data = {'secret_key': secrets.token_hex(32), 'password': 'Local-' + secrets.token_hex(6) + '!',
                'student_email': 'alumno@students.example.edu', 'kitchen_email': 'cocina@staff.example.edu'}
        path.write_text(json.dumps(data), encoding='utf-8')
    return json.loads(path.read_text(encoding='utf-8'))

def create_demo():
    from snackup.config import Settings
    from snackup.main import create_app
    from snackup.db import Base
    from snackup.auth import hash_password
    from snackup.identity_models import User, Career, AcademicRecord
    from snackup.operation_models import Business, Product
    data = config()
    # Import all models before applying SQL Server metadata adaptations.
    from snackup import admin_models, push_models, review_models
    database_url = 'sqlite:///' + (PRIVATE / 'demo.db').as_posix()
    sqlserver = (PRIVATE / 'database.json').exists()
    if sqlserver:
        from sqlserver_demo import prepare_database
        database_url = prepare_database(PRIVATE, Base.metadata)
    settings = Settings(_env_file=None, environment='test',
        database_url=database_url,
        secret_key=data['secret_key'], public_origin='http://localhost:8080',
        institution_id='demo-local', institution_name='Demostración local',
        cafeteria_id='campus-demo', cafeteria_name='Campus de prueba',
        admin_email_domains='staff.example.edu', student_email_domains='students.example.edu',
        media_dir=PRIVATE / 'media', redis_url='', smtp_host='', smtp_user='', smtp_password='',
        push_enabled=False, background_events=True)
    app = create_app(settings)
    Base.metadata.create_all(app.state.db.engine)
    with app.state.db.sessions.begin() as db:
        if db.get(User, 'demo-student') is None:
            db.add(Career(id='demo-career', name='Carrera de demostración'))
            db.flush()
            db.add(Business(id='demo-cafe', name='Cafetería de prueba local',
                description='Menú de demostración. No contiene datos de Firebase.',
                cafeteria_id='campus-demo', cafeteria_name='Campus de prueba', is_open=True))
            db.flush()
            password_hash = hash_password(data['password'])
            db.add(User(id='demo-student', email=data['student_email'], display_name='Alumno de demostración',
                password_hash=password_hash, role='user', is_active=True, email_verified=True, approval_status='approved', numero_de_control='DEMO-001'))
            db.add(User(id='demo-kitchen', email=data['kitchen_email'], display_name='Cocina de demostración',
                password_hash=password_hash, role='business', business_id='demo-cafe',
                is_active=True, email_verified=True, approval_status='approved'))
            db.add(AcademicRecord(email=data['student_email'], institutional_id='DEMO-001',
                display_name='Alumno de demostración', kind='student', career_id='demo-career', source='Synthetic local demo'))
            for index, (name, description, category, price, stock) in enumerate([
                ('Chilaquiles verdes con pollo', 'Totopos con salsa verde, pollo y queso.', 'Desayunos', '55.00', 20),
                ('Molletes especiales', 'Bolillo con frijoles, queso y pico de gallo.', 'Desayunos', '45.00', 15),
                ('Torta de milanesa', 'Milanesa con lechuga y jitomate.', 'Comidas', '52.00', 12),
                ('Smoothie energético verde', 'Manzana y espinaca.', 'Bebidas', '35.00', 20),
                ('Café americano', 'Café recién preparado.', 'Bebidas', '20.00', None),
                ('Producto agotado de prueba', 'Este producto no debe aparecer en el menú.', 'Prueba', '12.00', 0),
            ]):
                db.add(Product(id='demo-product-' + str(index + 1), business_id='demo-cafe', name=name,
                    description=description, category=category, price=price, stock=stock,
                    is_available=stock != 0, manual_available=stock != 0, is_featured=index in [0, 2], preparation_minutes=10))
    (PRIVATE / 'ACCESO-LOCAL.txt').write_text(
        'SnackUP LOCAL\nhttp://localhost:8080\n\nCorreo: ' + data['student_email'] + '\nContraseña: ' + data['password'] +
        '\n\nDatos ficticios. Firebase no se utiliza ni se modifica.\n', encoding='utf-8')
    return app

def complete_last():
    import httpx
    data = config()
    base = 'http://localhost:8000/api/v1'
    sessions = []
    with httpx.Client(timeout=20, trust_env=False) as client:
        def login(email):
            result = client.post(base + '/auth/login', json={'email': email, 'password': data['password']})
            result.raise_for_status()
            tokens = result.json()['tokens']; sessions.append(tokens)
            return {'Authorization': 'Bearer ' + tokens['accessToken']}
        try:
            student = login(data['student_email'])
            kitchen = login(data['kitchen_email'])
            active = client.get(base + '/users/me/orders/active', headers=student)
            active.raise_for_status()
            rows = active.json()['data']
            if not rows:
                print('No hay pedidos pendientes. Primero crea uno en http://localhost:8080.'); return
            rows.sort(key=lambda row: row['createdAt'], reverse=True)
            order = rows[0]
            endpoint = base + '/orders/' + order['id']
            for status, action in [('pending', 'accept'), ('accepted', 'start'), ('preparing', 'ready')]:
                if order['status'] == status:
                    reply = client.post(endpoint + '/' + action, headers=kitchen, json={'expectedVersion': order['version']})
                    reply.raise_for_status(); order = reply.json()
            if order['status'] == 'ready':
                own = client.get(endpoint, headers=student); own.raise_for_status()
                reply = client.post(endpoint + '/complete', headers=kitchen,
                    json={'method': 'qr', 'code': own.json()['pickupCode'], 'expectedVersion': order['version']})
                reply.raise_for_status(); order = reply.json()
            print('Pedido #' + str(order['orderNumber']) + ' entregado en la demostración local. Ya puedes valorarlo en la app.')
        finally:
            for tokens in sessions:
                try: client.post(base + '/auth/logout', json={'refreshToken': tokens.get('refreshToken')})
                except httpx.HTTPError: pass

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--complete-last', action='store_true')
    parser.add_argument('--init-only', action='store_true')
    args = parser.parse_args()
    if args.complete_last:
        complete_last()
    elif args.init_only:
        app = create_demo()
        print('Base local preparada: ' + app.state.db.engine.dialect.name)
        app.state.db.dispose()
    else:
        import uvicorn
        app = create_demo()
        uvicorn.run(app, host='127.0.0.1', port=8000, log_level='warning', access_log=False)

