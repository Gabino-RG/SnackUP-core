"""Reject resource reports that silently exceed the promised isolated budget."""
from copy import deepcopy
import pytest
from load.phase_c import verify_pessimistic_limits as limits


@pytest.fixture(autouse=True)
def host(monkeypatch):
    monkeypatch.setattr(limits, 'host_metadata', lambda: {'testOnly': True})


def sample():
    return {'utc': 'test', 'monotonicSeconds': 1, 'generatorAffinity': [2, 3], 'errors': [], 'services': {
        name: {'id': name, 'state': 'running', 'configuredMemoryBytes': budget, 'configuredMemorySwapBytes': budget,
               'configuredCpuSet': '0-1', 'oomKilled': False, 'restarts': 0, 'runtimeSettings': dict(limits.RUNTIME),
               'cgroup': {'memoryMax': str(budget), 'memorySwapMax': '0', 'memoryCurrentBytes': 1,
                          'memoryPeakBytes': 1, 'cpuSetEffective': '0-1', 'memoryEvents': {'oom': 0, 'oom_kill': 0}}}
        for name, budget in limits.BUDGET.items()}}


def test_exact_combined_budget_and_separate_generator_are_accepted():
    report = limits.validate_history([sample(), sample()])
    assert report['success'] is True
    assert report['configuredTotalBytes'] == 2147483648


@pytest.mark.parametrize('alter', [
    lambda row: row['services']['app'].update(configuredMemoryBytes=3 * 2**30),
    lambda row: row['services']['db']['cgroup'].update(memoryMax='max'),
    lambda row: row['services']['tls']['cgroup'].update(memorySwapMax='134217728'),
    lambda row: row['services']['app'].update(configuredCpuSet='0-3'),
    lambda row: row['services']['app']['cgroup'].update(cpuSetEffective='2-3'),
    lambda row: row.update(generatorAffinity=[0, 1, 2, 3]),
    lambda row: row['services']['app']['cgroup']['memoryEvents'].update(oom_kill=1),
    lambda row: row['services']['app'].update(restarts=1),
    lambda row: row['services'].pop('tls'),
    lambda row: row['errors'].append('PermissionError'),
    lambda row: row['services']['app']['runtimeSettings'].update(SNACKUP_WORKERS='4'),
])
def test_misconfigured_or_failed_runtime_is_not_reported_as_passed(alter):
    row = sample()
    alter(row)
    assert limits.validate_history([row])['success'] is False


def test_recreated_container_cannot_reset_oom_history_silently():
    before = sample()
    after = deepcopy(before)
    after['services']['app']['id'] = 'replacement'
    assert limits.validate_history([before, after])['checks']['containerIdentityStable'] is False


def test_missing_measurements_do_not_pass():
    assert limits.validate_history([])['success'] is False
