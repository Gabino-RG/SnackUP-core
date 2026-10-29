#!/usr/bin/env python3
"""Reproducibly export the running V3 API contract without real configuration.

From backend/: python tools/export_v3_openapi.py [--check] [--output path]
No database connection, service credentials or application lifespan is used.
"""
import argparse
import json
from pathlib import Path
import sys
from tempfile import TemporaryDirectory

BACKEND = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(BACKEND))

from snackup.config import Settings  # noqa: E402
from snackup.main import create_app  # noqa: E402


def export_document():
    # Explicitly provide every default so developer/production environment
    # variables cannot make the artifact depend on private local configuration.
    defaults = {name: field.get_default(call_default_factory=True)
                for name, field in Settings.model_fields.items() if not field.is_required()}
    with TemporaryDirectory(prefix="snackup-openapi-") as temporary:
        defaults.update(environment="test", secret_key="schema-export-placeholder-not-a-deployment-key",
                        database_url="sqlite://", public_origin="http://contract.invalid",
                        redis_url="", background_events=False, web_dir=None, media_dir=Path(temporary))
        app = create_app(Settings(_env_file=None, **defaults))
        try:
            return app.openapi()
        finally:
            app.state.limiter.close()
            app.state.db.dispose()


def encoded_document(document):
    return json.dumps(document, ensure_ascii=False, indent=2, sort_keys=True) + "\n"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="Fail if the checked-in contract is stale; do not write.")
    parser.add_argument("--output", type=Path, default=BACKEND / "contracts" / "v3.openapi.json")
    args = parser.parse_args()
    encoded = encoded_document(export_document())
    if args.check:
        if not args.output.is_file() or args.output.read_text(encoding="utf-8") != encoded:
            parser.exit(1, "V3 OpenAPI snapshot is stale. Run python tools/export_v3_openapi.py.\n")
        print("V3 OpenAPI snapshot matches the application.")
    else:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(encoded, encoding="utf-8")
        print("Wrote " + str(args.output))


if __name__ == "__main__":
    main()
