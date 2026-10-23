from datetime import timezone
from functools import lru_cache
import json
import math
from pathlib import Path

from jsonschema import Draft202012Validator, FormatChecker
from sqlalchemy import func, select

from .errors import ApiError


def require(condition, status=422, code='INVALID_INPUT', message='Revisa los datos del formulario.'):
    if not condition:
        raise ApiError(status, code, message)


@lru_cache
def contract():
    path = Path(__file__).resolve().parents[1] / 'contracts/panels.openapi.json'
    return json.loads(path.read_text(encoding='utf-8'))


@lru_cache
def request_validator(operation_id):
    spec = contract()
    for item in spec['paths'].values():
        for operation in item.values():
            if isinstance(operation, dict) and operation.get('operationId') == operation_id:
                schema = operation.get('requestBody', {}).get('content', {}).get('application/json', {}).get('schema')
                if schema is None:
                    raise ValueError('Operation has no JSON request schema: ' + operation_id)
                return Draft202012Validator({**schema, 'components': spec['components']}, format_checker=FormatChecker())
    raise ValueError('Unknown operation: ' + operation_id)


def validate_body(operation_id, data):
    errors = list(request_validator(operation_id).iter_errors(data))
    if errors:
        # Never echo values: requests may carry passwords, tokens or personal data.
        fields = [{'field': '.'.join(map(str, e.absolute_path)), 'rule': str(e.validator)} for e in errors[:10]]
        raise ApiError(422, 'INVALID_INPUT', 'La solicitud no cumple el contrato.', fields)
    return data


def version_check(record, expected):
    require(type(expected) is int and expected >= 0, 422, 'INVALID_INPUT')
    require(record.version == expected, 409, 'VERSION_CONFLICT', 'Los datos cambiaron. Actualiza e intenta nuevamente.')


def iso(value):
    if value is None:
        return None
    if value.tzinfo is None:
        value = value.replace(tzinfo=timezone.utc)
    return value.astimezone(timezone.utc).isoformat().replace('+00:00', 'Z')


def page_result(db, statement, serializer, page=1, limit=20):
    require(type(page) is int and page >= 1 and type(limit) is int and 1 <= limit <= 200)
    total = db.scalar(select(func.count()).select_from(statement.order_by(None).subquery()))
    rows = db.scalars(statement.offset((page - 1) * limit).limit(limit)).all()
    return {'data': [serializer(row) for row in rows], 'pagination': {
        'page': page, 'limit': limit, 'total': total, 'totalPages': math.ceil(total / limit),
    }}
