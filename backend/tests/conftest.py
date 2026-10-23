"""Isolated test identities only. Never imported by the application or CLI."""
import os
import json
from pathlib import Path
import re
from threading import Lock
from uuid import uuid4

from fastapi.testclient import TestClient
import pytest
from sqlalchemy import create_engine, text
from jsonschema import Draft202012Validator, FormatChecker

from snackup.config import Settings
from snackup.db import Base
from snackup.main import create_app
from snackup.auth import hash_password
from snackup.identity_models import AcademicGroup, AcademicRecord, Career, User
from snackup.operation_models import Business, Product

PASSWORD = 'Test-Only-Password-392!'

# Validate actual API responses from every module's TestClient, not serializers
# alone. No personal input, cookies, tokens or response bodies enter the report.
CONTRACT = json.loads((Path(__file__).parents[1] / 'contracts/panels.openapi.json').read_text(encoding='utf-8'))
OPERATIONS = [(method.upper(), re.compile('^/api/legacy/v1' + re.sub(r'\{[^}]+\}', '[^/]+', path) + '$'), operation)
              for path, item in CONTRACT['paths'].items() for method, operation in item.items()
              if method in {'get', 'post', 'put', 'patch', 'delete'}]
CONTRACT_COUNTS = {}
EXTENSION_CONTRACT = json.loads((Path(__file__).parents[1] / 'contracts/extensions.openapi.json').read_text(encoding='utf-8'))
EXTENSION_OPERATIONS = [(method.upper(), re.compile('^/api/legacy/v1' + re.sub(r'\{[^}]+\}', '[^/]+', path) + '$'), operation)
                       for path, item in EXTENSION_CONTRACT['paths'].items() for method, operation in item.items()
                       if method in {'get', 'post', 'put', 'patch', 'delete'}]
EXTENSION_COUNTS = {}
CONTRACT_LOCK = Lock()


@pytest.fixture(autouse=True)
def validate_real_panel_responses(monkeypatch):
    original = TestClient.request

    def checked(self, method, url, **kwargs):
        response = original(self, method, url, **kwargs)
        specifications = [(verb, pattern, operation, CONTRACT, CONTRACT_COUNTS) for verb, pattern, operation in OPERATIONS]
        specifications += [(verb, pattern, operation, EXTENSION_CONTRACT, EXTENSION_COUNTS)
                           for verb, pattern, operation in EXTENSION_OPERATIONS]
        for verb, pattern, operation, spec, report in specifications:
            if method.upper() != verb or not pattern.fullmatch(response.request.url.path):
                continue
            response_spec = operation['responses'].get(str(response.status_code), operation['responses'].get('default'))
            assert response_spec is not None, f"Undocumented HTTP status: {operation['operationId']} {response.status_code}"
            if '$ref' in response_spec:
                response_spec = spec['components']['responses'][response_spec['$ref'].rsplit('/', 1)[-1]]
            schema = response_spec.get('content', {}).get('application/json', {}).get('schema')
            if schema:
                validator = Draft202012Validator({**schema, 'components': spec['components']}, format_checker=FormatChecker())
                errors = list(validator.iter_errors(response.json()))
                # Paths/rules suffice to diagnose mismatch without printing JWTs.
                assert not errors, (operation['operationId'], response.status_code,
                                    [(list(error.path), error.validator) for error in errors[:8]])
            elif response.status_code == 204:
                assert not response.content
            with CONTRACT_LOCK:
                counts = report.setdefault(operation['operationId'], {})
                counts[str(response.status_code)] = counts.get(str(response.status_code), 0) + 1
        return response

    monkeypatch.setattr(TestClient, 'request', checked)


def pytest_sessionfinish(session, exitstatus):
    reports = Path(__file__).parents[1] / 'reports'
    reports.mkdir(exist_ok=True)
    (reports / 'contract-responses.json').write_text(json.dumps({
        'exitStatus': exitstatus, 'canonicalOperations': 43,
        'observedOperations': len(CONTRACT_COUNTS),
        'responsesChecked': sum(sum(counts.values()) for counts in CONTRACT_COUNTS.values()),
        'responsesByOperation': CONTRACT_COUNTS,
        'unobservedOperations': sorted({operation['operationId'] for _, _, operation in OPERATIONS} - set(CONTRACT_COUNTS)),
        'extensions': {'documentedOperations': len(EXTENSION_OPERATIONS), 'observedOperations': len(EXTENSION_COUNTS),
                       'responsesByOperation': EXTENSION_COUNTS,
                       'unobservedOperations': sorted({op['operationId'] for _, _, op in EXTENSION_OPERATIONS} - set(EXTENSION_COUNTS))},
    }, indent=2) + '\n', encoding='utf-8')


