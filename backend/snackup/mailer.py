"""SMTP delivery only; no production log/file mailbox or fake success mode."""
import smtplib
import ssl
from email.message import EmailMessage

from .errors import ApiError


def mail_available(settings) -> bool:
    return bool(settings.smtp_host and settings.smtp_from)


def send_mail(settings, recipient: str, subject: str, body: str) -> None:
    if not mail_available(settings):
        raise ApiError(503, "EMAIL_UNAVAILABLE", "El envío de correo aún no está configurado.")
    message = EmailMessage()
    message["From"] = settings.smtp_from
    message["To"] = recipient
    message["Subject"] = subject
    message.set_content(body)
    try:
        connection_type = smtplib.SMTP_SSL if int(settings.smtp_port) == 465 else smtplib.SMTP
        kwargs = {"timeout": 15}
        if connection_type is smtplib.SMTP_SSL:
            kwargs["context"] = ssl.create_default_context()
        with connection_type(settings.smtp_host, int(settings.smtp_port), **kwargs) as server:
            if connection_type is smtplib.SMTP and settings.smtp_starttls:
                server.starttls(context=ssl.create_default_context())
            if settings.smtp_user:
                server.login(settings.smtp_user, settings.smtp_password)
            server.send_message(message)
    except (OSError, smtplib.SMTPException):
        # Provider diagnostics can contain addresses/secrets; never echo them.
        raise ApiError(503, "EMAIL_UNAVAILABLE", "No se pudo enviar el correo. Intenta nuevamente.") from None
