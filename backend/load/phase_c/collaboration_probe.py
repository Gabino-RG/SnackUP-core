"""Sample real chat/rating/admin round trips inside the disposable mixed load.

No application data is injected by this probe: each rating belongs to a real
API-created and kitchen-completed order. Reports contain counts, not messages,
account credentials, tokens or order identifiers.
"""
from collections import Counter


class Probe:
    def __init__(self, run, *, every=31, maximum=20):
        self.run = run
        self.every = every
        self.maximum = maximum
        self.created = 0
        self.selected = {}
        self.delivered = set()
        self.counts = Counter()
        self.ratings_by_business = Counter()

    def expect(self, condition, description):
        self.run.check(bool(condition), 'Collaboration probe: ' + description)
        return bool(condition)

    async def call(self, method, path, actor, metric, **kwargs):
        return await self.run.request(method, path, actor, metric, **kwargs)

    async def on_order_created(self, student, order, operator):
        self.created += 1
        if (self.created - 1) % self.every or len(self.selected) >= self.maximum:
            return
        self.selected[order['id']] = operator['businessId']
        self.counts['selectedOrders'] += 1
        try:
            status, chat, _ = await self.call('POST',
                f"/api/v1/businesses/{operator['businessId']}/chats", student,
                'probe_chat_open', json={'orderId': order['id']})
            if not self.expect(status == 200 and chat.get('id'), 'student opens order chat'):
                return
            path = f"/api/v1/chats/{chat['id']}/messages"
            question = '[CARGA AISLADA] Confirmo mi pedido de prueba.'
            answer = '[CARGA AISLADA] Cocina recibió tu mensaje.'
            status, message, _ = await self.call('POST', path, student,
                'probe_chat_student_send', json={'text': question})
            if not self.expect(status == 201 and message.get('senderRole') == 'ALUMNO',
                               'student sends chat message'):
                return
            status, received, _ = await self.call('GET', path, operator, 'probe_chat_kitchen_read')
            if not self.expect(status == 200 and any(
                row.get('id') == message.get('id') and row.get('text') == question
                for row in received.get('data', [])), 'kitchen reads exact student message'):
                return
            status, reply, _ = await self.call('POST', path, operator,
                'probe_chat_kitchen_send', json={'text': answer})
            if not self.expect(status == 201 and reply.get('senderRole') == 'COCINA',
                               'kitchen sends chat reply'):
                return
            status, received, _ = await self.call('GET', path, student, 'probe_chat_student_read')
            if self.expect(status == 200 and any(
                row.get('id') == reply.get('id') and row.get('text') == answer
                for row in received.get('data', [])), 'student reads exact kitchen reply'):
                self.counts['chatRoundTrips'] += 1
        except Exception as exc:
            self.run.check(False, 'Collaboration probe chat raised ' + type(exc).__name__)

    async def on_order_delivered(self, student, order, operator):
        order_id = order['id']
        if order_id not in self.selected or order_id in self.delivered:
            return
        self.delivered.add(order_id)
        self.counts['selectedDelivered'] += 1
        try:
            comment = '[CARGA AISLADA] Pedido recibido y evaluado desde la API del alumno.'
            status, rating, _ = await self.call('POST', f'/api/v1/orders/{order_id}/rating',
                student, 'probe_student_rating', json={
                    'rating': 4, 'foodRating': 5, 'serviceRating': 4, 'comment': comment})
            if not self.expect(status == 201 and rating.get('rating') == 4 and rating.get('id'),
                               'student rates completed order'):
                return
            self.counts['ratingsCreated'] += 1
            self.ratings_by_business[operator['businessId']] += 1
            status, refreshed, _ = await self.call('GET', f'/api/v1/orders/{order_id}',
                student, 'probe_student_rated_order')
            if self.expect(status == 200 and refreshed.get('isRated') is True
                           and isinstance(refreshed.get('version'), int),
                           'rating reflected in student order'):
                # A business rating emits a new order.updated version. Include
                # that real event in the mixed workload's delivery oracle.
                self.run.expected_order_events.add((order_id, refreshed['version']))
            status, reviews, _ = await self.call('GET', '/api/v1/admin/reviews?limit=200',
                self.run.admin, 'probe_admin_reviews')
            if self.expect(status == 200 and any(
                row.get('id') == rating['id'] and row.get('rating') == 4
                and row.get('foodRating') == 5 and row.get('serviceRating') == 4
                and row.get('comment') == comment
                for row in reviews.get('data', [])), 'administrator sees same detailed rating'):
                self.counts['ratingsVisibleToAdmin'] += 1
        except Exception as exc:
            self.run.check(False, 'Collaboration probe rating raised ' + type(exc).__name__)

    async def finish(self):
        """Call after all order hooks finish and before websocket teardown."""
        for business_id, count in self.ratings_by_business.items():
            try:
                status, business, _ = await self.call('GET',
                    f'/api/v1/admin/businesses/{business_id}', self.run.admin,
                    'probe_admin_rating_aggregate')
                if self.expect(status == 200 and business.get('totalRatings') == count
                               and business.get('averageRating') == 4,
                               'administrator aggregate matches API-created ratings'):
                    self.counts['businessAggregatesVerified'] += 1
            except Exception as exc:
                self.run.check(False, 'Collaboration probe aggregate raised ' + type(exc).__name__)
        selected = self.counts['selectedOrders']
        self.expect(selected > 0, 'sample contains real orders')
        for metric in ('chatRoundTrips', 'selectedDelivered', 'ratingsCreated', 'ratingsVisibleToAdmin'):
            self.expect(self.counts[metric] == selected, metric + ' matches selected orders')
        self.expect(self.counts['businessAggregatesVerified'] == len(self.ratings_by_business),
                    'all rated business aggregates verified')
        self.run.details['collaboration'] = {
            **dict(self.counts), 'sampleEveryOrders': self.every,
            'sampleMaximum': self.maximum, 'chatTransport': 'real authenticated HTTP',
            'ratingTransport': 'real authenticated HTTP plus order.updated websocket',
            'productRatingsIncluded': False,
        }
