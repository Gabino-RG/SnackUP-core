#!/usr/bin/env python3
"""Synthetic, loopback-only backend fixture for student frontend verification.

No backend source, .env or existing database is read or changed. The schema and
all records live in a new temporary SQLite directory outside this repository.
Default mode runs an API self-check and exits. --serve explicitly starts the
unchanged backend on 127.0.0.1:18081 for the frontend proxy on localhost:18080.
Never use these public test credentials with a real deployment.
"""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import secrets
import sys
import tempfile
from urllib.parse import urlsplit
from uuid import uuid4

sys.dont_write_bytecode = True
REPOSITORY = Path(__file__).resolve().parents[1]
STUDENT_EMAIL = "alumno@students.example.edu"
OPERATOR_EMAIL = "cocina@staff.example.edu"
PASSWORD = "Student-Fixture-Only-2026!"
BUSINESS_ID = "fixture-cafe-1"
PRODUCT_ID = "fixture-torta"


def isolate_environment() -> None:
    # Never consume deployment credentials or let an inherited setting select
    # production/storage/SMTP. This affects this process only, not the user env.
    if os.environ.get("SNACKUP_ENVIRONMENT", "").lower() == "production":
        raise SystemExit("Refusing to run a synthetic fixture in a production environment.")
    for name in tuple(os.environ):
        if name.startswith("SNACKUP_"):
            del os.environ[name]


def local_origin(value: str) -> str:
    url = urlsplit(value)
    if (url.scheme != "http" or url.hostname not in {"localhost", "127.0.0.1"}
            or url.username or url.password or url.path not in {"", "/"}
            or url.query or url.fragment or not url.port):
        raise argparse.ArgumentTypeError("Use an explicit loopback HTTP origin, e.g. http://localhost:18080.")
    return value.rstrip("/")


