"""Bound DB-bound HTTP requests before they occupy a thread or SQL connection."""
import asyncio
from starlette.responses import JSONResponse


class DatabaseAdmission:
    def __init__(self, app, capacity, wait_seconds, login_wait_seconds=8, write_concurrency=2):
        self.app = app
        self.capacity, self.wait_seconds = capacity, wait_seconds
        self.login_wait_seconds = login_wait_seconds
        self.write_concurrency = min(capacity, write_concurrency)
        self._loop = None
        self._slots = None

    async def __call__(self, scope, receive, send):
        if scope['type'] != 'http' or not scope.get('path', '').startswith('/api/'):
            return await self.app(scope, receive, send)
        loop = asyncio.get_running_loop()
        if self._loop is not loop:
            self._loop, self._slots = loop, asyncio.Semaphore(self.capacity)
            self._writes = asyncio.Semaphore(self.write_concurrency)
        slots = self._slots
        login = scope['path'].endswith('/auth/login')
        writes = self._writes if scope.get('method', 'GET') not in ('GET', 'HEAD', 'OPTIONS') and not login else None
        write_acquired = False
        try:
            # Wait before opening SQL. A convoy of writers on one stock row
            # otherwise fills all connections and delays even its lock holder.
            async with asyncio.timeout(self.login_wait_seconds if login else self.wait_seconds):
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
