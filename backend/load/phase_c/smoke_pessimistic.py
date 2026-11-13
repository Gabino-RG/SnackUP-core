"""Fetch both compiled clients and API options through verified local HTTPS."""
import argparse
import json
from pathlib import Path
import ssl
from urllib.parse import urlsplit
from urllib.request import HTTPSHandler, ProxyHandler, build_opener

from deploy.smoke_apps import NoRedirect, Smoke, require
from load.phase_c.runner import load_transport


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', required=True)
    args = parser.parse_args()
    base, context, transport = load_transport()
    require(context is not None and context.check_hostname and context.verify_mode == ssl.CERT_REQUIRED,
            'This complete-app smoke requires verified HTTPS')
    probe = Smoke(base, urlsplit(base).netloc, base)
    probe.opener = build_opener(ProxyHandler({}), NoRedirect(), HTTPSHandler(context=context))
    errors = []
    try:
        require(probe.json('/health/ready') == {'status': 'ready'}, 'Backend unavailable')
        probe.frontend('/', integrated=True)
        probe.frontend('/paneles/', integrated=True)
        for path in ('/api/v1/auth/options', '/api/legacy/v1/auth/options'):
            require(probe.json(path)['passwordLogin'] is True, 'Password login unavailable')
    except Exception as error:
        errors.append(type(error).__name__)
    report = {'success': not errors and all(row['ok'] for row in probe.results), 'transport': transport,
              'errors': errors, 'results': probe.results, 'generatorAffinity': sorted(__import__('os').sched_getaffinity(0))}
    Path(args.output).write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps({'success': report['success'], 'checks': len(probe.results), 'errors': errors}))
    return 0 if report['success'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
