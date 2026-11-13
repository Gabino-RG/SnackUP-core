"""Inspect effective Linux cgroups; report only public service/resource metadata."""
import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path, PurePosixPath
import platform
import subprocess
import time

MIB = 2**20
BUDGET = {'app': 1152 * MIB, 'db': 768 * MIB, 'tls': 128 * MIB}
TOTAL = 2 * 2**30
RUNTIME = {'SNACKUP_WORKERS': '1', 'SNACKUP_WRITE_CONCURRENCY': '1',
           'SNACKUP_PASSWORD_CONCURRENCY': '2', 'SNACKUP_POOL_SIZE': '10', 'SNACKUP_MAX_OVERFLOW': '5'}


def cpus(value):
    result = set()
    for part in value.split(','):
        if not part:
            continue
        ends = part.split('-')
        first, last = int(ends[0]), int(ends[-1])
        if len(ends) > 2 or first < 0 or last < first or last > 4096:
            raise ValueError('Invalid CPU set')
        result.update(range(first, last + 1))
    return result


def read_numbers(path):
    return {parts[0]: int(parts[1]) for line in path.read_text().splitlines() if (parts := line.split())}


def cgroup_for_pid(pid):
    line = next(line for line in Path(f'/proc/{pid}/cgroup').read_text().splitlines() if line.startswith('0::'))
    relative = PurePosixPath(line.split(':', 2)[2])
    if '..' in relative.parts:
        raise ValueError('Unexpected cgroup path')
    root = Path('/sys/fs/cgroup').resolve()
    group = (root / str(relative).lstrip('/')).resolve()
    if not group.is_relative_to(root):
        raise ValueError('Unexpected cgroup location')
    return group


def _json_rows(raw):
    if not raw.strip():
        return []
    try:
        value = json.loads(raw)
        return value if isinstance(value, list) else [value]
    except ValueError:
        return [json.loads(line) for line in raw.splitlines() if line.strip()]


def host_metadata():
    cpu_info = Path('/proc/cpuinfo').read_text()
    memory = read_numbers(Path('/proc/meminfo'))
    return {'platform': platform.platform(), 'logicalProcessors': os.cpu_count(),
            'model': next((line.split(':', 1)[1].strip() for line in cpu_info.splitlines() if line.startswith('model name')), 'unavailable'),
            'totalRamKiB': memory['MemTotal:'], 'totalSwapKiB': memory['SwapTotal:']}


def sample_limits():
    sample = {'utc': datetime.now(timezone.utc).isoformat(), 'monotonicSeconds': time.monotonic(),
              'generatorAffinity': sorted(os.sched_getaffinity(0)), 'services': {}, 'errors': []}
    project = os.environ['COMPOSE_PROJECT_NAME']
    if not project.startswith('snackup-pessimistic-'):
        raise ValueError('Only the dedicated pessimistic CI project may be inspected')
    try:
        raw = subprocess.check_output(['docker', 'compose', '--env-file', '/dev/null', 'ps', '--all', '--format', 'json'], text=True, timeout=10)
        rows = _json_rows(raw)
        if len(rows) != 3 or {row.get('Service') for row in rows} != set(BUDGET):
            raise ValueError('Expected exactly app, db and tls services')
        ids = [row['ID'] for row in rows]
        inspected = json.loads(subprocess.check_output(['docker', 'inspect', *ids], text=True, timeout=10))
        for container in inspected:
            labels = container['Config']['Labels']
            service = labels['com.docker.compose.service']
            if labels.get('com.docker.compose.project') != project or service not in BUDGET:
                raise ValueError('Container ownership mismatch')
            config, state = container['HostConfig'], container['State']
            result = {'id': container['Id'], 'imageId': container['Image'], 'pid': state['Pid'], 'state': state['Status'],
                      'health': state.get('Health', {}).get('Status'), 'oomKilled': state['OOMKilled'],
                      'restarts': container['RestartCount'], 'configuredMemoryBytes': config['Memory'],
                      'configuredMemorySwapBytes': config['MemorySwap'], 'configuredCpuSet': config['CpusetCpus'],
                      'configuredCpuQuota': config['CpuQuota'], 'configuredCpuPeriod': config['CpuPeriod']}
            sample['services'][service] = result
            if service == 'app':
                # Explicit public numeric settings only: never serialize credentials or the full environment.
                result['runtimeSettings'] = {key: value for item in container['Config'].get('Env', [])
                                             for key, _, value in [item.partition('=')] if key in RUNTIME}
            group = cgroup_for_pid(state['Pid'])
            result['cgroup'] = {
                'memoryMax': (group / 'memory.max').read_text().strip(),
                'memorySwapMax': (group / 'memory.swap.max').read_text().strip(),
                'memoryCurrentBytes': int((group / 'memory.current').read_text()),
                'memoryPeakBytes': int((group / 'memory.peak').read_text()) if (group / 'memory.peak').exists() else None,
                'memoryEvents': read_numbers(group / 'memory.events'),
                'cpuSetEffective': (group / 'cpuset.cpus.effective').read_text().strip(),
                'cpuMax': (group / 'cpu.max').read_text().strip(),
                'cpuStat': read_numbers(group / 'cpu.stat'),
            }
    except Exception as error:
        # Never copy Docker inspect's environment, commands, labels or stderr into reports.
        sample['errors'].append(type(error).__name__)
    return sample


