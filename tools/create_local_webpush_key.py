#!/usr/bin/env python3
"""Explicitly create one VAPID signing key outside the repository; never overwrite.

Run only after the deployment owner authorizes configuring browser push. This
does not enable a service, register devices, send notifications or contact any
provider. The output directory must already exist and be private to its owner.
"""
import argparse
import os
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', required=True, type=Path, help='Absolute PEM path in a private directory outside Git')
    args = parser.parse_args()
    output = args.output
    if not output.is_absolute() or output.resolve().is_relative_to(ROOT):
        parser.error('La clave debe usar una ruta absoluta fuera del repositorio.')
    if not output.parent.is_dir():
        parser.error('La carpeta privada debe existir antes de crear la clave.')
    try:
        from cryptography.hazmat.primitives import serialization
        from cryptography.hazmat.primitives.asymmetric import ec
        private = ec.generate_private_key(ec.SECP256R1())
        data = private.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8,
                                     serialization.NoEncryption())
        # O_EXCL also refuses existing symbolic links; no key rotation by accident.
        descriptor = os.open(output, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(descriptor, 'wb') as stream:
            stream.write(data)
        print('Clave VAPID creada en el archivo solicitado. No se habilitaron servicios ni se enviaron mensajes.')
    except FileExistsError:
        print('El archivo ya existe; se conserva sin cambios.', file=sys.stderr)
        return 1
    except Exception as error:
        print('No se pudo crear la clave: ' + type(error).__name__ + '. No se muestra material privado.', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
