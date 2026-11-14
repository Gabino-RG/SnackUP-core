"""Real cookies, role authorization and origin checks for separate staff sites."""
import json
import re

import pytest
from fastapi.testclient import TestClient
from pydantic import ValidationError
from sqlalchemy import func, select
from starlette.websockets import WebSocketDisconnect

from conftest import PASSWORD
from snackup.auth import password_matches
from snackup.config import Settings
from snackup.identity_models import AcademicRecord, AccessRequest, RefreshSession, User
from snackup.main import create_app

STUDENT = 'http://testserver'
KITCHEN = 'http://cocina.testserver'
ADMIN = 'http://administracion.testserver'
LEGACY = '/api/legacy/v1'


@pytest.fixture
def isolated_portals(app):
    settings = Settings(**{**app.state.settings.model_dump(),
        'kitchen_public_origin': KITCHEN, 'administration_public_origin': ADMIN,
        'kitchen_password_reset_frontend_path': '/', 'admin_password_reset_frontend_path': '/',
        'student_password_reset_frontend_path': '/'})
    application = create_app(settings)
    application.state.mailbox = []
    application.state.mailer = lambda settings, recipient, subject, body: application.state.mailbox.append(body)
    with TestClient(application, base_url=STUDENT) as browser:
        yield application, browser


def login(browser, origin, identity, version=LEGACY):
    domain = 'students.example.edu' if identity == 'student' else 'staff.example.edu'
    return browser.post(origin + version + '/auth/login', headers={'Origin': origin},
                        json={'email': identity + '@' + domain, 'password': PASSWORD})


def refresh(browser, origin, version=LEGACY):
    return browser.post(origin + version + '/auth/refresh', headers={'Origin': origin}, json={})


def test_three_accounts_keep_independent_host_only_cookies(isolated_portals):
    _, browser = isolated_portals
    for origin, identity, cookie in [(STUDENT, 'student', 'snackup_refresh'),
                                     (KITCHEN, 'operator', 'snackup_refresh_cocina'),
                                     (ADMIN, 'master', 'snackup_refresh_administracion')]:
        response = login(browser, origin, identity)
        assert response.status_code == 200
        value = response.headers['set-cookie']
        assert value.startswith(cookie + '=') and 'Path=/api' in value
        assert 'HttpOnly' in value and 'SameSite=strict' in value and 'Domain=' not in value
    assert len(browser.cookies) == 3
    for origin, identity in [(STUDENT, 'student'), (KITCHEN, 'operator'), (ADMIN, 'master')]:
        response = refresh(browser, origin)
        assert response.status_code == 200
        token = response.json()['tokens']['accessToken']
        profile = browser.get(origin + LEGACY + '/users/me', headers={'Authorization': 'Bearer ' + token})
        assert profile.status_code == 200 and profile.json()['id'] == identity
    assert browser.post(ADMIN + LEGACY + '/auth/logout', json={}, headers={'Origin': ADMIN}).status_code == 204
    assert refresh(browser, ADMIN).status_code == 401
    assert refresh(browser, KITCHEN).status_code == refresh(browser, STUDENT).status_code == 200


@pytest.mark.parametrize('version', [LEGACY, '/api/v1'])
@pytest.mark.parametrize('origin,identity', [(KITCHEN, 'master'), (ADMIN, 'operator'), (KITCHEN, 'student')])
def test_wrong_role_login_cannot_create_or_replace_session(isolated_portals, version, origin, identity):
    app, browser = isolated_portals
    response = login(browser, origin, identity, version)
    assert response.status_code == 403 and response.json()['error']['code'] == 'PORTAL_ROLE_MISMATCH'
    assert 'set-cookie' not in response.headers
    with app.state.db.sessions() as db:
        assert db.scalar(select(func.count()).select_from(RefreshSession)) == 0


@pytest.mark.parametrize('version', [LEGACY, '/api/v1'])
@pytest.mark.parametrize('identity', ['master', 'operator'])
def test_student_origin_cannot_issue_browser_staff_sessions(isolated_portals, version, identity):
    app, browser = isolated_portals
    response = login(browser, STUDENT, identity, version)
    assert response.status_code == 403 and response.json()['error']['code'] == 'PORTAL_ORIGIN_MISMATCH'
    assert 'set-cookie' not in response.headers
    with app.state.db.sessions() as db:
        assert db.scalar(select(func.count()).select_from(RefreshSession)) == 0


