"""Contract tests for load measurement; no HTTP server or database is needed."""
import argparse
import asyncio
from collections import Counter, defaultdict
import json

import pytest

from load.phase_c.pessimistic_suite import (
    PessimisticRun, Response, automatic_retry_delay, attempt_once_with_retry,
    configure_file_limit, execute_all, memory_bytes, response_evidence,
)


def busy(delay='1'):
    return Response(503, {'error': {'code': 'SERVICE_BUSY'}}, '{}', {'retry-after': delay})


@pytest.mark.parametrize('response', [
    Response(500, {'error': {'code': 'SERVICE_BUSY'}}, '{}', {'retry-after': '1'}),
    Response(0, {}, ''), Response(503, {'error': {'code': 'OTHER'}}, '{}', {'retry-after': '1'}),
    busy('-1'), busy('6'), busy('nonsense'), busy('1.5'), busy(''),
])
def test_auto_retry_never_broadens_client_policy(response):
    assert automatic_retry_delay(response, .5) is None


@pytest.mark.parametrize('value, expected', [('0', .5), ('1', 1.5), ('5', 5.5)])
def test_retry_honors_retry_after_plus_jitter(value, expected):
    assert automatic_retry_delay(busy(value), .5) == expected


def test_retry_is_exactly_once_and_preserves_first_failure():
    calls, waits = [], []
    async def send(phase):
        calls.append(phase)
        return busy()
    async def sleep(seconds):
        waits.append(seconds)
    first, retry, final = asyncio.run(attempt_once_with_retry(send, lambda: .4, sleep))
    assert calls == ['first', 'automatic_retry']
    assert waits == [1.4]
    assert first.status == retry.status == final.status == 503


def test_successful_first_attempt_does_not_add_retry_or_sleep():
    calls = []
    async def send(phase):
        calls.append(phase)
        return Response(201, {'id': 'one'}, '{"id":"one"}')
    async def fail_sleep(seconds):
        raise AssertionError('Successful initial response must not retry')
    first, retry, final = asyncio.run(attempt_once_with_retry(send, lambda: 0, fail_sleep))
    assert calls == ['first'] and retry is None and final is first


def test_duplicate_evidence_counts_all_errors_and_compares_raw_bodies():
    result = response_evidence([
        Response(201, {'id': 'same'}, '{"id":"same"}'),
        Response(201, {'id': 'same'}, '{ "id":"same" }'),
        busy(), Response(500, {}, '{}'), Response(0, {}, ''),
    ])
    assert result == {'attempts': 5, 'status': {201: 2, 503: 1, 500: 1, 0: 1},
                      'successfulBodies': 2, 'successfulOrderIds': 1}


def test_scenario_failure_and_exception_do_not_skip_later_workloads():
    visited = []
    async def execute(name):
        visited.append(name)
        if name == 'broken':
            raise RuntimeError('private error details must not leak')
        return {'scenario': name, 'success': name != 'slow'}
    results = asyncio.run(execute_all(('slow', 'broken', '1000users'), execute))
    assert visited == ['slow', 'broken', '1000users']
    assert [row['success'] for row in results] == [False, False, True]
    assert results[1]['failureType'] == 'RuntimeError'
    assert 'private' not in json.dumps(results)


def bare_run(scenario='reads', memory='2GiB / 2GiB'):
    run = object.__new__(PessimisticRun)
    run.args = argparse.Namespace(scenario=scenario)
    run.failures, run.details = [], {}
    run.worker_samples = [
        {'time': 0, 'workers': [{'pid': 1, 'cpuSeconds': 0, 'rssBytes': 200 * 2**20}]},
        {'time': 10, 'workers': [{'pid': 1, 'cpuSeconds': 2, 'rssBytes': 200 * 2**20}]},
    ]
    run.monitor = [{'elapsed': 5, 'containers': [{'MemUsage': memory, 'CPUPerc': '100.0%'}]}]
    return run


def test_combined_memory_budget_is_2048_not_inherited_3584():
    run = bare_run(memory='2049MiB / 4GiB')
    report = run.resource_summary()
    assert report['budgetMiB'] == 2048
    assert 'Combined service memory exceeds 2048 MiB' in run.failures


def test_one_worker_does_not_require_multiworker_cpu_balance():
    run = bare_run()
    result = run.resource_summary()
    assert result['peakContainersMiB'] == 2048
    assert not run.failures
    assert result['workerBalanceCriterion'] == 'not applicable: one worker'


def test_read_cpu_uses_only_steady_window_and_two_shared_cpus():
    run = bare_run()
    run.details['readingStages'] = [{'users': 1000, 'start': 15, 'end': 105}]
    run.monitor = [{'elapsed': 2, 'containers': [{'MemUsage': '1GiB', 'CPUPerc': '200%'}]},
                   {'elapsed': 50, 'containers': [{'MemUsage': '1GiB', 'CPUPerc': '120%'}]}]
    report = run.resource_summary()
    assert report['readingStages'][0]['meanTwoCpuUtilizationPercent'] == 60
    assert not run.failures


def test_busy_read_cpu_marks_capacity_failure_without_hiding_metrics():
    run = bare_run()
    run.details['readingStages'] = [{'users': 1000, 'start': 0, 'end': 10}]
    run.details['stages'] = [{'name': 'reads_1000', 'success': True}]
    run.monitor[0]['containers'][0]['CPUPerc'] = '160%'
    assert run.resource_summary()['readingStages'][0]['meanTwoCpuUtilizationPercent'] == 80
    assert run.failures
    assert run.details['stages'][0]['success'] is False


def test_login_worker_rss_is_checked_in_named_suite_scenario():
    run = bare_run('logins')
    run.worker_samples[1]['workers'][0]['rssBytes'] = 400 * 2**20
    run.resource_summary()
    assert 'Login worker RSS >=400 MiB' in run.failures


def test_stage_exception_keeps_following_stage_executable():
    run = bare_run()
    async def bad():
        raise TimeoutError()
    async def good():
        run.details['laterRan'] = True
    async def stages():
        await run.stage('50', bad)
        await run.stage('1000', good)
    asyncio.run(stages())
    assert run.details['laterRan']
    assert [row['success'] for row in run.details['stages']] == [False, True]


def test_memory_units_and_limits_are_not_confused():
    assert memory_bytes('768MiB / 1GiB') == 768 * 2**20
    assert memory_bytes('1.5GiB / 2GiB') == 1.5 * 2**30
    with pytest.raises(ValueError):
        memory_bytes('unknown')


@pytest.mark.parametrize('hard,target', [(4096, 4096), (16384, 8192), (-1, 8192)])
def test_file_limit_preserves_infinity_and_has_a_recorded_capacity(hard, target):
    class Resource:
        RLIMIT_NOFILE = 7
        RLIM_INFINITY = -1
        @staticmethod
        def getrlimit(which):
            return 1024, hard
        @staticmethod
        def setrlimit(which, values):
            assert which == 7 and values == (target, hard)
    assert configure_file_limit(Resource) == {'soft': target, 'hard': hard, 'minimumRequired': 4096}


def test_too_small_generator_is_rejected_before_load():
    class Resource:
        RLIMIT_NOFILE = 7
        RLIM_INFINITY = -1
        @staticmethod
        def getrlimit(which):
            return 1024, 2048
    with pytest.raises(ValueError, match='4096'):
        configure_file_limit(Resource)
