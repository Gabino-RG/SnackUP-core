"""Explicit private SMTP/push settings for the local integration launcher.

This module never connects to a provider. Disabled services do not read their
credentials. Error messages contain setting names only, never supplied values.
"""
from __future__ import annotations

from email.utils import parseaddr
import ipaddress
import json
from pathlib import Path
import re


class ServiceConfigurationError(ValueError):
    """A configuration error whose message is safe to display."""


def _fail(field: str, reason: str) -> None:
    raise ServiceConfigurationError(f'{field}: {reason}')


def _object(value, field: str, allowed: set[str]) -> dict:
    if not isinstance(value, dict):
        _fail(field, 'debe ser un objeto JSON.')
    if set(value) - allowed:
        _fail(field, 'contiene campos no admitidos; consulta el ejemplo sin secretos.')
    return value


def _boolean(data: dict, key: str, field: str, default: bool = False) -> bool:
    value = data.get(key, default)
    if not isinstance(value, bool):
        _fail(field, 'debe ser true o false, sin comillas.')
    return value


def _text(data: dict, key: str, field: str, required: bool = False) -> str:
    value = data.get(key, '')
    if not isinstance(value, str) or any(c in value for c in '\r\n\x00'):
        _fail(field, 'debe ser texto de una sola línea.')
    value = value.strip()
    if required and not value:
        _fail(field, 'es obligatorio cuando se habilita el servicio.')
    return value


def _private_file(value, field: str, repo: Path) -> Path:
    if not isinstance(value, str) or not value.strip():
        _fail(field, 'indica un archivo privado absoluto fuera del repositorio.')
    path = Path(value)
    if not path.is_absolute() or path.resolve().is_relative_to(repo.resolve()):
        _fail(field, 'el archivo debe estar fuera del repositorio y usar una ruta absoluta.')
    if not path.is_file():
        _fail(field, 'el archivo privado no existe o no es accesible.')
    return path.resolve()


def _host(value: str, field: str) -> None:
    try:
        ipaddress.ip_address(value)
        return
    except ValueError:
        pass
    labels = value.rstrip('.').split('.')
    if (len(value) > 253 or not labels or any(
            not re.fullmatch(r'[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?', label)
            for label in labels)):
        _fail(field, 'indica un nombre de servidor o IP, sin URL, puerto ni credenciales.')


