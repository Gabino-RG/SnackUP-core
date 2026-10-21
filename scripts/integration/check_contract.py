"""Validate OpenAPI and real fixture responses exercised by the existing suite.

No production URL, credentials, tokens or response bodies are logged.
The review server is a temporary local fixture, not the future SQL backend.
"""
import argparse
import json
from pathlib import Path
import re
import sys
import threading
import unittest
from urllib.parse import urlsplit

from jsonschema import Draft202012Validator, FormatChecker
from openapi_spec_validator import validate

ROOT = Path(__file__).resolve().parents[2]
HTTP = {'get', 'post', 'put', 'patch', 'delete', 'head', 'options'}


class Contract:
    def __init__(self):
        self.spec = json.loads((ROOT / 'docs/integracion/openapi.json').read_text(encoding='utf-8'))
        validate(self.spec)
        self.routes = []
        self.validators = {}
        self.covered = set()
        self.responses = 0
        self.lock = threading.Lock()
        ids = set()
        for route, item in self.spec['paths'].items():
            pattern = re.compile('^' + re.sub(r'\{[^}]+\}', '[^/]+', route) + '$')
            for method, operation in item.items():
                if method not in HTTP:
                    continue
                oid = operation['operationId']
                if oid in ids:
                    raise ValueError('Duplicate operationId: ' + oid)
                ids.add(oid)
                source = ROOT / operation['x-frontend-source']
                if not source.is_file():
                    raise ValueError('Missing frontend source: ' + str(source))
                self.routes.append((method.upper(), pattern, operation))
                for status, response in operation['responses'].items():
                    schema = response.get('content', {}).get('application/json', {}).get('schema')
                    if schema:
                        self.validators[(oid, status)] = self.validator(schema)
        self.ids = ids

    def validator(self, schema):
        # Local refs keep resolving at the document root, with no remote retrieval.
        return Draft202012Validator(
            {**schema, 'components': self.spec['components']}, format_checker=FormatChecker()
        )

    def check_response(self, method, path, status, body):
        route = '/' + urlsplit(path).path.lstrip('/')
        if route.startswith('/review/'):
            return  # Deliberately absent from the production contract.
        matches = [o for m, p, o in self.routes if m == method and p.fullmatch(route)]
        if len(matches) != 1:
            raise AssertionError(f'Undocumented operation: {method} {route}')
        operation = matches[0]
        oid = operation['operationId']
        key = str(status) if str(status) in operation['responses'] else 'default'
        if key == 'default' and status < 400:
            raise AssertionError(f'{oid}: undocumented success status {status}')
        validator = self.validators.get((oid, key))
        if validator:
            errors = list(validator.iter_errors(body))
            if errors:
                # Report paths/rules, never bodies containing credentials or tokens.
                fields = ['.'.join(map(str, e.absolute_path)) + ':' + str(e.validator) for e in errors]
                raise AssertionError(f'{oid} HTTP {status}: ' + ', '.join(fields))
        elif status == 204 and body is not None:
            raise AssertionError(f'{oid}: 204 must be empty')
        with self.lock:
            self.responses += 1
            if status < 400:
                self.covered.add(oid)

    def check_trace(self, records):
        for record in records:
            self.check_response(record['method'], record['path'], record['status'], record['body'])
            route = '/' + urlsplit(record['path']).path.lstrip('/')
            matches = [o for m, p, o in self.routes if m == record['method'] and p.fullmatch(route)]
            if not matches or record['status'] >= 400:
                continue  # Invalid credentials/requests are intentional negative tests.
            schema = matches[0].get('requestBody', {}).get('content', {}).get('application/json', {}).get('schema')
            if schema:
                errors = list(self.validator(schema).iter_errors(record['requestBody']))
                if errors:
                    fields = ['.'.join(map(str, e.absolute_path)) + ':' + str(e.validator) for e in errors]
                    raise AssertionError(matches[0]['operationId'] + ' request: ' + ', '.join(fields))


def run_review(contract):
    sys.path.insert(0, str(ROOT / 'scripts/review'))
    import test_review_server as suite
    original = suite.Client.call

    def checked(client, method, path, *args, **kwargs):
        result = original(client, method, path, *args, **kwargs)
        contract.check_response(method, path, *result)
        return result

    suite.Client.call = checked
    try:
        return unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromModule(suite))
    finally:
        suite.Client.call = original


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--review', action='store_true', help='Also run local review suite against schemas')
    parser.add_argument('--report', type=Path)
    parser.add_argument('--trace', type=Path, help='Validate redacted local browser request/response trace')
    args = parser.parse_args()
    contract = Contract()
    result = run_review(contract) if args.review else None
    if args.trace:
        contract.check_trace(json.loads(args.trace.read_text(encoding='utf-8')))
    report = {
        'openapi_valid': True,
        'operations': len(contract.ids),
        'review_suite_run': result is not None,
        'browser_trace_validated': args.trace is not None,
        'tests': result.testsRun if result else 0,
        'passed': result.wasSuccessful() if result else None,
        'responses_validated': contract.responses,
        'successful_operations_exercised': sorted(contract.covered),
        'operations_without_successful_fixture_response': sorted(contract.ids - contract.covered),
        'production_backend_tested': False,
        'scope': 'Schema validation and temporary local simulator; not SQL/TLS/OAuth/load certification.',
    }
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(report, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')
    print(json.dumps(report, ensure_ascii=False))
    return 0 if result is None or result.wasSuccessful() else 1


if __name__ == '__main__':
    raise SystemExit(main())