def make_app(directory: Path, origin: str):
    sys.path.insert(0, str(REPOSITORY / "backend"))
    from snackup.auth import hash_password
    from snackup.config import Settings
    from snackup.db import Base, utcnow
    from snackup.identity_models import AcademicGroup, AcademicRecord, Career, User
    from snackup.main import create_app
    from snackup.operation_models import Business, Product

    settings = Settings(
        _env_file=None,
        environment="test",
        database_url="sqlite:///" + (directory / "synthetic.sqlite3").as_posix(),
        secret_key=secrets.token_hex(32),
        public_origin=origin,
        institution_id="fixture-institution",
        institution_name="Institución de prueba",
        cafeteria_id="fixture-cafeteria",
        cafeteria_name="Cafeterías de prueba",
        admin_email_domains="staff.example.edu",
        student_email_domains="students.example.edu",
        media_dir=directory / "media",
        web_dir=None,
        redis_url="",
        smtp_host="",
        smtp_user="",
        smtp_password="",
        smtp_from="",
        enable_test_mailbox=True,
        background_events=True,
        push_enabled=False,
    )
    assert settings.environment == "test" and settings.database_url.startswith("sqlite:///")
    app = create_app(settings)
    app.state.mailbox = []
    app.state.mailer = lambda _settings, recipient, subject, body: app.state.mailbox.append(
        {"recipient": recipient, "subject": subject, "body": body})
    # Disposable test storage does not need crash durability. Keep foreign-key
    # constraints enabled, but avoid per-index fsync delays in Windows sandbox.
    from sqlalchemy import event

    @event.listens_for(app.state.db.engine, "connect")
    def temporary_sqlite_settings(connection, _record):
        cursor = connection.cursor()
        cursor.execute("PRAGMA journal_mode=MEMORY")
        cursor.execute("PRAGMA synchronous=OFF")
        cursor.close()

    Base.metadata.create_all(app.state.db.engine)
    password_hash = hash_password(PASSWORD)
    with app.state.db.sessions.begin() as db:
        db.add(Career(id="fixture-career", name="Ingeniería de Software (prueba)", is_active=True))
        db.flush()
        db.add(AcademicGroup(id="fixture-group", career_id="fixture-career", name="DEMO-1", is_active=True))
        db.add_all([
            Business(id=BUSINESS_ID, name="Cafetería de prueba", category="Comida y bebidas",
                     description="Datos sintéticos para verificar el cliente SnackUP.",
                     cafeteria_id="fixture-cafeteria", cafeteria_name="Cafeterías de prueba", is_open=True, is_active=True),
            Business(id="fixture-cafe-2", name="Rincón de prueba", category="Opciones ligeras",
                     cafeteria_id="fixture-cafeteria", cafeteria_name="Cafeterías de prueba", is_open=True, is_active=True),
            Business(id="fixture-cafe-closed", name="Local cerrado de prueba", category="Menú",
                     cafeteria_id="fixture-cafeteria", cafeteria_name="Cafeterías de prueba", is_open=False, is_active=True),
        ])
        db.flush()
        db.add_all([
            User(id="fixture-student", email=STUDENT_EMAIL, display_name="Alumno de prueba",
                 password_hash=password_hash, role="user", is_active=True, approval_status="approved",
                 email_verified=True, numero_de_control="DEMO-0001", institutional_verified_at=utcnow()),
            User(id="fixture-operator", email=OPERATOR_EMAIL, display_name="Cocina de prueba",
                 password_hash=password_hash, role="business", business_id=BUSINESS_ID,
                 is_active=True, approval_status="approved", email_verified=True),
        ])
        db.add(AcademicRecord(id="fixture-roster", email=STUDENT_EMAIL, institutional_id="DEMO-0001",
                             display_name="Alumno de prueba", kind="student", career_id="fixture-career",
                             group_id="fixture-group", is_active=True, source="synthetic frontend fixture"))
        db.add(AcademicRecord(id="fixture-new-roster", email="nuevo@students.example.edu", institutional_id="DEMO-0002",
                             display_name="Registro de prueba", kind="student", career_id="fixture-career",
                             group_id="fixture-group", is_active=True, source="synthetic frontend fixture"))
        db.add_all([
            Product(id=PRODUCT_ID, business_id=BUSINESS_ID, name="Torta de pollo", category="Comida",
                    description="Pan, pollo y verduras. Personaliza tus notas.", price="35.50", stock=30,
                    preparation_minutes=8, calories=420, is_featured=True, is_available=True, manual_available=True),
            Product(id="fixture-agua", business_id=BUSINESS_ID, name="Agua de jamaica", category="Bebidas",
                    description="Vaso de agua fresca.", price="18.00", stock=None,
                    preparation_minutes=2, is_featured=True, is_available=True, manual_available=True),
            Product(id="fixture-sold-out", business_id=BUSINESS_ID, name="Ensalada agotada", category="Comida",
                    description="Ejemplo de producto sin existencias.", price="48.00", stock=0,
                    is_available=False, manual_available=True),
            Product(id="fixture-sandwich", business_id="fixture-cafe-2", name="Sándwich integral", category="Comida",
                    description="Ejemplo de producto de otro local.", price="42.00", stock=20, is_available=True),
        ])
    return app


