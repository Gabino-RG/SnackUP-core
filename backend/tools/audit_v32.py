"""Compare Markdown route tables and the attached ORM with the live app schema.

Presence of a route is not proof that its payload or business rules match.
This script imports the app but never connects to or migrates a database.
"""
import argparse
import ast
import hashlib
import json
from pathlib import Path
import re
import sys
import tempfile

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from snackup.config import Settings
from snackup.db import Base
from snackup.main import create_app

METHODS = {'get', 'post', 'put', 'patch', 'delete'}


def normalized(path):
    return re.sub(r'\{[^}]+\}', '{id}', path.split('?')[0].removeprefix('/api/v1'))


def attached_tables(source):
    # Do not execute the supplied model file to enumerate its declarations.
    tables = {}
    for cls in ast.parse(source).body:
        if isinstance(cls, ast.ClassDef):
            for node in cls.body:
                if isinstance(node, ast.Assign) and any(isinstance(target, ast.Name) and target.id == '__tablename__'
                                                       for target in node.targets):
                    tables[cls.name] = ast.literal_eval(node.value)
    return tables


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--contract', required=True, type=Path)
    parser.add_argument('--models', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    source = args.contract.read_text()
    documented = set()
    for line in source.splitlines():
        if not line.startswith('|'):
            continue
        cells = [cell.strip().strip('`') for cell in line.strip('|').split('|')]
        for index, cell in enumerate(cells[:-1]):
            if cell.lower() in METHODS and cells[index + 1].startswith('/'):
                documented.add((cell, normalized(cells[index + 1])))
    with tempfile.TemporaryDirectory() as temporary:
        app = create_app(Settings(environment='test', secret_key='inventory-only-' + '0' * 32,
                                  database_url='sqlite://', background_events=False, media_dir=Path(temporary)))
        runtime = {(method.upper(), normalized(path)) for path, item in app.openapi()['paths'].items()
                   if path.startswith('/api/v1/') for method in item if method in METHODS}
        app.state.db.dispose()
    render = lambda routes: [method + ' ' + path for method, path in sorted(routes)]
    result = {
        'scope': 'Route presence and model declarations only; not functional certification',
        'inputs': {path.name: hashlib.sha256(path.read_bytes()).hexdigest() for path in [args.contract, args.models]},
        'documentedRouteCount': len(documented), 'runtimeRouteCount': len(runtime),
        'missingRoutes': render(documented - runtime),
        'runtimeRoutesNotInDocumentTables': render(runtime - documented),
        'runtimeRoutes': render(runtime),
        'attachedModelTables': attached_tables(args.models.read_text()),
        'runtimeTables': sorted(Base.metadata.tables),
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + '\n')
    print(f'{len(runtime)} API operations; {len(documented - runtime)} documented operations absent; '
          f'{len(Base.metadata.tables)} existing SQL tables')


if __name__ == '__main__':
    main()
