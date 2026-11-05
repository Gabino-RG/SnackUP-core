#!/usr/bin/env python3
"""Serve students, staff panels and the unchanged API on localhost:18080.

Run after migrations and both Flutter builds:
  python tools/integrated_server.py --config C:/Users/video/Documents/JC/SnackUP-Integracion-Local/config.json

Private JSON fields: database_url (postgresql+psycopg, database must be
snackup_integration), secret_key (32+ random characters), media_dir (absolute,
outside the checkout). Optional students_web and panels_web are absolute build
directories; defaults are build/web and app/build/web in this checkout.
Optional services_file points to a private, external JSON for real SMTP/push
providers. Services remain disabled when it is absent; no credentials are made.
No .env or inherited SNACKUP_* configuration is used. This launcher is local
HTTP development, one worker, no Redis; it does not certify production capacity.
Use separate browser profiles for simultaneous student/kitchen/admin accounts:
the unchanged backend deliberately shares its refresh cookie under /api.
"""
from __future__ import annotations

import argparse
import asyncio
from contextlib import asynccontextmanager
import json
import logging
import os
from pathlib import Path
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_CONFIG = Path('C:/Users/video/Documents/JC/SnackUP-Integracion-Local/config.json')
ORIGIN = 'http://localhost:18080'
sys.dont_write_bytecode = True
sys.path.insert(0, str(ROOT / 'backend'))


def configuration(path: Path):
    """Validate isolated storage before creating any database connection."""
    from sqlalchemy.engine import make_url
    config = json.loads(path.read_text(encoding='utf-8-sig'))
    url = make_url(config['database_url'])
    if url.drivername != 'postgresql+psycopg' or url.database != 'snackup_integration':
        raise ValueError('Only the isolated PostgreSQL database snackup_integration is allowed.')
    media = Path(config['media_dir'])
    if not media.is_absolute() or media.resolve().is_relative_to(ROOT):
        raise ValueError('media_dir must be absolute and outside the repository.')
    if not isinstance(config.get('secret_key'), str) or len(config['secret_key']) < 32:
        raise ValueError('A private secret_key with at least 32 characters is required.')
    return config


def local_settings(config):
    from snackup.config import Settings
    from integration_services import service_settings
    services = service_settings(config, ROOT)
    # BaseSettings still reads the environment with _env_file=None. Remove only
    # these variables while constructing explicit settings, then restore them.
    inherited = {k: v for k, v in os.environ.items() if k.startswith('SNACKUP_')}
    try:
        for key in inherited:
            os.environ.pop(key, None)
        return Settings(_env_file=None, environment='development',
            database_url=config['database_url'], secret_key=config['secret_key'],
            public_origin=ORIGIN, password_reset_frontend_path='/paneles/',
            media_dir=Path(config['media_dir']), web_dir=None, redis_url='',
            institution_id='integration-institution', institution_name='SnackUP · prueba integrada',
            cafeteria_id='integration-cafeteria', cafeteria_name='Cafetería de prueba',
            admin_email_domains='staff.example.edu', student_email_domains='utsjr.edu.mx',
            enable_test_mailbox=False, background_events=True, **services)
    finally:
        os.environ.update(inherited)


def create_integrated_app(config):
    from fastapi import HTTPException
    from fastapi.responses import FileResponse, JSONResponse, RedirectResponse
    from snackup.main import create_app
    from snackup.jobs import run_cycle

    students = Path(config.get('students_web', ROOT / 'build/web')).resolve()
    panels = Path(config.get('panels_web', ROOT / 'app/build/web')).resolve()
    for root, base in ((students, '/'), (panels, '/paneles/')):
        index = root / 'index.html'
        if not index.is_file() or f'<base href="{base}">' not in index.read_text(encoding='utf-8'):
            raise ValueError('Compile both frontends with their expected base paths first.')
    settings = local_settings(config)
    app = create_app(settings)
    original_lifespan = app.router.lifespan_context
    scheduler_state = {'last_success': None, 'failed': False}

    @asynccontextmanager
    async def lifespan(application):
        async with original_lifespan(application):
            stop = asyncio.Event()

            async def scheduled_jobs():
                while not stop.is_set():
                    try:
                        await asyncio.to_thread(run_cycle, app.state.db, settings)
                        scheduler_state.update(last_success=time.monotonic(), failed=False)
                    except Exception as error:
                        scheduler_state['failed'] = True
                        logging.getLogger('snackup.integration').error(
                            'Scheduled cycle failed: %s', type(error).__name__)
                    try:
                        await asyncio.wait_for(stop.wait(), timeout=5)
                    except TimeoutError:
                        pass

            worker = asyncio.create_task(scheduled_jobs())
            try:
                yield
            finally:
                stop.set()
                # Wait for any SQL cycle to finish before the backend disposes
                # connections, event bridges and its authentication executor.
                await worker

    app.router.lifespan_context = lifespan

    @app.get('/health/integration', include_in_schema=False)
    def integration_health():
        last = scheduler_state['last_success']
        ready = last is not None and time.monotonic() - last < 30 and not scheduler_state['failed']
        return JSONResponse({'status': 'ready' if ready else 'unavailable',
                             'scheduler': ready, 'mode': 'local-development'},
                            status_code=200 if ready else 503)

    @app.get('/{path:path}', include_in_schema=False)
    def frontend(path: str):
        # Unknown backend routes must never be disguised as successful HTML.
        if path.split('/', 1)[0] in {'api', 'socket.io', 'media', 'health'}:
            raise HTTPException(404)
        if path == 'paneles':
            return RedirectResponse('/paneles/', status_code=308)
        panel = path.startswith('paneles/')
        root = panels if panel else students
        relative = path.removeprefix('paneles/') if panel else path
        target = (root / relative).resolve()
        if not target.is_relative_to(root):
            raise HTTPException(404)
        if not target.is_file():
            if Path(relative).suffix:
                raise HTTPException(404)
            target = root / 'index.html'
        return FileResponse(target, headers={'Cache-Control': 'no-store'})

    return app


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--config', type=Path, default=DEFAULT_CONFIG)
    args = parser.parse_args()
    try:
        app = create_integrated_app(configuration(args.config))
        import uvicorn
        print('SnackUP integrado: ' + ORIGIN + '/ y ' + ORIGIN + '/paneles/', flush=True)
        uvicorn.run(app, host='127.0.0.1', port=18080, workers=1,
                    access_log=False, proxy_headers=False)
    except Exception as error:
        # SQL/validation exceptions may contain private DSNs or passwords.
        print('Integrated server failed: ' + type(error).__name__, file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
