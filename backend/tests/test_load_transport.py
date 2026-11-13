"""Keep isolated load traffic on loopback and preserve TLS verification."""
from datetime import datetime, timedelta, timezone
import ssl

from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.x509.oid import NameOID
import pytest

from load.phase_c.runner import load_transport


@pytest.fixture(autouse=True)
def isolated_transport_environment(monkeypatch):
    monkeypatch.delenv('SNACKUP_LOAD_BASE_URL', raising=False)
    monkeypatch.delenv('SNACKUP_LOAD_CA_FILE', raising=False)


@pytest.mark.parametrize('origin', [
    'https://example.com',
    'https://user:password@localhost:18443',
    'https://localhost:18443/api',
    'https://localhost:18443?target=elsewhere',
    'https://localhost:18443#fragment',
    'file:///tmp/target',
    'https://localhost:0',
])
def test_reject_nonisolated_or_ambiguous_destinations(monkeypatch, origin):
    monkeypatch.setenv('SNACKUP_LOAD_BASE_URL', origin)
    with pytest.raises(ValueError):
        load_transport()


def test_original_http_loopback_default_is_preserved():
    origin, context, metadata = load_transport()
    assert origin == 'http://127.0.0.1:18080'
    assert context is None
    assert metadata['trust'] == 'HTTP'


def test_ca_is_rejected_for_plain_http(monkeypatch, tmp_path):
    ca = tmp_path / 'ca.pem'
    ca.write_text('not used')
    monkeypatch.setenv('SNACKUP_LOAD_CA_FILE', str(ca))
    with pytest.raises(ValueError):
        load_transport()


def test_https_ca_keeps_hostname_and_certificate_validation(monkeypatch, tmp_path):
    key = ec.generate_private_key(ec.SECP256R1())
    name = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, 'Isolated load test CA')])
    now = datetime.now(timezone.utc)
    certificate = (x509.CertificateBuilder().subject_name(name).issuer_name(name)
                   .public_key(key.public_key()).serial_number(x509.random_serial_number())
                   .not_valid_before(now - timedelta(minutes=1)).not_valid_after(now + timedelta(hours=1))
                   .add_extension(x509.BasicConstraints(ca=True, path_length=0), critical=True)
                   .sign(key, hashes.SHA256()))
    ca = tmp_path / 'ca.pem'
    ca.write_bytes(certificate.public_bytes(serialization.Encoding.PEM))
    monkeypatch.setenv('SNACKUP_LOAD_BASE_URL', 'https://localhost:18443/')
    monkeypatch.setenv('SNACKUP_LOAD_CA_FILE', str(ca))
    origin, context, metadata = load_transport()
    assert origin == 'https://localhost:18443'
    assert context.check_hostname is True
    assert context.verify_mode == ssl.CERT_REQUIRED
    assert metadata['tlsCertificateValidation'] is True
    assert metadata['trust'] == 'explicit test CA, client only'


@pytest.mark.parametrize('path', ['relative-ca.pem', '/does-not-exist/snackup-load-ca.pem'])
def test_https_requires_a_real_absolute_ca_file_when_configured(monkeypatch, path):
    monkeypatch.setenv('SNACKUP_LOAD_BASE_URL', 'https://localhost:18443')
    monkeypatch.setenv('SNACKUP_LOAD_CA_FILE', path)
    with pytest.raises(ValueError):
        load_transport()
