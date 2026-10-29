import json
from pathlib import Path
import re

from openapi_spec_validator import validate
from starlette.routing import Match


def normalized(path):
    return re.sub(r'\{[^}]+\}', '{}', path)


def test_all_panel_contract_routes_exist_and_snapshot_matches_frontend(app):
    root = Path(__file__).parents[2]
    original = json.loads((root / 'docs/integracion/openapi.json').read_text(encoding='utf-8'))
    bundled = json.loads((root / 'backend/contracts/panels.openapi.json').read_text(encoding='utf-8'))
    assert original == bundled, 'Backend contract snapshot must match the frontend canonical contract.'
    validate(bundled)
    # Legacy is intentionally omitted from the canonical V3 Swagger document.
    # Verify mounted HTTP routes instead of confusing hidden documentation with
    # a removed compatibility endpoint.
    expected = {(method, normalized(path)) for path, item in bundled['paths'].items()
                for method in item if method in {'get', 'post', 'put', 'patch', 'delete'}}
    assert len(expected) == 43
    missing = set()
    for method, template in expected:
        path = '/api/legacy/v1' + template.replace('{}', 'contract-resource')
        scope = {'type': 'http', 'path': path, 'root_path': '', 'method': method.upper()}
        # Public route matching also handles FastAPI's lazily included routers.
        if not any(route.matches(scope.copy())[0] == Match.FULL for route in app.routes):
            missing.add((method, template))
    assert not missing, f'Missing panel routes: {missing}'


def test_unconfigured_google_and_http_websocket_return_explicit_errors(client):
    google = client.get('/api/legacy/v1/auth/google/start', follow_redirects=False)
    assert google.status_code == 503
    upgrade = client.get('/api/legacy/v1/realtime')
    assert upgrade.status_code == 426