@pytest.fixture(scope='session')
def password_hash():
    return hash_password(PASSWORD)


@pytest.fixture
def app(tmp_path, password_hash):
    database_url = os.environ.get('SNACKUP_TEST_DATABASE_URL')
    schema = None
    if database_url:
        # A fresh schema per test, within the explicitly dedicated test database.
        schema = 'test_' + uuid4().hex
        admin_engine = create_engine(database_url)
        with admin_engine.begin() as connection:
            connection.execute(text(f'CREATE SCHEMA "{schema}"'))
        separator = '&' if '?' in database_url else '?'
        from urllib.parse import quote
        database_url += separator + 'options=' + quote('-c search_path=' + schema)
    else:
        database_url = 'sqlite:///' + (tmp_path / 'test.db').as_posix()
    settings = Settings(environment='test', secret_key='isolated-test-key-' + uuid4().hex,
                        database_url=database_url, public_origin='http://testserver',
                        admin_email_domains='staff.example.edu', student_email_domains='students.example.edu',
                        media_dir=tmp_path / 'media', background_events=False,
                        smtp_host='smtp.example.edu', smtp_from='snackup@staff.example.edu')
    application = create_app(settings)
    application.state.mailbox = []
    application.state.mailer = lambda settings, recipient, subject, body: application.state.mailbox.append(
        {'recipient': recipient, 'subject': subject, 'body': body})
    Base.metadata.create_all(application.state.db.engine)
    with application.state.db.sessions.begin() as db:
        db.add(Career(id='career-1', name='Desarrollo de Software'))
        db.flush()
        db.add(AcademicGroup(id='group-1', career_id='career-1', name='DSM-1'))
        db.add_all([Business(id='business-1', name='Cafetería Uno', cafeteria_id='cafeteria', cafeteria_name='Cafetería', is_open=True),
                    Business(id='business-2', name='Cafetería Dos', cafeteria_id='cafeteria', cafeteria_name='Cafetería', is_open=True)])
        db.flush()
        for identity, role, business in [('master', 'admin', None), ('admin', 'admin', None),
                                          ('operator', 'business', 'business-1'), ('other-operator', 'business', 'business-2'),
                                          ('student', 'user', None), ('other-student', 'user', None)]:
            email = identity + ('@students.example.edu' if role == 'user' else '@staff.example.edu')
            db.add(User(id=identity, email=email, display_name=identity, password_hash=password_hash,
                        role=role, business_id=business, is_active=True, is_master=identity == 'master',
                        email_verified=True, approval_status='approved'))
            if role == 'user':
                db.add(AcademicRecord(email=email, institutional_id='ID-' + identity, display_name=identity,
                                      kind='student', career_id='career-1', group_id='group-1', source='test fixture'))
        db.add(Product(id='product-1', business_id='business-1', name='Torta', category='Comida', price='35.50', stock=10))
    yield application
    application.state.db.dispose()
    if schema:
        with admin_engine.begin() as connection:
            connection.execute(text(f'DROP SCHEMA "{schema}" CASCADE'))
        admin_engine.dispose()


@pytest.fixture
def client(app):
    with TestClient(app, base_url=app.state.settings.public_origin) as client:
        yield client


@pytest.fixture
def tokens(client):
    result = {}
    for identity in ['master', 'admin', 'operator', 'other-operator', 'student', 'other-student']:
        domain = 'students.example.edu' if 'student' in identity else 'staff.example.edu'
        response = client.post('/api/legacy/v1/auth/login', json={'email': identity + '@' + domain, 'password': PASSWORD},
                               headers={'Origin': 'http://testserver'})
        assert response.status_code == 200, response.text
        result[identity] = {'Authorization': 'Bearer ' + response.json()['tokens']['accessToken'], 'Origin': 'http://testserver'}
    return result
