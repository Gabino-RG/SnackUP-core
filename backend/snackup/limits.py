"""Shared, atomic request limits; no dependence on a request SQL transaction."""
import hashlib
import hmac
from threading import Lock
import time

from redis import Redis
from redis.exceptions import RedisError

from .errors import ApiError


class RateLimiter:
    def __init__(self, settings):
        self.secret = settings.secret_key.encode()
        self.redis = Redis.from_url(settings.redis_url, socket_timeout=2, socket_connect_timeout=2) if settings.redis_url else None
        self.local = {}
        self.lock = Lock()

    def check(self, bucket, identity, limit, window):
        digest = hmac.new(self.secret, str(identity).encode(), hashlib.sha256).hexdigest()
        key = 'snackup:limit:' + bucket + ':' + digest
        if self.redis:
            try:
                count = self.redis.eval(
                    "local n=redis.call('INCR',KEYS[1]); if n==1 then redis.call('EXPIRE',KEYS[1],ARGV[1]) end; return n",
                    1, key, window,
                )
            except RedisError as exc:
                raise ApiError(503, 'SERVICE_UNAVAILABLE', 'El control de acceso no está disponible. Intenta más tarde.') from exc
        else:
            now = time.monotonic()
            with self.lock:
                if len(self.local) > 10000:
                    self.local = {k: v for k, v in self.local.items() if v[1] > now}
                count, expires = self.local.get(key, (0, now + window))
                if expires <= now:
                    count, expires = 0, now + window
                count += 1
                self.local[key] = (count, expires)
        if count > limit:
            raise ApiError(429, 'RATE_LIMITED', 'Demasiados intentos. Espera antes de volver a intentar.')

    def close(self):
        if self.redis:
            self.redis.close()