def service_settings(config: dict, repo: Path) -> dict:
    """Return explicit Settings keyword arguments; no networking or database I/O."""
    result = {
        'smtp_host': '', 'smtp_from': '', 'smtp_user': '', 'smtp_password': '',
        'smtp_port': 587, 'smtp_starttls': True,
        'push_enabled': False,
        'push_fcm_credentials_file': None, 'push_fcm_project_id': '',
        'push_apns_key_file': None, 'push_apns_key_id': '', 'push_apns_team_id': '',
        'push_apns_topic': '', 'push_apns_sandbox': False,
        'push_webpush_private_key_file': None, 'push_webpush_subject': '',
    }
    if not config.get('services_file'):
        return result
    path = _private_file(config['services_file'], 'services_file', repo)
    try:
        if path.stat().st_size > 64 * 1024:
            _fail('services_file', 'el JSON supera el tamaño permitido.')
        services = json.loads(path.read_text(encoding='utf-8-sig'))
    except (OSError, UnicodeError, json.JSONDecodeError):
        _fail('services_file', 'no se pudo leer un JSON válido; no se muestra su contenido.')
    services = _object(services, 'services_file', {'schema_version', 'smtp', 'push'})
    if type(services.get('schema_version')) is not int or services['schema_version'] != 1:
        _fail('schema_version', 'debe ser 1.')

    smtp = _object(services.get('smtp', {}), 'smtp', {
        'enabled', 'host', 'port', 'starttls', 'from', 'user', 'password_file',
    })
    if _boolean(smtp, 'enabled', 'smtp.enabled'):
        host = _text(smtp, 'host', 'smtp.host', required=True)
        _host(host, 'smtp.host')
        sender = _text(smtp, 'from', 'smtp.from', required=True)
        _, address = parseaddr(sender)
        if not re.fullmatch(r'[^\s<>@]+@[^\s<>@]+\.[^\s<>@]+', address):
            _fail('smtp.from', 'indica un remitente de correo válido y autorizado por el proveedor.')
        port = smtp.get('port', 587)
        if type(port) is not int or not 1 <= port <= 65535:
            _fail('smtp.port', 'debe ser un número de puerto válido.')
        starttls = _boolean(smtp, 'starttls', 'smtp.starttls', True)
        if port != 465 and not starttls:
            _fail('smtp.starttls', 'usa STARTTLS o el puerto 465 con TLS; no se admite correo sin cifrar.')
        user = _text(smtp, 'user', 'smtp.user')
        password = ''
        if user:
            password_path = _private_file(smtp.get('password_file'), 'smtp.password_file', repo)
            try:
                if not 1 <= password_path.stat().st_size <= 4096:
                    _fail('smtp.password_file', 'el tamaño del archivo no es válido.')
                password = password_path.read_text(encoding='utf-8-sig').rstrip('\r\n')
            except (OSError, UnicodeError):
                _fail('smtp.password_file', 'no se pudo leer el archivo privado.')
            if not password or any(c in password for c in '\r\n\x00'):
                _fail('smtp.password_file', 'debe contener una sola contraseña no vacía.')
        elif smtp.get('password_file'):
            _fail('smtp.user', 'es obligatorio si se indica un archivo de contraseña.')
        result.update(smtp_host=host, smtp_from=sender, smtp_port=port,
                      smtp_starttls=starttls, smtp_user=user, smtp_password=password)

    push = _object(services.get('push', {}), 'push', {'enabled', 'fcm', 'apns', 'webpush'})
    fcm = _object(push.get('fcm', {}), 'push.fcm', {'credentials_file', 'project_id'})
    apns = _object(push.get('apns', {}), 'push.apns', {'key_file', 'key_id', 'team_id', 'topic', 'sandbox'})
    webpush = _object(push.get('webpush', {}), 'push.webpush', {'private_key_file', 'subject'})
    if not _boolean(push, 'enabled', 'push.enabled'):
        return result
    configured = []
    if fcm.get('credentials_file') or fcm.get('project_id'):
        project = _text(fcm, 'project_id', 'push.fcm.project_id', required=True)
        if not re.fullmatch(r'[a-z0-9][a-z0-9-]{3,62}', project):
            _fail('push.fcm.project_id', 'el identificador de proyecto no es válido.')
        result.update(push_fcm_credentials_file=_private_file(
            fcm.get('credentials_file'), 'push.fcm.credentials_file', repo),
            push_fcm_project_id=project)
        configured.append('fcm')
    if any(apns.get(key) for key in ('key_file', 'key_id', 'team_id', 'topic')):
        values = {key: _text(apns, key, f'push.apns.{key}', required=True)
                  for key in ('key_id', 'team_id', 'topic')}
        if any(not re.fullmatch(r'[A-Za-z0-9]{8,32}', values[key]) for key in ('key_id', 'team_id')):
            _fail('push.apns', 'key_id y team_id no tienen un formato válido.')
        if not re.fullmatch(r'[A-Za-z0-9.-]{3,255}', values['topic']):
            _fail('push.apns.topic', 'el identificador de aplicación no es válido.')
        result.update(push_apns_key_file=_private_file(apns.get('key_file'), 'push.apns.key_file', repo),
                      push_apns_key_id=values['key_id'], push_apns_team_id=values['team_id'],
                      push_apns_topic=values['topic'],
                      push_apns_sandbox=_boolean(apns, 'sandbox', 'push.apns.sandbox'))
        configured.append('apns')
    if webpush.get('private_key_file') or webpush.get('subject'):
        subject = _text(webpush, 'subject', 'push.webpush.subject', required=True)
        from urllib.parse import urlsplit
        parsed = urlsplit(subject)
        valid_subject = (parsed.scheme == 'mailto' and re.fullmatch(r'[^\s@]+@[^\s@]+\.[^\s@]+', parsed.path)
                         or parsed.scheme == 'https' and parsed.hostname and not parsed.username and not parsed.password)
        if not valid_subject or parsed.query or parsed.fragment or any(c.isspace() for c in subject):
            _fail('push.webpush.subject', 'usa un contacto mailto: o HTTPS sin credenciales.')
        result.update(push_webpush_private_key_file=_private_file(
            webpush.get('private_key_file'), 'push.webpush.private_key_file', repo),
            push_webpush_subject=subject)
        configured.append('webpush')
    if not configured:
        _fail('push.enabled', 'configura al menos un proveedor real antes de habilitar las notificaciones.')
    result['push_enabled'] = True
    return result


def service_status(settings) -> dict:
    """Safe local diagnostic: describes configuration, not delivery success."""
    from snackup.push import webpush_public_key
    return {
        'email': {
            'configured': bool(settings.smtp_host and settings.smtp_from),
            'encryptedTransportRequired': True,
            'deliveryVerified': False,
        },
        'push': {
            'enabled': settings.push_enabled,
            'providersConfigured': {
                'fcm': bool(settings.push_fcm_credentials_file and settings.push_fcm_project_id),
                'apns': bool(settings.push_apns_key_file and settings.push_apns_key_id
                             and settings.push_apns_team_id and settings.push_apns_topic),
                'webpush': bool(settings.push_webpush_private_key_file and settings.push_webpush_subject),
            },
            'webPushPublicKeyAvailable': webpush_public_key(settings) is not None,
            'deviceSubscriptionVerified': False,
            'deliveryVerified': False,
        },
        'scope': 'configuration-only; no provider connection, messages, database writes or seed data',
    }
