from contextlib import asynccontextmanager
import json
import logging
from pathlib import Path
import time
from threading import BoundedSemaphore
from urllib.parse import urlsplit

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import FileResponse, JSONResponse
from fastapi.staticfiles import StaticFiles
from sqlalchemy import text
from sqlalchemy.exc import IntegrityError, OperationalError, TimeoutError as PoolTimeoutError
from starlette.middleware.trustedhost import TrustedHostMiddleware
from starlette.exceptions import HTTPException
from starlette.concurrency import run_in_threadpool

from .config import Settings
from .db import Database
from .errors import ApiError
from .limits import RateLimiter
from .realtime import EventBridge

log = logging.getLogger('snackup.http')


def create_app(settings: Settings | None = None):
    from . import admin, identity, operations, realtime, v3_admin, v3_identity, v3_operations, v3_media, v3_reviews, push, v32_api, v32_chat
    from .push import install_push
    from .socketio_gateway import install_socketio

    settings = settings or Settings()
    app_logger = logging.getLogger('snackup')
    if not app_logger.handlers:
        handler = logging.StreamHandler()
        handler.setFormatter(logging.Formatter('%(asctime)s %(levelname)s %(name)s %(message)s'))
        app_logger.addHandler(handler)
    app_logger.setLevel(logging.INFO)
    app_logger.propagate = False
    database = Database(settings)

    @asynccontextmanager
    async def lifespan(app):
        with database.engine.connect() as connection:
            connection.execute(text('SELECT 1'))
            if settings.environment != 'test':
                connection.execute(text('SELECT version_num FROM alembic_version'))
        if settings.background_events:
            await app.state.socketio_gateway.start()
            await app.state.events.start()
            await app.state.push.start()
        try:
            yield
        finally:
            await app.state.push.stop()
            await app.state.events.stop()
            await app.state.socketio_gateway.stop()
            app.state.limiter.close()
            database.dispose()

    app = FastAPI(title='SnackUP API V3 · FastAPI', version='3.2.0', lifespan=lifespan,
                  description='Contrato canónico V3 en /api/v1. Compatibilidad de paneles anteriores en /api/legacy/v1. '
                              'Registro institucional requiere verificación de correo antes de emitir una sesión. '
                              'Pagos son métodos registrados; no se procesa cobro. Tiempo real Socket.IO: /socket.io.',
                  docs_url='/api/docs' if settings.environment != 'production' else None,
                  redoc_url=None, openapi_url='/api/openapi.json' if settings.environment != 'production' else None)
    app.state.settings = settings
    app.state.db = database
    app.state.password_slots = BoundedSemaphore(settings.password_concurrency)
    from .admission import DatabaseAdmission
    app.add_middleware(DatabaseAdmission, capacity=min(24, max(1, settings.pool_size + settings.max_overflow - 4)),
                       wait_seconds=settings.admission_wait_seconds, login_wait_seconds=settings.login_wait_seconds)
    app.state.limiter = RateLimiter(settings)
    app.state.events = EventBridge(database, settings)
    app.add_middleware(TrustedHostMiddleware, allowed_hosts=[urlsplit(settings.public_origin).hostname])

    @app.exception_handler(ApiError)
    async def api_error(_, error):
        if error.audit:
            def persist_failure():
                from .identity_models import audit_event
                with database.sessions.begin() as db:
                    audit_event(db, **error.audit)
            try:
                await run_in_threadpool(persist_failure)
            except Exception:
                # An unavailable audit store must not expose exception details
                # or turn a denied delivery into a successful operation.
                log.warning('Audit persistence unavailable for %s', error.code)
        return JSONResponse(error.payload(), status_code=error.status,
                            headers={'Retry-After': '60' if error.status == 429 else '1'} if error.status in {429, 503} else None)

    @app.exception_handler(RequestValidationError)
    async def invalid_request(_, error):
        return JSONResponse({'error': {'code': 'INVALID_INPUT', 'message': 'Revisa los campos de la solicitud.',
                                      'details': [{'field': '.'.join(map(str, e['loc'])), 'rule': e['type']} for e in error.errors()[:10]]}}, status_code=422)

    @app.exception_handler(IntegrityError)
    async def conflict(_, error):
        return JSONResponse({'error': {'code': 'CONFLICT', 'message': 'La operación entra en conflicto con un registro existente.'}}, status_code=409)

    @app.exception_handler(PoolTimeoutError)
    @app.exception_handler(OperationalError)
    async def database_unavailable(_, error):
        return JSONResponse({'error': {'code': 'DATABASE_UNAVAILABLE', 'message': 'No se pudo confirmar la operación. Actualiza antes de repetirla.'}}, status_code=503, headers={'Retry-After': '1'})

    @app.exception_handler(HTTPException)
    async def http_error(_, error):
        code = {404: 'NOT_FOUND', 405: 'METHOD_NOT_ALLOWED', 413: 'PAYLOAD_TOO_LARGE'}.get(error.status_code, 'INVALID_REQUEST')
        return JSONResponse({'error': {'code': code, 'message': 'La solicitud no está disponible.'}},
                            status_code=error.status_code, headers=error.headers)

    @app.middleware('http')
    async def guard(request: Request, call_next):
        started = time.monotonic()
        path = request.url.path
        try:
            if request.method in {'POST', 'PUT', 'PATCH', 'DELETE'}:
                origin = request.headers.get('origin')
                # Cookie endpoints enforce presence too; bearer CLI clients can omit Origin.
                if origin and origin != settings.public_origin:
                    raise ApiError(403, 'ORIGIN_DENIED', 'Origen no autorizado.')
                maximum = 6 * 1024 * 1024 if path in {'/api/v1/media', '/api/legacy/v1/media'} else 64 * 1024
                try:
                    claimed = int(request.headers.get('content-length', '0'))
                except ValueError:
                    raise ApiError(400, 'INVALID_INPUT')
                if claimed < 0 or claimed > maximum:
                    raise ApiError(413, 'PAYLOAD_TOO_LARGE')
                # Bound chunked bodies as well as Content-Length; middleware's
                # cached body is replayed to multipart and JSON parsers downstream.
                body = bytearray()
                async for chunk in request.stream():
                    body.extend(chunk)
                    if len(body) > maximum:
                        raise ApiError(413, 'PAYLOAD_TOO_LARGE')
                request._body = bytes(body)
                if path.startswith(('/api/v1/auth/', '/api/legacy/v1/auth/')) or path == '/api/legacy/v1/student/register':
                    address = request.client.host if request.client else 'unknown'
                    await run_in_threadpool(app.state.limiter.check, 'auth-ip', address, 3000, 60)
                    if path.endswith(('/login', '/register', '/forgot-password', '/resend-verification')):
                        try:
                            payload = json.loads(body)
                            email = payload.get('email', '')
                            if isinstance(email, str) and email:
                                await run_in_threadpool(app.state.limiter.check, 'auth-account:' + path.rsplit('/', 1)[-1],
                                                        email.strip().lower(), 10, 60)
                        except (ValueError, AttributeError):
                            pass
            response = await call_next(request)
        except ApiError as error:
            response = await api_error(request, error)
        response.headers['X-Content-Type-Options'] = 'nosniff'
        response.headers['Referrer-Policy'] = 'no-referrer'
        response.headers['X-Frame-Options'] = 'DENY'
        if path.startswith('/api/'):
            response.headers['Cache-Control'] = 'no-store'
        if settings.environment == 'production':
            response.headers['Strict-Transport-Security'] = 'max-age=31536000'
        log.info('%s %s %d %.0fms', request.method, path, response.status_code, (time.monotonic() - started) * 1000)
        return response

    for router in (v32_api.router, v32_chat.router, v3_identity.router, v3_admin.router, v3_operations.router, v3_media.router, v3_reviews.router, push.router):
        app.include_router(router, prefix='/api/v1')
    # Keep the established panels' strict lower-case DTOs explicitly versioned.
    # They do not override or dilute the canonical V3 roles, errors or payloads.
    for router in (identity.router, admin.router, operations.router, realtime.router):
        app.include_router(router, prefix='/api/legacy/v1', include_in_schema=False)
    from fastapi import APIRouter
    administrative_extensions = APIRouter(tags=['Administración institucional'])
    for route in admin.router.routes:
        if (route.path in {'/institution', '/admin/access-requests', '/admin/access-requests/{id}/decision'} or (route.path == '/admin/users' and 'POST' in route.methods) or route.path.startswith(('/admin/reviews', '/admin/followups', '/admin/academic-catalog'))):
            administrative_extensions.routes.append(route)
    app.include_router(administrative_extensions, prefix='/api/v1')
    install_push(app)
    install_socketio(app)

    @app.get('/health/live')
    def live():
        return {'status': 'ok'}

    @app.get('/health/ready')
    def ready():
        with database.engine.connect() as connection:
            connection.execute(text('SELECT 1'))
        if app.state.limiter.redis:
            try:
                app.state.limiter.redis.ping()
            except Exception as error:
                raise ApiError(503, 'SERVICE_UNAVAILABLE') from error
        return {'status': 'ready'}

    settings.media_dir.mkdir(parents=True, exist_ok=True)
    app.mount('/media', StaticFiles(directory=settings.media_dir), name='media')

    if settings.web_dir:
        web_root = settings.web_dir.resolve()
        if not (web_root / 'index.html').is_file():
            raise ValueError('SNACKUP_WEB_DIR does not contain a compiled frontend.')

        @app.get('/{path:path}', include_in_schema=False)
        def frontend(path: str):
            if path == 'api' or path.startswith(('api/', 'health/', 'media/')):
                raise ApiError(404, 'NOT_FOUND')
            target = (web_root / path).resolve()
            if not target.is_relative_to(web_root):
                raise ApiError(404, 'NOT_FOUND')
            if not target.is_file():
                target = web_root / 'index.html'
            return FileResponse(target)

    from .openapi import install_openapi
    install_openapi(app)
    return app
