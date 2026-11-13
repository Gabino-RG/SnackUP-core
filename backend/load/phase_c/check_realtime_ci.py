"""Record strict acceptance and public host metadata without copying credentials."""
import json
import os
from pathlib import Path
import platform
import sys


def main():
    report_path = Path(sys.argv[1])
    report = json.loads(report_path.read_text())
    details = report['details']
    integrity = details.get('integrity', {})
    resources = details.get('resources', {})
    checks = {
        'fullFiveMinuteScenario': report['scenario'] == 'P8-1000' and not report['quick'] and report['elapsedSeconds'] >= 300,
        'verifiedClientTls': report.get('transport', {}).get('tlsCertificateValidation') is True
                             and report['transport']['trust'] == 'explicit test CA, client only',
        'oneThousandSubscriptions': details.get('connections') == 1000,
        'fourMeasuredApiWorkers': len(resources.get('workers', [])) == 4,
        'sufficientGeneratorFileLimit': report.get('generatorOpenFilesLimit', {}).get('soft', 0) >= 4096,
        'nonzeroWorkerCpu': all(w['meanCpuPercent'] > 0 for w in resources.get('workers', [])),
        'allExpectedDeliveries': details.get('expectedEvents', 0) > 0 and details.get('receivedEvents') == details.get('expectedEvents'),
        'noMissingUnexpectedOrDuplicateDeliveries': all(details.get(key) == 0 for key in
            ('missingDeliveries', 'unexpectedDeliveries', 'duplicateDeliveries', 'unmappedProductEvents', 'unexpectedDisconnects')),
        'integrityAndDrainedOutbox': all(integrity.get(key) == 0 for key in
            ('negativeStock', 'duplicateNumbers', 'duplicateCodes', 'duplicateKeys', 'inventoryMismatch', 'deadlocks', 'pendingOutbox', 'orders')),
    }
    report['ciChecks'] = checks
    report['success'] = report['success'] and all(checks.values())
    report['failures'].update({'CI: ' + name: 1 for name, ok in checks.items() if not ok})
    report['environment'] = {
        'platform': platform.platform(), 'python': platform.python_version(), 'logicalProcessors': os.cpu_count(),
        'totalRamKiB': int(next(line.split()[1] for line in Path('/proc/meminfo').read_text().splitlines() if line.startswith('MemTotal:'))),
        'serverCpuSet': '0-3', 'appMemoryLimitMiB': 5120, 'postgresMemoryLimitMiB': 2048,
        'tlsGatewayMemoryLimitMiB': 128, 'apiWorkers': 4, 'writeConcurrencyPerWorker': 2,
        'topology': 'Verified TLS gateway -> application Caddy -> four API workers; PostgreSQL and Redis are real temporary services.',
        'resourceScope': 'Container CPU/RAM samples include app, PostgreSQL and the TLS gateway. The generator shares this GitHub runner.',
    }
    report['scopeLimits'] = [
        'This measures the GitHub Actions Linux runner, not the Windows laptop or the future university server.',
        'The load image uses minimal static pages; the unified-container workflow builds and verifies both Flutter applications separately.',
        'Accounts, businesses and products are synthetic and isolated; no production service or external mail/push provider is used.',
        'Connections remain open for this scenario; it does not force token renewal or voluntary reconnects.',
        'The test CA is supplied only to the client and is never installed in the host trust store.',
    ]
    report_path.write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps({'success': report['success'], 'ciChecks': checks}))
    return 0 if report['success'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
