"""Documentation overrides for behavior not inferred from FastAPI signatures.

This module changes the published contract only. Runtime authorization, DTO
filtering and error responses remain in their existing routes and handlers.
"""
from copy import deepcopy

from .common import contract as panel_contract

METHODS = {"get", "post", "put", "patch", "delete", "options", "head", "trace"}
ERROR_REF = {"$ref": "#/components/schemas/ApiErrorEnvelope"}


def _error_response(description):
    return {"description": description, "content": {"application/json": {"schema": deepcopy(ERROR_REF)}}}


def _institutional_extensions(document):
    """Reuse the schemas the retained institutional routes actually validate.

    Only reachable component schemas are imported, under an explicit prefix;
    the old account roles and old order DTOs do not enter the V3 contract.
    """
    source = panel_contract()
    schemas = document.setdefault("components", {}).setdefault("schemas", {})

    def rewrite(value):
        if isinstance(value, list):
            return [rewrite(item) for item in value]
        if not isinstance(value, dict):
            return value
        result = {}
        for key, item in value.items():
            if key == "$ref" and item.startswith("#/components/schemas/"):
                original = item.removeprefix("#/components/schemas/")
                name = "Institutional_" + original
                if name not in schemas:
                    schemas[name] = {}  # Handle recursive schemas, if later added.
                    schemas[name] = rewrite(source["components"]["schemas"][original])
                result[key] = "#/components/schemas/" + name
            else:
                result[key] = rewrite(item)
        return result

    for path, item in document["paths"].items():
        relative = path.removeprefix("/api/v1")
        if relative != "/institution" and not relative.startswith(("/admin/reviews", "/admin/followups", "/admin/academic-catalog")):
            continue
        for method, operation in item.items():
            if method not in METHODS:
                continue
            original = source["paths"][relative][method]
            operation["responses"] = rewrite(original["responses"])
            if "requestBody" in original:
                operation["requestBody"] = rewrite(original["requestBody"])
            # Keep generated query/path constraints and actual Bearer dependency.
            operation["description"] = (original.get("description", "") + "\n\n"
                "Extensión institucional conservada con su DTO de paneles. No utiliza los DTOs de cuenta o pedido V3.").strip()
            operation["x-contract-origin"] = "panels.openapi.json"
            operation["x-api-scope"] = "institutional-extension"


