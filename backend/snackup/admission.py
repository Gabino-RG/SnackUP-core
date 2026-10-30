"""Bound DB-bound HTTP requests before they occupy a thread or SQL connection."""
import asyncio
import re
import time
from starlette.responses import JSONResponse

# Mutations that wait on an outside party or lock only the caller's own rows
# get their own lane instead of the per-worker write slot. A slow SMTP server
# or a burst of session renewals must not stall orders and kitchen updates.
MAIL_PATHS = re.compile(r'/api/(?:v1|legacy/v1)/(?:auth/(?:register|forgot-password|resend-verification)'
                        r'|student/register|admin/users/[^/]+/reset-password)')
SESSION_PATHS = re.compile(r'/api/(?:v1|legacy/v1)/auth/(?:refresh|logout)')
EDGE_HEADER = b'x-snackup-edge-ms'


def edge_wait(headers) -> float:
    """Seconds since the proxy received the request, or 0 without a usable stamp.

    Caddy sets the header to its arrival time in epoch milliseconds and replaces
    any client value; the workers listen on loopback only behind it.
    """
    for name, value in headers:
        if name == EDGE_HEADER:
            try:
                waited = time.time() - int(value) / 1000
            except ValueError:
                return 0.0
            return waited if 0 <= waited < 60 else 0.0
    return 0.0


class DatabaseAdmission:
    def __init__(self, app, capacity, wait_seconds, login_wait_seconds=8, write_concurrency=1,
                 mail_concurrency=2, session_concurrency=4, login_concurrency=4):
        self.app = app
        self.capacity, self.wait_seconds = capacity, wait_seconds
        self.login_wait_seconds = login_wait_seconds
        self.write_concurrency = min(capacity, write_concurrency)
        # Logins in flight match the password threads: the rest of a wave waits
        # here, without holding a slot that reads and kitchen updates need.
        self.lane_limits = {'write': self.write_concurrency, 'mail': min(capacity, mail_concurrency),
                            'session': min(capacity, session_concurrency), 'login': min(capacity, login_concurrency)}
        self._loop = None
        self._slots = None

    def lane(self, scope):
        path = scope['path']
        if scope.get('method', 'GET') in ('GET', 'HEAD', 'OPTIONS'):
            return None
        if path.endswith('/auth/login'):
            return 'login'
        if MAIL_PATHS.fullmatch(path):
            return 'mail'
        if SESSION_PATHS.fullmatch(path):
            return 'session'
        return 'write'

    async def __call__(self, scope, receive, send):
        if scope['type'] != 'http' or not scope.get('path', '').startswith('/api/'):
            return await self.app(scope, receive, send)
        loop = asyncio.get_running_loop()
        if self._loop is not loop:
            self._loop, self._slots = loop, asyncio.Semaphore(self.capacity)
            self._lanes = {name: asyncio.Semaphore(limit) for name, limit in self.lane_limits.items()}
        slots = self._slots
        login = scope['path'].endswith('/auth/login')
        lane = self.lane(scope)
        writes = self._lanes[lane] if lane else None
        write_acquired = False
        # Time already queued in the proxy or before this loop ran counts
        # against the budget, so a rejection reaches the client in ~wait_seconds.
        budget = max(0.0, (self.login_wait_seconds if login else self.wait_seconds) - edge_wait(scope.get('headers', ())))
        try:
            # Wait before opening SQL. A convoy of writers on one stock row
            # otherwise fills all connections and delays even its lock holder.
            async with asyncio.timeout(budget):
                if writes is not None:
                    await writes.acquire()
                    write_acquired = True
                await slots.acquire()
        except TimeoutError:
            if write_acquired:
                writes.release()
            response = JSONResponse({'error': {'code': 'SERVICE_BUSY', 'message': 'Servicio ocupado. Reintenta en un momento.'}},
                                    status_code=503, headers={'Retry-After': '1', 'Cache-Control': 'no-store'})
            return await response(scope, receive, send)
        except BaseException:
            if write_acquired:
                writes.release()
            raise
        try:
            # Includes dependency cleanup/commit, not just response headers.
            await self.app(scope, receive, send)
        finally:
            slots.release()
            if write_acquired:
                writes.release()
