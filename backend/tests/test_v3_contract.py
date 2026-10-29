"""Standalone OpenAPI validity and actual HTTP response/privacy compatibility."""
import json
from pathlib import Path
import re
from uuid import uuid4

from jsonschema import Draft202012Validator, FormatChecker
from openapi_spec_validator import validate
import pytest

from snackup.db import utcnow
from snackup.operation_models import Order
from tools.export_v3_openapi import encoded_document, export_document

pytestmark = pytest.mark.v3
CONTRACT_PATH = Path(__file__).parents[1] / "contracts" / "v3.openapi.json"
CONTRACT = json.loads(CONTRACT_PATH.read_text(encoding="utf-8"))
METHODS = {"get", "post", "put", "patch", "delete"}


def assert_response(method, path, response):
    operation = CONTRACT["paths"][path][method.lower()]
    descriptor = operation["responses"].get(str(response.status_code), operation["responses"]["default"])
    content = descriptor.get("content", {})
    if "application/json" in content:
        schema = {**content["application/json"]["schema"], "components": CONTRACT["components"]}
        errors = list(Draft202012Validator(schema, format_checker=FormatChecker()).iter_errors(response.json()))
        # Diagnostics identify schema paths, never tokens or private response data.
        assert not errors, (operation["operationId"], response.status_code,
                            [(list(error.path), error.validator) for error in errors[:8]])
    else:
        assert response.status_code == 204 and not response.content
    return response.json() if response.content else None


def buy(client, headers):
    response = client.post("/api/v1/orders", headers={**headers, "Idempotency-Key": str(uuid4())},
        json={"businessId": "business-1", "items": [{"productId": "product-1", "quantity": 1}],
              "expectedTotal": 35.50, "paymentMethod": "Efectivo"})
    assert response.status_code == 201, response.text
    return assert_response("post", "/api/v1/orders", response)


def test_v3_snapshot_is_valid_standalone_current_and_environment_independent(app, monkeypatch):
    validate(CONTRACT)
    assert CONTRACT == app.openapi(), "Regenerate contracts/v3.openapi.json after changing the API."
    monkeypatch.setenv("SNACKUP_SECRET_KEY", "invalid-private-environment-must-not-be-read")
    monkeypatch.setenv("SNACKUP_DATABASE_URL", "not-a-database-url")
    monkeypatch.setenv("SNACKUP_WEB_DIR", "/directory-that-does-not-exist")
    assert encoded_document(export_document()) == CONTRACT_PATH.read_text(encoding="utf-8")
    assert CONTRACT["openapi"] == "3.1.0"
    assert not any("/legacy/" in path or path.endswith("/realtime") for path in CONTRACT["paths"])
    assert all(path.startswith("/api/v1/") or path in {"/health/live", "/health/ready"} for path in CONTRACT["paths"])
    operations = [op for item in CONTRACT["paths"].values() for method, op in item.items() if method in METHODS]
    identifiers = [operation["operationId"] for operation in operations]
    assert len(identifiers) == len(set(identifiers))
    assert "HTTPValidationError" not in CONTRACT["components"]["schemas"]
    assert CONTRACT["components"]["schemas"]["AppUserResponse"]["properties"]["role"]["enum"] == ["ALUMNO", "COCINA", "ADMIN"]
    for path, item in CONTRACT["paths"].items():
        for method, operation in item.items():
            if method not in METHODS:
                continue
            for status, response in operation["responses"].items():
                if status.startswith("2") and status != "204":
                    assert response["content"]["application/json"]["schema"], (path, method, "missing response DTO")
            if path.startswith("/api/v1/") and not path.startswith("/api/v1/auth/"):
                assert {"BearerAuth": []} in operation.get("security", []), path


def test_real_login_profile_device_and_catalog_match_contract(client, tokens):
    native = client.post("/api/v1/auth/login", json={"email": "student@students.example.edu", "password": "Test-Only-Password-392!"})
    assert native.status_code == 200
    session = assert_response("post", "/api/v1/auth/login", native)
    assert session["user"]["role"] == "ALUMNO" and "refreshToken" in session["tokens"]
    assert set(session["user"]).isdisjoint({"password", "passwordHash", "password_hash", "auth_version", "approval_status"})
    browser = client.post("/api/v1/auth/login", headers={"Origin": "http://testserver"},
                         json={"email": "student@students.example.edu", "password": "Test-Only-Password-392!"})
    assert "refreshToken" not in assert_response("post", "/api/v1/auth/login", browser)["tokens"]
    assert "HttpOnly" in browser.headers["set-cookie"]
    for path, template in [("/api/v1/users/me", "/api/v1/users/me"),
                           ("/api/v1/businesses", "/api/v1/businesses"),
                           ("/api/v1/businesses/business-1/products?fields=id,price", "/api/v1/businesses/{id}/products")]:
        response = client.get(path, headers=tokens["student"])
        assert response.status_code == 200
        body = assert_response("get", template, response)
        if "fields=" in path:
            assert set(body["data"][0]) == {"id", "price"}
    registered = client.post("/api/v1/users/me/devices", headers=tokens["student"],
        json={"token": "private-contract-test-device-token", "platform": "android", "provider": "fcm"})
    assert registered.status_code == 201
    device = assert_response("post", "/api/v1/users/me/devices", registered)
    assert "token" not in device
    removed = client.delete("/api/v1/users/me/devices/" + device["id"], headers=tokens["student"])
    assert removed.status_code == 204
    assert_response("delete", "/api/v1/users/me/devices/{deviceId}", removed)


