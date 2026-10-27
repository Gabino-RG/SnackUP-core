"""Bound DB-bound HTTP requests before they occupy a thread or SQL connection."""
import asyncio
from starlette.responses import JSONResponse


class DatabaseAdmission:
    def __init__(self, app, capacity, wait_seconds):
        self.app = app
        self.capacity, self.wait_seconds = capacity, wait_seconds
        self._loop = None
        self._slots = None

    async def __call__(self, scope, receive, send):
        if scope['type'] != 'http' or not scope.get('path', '').startswith('/api/'):
            return await self.app(scope, receive, send)
        loop = asyncio.get_running_loop()
        if self._loop is not loop:
            self._loop, self._slots = loop, asyncio.Semaphore(self.capacity)
        slots = self._slots
        try:
            await asyncio.wait_for(slots.acquire(), timeout=self.wait_seconds)
        except TimeoutError:
            response = JSONResponse({'error': {'code': 'SERVICE_BUSY', 'message': 'Servicio ocupado. Reintenta en un momento.'}},
                                    status_code=503, headers={'Retry-After': '1', 'Cache-Control': 'no-store'})
            return await response(scope, receive, send)
        try:
            # Includes dependency cleanup/commit, not just response headers.
            await self.app(scope, receive, send)
        finally:
            slots.release()
