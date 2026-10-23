from pathlib import Path
from typing import Literal
from urllib.parse import urlsplit

from pydantic import model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_prefix='SNACKUP_', env_file='.env', extra='ignore', hide_input_in_errors=True)

    environment: Literal['development', 'test', 'production'] = 'development'
    database_url: str = 'sqlite:///./data/snackup.db'
    secret_key: str
    public_origin: str = 'http://localhost:8000'
    admin_email_domains: str = ''
    student_email_domains: str = ''
    institution_id: str = 'institution'
    institution_name: str = 'Institución pendiente de configurar'
    cafeteria_id: str = 'cafeteria'
    cafeteria_name: str = 'Cafetería'
    media_dir: Path = Path('data/media')
    web_dir: Path | None = None
    redis_url: str = ''
    smtp_host: str = ''
    smtp_port: int = 587
    smtp_user: str = ''
    smtp_password: str = ''
    smtp_from: str = ''
    smtp_starttls: bool = True
    access_token_minutes: int = 15
    refresh_days: int = 7
    pool_size: int = 10
    max_overflow: int = 5
    max_websockets: int = 2000
    websocket_revalidate_seconds: float = 15
    enable_test_mailbox: bool = False
    background_events: bool = True

    @model_validator(mode='after')
    def validate_configuration(self):
        if len(self.secret_key) < 32:
            raise ValueError('SNACKUP_SECRET_KEY must contain at least 32 random characters.')
        origin = urlsplit(self.public_origin)
        if origin.scheme not in {'http', 'https'} or not origin.hostname or origin.path not in {'', '/'} or origin.query or origin.fragment or origin.username:
            raise ValueError('SNACKUP_PUBLIC_ORIGIN must be an HTTP(S) origin without credentials or path.')
        self.public_origin = self.public_origin.rstrip('/')
        if not (1 <= self.pool_size <= 50 and 0 <= self.max_overflow <= 50):
            raise ValueError('Invalid SQL connection pool limits.')
        if not (1 <= self.max_websockets <= 10000 and 1 <= self.websocket_revalidate_seconds <= 30):
            raise ValueError('Invalid WebSocket capacity or authorization revalidation interval.')
        if not (1 <= self.access_token_minutes <= 60 and 1 <= self.refresh_days <= 30):
            raise ValueError('Invalid session lifetimes.')
        if self.enable_test_mailbox and self.environment != 'test':
            raise ValueError('Test mailbox is only available in the test environment.')
        if self.environment == 'production':
            if not self.database_url.startswith('postgresql+psycopg://'):
                raise ValueError('Production requires PostgreSQL with the psycopg driver.')
            if origin.scheme != 'https':
                raise ValueError('Production requires an HTTPS public origin.')
            if not self.redis_url:
                raise ValueError('Production requires Redis for cross-worker events and rate limits.')
            if not self.admin_email_domains:
                raise ValueError('Configure authorized administrative email domains before production.')
            if not all(value.strip() for value in (self.institution_id, self.institution_name, self.cafeteria_id, self.cafeteria_name)):
                raise ValueError('Configure the institution and cafeteria identifiers and names before production.')
            if self.smtp_host and self.smtp_port != 465 and not self.smtp_starttls:
                raise ValueError('Production SMTP requires TLS or STARTTLS.')
        return self