@pytest.mark.parametrize('role', ['admin', 'business'])
def test_student_origin_cannot_register_staff_accounts(isolated_portals, role):
    app, browser = isolated_portals
    payload = {'email': 'new@staff.example.edu', 'password': PASSWORD,
               'displayName': 'New staff', 'context': 'Local', 'requestedRole': role}
    response = browser.post(STUDENT + LEGACY + '/auth/register', json=payload, headers={'Origin': STUDENT})
    assert response.status_code == 403 and response.json()['error']['code'] == 'PORTAL_ORIGIN_MISMATCH'
    assert not app.state.mailbox


@pytest.mark.parametrize('version', [LEGACY, '/api/v1'])
@pytest.mark.parametrize('identity', ['master', 'operator'])
def test_native_staff_api_survives_and_old_root_browser_cannot_restore_session(isolated_portals, version, identity):
    _, browser = isolated_portals
    response = browser.post(STUDENT + '/api/v1/auth/login',
        json={'email': identity + '@staff.example.edu', 'password': PASSWORD})
    assert response.status_code == 200 and 'set-cookie' not in response.headers
    initial = response.json()['tokens']['refreshToken']
    response = browser.post(STUDENT + '/api/v1/auth/refresh', json={'refreshToken': initial})
    assert response.status_code == 200 and 'set-cookie' not in response.headers
    current = response.json()['tokens']['refreshToken']
    # An old cookie, including a rotated one, must neither restore a browser
    # session on the students' site nor revoke this native token family.
    for raw in (initial, current):
        response = browser.post(STUDENT + version + '/auth/refresh', json={}, headers={
            'Origin': STUDENT, 'Cookie': 'snackup_refresh=' + raw})
        assert response.status_code == 403 and response.json()['error']['code'] == 'PORTAL_ORIGIN_MISMATCH'
        assert 'set-cookie' not in response.headers
    response = browser.post(STUDENT + '/api/v1/auth/refresh', json={'refreshToken': current})
    assert response.status_code == 200
    current = response.json()['tokens']['refreshToken']
    # Keep root logout available to clean pre-migration browser cookies.
    response = browser.post(STUDENT + version + '/auth/logout', json={}, headers={
        'Origin': STUDENT, 'Cookie': 'snackup_refresh=' + current})
    assert response.status_code == 204 and response.headers['set-cookie'].startswith('snackup_refresh=')
    assert browser.post(STUDENT + '/api/v1/auth/refresh', json={'refreshToken': current}).status_code == 401


@pytest.mark.parametrize('version', [LEGACY, '/api/v1'])
def test_cross_origin_requests_and_cross_role_bearers_are_rejected(isolated_portals, version):
    _, browser = isolated_portals
    kitchen = login(browser, KITCHEN, 'operator', version).json()['tokens']['accessToken']
    admin = login(browser, ADMIN, 'master', version).json()['tokens']['accessToken']
    assert browser.get(ADMIN + version + '/users/me', headers={'Authorization': 'Bearer ' + kitchen}).status_code == 403
    assert browser.get(KITCHEN + version + '/users/me', headers={'Authorization': 'Bearer ' + admin}).status_code == 403
    for other in (STUDENT, KITCHEN, 'http://untrusted.test'):
        response = browser.post(ADMIN + version + '/auth/refresh', json={}, headers={'Origin': other})
        assert response.status_code == 403 and 'set-cookie' not in response.headers
    assert refresh(browser, ADMIN, version).status_code == 200
    assert refresh(browser, KITCHEN, version).status_code == 200


@pytest.mark.parametrize('version', [LEGACY, '/api/v1'])
def test_wrong_role_logout_token_does_not_revoke_other_portal(isolated_portals, version):
    _, browser = isolated_portals
    kitchen = login(browser, KITCHEN, 'operator', version).json()['tokens']['accessToken']
    login(browser, ADMIN, 'master', version)
    result = browser.post(ADMIN + version + '/auth/logout', json={}, headers={
        'Origin': ADMIN, 'Authorization': 'Bearer ' + kitchen})
    assert result.status_code == 204
    assert refresh(browser, ADMIN, version).status_code == 401
    assert refresh(browser, KITCHEN, version).status_code == 200


