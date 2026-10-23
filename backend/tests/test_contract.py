import json
from pathlib import Path
import re

from openapi_spec_validator import validate


def normalized(path):
    return re.sub(r'\{[^}]+\}', '{}', path)


def test_all_panel_contract_routes_exist_and_snapshot_matches_frontend(app):
    root = Path(__file__).parents[2]
    original = json.loads((root / 'docs/integracion/openapi.json').read_text(encoding='utf-8'))
    bundled = json.loads((root / 'backend/contracts/panels.openapi.json').read_text(encoding='utf-8'))
    assert original == bundled, 'Backend contract snapshot must match the frontend canonical contract.'
    validate(bundled)
    available = {(method, normalized(path.removeprefix('/api/v1')))
                 for path, methods in app.openapi()['paths'].items() for method in methods}
    expected = {(method, normalized(path)) for path, item in bundled['paths'].items()
                for method in item if method in {'get', 'post', 'put', 'patch', 'delete'}}
    assert len(expected) == 43
    assert expected <= available, f'Missing panel routes: {expected - available}'


def test_unconfigured_google_and_http_websocket_return_explicit_errors(client):
    google = client.get('/api/v1/auth/google/start', follow_redirects=False)
    assert google.status_code == 503
    upgrade = client.get('/api/v1/realtime')
    assert upgrade.status_code == 426