def enrich_openapi(document):
    document = deepcopy(document)
    _institutional_extensions(document)
    components = document.setdefault("components", {})
    schemas = components.setdefault("schemas", {})
    schemas["ApiErrorEnvelope"] = {
        "type": "object", "additionalProperties": False, "required": ["error"],
        "properties": {"error": {"type": "object", "additionalProperties": False,
            "required": ["code", "message"], "properties": {
                "code": {"type": "string", "minLength": 1}, "message": {"type": "string"},
                "details": {"description": "Metadatos opcionales; la validación devuelve field/rule sin repetir valores privados."}}}},
    }
    for name in ("HTTPValidationError", "ValidationError"):
        schemas.pop(name, None)
    for path, item in document["paths"].items():
        for method, operation in item.items():
            if method not in METHODS:
                continue
            responses = operation.setdefault("responses", {})
            if "422" in responses:
                responses["422"] = _error_response("Entrada inválida. El backend devuelve error.code/message/details.")
            responses["default"] = _error_response("Error controlado de la API; code identifica la causa.")
            responses.setdefault("500", {"description": "Error interno no controlado.",
                "content": {"text/plain": {"schema": {"type": "string"}}}})
            if path.startswith("/api/v1") and not path.startswith("/api/v1/auth/"):
                responses.setdefault("401", _error_response("JWT ausente, vencido o sesión revocada."))
                responses.setdefault("403", _error_response("El rol o el ámbito del recurso no está autorizado."))
            if path in {"/health/live", "/health/ready"}:
                responses["200"] = {"description": "Estado del servicio.", "content": {"application/json": {"schema": {
                    "type": "object", "additionalProperties": False, "required": ["status"],
                    "properties": {"status": {"type": "string", "const": "ok" if path.endswith("live") else "ready"}}}}}}
    google = document["paths"]["/api/v1/auth/google/start"]["get"]
    google["description"] = "Google está deshabilitado; la ruta siempre devuelve GOOGLE_DISABLED (503)."
    google["responses"].pop("200", None)
    google["responses"]["503"] = _error_response("GOOGLE_DISABLED. No se redirige a un proveedor externo.")

    components.setdefault("securitySchemes", {})["RefreshCookie"] = {
        "type": "apiKey", "in": "cookie", "name": "snackup_refresh",
        "description": "Cookie HttpOnly del navegador. Se requiere Origin autorizado; clientes nativos envían refreshToken en JSON."}
    for path in ("/api/v1/auth/refresh", "/api/v1/auth/logout"):
        operation = document["paths"][path]["post"]
        operation["security"] = [{"RefreshCookie": []}, {}]
        operation["description"] = (operation.get("description", "") + "\n\n"
            "Navegador: cookie HttpOnly y Origin autorizado, cuerpo {}. Nativo: refreshToken en JSON sin Origin. "
            "La alternativa sin security scheme representa el token del cuerpo, no una renovación anónima.").strip()
        if path.endswith("logout"):
            operation["security"].append({"BearerAuth": []})
            operation["description"] += " Logout también acepta Bearer y es idempotente si no queda sesión."
    login = document["paths"]["/api/v1/auth/login"]["post"]
    login["description"] = (login.get("description", "") + "\n\n"
        "Con Origin autorizado, refreshToken solo se entrega como cookie HttpOnly y se omite del JSON. "
        "Sin Origin, el cliente nativo recibe refreshToken en tokens.").strip()

    # Make the role-filtered shape explicit without changing Pydantic's output.
    if "OrderResponse" in schemas:
        schemas["OrderResponse"]["description"] = (
            "ALUMNO dueño: incluye userId, customerNumeroDeControl y pickupCode. COCINA del local: "
            "omite por completo esos tres campos, también en historial y respuestas de transiciones. ADMIN no accede a pedidos.")
        schemas["OrderResponse"]["x-role-visibility"] = {
            "ALUMNO_owner_only": ["userId", "customerNumeroDeControl", "pickupCode"],
            "COCINA_omitted": ["userId", "customerNumeroDeControl", "pickupCode"], "ADMIN": "forbidden"}
    document["x-socketio"] = {
        "path": "/socket.io", "transports": ["websocket"],
        "authentication": {"location": "auth.token", "queryCredentialsAllowed": False,
                           "handshakeTimeoutSeconds": 10, "reauthentication": "REST refresh, then reconnect"},
        "subscribe": {"event": "subscribe", "payload": {"topics": ["business:{id}:products"]},
                      "acknowledgment": {"ok": True, "topics": ["business:{id}:products"]}},
        "unsubscribe": {"event": "unsubscribe", "payload": {"topics": ["business:{id}:products"]}},
        "topics": {"business:{id}": "Authenticated catalog; COCINA is restricted to its assigned business",
                   "business:{id}:products": "Authenticated catalog; COCINA is restricted to its assigned business",
                   "business:{id}:orders": "COCINA of this business only (alias room_business_{id})",
                   "user:{id}:orders": "ALUMNO whose JWT sub is id only (alias room_user_{id})"},
        "events": ["business.updated", "product.updated", "order.created", "order.updated"],
        "envelopeFields": ["id", "type", "topic", "occurredAt", "data"],
        "privateFieldsOmitted": ["pickupCode", "numeroDeControl", "customerNumeroDeControl", "refreshToken"],
        "clientReconciliation": "GET after subscribe ACK and reconnect; no periodic HTTP fallback or replay guarantee",
        "deduplication": ["id", "data.version"],
    }
    return document


def install_openapi(app):
    original = app.openapi

    def canonical_openapi():
        if app.openapi_schema is not None:
            return app.openapi_schema
        try:
            app.openapi_schema = enrich_openapi(original())
        except Exception:
            app.openapi_schema = None
            raise
        return app.openapi_schema

    app.openapi = canonical_openapi