@pytest.mark.parametrize('version', [LEGACY, '/api/v1'])
def test_foreign_refresh_cookie_cannot_revoke_family_even_if_replayed(isolated_portals, version):
    _, browser = isolated_portals
    login(browser, ADMIN, 'master', version)
    cookie = browser.cookies.get('snackup_refresh_administracion')
    assert refresh(browser, ADMIN, version).status_code == 200
    result = browser.post(KITCHEN + version + '/auth/refresh', json={}, headers={
        'Origin': KITCHEN, 'Cookie': 'snackup_refresh_cocina=' + cookie})
    assert result.status_code == 403
    assert refresh(browser, ADMIN, version).status_code == 200


def test_shared_host_aliases_cannot_bypass_configured_domains(isolated_portals):
    _, browser = isolated_portals
    for url in (STUDENT + '/cocina' + LEGACY + '/auth/options',
                STUDENT + '/administracion' + LEGACY + '/auth/options',
                KITCHEN + '/administracion' + LEGACY + '/auth/options'):
        assert browser.get(url).status_code == 403


@pytest.mark.parametrize('method', ['GET', 'HEAD'])
@pytest.mark.parametrize('origin', [KITCHEN, ADMIN])
def test_public_media_is_readable_from_configured_staff_origins(isolated_portals, method, origin):
    app, browser = isolated_portals
    from PIL import Image
    Image.new('RGB', (2, 2), 'blue').save(app.state.settings.media_dir / 'portal-image.webp', 'WEBP')
    response = browser.request(method, STUDENT + '/media/portal-image.webp', headers={'Origin': origin})
    assert response.status_code == 200 and response.headers['content-type'] == 'image/webp'
    assert response.headers['access-control-allow-origin'] == origin
    assert 'Origin' in response.headers['vary']
    assert 'access-control-allow-credentials' not in response.headers and 'set-cookie' not in response.headers
    assert bool(response.content) == (method == 'GET')


@pytest.mark.parametrize('origin', [None, 'null', 'http://untrusted.test', KITCHEN + '.untrusted.test', STUDENT])
def test_media_cors_never_allows_other_origins(isolated_portals, origin):
    app, browser = isolated_portals
    (app.state.settings.media_dir / 'image.webp').write_bytes(b'public-media-fixture')
    response = browser.get(STUDENT + '/media/image.webp', headers={'Origin': origin} if origin else {})
    # Files remain public; CORS only authorizes browser canvas access for the
    # exact configured staff origins, not arbitrary sites or credentials.
    assert response.status_code == 200 and 'Origin' in response.headers['vary']
    assert 'access-control-allow-origin' not in response.headers
    assert 'access-control-allow-credentials' not in response.headers


def test_media_cors_supports_cache_revalidation_but_not_errors(isolated_portals):
    app, browser = isolated_portals
    (app.state.settings.media_dir / 'cache.webp').write_bytes(b'public-media-fixture')
    response = browser.get(STUDENT + '/media/cache.webp')
    response = browser.get(STUDENT + '/media/cache.webp', headers={'Origin': KITCHEN, 'If-None-Match': response.headers['etag']})
    assert response.status_code == 304 and response.headers['access-control-allow-origin'] == KITCHEN
    assert 'Origin' in response.headers['vary'] and 'access-control-allow-credentials' not in response.headers
    response = browser.get(STUDENT + '/media/missing.webp', headers={'Origin': KITCHEN})
    assert response.status_code == 404 and 'Origin' in response.headers['vary']
    assert 'access-control-allow-origin' not in response.headers


@pytest.mark.parametrize('method,path', [
    ('OPTIONS', '/media/image.webp'), ('POST', '/media/image.webp'),
    ('GET', '/api/v1/auth/options'), ('GET', '/api/v1/users/me'),
    ('GET', '/api/legacy/v1/auth/options'), ('GET', '/health/live'),
])
def test_public_media_cors_does_not_open_writes_preflight_or_api(isolated_portals, method, path):
    _, browser = isolated_portals
    response = browser.request(method, STUDENT + path, headers={
        'Origin': KITCHEN, 'Access-Control-Request-Method': 'GET'})
    assert 'access-control-allow-origin' not in response.headers
    assert 'access-control-allow-credentials' not in response.headers
    if method in {'OPTIONS', 'POST'}:
        assert response.status_code in {403, 405}


