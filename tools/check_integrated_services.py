#!/usr/bin/env python3
"""Check private service configuration without sending messages or touching SQL."""
import argparse
import json
from pathlib import Path
import sys

sys.dont_write_bytecode = True
from integrated_server import DEFAULT_CONFIG, configuration, local_settings
from integration_services import ServiceConfigurationError, service_status


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--config', type=Path, default=DEFAULT_CONFIG)
    args = parser.parse_args()
    try:
        settings = local_settings(configuration(args.config))
        print(json.dumps(service_status(settings), ensure_ascii=False, indent=2))
    except ServiceConfigurationError as error:
        print('Configuración de servicios inválida: ' + str(error), file=sys.stderr)
        return 1
    except Exception as error:
        print('No se pudo comprobar la configuración: ' + type(error).__name__
              + '. No se muestran datos privados.', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
