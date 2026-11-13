"""Exercise the load probe's failure oracle without a database or network.

These unit tests deliberately corrupt returned observations. The real load run
uses authenticated HTTP and WebSocket delivery; this double is only for checking
that its observer cannot approve an incomplete or mismatched round trip.
"""
import asyncio
from copy import deepcopy

import pytest

from load.phase_c.collaboration_probe import Probe


STUDENT = {'email': 'probe-student@load.snackup.invalid'}
OPERATOR = {'email': 'probe-kitchen@load.snackup.invalid', 'businessId': 'local-1'}
ORDER = {'id': 'order-1', 'businessId': 'local-1', 'status': 'completed'}


class Observations:
    """Return API-shaped observations and optionally corrupt one boundary."""

    def __init__(self, *, wrong_message=None, wrong_aggregate=None, fail_chat=False):
        self.admin = {'email': 'probe-admin@load.snackup.invalid'}
        self.expected_order_events = set()
        self.details = {}
        self.failures = []
        self.calls = []
        self.messages = []
        self.rating = None
        self.wrong_message = wrong_message
        self.wrong_aggregate = wrong_aggregate
        self.fail_chat = fail_chat

    def check(self, condition, description):
        if not condition:
            self.failures.append(description)

    async def request(self, method, path, actor, metric, **kwargs):
        self.calls.append((method, path, actor, metric))
        payload = kwargs.get('json', {})
        if metric == 'probe_chat_open':
            if self.fail_chat:
                raise TimeoutError('Deliberate transport failure in the observer test')
            return 200, {'id': 'chat-1', 'businessId': 'local-1', 'orderId': 'order-1'}, ''
        if metric in ('probe_chat_student_send', 'probe_chat_kitchen_send'):
            message = {'id': f'message-{len(self.messages) + 1}', 'chatId': 'chat-1',
                       'senderRole': 'ALUMNO' if actor is STUDENT else 'COCINA',
                       'text': payload['text']}
            self.messages.append(message)
            return 201, deepcopy(message), ''
        if metric in ('probe_chat_kitchen_read', 'probe_chat_student_read'):
            messages = deepcopy(self.messages)
            if self.wrong_message and metric == 'probe_chat_kitchen_read':
                messages[-1][self.wrong_message] = 'a different message'
            return 200, {'data': messages}, ''
        if metric == 'probe_student_rating':
            self.rating = {'id': 'rating-1', 'orderId': 'order-1',
                           'businessId': 'local-1', **payload}
            return 201, deepcopy(self.rating), ''
        if metric == 'probe_student_rated_order':
            return 200, {**ORDER, 'isRated': True, 'version': 7}, ''
        if metric == 'probe_admin_reviews':
            return 200, {'data': [deepcopy(self.rating)]}, ''
        if metric == 'probe_admin_rating_aggregate':
            aggregate = {'id': 'local-1', 'totalRatings': 1, 'averageRating': 4}
            if self.wrong_aggregate:
                aggregate[self.wrong_aggregate] = 0
            return 200, aggregate, ''
        raise AssertionError('Unexpected observation requested: ' + metric)


async def complete_round_trip(observations):
    probe = Probe(observations, every=1, maximum=1)
    await probe.on_order_created(STUDENT, ORDER, OPERATOR)
    await probe.on_order_delivered(STUDENT, ORDER, OPERATOR)
    await probe.finish()
    return probe


def test_complete_round_trip_counts_both_roles_and_the_rating_event():
    run = Observations()
    asyncio.run(complete_round_trip(run))
    assert run.failures == []
    assert run.expected_order_events == {('order-1', 7)}
    counts = run.details['collaboration']
    for key in ('selectedOrders', 'chatRoundTrips', 'selectedDelivered',
                'ratingsCreated', 'ratingsVisibleToAdmin', 'businessAggregatesVerified'):
        assert counts[key] == 1
    actors = {metric: actor for _, _, actor, metric in run.calls}
    assert actors['probe_chat_student_send'] is STUDENT
    assert actors['probe_chat_kitchen_read'] is OPERATOR
    assert actors['probe_chat_kitchen_send'] is OPERATOR
    assert actors['probe_chat_student_read'] is STUDENT
    assert actors['probe_admin_reviews'] is run.admin


@pytest.mark.parametrize('field', ['id', 'text'])
def test_wrong_message_cannot_be_counted_as_a_completed_chat(field):
    run = Observations(wrong_message=field)
    asyncio.run(complete_round_trip(run))
    assert any('kitchen reads exact student message' in failure for failure in run.failures)
    assert run.details['collaboration'].get('chatRoundTrips', 0) == 0
    assert any('chatRoundTrips matches selected orders' in failure for failure in run.failures)


@pytest.mark.parametrize('field', ['totalRatings', 'averageRating'])
def test_wrong_admin_aggregate_fails_even_when_the_rating_is_visible(field):
    run = Observations(wrong_aggregate=field)
    asyncio.run(complete_round_trip(run))
    assert run.details['collaboration']['ratingsVisibleToAdmin'] == 1
    assert run.details['collaboration'].get('businessAggregatesVerified', 0) == 0
    assert any('aggregate matches API-created ratings' in failure for failure in run.failures)


def test_interrupted_selected_order_stays_in_the_denominator():
    run = Observations(fail_chat=True)

    async def interrupted():
        probe = Probe(run, every=1, maximum=1)
        await probe.on_order_created(STUDENT, ORDER, OPERATOR)
        await probe.finish()

    asyncio.run(interrupted())
    assert run.details['collaboration']['selectedOrders'] == 1
    for key in ('chatRoundTrips', 'selectedDelivered', 'ratingsCreated', 'ratingsVisibleToAdmin'):
        assert run.details['collaboration'].get(key, 0) == 0
        assert any(f'{key} matches selected orders' in failure for failure in run.failures)
    assert any('chat raised TimeoutError' in failure for failure in run.failures)


def test_two_kitchen_completion_observations_do_not_submit_a_second_rating():
    run = Observations()

    async def duplicated_delivery_observation():
        probe = Probe(run, every=1, maximum=1)
        await probe.on_order_created(STUDENT, ORDER, OPERATOR)
        await probe.on_order_delivered(STUDENT, ORDER, OPERATOR)
        await probe.on_order_delivered(STUDENT, ORDER, OPERATOR)
        await probe.finish()

    asyncio.run(duplicated_delivery_observation())
    assert run.failures == []
    assert sum(metric == 'probe_student_rating' for _, _, _, metric in run.calls) == 1


def test_empty_sample_is_not_a_successful_collaboration_check():
    run = Observations()
    asyncio.run(Probe(run).finish())
    assert any('sample contains real orders' in failure for failure in run.failures)