def test_path_fallback_has_separate_cookies_and_preserves_guards(client):
    for portal, identity in [('cocina', 'operator'), ('administracion', 'master')]:
        response = login(client, STUDENT + '/' + portal, identity)
        # The browser Origin never includes a path.
        assert response.status_code == 403
        response = client.post('/' + portal + LEGACY + '/auth/login', headers={'Origin': STUDENT},
            json={'email': identity + '@staff.example.edu', 'password': PASSWORD})
        assert response.status_code == 200
        assert 'Path=/' + portal + '/api' in response.headers['set-cookie']
    assert len(client.cookies) == 2
    response = client.post('/cocina' + LEGACY + '/auth/login', content='x' * (65 * 1024),
        headers={'Origin': STUDENT, 'Content-Type': 'application/json'})
    assert response.status_code == 413


def test_scoped_registration_cannot_request_another_role(isolated_portals):
    app, browser = isolated_portals
    payload = {'email': 'new@staff.example.edu', 'password': PASSWORD,
               'displayName': 'New kitchen', 'context': 'Local', 'requestedRole': 'admin'}
    assert browser.post(KITCHEN + LEGACY + '/auth/register', json=payload, headers={'Origin': KITCHEN}).status_code == 403
    payload['requestedRole'] = 'business'
    assert browser.post(KITCHEN + LEGACY + '/auth/register', json=payload, headers={'Origin': KITCHEN}).status_code == 202
    assert KITCHEN + '/api/v1/auth/verify-email#token=' in app.state.mailbox[-1]
    token = re.search(r'token=([A-Za-z0-9_-]+)', app.state.mailbox[-1]).group(1)
    assert browser.post(ADMIN + '/api/v1/auth/verify-email', json={'token': token}, headers={'Origin': ADMIN}).status_code == 403
    result = browser.post(KITCHEN + '/api/v1/auth/verify-email', json={'token': token}, headers={'Origin': KITCHEN})
    assert result.status_code == 204 and result.headers['X-SnackUP-Login-Path'] == '/'


def test_password_recovery_stays_on_account_origin_and_wrong_portal_does_not_consume_token(isolated_portals):
    app, browser = isolated_portals
    for origin, identity in [(KITCHEN, 'operator'), (ADMIN, 'master')]:
        result = browser.post(origin + LEGACY + '/auth/forgot-password',
            json={'email': identity + '@staff.example.edu'}, headers={'Origin': origin})
        assert result.status_code == 204
        assert origin + '/#/reset-password?token=' in app.state.mailbox[-1]
    token = re.search(r'token=([A-Za-z0-9_-]+)', app.state.mailbox[-1]).group(1)
    body = {'token': token, 'newPassword': 'Replacement-password-45!'}
    assert browser.post(KITCHEN + LEGACY + '/auth/reset-password', json=body, headers={'Origin': KITCHEN}).status_code == 403
    assert browser.post(ADMIN + LEGACY + '/auth/reset-password', json=body, headers={'Origin': ADMIN}).status_code == 204


@pytest.mark.parametrize('version', [LEGACY, '/api/v1'])
def test_pending_staff_password_recovery_uses_requested_portal(isolated_portals, version):
    app, browser = isolated_portals
    payload = {'email': 'new@staff.example.edu', 'password': PASSWORD,
               'displayName': 'New kitchen', 'context': 'Local', 'requestedRole': 'business'}
    assert browser.post(KITCHEN + LEGACY + '/auth/register', json=payload, headers={'Origin': KITCHEN}).status_code == 202
    result = browser.post(KITCHEN + version + '/auth/forgot-password', json={'email': payload['email']},
        headers={'Origin': KITCHEN})
    assert result.status_code == 204 and KITCHEN + '/#/reset-password?token=' in app.state.mailbox[-1]
    token = re.search(r'token=([A-Za-z0-9_-]+)', app.state.mailbox[-1]).group(1)
    replacement = 'Replacement-password-45!'
    result = browser.post(KITCHEN + version + '/auth/reset-password', json={'token': token, 'newPassword': replacement},
        headers={'Origin': KITCHEN})
    assert result.status_code == 204
    with app.state.db.sessions() as db:
        user = db.scalar(select(User).where(User.email == payload['email']))
        assert password_matches(replacement, user.password_hash) and user.role == 'pending' and not user.is_active


