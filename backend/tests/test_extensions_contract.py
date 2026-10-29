"""Standalone student/identity specification and actual HTTP DTO compatibility."""
import json
from pathlib import Path
import re

from jsonschema import Draft202012Validator, FormatChecker
from openapi_spec_validator import validate

from snackup import admin, identity, operations

CONTRACT_DIR = Path(__file__).parents[1] / "contracts"
EXTENSIONS = json.loads((CONTRACT_DIR / "extensions.openapi.json").read_text(encoding="utf-8"))


def assert_extension_response(method, path, response):
    """Reusable response validator; never persist tokens, email or response bodies."""
    operation = EXTENSIONS["paths"][path][method.lower()]
    descriptor = operation["responses"].get(str(response.status_code), operation["responses"]["default"])
    content = descriptor.get("content", {})
    if "application/json" in content:
        schema = {**content["application/json"]["schema"], "components": EXTENSIONS["components"]}
        Draft202012Validator(schema, format_checker=FormatChecker()).validate(response.json())
    elif "text/html" in content:
        assert response.headers["content-type"].startswith("text/html")
        assert "<!doctype html>" in response.text.lower()
    else:
        assert response.content == b""


def test_extensions_are_valid_standalone_and_all_routes_exist():
    validate(EXTENSIONS)
    available = {(method.lower(), route.path) for router in (identity.router, operations.router, admin.router)
                 for route in router.routes for method in getattr(route, "methods", set())}
    expected = {(method, path) for path, item in EXTENSIONS["paths"].items() for method in item}
    assert len(expected) == 12
    assert expected <= available, expected - available
    original = json.loads((CONTRACT_DIR / "panels.openapi.json").read_text(encoding="utf-8"))
    for name in ["Error", "Pagination", "Business", "BusinessPage", "Product", "ProductPage", "OrderItem", "Review", "Profile", "VersionInput", "Received"]:
        assert EXTENSIONS["components"]["schemas"][name] == original["components"]["schemas"][name]


def test_actual_student_profile_catalog_order_and_cancel_match_contract(client, tokens):
    student = tokens["student"]
    for path in ["/users/me", "/student/businesses", "/student/businesses/business-1/products"]:
        response = client.get("/api/legacy/v1" + path, headers=student)
        assert response.status_code == 200
        template = "/student/businesses/{id}/products" if path.endswith("/products") else path
        assert_extension_response("get", template, response)
    response = client.post("/api/legacy/v1/student/orders", headers={**student, "Idempotency-Key": "contract-student-order-0001"},
                           json={"businessId": "business-1", "items": [{"productId": "product-1", "quantity": 1}]})
    assert response.status_code == 201, response.text
    assert_extension_response("post", "/student/orders", response)
    order = response.json()
    assert_extension_response("get", "/student/orders", client.get("/api/legacy/v1/student/orders", headers=student))
    assert_extension_response("get", "/student/orders/{id}", client.get(f"/api/legacy/v1/student/orders/{order['id']}", headers=student))
    denied = client.get(f"/api/legacy/v1/student/orders/{order['id']}", headers=tokens["other-student"])
    assert denied.status_code == 404
    assert_extension_response("get", "/student/orders/{id}", denied)
    cancelled = client.post(f"/api/legacy/v1/student/orders/{order['id']}/cancel", headers=student,
                            json={"expectedVersion": order["version"]})
    assert cancelled.status_code == 200
    assert_extension_response("post", "/student/orders/{id}/cancel", cancelled)


def test_actual_completed_order_review_matches_contract(client, tokens):
    response = client.post("/api/legacy/v1/student/orders", headers={**tokens["student"], "Idempotency-Key": "contract-student-review-001"},
                           json={"businessId": "business-1", "items": [{"productId": "product-1", "quantity": 1}]})
    assert response.status_code == 201
    order = response.json()
    code = order["pickupCode"]
    for action in ["accept", "start", "ready", "complete"]:
        payload = {"expectedVersion": order["version"]}
        if action == "complete":
            payload.update(code=code, method="manual")
        response = client.post(f"/api/legacy/v1/orders/{order['id']}/{action}", headers=tokens["operator"], json=payload)
        assert response.status_code == 200, response.text
        order = response.json()
    reviewed = client.post(f"/api/legacy/v1/student/orders/{order['id']}/review", headers=tokens["student"],
                           json={"rating": 5, "foodRating": None, "serviceRating": 4, "comment": "Todo correcto."})
    assert reviewed.status_code == 201
    assert_extension_response("post", "/student/orders/{id}/review", reviewed)
    assert reviewed.json()["careerId"] == "career-1"


def test_actual_registration_and_verification_responses_match_contract(client, app):
    response = client.post("/api/legacy/v1/student/register", json={"email": "unknown@students.example.edu", "password": "Test-only-password-45!"})
    assert response.status_code == 202
    assert_extension_response("post", "/student/register", response)
    page = client.get("/api/legacy/v1/auth/verify-email")
    assert page.status_code == 200
    assert_extension_response("get", "/auth/verify-email", page)
    request = client.post("/api/legacy/v1/auth/register", json={"email": "new-staff@staff.example.edu", "displayName": "Solicitante",
        "password": "Test-only-password-45!", "requestedRole": "admin", "context": "Solicitud institucional"})
    assert request.status_code == 202
    resend = client.post("/api/legacy/v1/auth/resend-verification", json={"email": "new-staff@staff.example.edu"})
    assert resend.status_code == 202
    assert_extension_response("post", "/auth/resend-verification", resend)
    token = re.search(r"token=([A-Za-z0-9_-]+)", app.state.mailbox[-1]["body"]).group(1)
    confirmation = client.post("/api/legacy/v1/auth/verify-email", headers={"Origin": app.state.settings.public_origin}, json={"token": token})
    assert confirmation.status_code == 204
    assert_extension_response("post", "/auth/verify-email", confirmation)
