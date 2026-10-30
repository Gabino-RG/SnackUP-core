import re
from pathlib import Path
from typing import Literal
from urllib.parse import urlsplit

from pydantic import field_validator, model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_prefix='SNACKUP_', env_file='.env', extra='ignore', hide_input_in_errors=True)

    environment: Literal['development', 'test', 'production'] = 'development'
    database_url: str = 'sqlite:///./data/snackup.db'
    secret_key: str
    public_origin: str = 'http://localhost:8000'
    password_reset_frontend_path: str = '/'
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
    refresh_days: int = 30
    pool_size: int = 10
    max_overflow: int = 5
    pool_timeout_seconds: float = 2
    admission_wait_seconds: float = 5
    write_concurrency: int = 1
    mail_concurrency: int = 2
    session_concurrency: int = 4
    login_wait_seconds: float = 8
    password_concurrency: int = 4
    outbox_retention_days: int = 7
    outbox_cleanup_batch: int = 1000
    max_websockets: int = 2000
    websocket_revalidate_seconds: float = 15
    enable_test_mailbox: bool = False
    background_events: bool = True
    push_enabled: bool = False
    push_poll_seconds: float = 2
    push_batch_size: int = 25
    push_max_attempts: int = 8
    push_retry_base_seconds: int = 30
    push_unconfigured_retry_seconds: int = 300
    push_delivery_lease_seconds: int = 90
    push_http_timeout_seconds: float = 10
    push_fcm_credentials_file: Path | None = None
    push_fcm_project_id: str = ''
    push_apns_key_file: Path | None = None
    push_apns_key_id: str = ''
    push_apns_team_id: str = ''
    push_apns_topic: str = ''
    push_apns_sandbox: bool = False
    push_webpush_private_key_file: Path | None = None
    push_webpush_subject: str = ''
    push_webpush_allowed_hosts: str = 'fcm.googleapis.com,updates.push.services.mozilla.com,web.push.apple.com'

    @field_validator('push_fcm_credentials_file', 'push_apns_key_file', 'push_webpush_private_key_file', mode='before')
    @classmethod
    def optional_credential_file(cls, value):
        # Compose supplies empty variables for providers that are not enabled.
        return None if value == '' else value

    @field_validator('password_reset_frontend_path')
    @classmethod
    def local_password_reset_frontend_path(cls, value: str) -> str:
        # Restrict to unencoded local segments so browsers cannot reinterpret
        # a scheme, authority, separator or dot segment in the emailed link.
        if (not re.fullmatch(r'/[A-Za-z0-9._~/-]*', value) or '//' in value
                or any(segment in {'.', '..'} for segment in value.split('/'))):
            raise ValueError('SNACKUP_PASSWORD_RESET_FRONTEND_PATH must be a local root-relative path without '
                             'schemes, queries, fragments, backslashes, encoding or dot segments.')
        return value.rstrip('/') + '/'

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
        if not (0.1 <= self.pool_timeout_seconds <= 10 and 0.1 <= self.admission_wait_seconds <= 10
                and 1 <= self.login_wait_seconds <= 10 and 1 <= self.write_concurrency <= 24
                and 1 <= self.mail_concurrency <= 24 and 1 <= self.session_concurrency <= 24
                and 1 <= self.password_concurrency <= 8 and 1 <= self.outbox_retention_days <= 90
                and 1 <= self.outbox_cleanup_batch <= 10000):
            raise ValueError('Invalid admission, password or outbox limits.')
        if not (1 <= self.max_websockets <= 10000 and 1 <= self.websocket_revalidate_seconds <= 30):
            raise ValueError('Invalid WebSocket capacity or authorization revalidation interval.')
        if not (1 <= self.access_token_minutes <= 60 and 1 <= self.refresh_days <= 30):
            raise ValueError('Invalid session lifetimes.')
        if not (0.1 <= self.push_poll_seconds <= 60 and 1 <= self.push_batch_size <= 100
                and 1 <= self.push_max_attempts <= 20 and 1 <= self.push_http_timeout_seconds <= 30
                and 1 <= self.push_retry_base_seconds <= 3600
                and 30 <= self.push_unconfigured_retry_seconds <= 86400
                and self.push_delivery_lease_seconds >= 3 * self.push_http_timeout_seconds):
            raise ValueError('Invalid push delivery limits or lease.')
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
