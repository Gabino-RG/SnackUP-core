"""Supervise API, local Redis and Caddy as one application container.

All children run as the image's unprivileged user. Any child exit stops the
whole group, so the container restart policy can recover the complete stack.
PostgreSQL is external and its data never lives in this container filesystem.
"""
from contextlib import suppress
import os
from pathlib import Path
import signal
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
REDIS_URL = 'unix:///tmp/snackup-redis.sock?db=0'


class Processes:
    def __init__(self):
        self.children = []
        self.stopping = False

    def start(self, name, command):
        child = subprocess.Popen(command, cwd=ROOT, start_new_session=True)
        self.children.append((name, child))
        return child

    def check(self):
        if self.stopping:
            raise InterruptedError
        for name, child in self.children:
            if child.poll() is not None:
                raise RuntimeError(f'{name} exited with status {child.returncode}')

    def stop(self):
        # HTTP first, then API, then Redis; signal entire groups, including workers.
        for _, child in reversed(self.children):
            with suppress(ProcessLookupError):
                os.killpg(child.pid, signal.SIGTERM)
        deadline = time.monotonic() + 25
        for _, child in reversed(self.children):
            try:
                child.wait(timeout=max(0, deadline - time.monotonic()))
            except subprocess.TimeoutExpired:
                with suppress(ProcessLookupError):
                    os.killpg(child.pid, signal.SIGKILL)
                child.wait()


def wait_for(probe, processes, seconds=60):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        processes.check()
        try:
            if probe():
                return
        except Exception:
            # Never log connection URLs, credentials or request bodies.
            pass
        time.sleep(0.2)
    raise RuntimeError('A required service did not become ready before its deadline')


def main():
    # A private Unix socket avoids a publicly reachable Redis port or password.
    os.environ['SNACKUP_REDIS_URL'] = REDIS_URL
    arguments = sys.argv[1:] or ['serve']
    if arguments != ['serve']:
        os.chdir(ROOT)
        os.execvp(arguments[0], arguments)
    from redis import Redis
    from snackup.config import Settings

    Settings()  # Validate production settings before accepting any requests.
    workers = int(os.environ.get('SNACKUP_WORKERS', '2'))
    if not 1 <= workers <= 8:
        raise ValueError('SNACKUP_WORKERS must be between 1 and 8')
    processes = Processes()

    def stopping(signum, frame):
        processes.stopping = True

    signal.signal(signal.SIGTERM, stopping)
    signal.signal(signal.SIGINT, stopping)
    redis = Redis.from_url(REDIS_URL, socket_timeout=2, socket_connect_timeout=2)
    try:
        processes.start('redis', ['redis-server', '--port', '0', '--unixsocket', '/tmp/snackup-redis.sock',
                                 '--unixsocketperm', '700', '--dir', '/data/redis', '--appendonly', 'yes',
                                 '--maxmemory', '256mb', '--maxmemory-policy', 'noeviction'])
        wait_for(redis.ping, processes)
        # Single supervised migration, not one invocation per Uvicorn worker.
        migration = processes.start('migration', [sys.executable, '-m', 'alembic', 'upgrade', 'head'])
        while migration.poll() is None:
            if processes.stopping:
                raise InterruptedError
            if processes.children[0][1].poll() is not None:
                raise RuntimeError('Redis stopped during migration')
            time.sleep(0.2)
        if migration.returncode:
            raise RuntimeError('Database migration failed; the applications were not started')
        processes.children.remove(('migration', migration))
        processes.start('api', [sys.executable, '-m', 'uvicorn', 'snackup.main:create_app', '--factory',
                               '--host', '127.0.0.1', '--port', '8000', '--workers', str(workers),
                               '--proxy-headers', '--forwarded-allow-ips', '127.0.0.1', '--no-access-log'])
        from healthcheck import api_ready
        wait_for(api_ready, processes)
        processes.start('caddy', ['caddy', 'run', '--config', str(Path(__file__).with_name('Caddyfile')),
                                 '--adapter', 'caddyfile'])
        while True:
            processes.check()
            time.sleep(0.25)
    except InterruptedError:
        return 0
    except Exception as error:
        # Child exits are operational metadata; other exceptions can hold secrets.
        print('SnackUP startup/supervision failed: ' + type(error).__name__, file=sys.stderr)
        return 1
    finally:
        processes.stop()
        redis.close()


if __name__ == '__main__':
    sys.exit(main())