@pytest.mark.parametrize('version', [LEGACY, '/api/v1'])
def test_student_collision_proof_keeps_student_origin(isolated_portals, password_hash, version):
    app, browser = isolated_portals
    email = 'collision@students.example.edu'
    with app.state.db.sessions.begin() as db:
        db.add(AcademicRecord(email=email, institutional_id='CTRL-COLLISION', display_name='Student',
            kind='student', career_id='career-1', group_id='group-1', source='isolated portal fixture'))
        db.add(User(id='collision', email=email, display_name='Unverified staff', role='pending', is_active=False,
            approval_status='pending', email_verified=False, password_hash=password_hash))
        db.flush()
        db.add(AccessRequest(user_id='collision', email=email, display_name='Unverified staff',
            requested_role='business', request_context='Old request'))
    response = browser.post(STUDENT + '/api/v1/auth/register', headers={'Origin': STUDENT},
        json={'email': email, 'password': PASSWORD, 'displayName': 'Student', 'numeroDeControl': 'CTRL-COLLISION'})
    assert response.status_code == 202 and STUDENT + '/api/v1/auth/verify-email#token=' in app.state.mailbox[-1]
    response = browser.post(STUDENT + version + '/auth/resend-verification', headers={'Origin': STUDENT}, json={'email': email})
    assert response.status_code == 202 and STUDENT + '/api/v1/auth/verify-email#token=' in app.state.mailbox[-1]
    token = re.search(r'token=([A-Za-z0-9_-]+)', app.state.mailbox[-1]).group(1)
    assert browser.post(KITCHEN + version + '/auth/verify-email', headers={'Origin': KITCHEN}, json={'token': token}).status_code == 403
    assert browser.post(STUDENT + version + '/auth/verify-email', headers={'Origin': STUDENT}, json={'token': token}).status_code == 204
    with app.state.db.sessions() as db:
        user = db.get(User, 'collision')
        assert user.role == 'user' and user.is_active and user.email_verified


def test_staff_origins_cannot_share_a_hostname_even_on_different_ports(app):
    values = app.state.settings.model_dump()
    with pytest.raises(ValidationError):
        Settings(**{**values, 'kitchen_public_origin': 'http://testserver:8001'})
    with pytest.raises(ValidationError):
        Settings(**{**values, 'kitchen_public_origin': KITCHEN, 'administration_public_origin': KITCHEN + ':8001'})
    normalized = Settings(**{**values, 'administration_public_origin': 'https://ADMINISTRACION.TESTSERVER:443/'})
    assert normalized.administration_public_origin == 'https://administracion.testserver'


def test_https_staff_cookies_require_host_prefix_and_ignore_legacy_cookie(app):
    origin = KITCHEN.replace('http:', 'https:')
    settings = Settings(**{**app.state.settings.model_dump(), 'kitchen_public_origin': origin,
        'administration_public_origin': ADMIN.replace('http:', 'https:')})
    secured = create_app(settings)
    with TestClient(secured, base_url=origin) as browser:
        response = login(browser, origin, 'operator')
        cookie = response.headers['set-cookie']
        assert cookie.startswith('__Host-snackup_refresh_cocina=')
        assert 'Path=/;' in cookie and 'Secure' in cookie and 'HttpOnly' in cookie and 'Domain=' not in cookie
        denied = browser.post(LEGACY + '/auth/refresh', json={}, headers={
            'Origin': origin, 'Cookie': 'snackup_refresh_cocina=untrusted-parent-domain-cookie'})
        assert denied.status_code == 401
        assert refresh(browser, origin).status_code == 200
        response = browser.post(LEGACY + '/auth/logout', json={}, headers={'Origin': origin})
        assert response.status_code == 204 and response.headers['set-cookie'].startswith('__Host-snackup_refresh_cocina=')
        assert 'Path=/;' in response.headers['set-cookie'] and 'Secure' in response.headers['set-cookie']
        assert refresh(browser, origin).status_code == 401