def validate_history(samples):
    samples = list(samples)
    checks = {'samplesPresent': bool(samples), 'allSamplesReadable': bool(samples),
              'exactThreeServices': bool(samples), 'generatorOnSeparateCpuSet': bool(samples),
              'configuredBudgetIsExactlyTwoGiB': bool(samples), 'effectiveCgroupLimitsApplied': bool(samples),
              'sharedTwoCpuSet': bool(samples), 'noAdditionalSwap': bool(samples),
              'noOomOrRestart': bool(samples), 'allServicesRunning': bool(samples), 'containerIdentityStable': bool(samples),
              'singleWorkerRuntimeSettings': bool(samples)}
    peaks = {service: 0 for service in BUDGET}
    maximum_total = 0
    initial_ids = {service: samples[0].get('services', {}).get(service, {}).get('id') for service in BUDGET} if samples else {}
    for sample in samples:
        checks['allSamplesReadable'] &= not sample.get('errors')
        services = sample.get('services', {})
        checks['exactThreeServices'] &= set(services) == set(BUDGET)
        checks['generatorOnSeparateCpuSet'] &= sample.get('generatorAffinity') == [2, 3]
        checks['configuredBudgetIsExactlyTwoGiB'] &= sum(row.get('configuredMemoryBytes', 0) for row in services.values()) == TOTAL
        checks['singleWorkerRuntimeSettings'] &= services.get('app', {}).get('runtimeSettings') == RUNTIME
        total = 0
        for service, budget in BUDGET.items():
            row = services.get(service, {})
            group = row.get('cgroup', {})
            checks['containerIdentityStable'] &= bool(row.get('id')) and row.get('id') == initial_ids.get(service)
            checks['effectiveCgroupLimitsApplied'] &= (row.get('configuredMemoryBytes') == budget and group.get('memoryMax') == str(budget))
            checks['noAdditionalSwap'] &= (row.get('configuredMemorySwapBytes') == budget and group.get('memorySwapMax') == '0')
            try:
                checks['sharedTwoCpuSet'] &= cpus(row.get('configuredCpuSet', '')) == cpus(group.get('cpuSetEffective', '')) == {0, 1}
            except (ValueError, TypeError):
                checks['sharedTwoCpuSet'] = False
            events = group.get('memoryEvents', {})
            checks['noOomOrRestart'] &= (row.get('oomKilled') is False and row.get('restarts') == 0
                                       and events.get('oom', -1) == events.get('oom_kill', -1) == 0)
            checks['allServicesRunning'] &= row.get('state') == 'running'
            current = group.get('memoryCurrentBytes', 0)
            peaks[service] = max(peaks[service], group.get('memoryPeakBytes') or current)
            total += current
        maximum_total = max(maximum_total, total)
    return {'success': all(checks.values()), 'checks': checks, 'samples': len(samples),
            'sampledCombinedPeakBytes': maximum_total, 'cgroupPeakBytesByService': peaks,
            'configuredBudgetBytesByService': BUDGET, 'configuredTotalBytes': TOTAL,
            'host': host_metadata(),
            'limits': ['The 2 GiB budget covers app, PostgreSQL and TLS containers together; it excludes the host OS, Docker daemon, build and generator.',
                       'All service processes share logical CPUs 0-1. The generator is restricted to CPUs 2-3.',
                       'This is not proof that a complete 2 GiB virtual machine has enough RAM for its operating system and services.']}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', required=True)
    parser.add_argument('--history')
    args = parser.parse_args()
    samples = ([json.loads(line) for line in Path(args.history).read_text().splitlines() if line.strip()]
               if args.history else [sample_limits()])
    report = {'validation': validate_history(samples), 'samples': samples}
    Path(args.output).write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report['validation']['checks']))
    return 0 if report['validation']['success'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