def test_order_contract_excludes_private_fields_for_kitchen_and_denies_admin(client, tokens):
    order = buy(client, tokens["student"])
    private = {"userId", "customerNumeroDeControl", "pickupCode"}
    assert private <= set(order) and re.fullmatch(r"[A-Z0-9]{6}", order["pickupCode"])
    route = "/api/v1/orders/" + order["id"]
    own = client.get(route, headers=tokens["student"])
    assert assert_response("get", "/api/v1/orders/{id}", own)["pickupCode"] == order["pickupCode"]
    kitchen = client.get(route, headers=tokens["operator"])
    assert kitchen.status_code == 200
    assert not private & set(assert_response("get", "/api/v1/orders/{id}", kitchen))
    active = client.get("/api/v1/businesses/business-1/orders/active", headers=tokens["operator"])
    assert active.status_code == 200
    assert all(not private & set(value) for value in assert_response("get", "/api/v1/businesses/{id}/orders/active", active)["data"])
    for identity in ("admin", "other-student", "other-operator"):
        denied = client.get(route, headers=tokens[identity])
        assert denied.status_code in {403, 404}
        assert_response("get", "/api/v1/orders/{id}", denied)
        assert order["pickupCode"] not in denied.text
    for action in ("accept", "start", "ready", "complete"):
        payload = {"expectedVersion": order["version"]}
        if action == "complete":
            payload.update(method="manual", code=order["pickupCode"])
        response = client.post(route + "/" + action, headers=tokens["operator"], json=payload)
        assert response.status_code == 200, response.text
        kitchen_order = assert_response("post", "/api/v1/orders/{id}/" + action, response)
        assert not private & set(kitchen_order)
        order["version"] = kitchen_order["version"]
    rated = client.post(route + "/rating", headers=tokens["student"], json={"rating": 5, "comment": "Prueba de contrato"})
    assert rated.status_code == 201
    assert_response("post", "/api/v1/orders/{id}/rating", rated)


def test_controlled_errors_match_envelope_without_reflecting_private_input(client, tokens):
    secret = "PRIVATE-INPUT-DO-NOT-REFLECT"
    invalid = client.post("/api/v1/auth/login", json={"email": "student@students.example.edu", "password": {"secret": secret}})
    assert invalid.status_code == 422
    body = assert_response("post", "/api/v1/auth/login", invalid)
    assert body["error"]["code"] == "INVALID_INPUT" and secret not in invalid.text
    assert all(set(detail) == {"field", "rule"} for detail in body["error"]["details"])
    missing = client.get("/api/v1/users/me")
    assert missing.status_code == 401
    assert_response("get", "/api/v1/users/me", missing)
    bad_items = client.post("/api/v1/orders", headers={**tokens["student"], "Idempotency-Key": str(uuid4())},
                           json={"businessId": "business-1", "items": [], "expectedTotal": 0})
    assert bad_items.status_code == 400
    assert assert_response("post", "/api/v1/orders", bad_items)["error"]["code"] == "INVALID_ITEMS"
    google = client.get("/api/v1/auth/google/start", follow_redirects=False)
    assert google.status_code == 503
    assert assert_response("get", "/api/v1/auth/google/start", google)["error"]["code"] == "GOOGLE_DISABLED"
    assert "200" not in CONTRACT["paths"]["/api/v1/auth/google/start"]["get"]["responses"]
    assert client.get("/api/v1/student/orders", headers=tokens["student"]).status_code == 404


def test_retained_institutional_dtos_are_documented_and_keep_reviews_anonymous(client, app, tokens):
    order = buy(client, tokens["student"])
    with app.state.db.sessions.begin() as db:
        row = db.get(Order, order["id"])
        row.status, row.completed_at = "completed", utcnow()
    review = client.post("/api/v1/orders/" + order["id"] + "/rating", headers=tokens["student"],
                         json={"rating": 4, "comment": "Contrato institucional"})
    assert review.status_code == 201
    review_id = review.json()["id"]
    for path in ("/api/v1/institution", "/api/v1/admin/academic-catalog", "/api/v1/admin/reviews", "/api/v1/admin/followups"):
        response = client.get(path, headers=tokens["admin"])
        assert response.status_code == 200
        body = assert_response("get", path, response)
        assert CONTRACT["paths"][path]["get"]["x-api-scope"] == "institutional-extension"
        if path.endswith("reviews"):
            assert len(body["data"]) == 1
            assert not {"userId", "orderId", "email", "displayName", "customerName", "numeroDeControl"} & set(body["data"][0])
    followup = client.put("/api/v1/admin/reviews/" + review_id + "/followup", headers=tokens["admin"],
                         json={"status": "in_review", "assignee": "Coordinación", "note": "Revisión de prueba", "expectedVersion": 0})
    assert followup.status_code == 200, followup.text
    assert_response("put", "/api/v1/admin/reviews/{id}/followup", followup)
    history = client.get("/api/v1/admin/reviews/" + review_id + "/followup/history", headers=tokens["admin"])
    assert history.status_code == 200
    assert_response("get", "/api/v1/admin/reviews/{id}/followup/history", history)