@pytest.mark.parametrize('host', ['administracion.testserver:443', 'ADMINISTRACION.TESTSERVER', 'ADMINISTRACION.TESTSERVER:443'])
def test_default_port_or_host_case_does_not_remove_role_boundary(app, host):
    origin = ADMIN.replace('http:', 'https:')
    settings = Settings(**{**app.state.settings.model_dump(), 'administration_public_origin': origin})
    application = create_app(settings)
    with TestClient(application, base_url=origin) as browser:
        # Native V3 login deliberately has no Origin. Host must still select the
        # administration boundary rather than falling back to the general API.
        response = browser.post('/api/v1/auth/login', headers={'Host': host},
            json={'email': 'operator@staff.example.edu', 'password': PASSWORD})
        assert response.status_code == 403 and response.json()['error']['code'] == 'PORTAL_ROLE_MISMATCH'
        assert 'set-cookie' not in response.headers


@pytest.mark.parametrize('headers', [
    [('Host', 'administracion.testserver'), ('Host', 'testserver')],
    {'Host': 'administracion.testserver.'}, {'Host': 'administracion.testserver:1234'},
    {'Host': 'administracion.testserver:0'}, {'Host': 'administracion.testserver:'},
    {'Host': '@administracion.testserver'},
])
def test_ambiguous_or_wrong_staff_authority_is_rejected(isolated_portals, headers):
    _, browser = isolated_portals
    response = browser.post(ADMIN + '/api/v1/auth/login', headers=headers,
        json={'email': 'operator@staff.example.edu', 'password': PASSWORD})
    assert response.status_code == 403 and response.json()['error']['code'] == 'PORTAL_ORIGIN_MISMATCH'


def _packet(ws):
    while True:
        value = ws.receive_text()
        if value == '2':
            ws.send_text('3')
        else:
            return value


def test_staff_websockets_enforce_origin_and_role(isolated_portals):
    _, browser = isolated_portals
    token = login(browser, KITCHEN, 'operator').json()['tokens']['accessToken']
    admin = login(browser, ADMIN, 'master').json()['tokens']['accessToken']
    for origin, candidate, accepted in [(KITCHEN, token, True), (ADMIN, token, False), (KITCHEN, admin, False)]:
        url = origin.replace('http:', 'ws:') + '/socket.io/?EIO=4&transport=websocket'
        with browser.websocket_connect(url, headers={'Origin': origin, 'Upgrade': 'websocket'}) as ws:
            assert _packet(ws).startswith('0{')
            ws.send_text('40' + json.dumps({'token': candidate}))
            assert _packet(ws).startswith('40{' if accepted else '44')
    with pytest.raises(WebSocketDisconnect):
        with browser.websocket_connect(ADMIN.replace('http:', 'ws:') + LEGACY + '/realtime', headers={'Origin': KITCHEN}):
            pytest.fail('Cross-origin legacy websocket accepted')
    with browser.websocket_connect(KITCHEN.replace('http:', 'ws:') + LEGACY + '/realtime', headers={'Origin': KITCHEN}) as ws:
        ws.send_json({'action': 'auth', 'token': admin})
        assert ws.receive_json()['type'] == 'unauthorized'


def test_root_websocket_preserves_native_staff_but_rejects_student_browser(isolated_portals):
    _, browser = isolated_portals
    token = browser.post(STUDENT + '/api/v1/auth/login',
        json={'email': 'operator@staff.example.edu', 'password': PASSWORD}).json()['tokens']['accessToken']
    url = STUDENT.replace('http:', 'ws:') + '/socket.io/?EIO=4&transport=websocket'
    for headers, accepted in [({'Upgrade': 'websocket'}, True), ({'Upgrade': 'websocket', 'Origin': STUDENT}, False)]:
        with browser.websocket_connect(url, headers=headers) as ws:
            assert _packet(ws).startswith('0{')
            ws.send_text('40' + json.dumps({'token': token}))
            assert _packet(ws).startswith('40{' if accepted else '44')
    with browser.websocket_connect(STUDENT.replace('http:', 'ws:') + LEGACY + '/realtime', headers={'Origin': STUDENT}) as ws:
        ws.send_json({'action': 'auth', 'token': token})
        assert ws.receive_json()['type'] == 'unauthorized'
