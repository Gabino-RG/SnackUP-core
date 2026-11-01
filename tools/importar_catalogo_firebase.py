"""Copy only an explicitly selected public catalog into the local SQL database.

Export is read-only in Firebase. Apply inserts missing businesses/products in one
transaction, without users, roster, reviews or orders. Existing rows are preserved.
"""
import argparse
from datetime import datetime, timezone
from decimal import Decimal
import json
from pathlib import Path
import sys
from urllib.parse import urlsplit


def export_catalog(target):
    import httpx
    fields = {
        'businesses': {'name', 'category', 'description', 'imageUrl', 'coverImageUrl', 'isOpen', 'isActive'},
        'products': {'name', 'businessId', 'category', 'subcategory', 'description', 'price', 'stock',
                     'imageUrl', 'isAvailable', 'isFeatured', 'preparationMinutes', 'calories'},
    }
    base = 'https://firestore.googleapis.com/v1/projects/snackup-8fe96/databases/(default)/documents/'
    result = {'sourceProject': 'snackup-8fe96', 'sourceBranch': 'codex/cliente-firebase',
              'sourceClientCommit': '0f93fa6db49a304e70df95bfa5a4899252d114e8',
              'exportedAt': datetime.now(timezone.utc).isoformat()}

    def decode(value):
        if 'nullValue' in value:
            return None
        for kind in ('stringValue', 'booleanValue', 'integerValue', 'doubleValue'):
            if kind in value:
                return int(value[kind]) if kind == 'integerValue' else value[kind]
        raise ValueError('Tipo inesperado en un campo de catálogo.')

    with httpx.Client(timeout=20, trust_env=False) as client:
        for collection, allowed in fields.items():
            result[collection], token, seen = [], '', set()
            while True:
                response = client.get(base + collection, params={'pageSize': 100, **({'pageToken': token} if token else {})})
                response.raise_for_status()
                payload = response.json()
                for document in payload.get('documents', []):
                    row = {'id': document['name'].rsplit('/', 1)[-1]}
                    row.update({key: decode(value) for key, value in document.get('fields', {}).items() if key in allowed})
                    if 'price' in row:
                        row['price'] = str(row['price'])
                    result[collection].append(row)
                token = payload.get('nextPageToken', '')
                if not token:
                    break
                if token in seen or len(result[collection]) > 10000:
                    raise ValueError('Paginación de catálogo inesperada.')
                seen.add(token)
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({'export': str(target), 'businesses': len(result['businesses']),
                      'products': len(result['products']), 'firebaseWrites': 0}))


def import_catalog(source, backend, apply):
    sys.path.insert(0, str(backend.resolve()))
    from sqlalchemy import func, select
    from snackup import admin_models, operation_models, push_models, review_models
    from snackup.config import Settings
    from snackup.db import Database
    from snackup.identity_models import AcademicRecord, User
    from snackup.operation_models import Business, Order, Product
    from snackup.v3_operations import ProductCreate

    settings = Settings(_env_file=backend.resolve() / '.env')
    if settings.environment != 'development' or not settings.database_url.startswith('postgresql'):
        raise ValueError('Solo se admite la instalación PostgreSQL local de desarrollo.')
    catalog = json.loads(source.read_text(encoding='utf-8'))
    businesses, products = catalog['businesses'], catalog['products']
    ids = {row['id'] for row in businesses}
    if len(ids) != len(businesses) or len({row['id'] for row in products}) != len(products):
        raise ValueError('IDs duplicados en el catálogo.')

    def image_url(value):
        if value is None or value == '':
            return None
        url = urlsplit(value)
        if url.scheme != 'https' or not url.hostname or url.username or url.password or len(value) > 2048:
            raise ValueError('URL de imagen inválida.')
        return value

    business_values, product_values = [], []
    for row in businesses:
        if not isinstance(row['name'], str) or not 1 <= len(row['name']) <= 160:
            raise ValueError('Nombre de negocio inválido.')
        business_values.append(dict(id=row['id'], name=row['name'],
            category=row.get('category', ''), description=row.get('description', ''),
            image_url=image_url(row.get('imageUrl')), cover_image_url=image_url(row.get('coverImageUrl')),
            cafeteria_id=settings.cafeteria_id, cafeteria_name=settings.cafeteria_name,
            is_open=row.get('isOpen', False), is_active=row.get('isActive', True)))
    allowed_product_fields = set(ProductCreate.model_fields)
    for row in products:
        if row['businessId'] not in ids:
            raise ValueError('Un producto apunta a un negocio ausente.')
        values = {key: value for key, value in row.items() if key in allowed_product_fields}
        values['price'] = Decimal(str(values['price']))
        validated = ProductCreate.model_validate(values)
        product_values.append(dict(id=row['id'], business_id=row['businessId'], name=validated.name,
            description=validated.description or '', category=validated.category, subcategory=validated.subcategory,
            price=validated.price, stock=validated.stock, image_url=image_url(validated.imageUrl),
            manual_available=validated.isAvailable, is_available=validated.isAvailable and validated.stock != 0,
            is_featured=validated.isFeatured, preparation_minutes=validated.preparationMinutes, calories=validated.calories))

    database = Database(settings)
    counts = {'businessesCreated': 0, 'productsCreated': 0, 'businessesKept': 0, 'productsKept': 0}
    with database.sessions() as db:
        with db.begin():
            before = [db.scalar(select(func.count()).select_from(model)) for model in (User, AcademicRecord, Order)]
            for values in business_values:
                existing = db.get(Business, values['id'])
                if existing is not None:
                    if existing.name != values['name']:
                        raise ValueError('Un ID de negocio ya pertenece a otro nombre.')
                    counts['businessesKept'] += 1
                else:
                    counts['businessesCreated'] += 1
                    if apply:
                        db.add(Business(**values))
            if apply:
                db.flush()
            for values in product_values:
                existing = db.get(Product, values['id'])
                if existing is not None:
                    if existing.name != values['name'] or existing.business_id != values['business_id']:
                        raise ValueError('Un ID de producto ya pertenece a otro artículo.')
                    counts['productsKept'] += 1
                else:
                    counts['productsCreated'] += 1
                    if apply:
                        db.add(Product(**values))
            if apply:
                db.flush()
            after = [db.scalar(select(func.count()).select_from(model)) for model in (User, AcademicRecord, Order)]
            if before != after:
                raise ValueError('Cambio inesperado fuera del catálogo; se revierte la operación.')
            if not apply:
                db.rollback()
    print(json.dumps({'applied': apply, **counts, 'usersRosterOrdersUnchanged': True,
                      'outOfStock': sum(row['stock'] == 0 for row in product_values),
                      'productImagesInSource': sum(bool(row['image_url']) for row in product_values),
                      'sourceProject': catalog.get('sourceProject')}, ensure_ascii=False))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--export', type=Path)
    parser.add_argument('--source', type=Path)
    parser.add_argument('--backend', type=Path)
    parser.add_argument('--apply', action='store_true')
    args = parser.parse_args()
    try:
        if args.export and not args.source and not args.apply:
            export_catalog(args.export)
        elif args.source and args.backend and not args.export:
            import_catalog(args.source, args.backend, args.apply)
        else:
            parser.error('Usa --export ARCHIVO o --source ARCHIVO --backend CARPETA [--apply].')
    except Exception as error:
        print('No se pudo completar la operación de catálogo: ' + type(error).__name__)
        sys.exit(1)