def self_check(app, origin: str) -> dict:
    from fastapi.testclient import TestClient

    def checked(response, expected: int, operation: str):
        if response.status_code != expected:
            try:
                code = response.json().get("error", {}).get("code", "unknown")
            except (ValueError, AttributeError):
                code = "non-json"
            raise RuntimeError(f"{operation}: HTTP {response.status_code}, expected {expected}; code={code}")
        return response.json() if response.content else None

    with TestClient(app, base_url=origin) as client:
        student = checked(client.post("/api/v1/auth/login", headers={"Origin": origin},
                                     json={"email": STUDENT_EMAIL, "password": PASSWORD}), 200, "student login")
        assert student["user"]["role"] == "ALUMNO" and "refreshToken" not in student["tokens"]
        headers = {"Authorization": "Bearer " + student["tokens"]["accessToken"], "Origin": origin}
        businesses = checked(client.get("/api/v1/businesses", headers=headers), 200, "businesses")
        featured = checked(client.get("/api/v1/products/featured", headers=headers), 200, "featured")
        checked(client.put(f"/api/v1/users/me/favorites/{PRODUCT_ID}", headers=headers, json={"notes": "Sin cebolla"}), 200, "favorite")
        checked(client.post("/api/v1/users/me/cart/items", headers=headers,
                            json={"productId": PRODUCT_ID, "quantity": 2, "notes": "Sin cebolla"}), 200, "cart")
        payload = {"businessId": BUSINESS_ID, "items": [{"productId": PRODUCT_ID, "quantity": 2, "notes": "Sin cebolla"}],
                   "paymentMethod": "Efectivo", "expectedTotal": 71.0}
        order_headers = {**headers, "Idempotency-Key": str(uuid4())}
        order = checked(client.post("/api/v1/orders", headers=order_headers, json=payload), 201, "create order")
        duplicate = checked(client.post("/api/v1/orders", headers=order_headers, json=payload), 201, "idempotent retry")
        assert duplicate["id"] == order["id"]
        pickup_code = order["pickupCode"]
        operator = checked(client.post("/api/v1/auth/login", json={"email": OPERATOR_EMAIL, "password": PASSWORD}), 200, "operator login")
        assert operator["user"]["role"] == "COCINA"
        operator_headers = {"Authorization": "Bearer " + operator["tokens"]["accessToken"], "Origin": origin}
        states = [order["status"]]
        for action in ("accept", "start", "ready"):
            order = checked(client.post(f"/api/v1/orders/{order['id']}/{action}", headers=operator_headers,
                                        json={"expectedVersion": order["version"]}), 200, action)
            states.append(order["status"])
        order = checked(client.post(f"/api/v1/orders/{order['id']}/complete", headers=operator_headers,
                                    json={"expectedVersion": order["version"], "method": "manual", "code": pickup_code}), 200, "pickup")
        states.append(order["status"])
        history = checked(client.get("/api/v1/users/me/orders/history", headers=headers), 200, "history")
        assert any(row["id"] == order["id"] for row in history["data"])
        checked(client.post(f"/api/v1/orders/{order['id']}/rating", headers=headers,
                            json={"stars": 5, "comment": "Buen servicio de prueba"}), 201, "business rating")
        review_body = {"reviews": [{"productId": PRODUCT_ID, "rating": 0, "comment": "Reseña sintética"}]}
        checked(client.post(f"/api/v1/orders/{order['id']}/reviews", headers=headers,
                            json=review_body), 201, "product review")
        checked(client.post(f"/api/v1/orders/{order['id']}/reviews", headers=headers,
                            json=review_body), 409, "duplicate product review")
        reviews = checked(client.get(f"/api/v1/products/{PRODUCT_ID}/reviews", headers=headers), 200, "public product reviews")
        assert len(reviews["data"]) == 1 and reviews["data"][0]["rating"] == 0
        assert not {"userId", "orderId", "numeroDeControl"} & set(reviews["data"][0])
        return {"check": "passed", "backendSource": "unchanged", "database": "temporary SQLite",
                "businesses": len(businesses["data"]), "featured": len(featured["data"]),
                "flow": "login → catalog → favorite → cart → idempotent order → pickup → history → business/product reviews", "states": states,
                "duplicateReviewRejected": True, "publicReviewIdentityHidden": True}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--serve", action="store_true", help="Start the loopback-only fixture; otherwise run its self-check and exit.")
    parser.add_argument("--origin", type=local_origin, default="http://localhost:18080")
    parser.add_argument("--port", type=int, default=18081)
    args = parser.parse_args()
    if not 1024 <= args.port <= 65535:
        parser.error("The fixture port must be between 1024 and 65535.")
    isolate_environment()
    temporary_root = REPOSITORY.parent / "frontend-fixture-tmp"
    temporary_root.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="snackup-student-", dir=temporary_root) as directory:
        app = make_app(Path(directory), args.origin)
        try:
            if args.serve:
                import uvicorn
                print(json.dumps({"fixture": "synthetic only", "backend": f"http://127.0.0.1:{args.port}",
                                  "browserOrigin": args.origin, "studentEmail": STUDENT_EMAIL,
                                  "operatorEmail": OPERATOR_EMAIL, "password": PASSWORD,
                                  "businessId": BUSINESS_ID, "productId": PRODUCT_ID}), flush=True)
                uvicorn.run(app, host="127.0.0.1", port=args.port, access_log=False, log_level="warning")
            else:
                print(json.dumps(self_check(app, args.origin)), flush=True)
        finally:
            app.state.db.dispose()


if __name__ == "__main__":
    main()
