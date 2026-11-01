"""Refresh only this local setup's Docker host address; never print credentials."""
import ipaddress
from pathlib import Path
import re
import subprocess
import sys

import psycopg
from dotenv import dotenv_values, set_key
from sqlalchemy.engine import make_url

path = Path(__file__).resolve().parents[1] / 'backend' / '.env'
if not path.is_file():
    sys.exit('Falta backend/.env. Configura primero el backend local.')
url = make_url(dotenv_values(path).get('SNACKUP_DATABASE_URL', ''))
if not (url.username or '').startswith('snackup_local_'):
    print('Se conserva la configuración de base de datos existente.')
    sys.exit(0)

def connects(host):
    try:
        with psycopg.connect(host=host, port=url.port or 5432, user=url.username,
                             password=url.password, dbname=url.database, connect_timeout=3) as connection:
            return 'Debian' in connection.execute('SELECT version()').fetchone()[0]
    except psycopg.Error:
        return False

if connects(url.host):
    print('Conexión con PostgreSQL de Docker verificada.')
    sys.exit(0)
result = subprocess.run(['wsl.exe', '-d', 'docker-desktop', '--', 'sh', '-c', 'ip -4 -o addr show eth0'],
                        capture_output=True, text=True)
match = re.search(r'\binet ([0-9.]+)/', result.stdout)
if not match or not ipaddress.ip_address(match[1]).is_private or not connects(match[1]):
    sys.exit('No se pudo conectar con PostgreSQL de Docker. Comprueba Docker Desktop y snackup-postgres.')
set_key(str(path), 'SNACKUP_DATABASE_URL', url.set(host=match[1]).render_as_string(hide_password=False))
print('Dirección local de Docker actualizada y conexión PostgreSQL verificada.')
