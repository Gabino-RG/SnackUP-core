"""Keep the delivered Prisma reference complete without a Node runtime in CI."""
from pathlib import Path
import re

import pytest
from sqlalchemy import CheckConstraint

from tools.export_prisma_reference import MODELS, metadata, render_schema

pytestmark = pytest.mark.v3
SCHEMA = Path(__file__).parents[1] / "schema.prisma"


def parsed_models():
    content = SCHEMA.read_text(encoding="utf-8")
    models = {}
    for name, body in re.findall(r"^model (\w+) \{\n(.*?)^\}", content, re.MULTILINE | re.DOTALL):
        table = re.search(r'@@map\("([^"]+)"\)', body).group(1)
        fields = {}
        for line in body.splitlines():
            field = re.match(r'  (\w+) (\w+\??) .*?@map\("([^"]+)"\)', line)
            if field:
                fields[field[3]] = {"name": field[1], "type": field[2], "line": line}
        models[table] = {"name": name, "body": body, "fields": fields}
    return content, models


def test_checked_in_prisma_reference_matches_the_authoritative_metadata():
    assert SCHEMA.read_text(encoding="utf-8") == render_schema(), (
        "El ORM cambió: ejecuta python tools/export_prisma_reference.py y revisa el mapa."
    )


def test_every_sql_table_column_foreign_key_and_check_is_represented():
    _, models = parsed_models()
    tables = metadata().tables
    assert set(models) == set(tables) == set(MODELS)
    assert sum(len(model["fields"]) for model in models.values()) == sum(len(table.c) for table in tables.values())
    for table in tables.values():
        model = models[table.name]
        assert model["name"] == MODELS[table.name]
        assert set(model["fields"]) == {column.name for column in table.c}
        for column in table.c:
            assert model["fields"][column.name]["type"].endswith("?") == column.nullable
        for fk in table.foreign_key_constraints:
            relation = table.name + "_" + "_".join(column.name for column in fk.columns)
            assert model["body"].count('@relation("' + relation + '"') >= 1
            target_body = models[fk.elements[0].column.table.name]["body"]
            assert target_body.count('@relation("' + relation + '"') >= 1
            # Only the referencing side declares fields/references; self-relations
            # still need an inverse field with the exact same relation identity.
            assert ('@relation("' + relation + '", fields: [') in model["body"]
            assert ('@relation("' + relation + '")') in target_body
        for constraint in table.constraints:
            if isinstance(constraint, CheckConstraint):
                assert " ".join(str(constraint.sqltext).split()) in model["body"]


def test_reference_preserves_partial_uniqueness_snapshots_and_python_defaults():
    content, models = parsed_models()
    assert not re.search(r"^enum ", content, re.MULTILINE)
    assert models["users"]["fields"]["role"]["type"] == "String"
    assert "@unique" not in models["users"]["fields"]["business_id"]["line"]
    assert "@unique" not in models["orders"]["fields"]["pickup_code"]["line"]
    assert "@unique" not in models["idempotency_records"]["fields"]["order_id"]["line"]
    assert "uq_active_business_operator (business_id) WHERE role = 'business' AND is_active = true AND approval_status = 'approved'" in content
    assert "uq_orders_v3_pickup_code (pickup_code) WHERE length(pickup_code) = 6" in content
    for table, fields in {
        "products": ("stock", "manual_available", "is_deleted"),
        "orders": ("stock_restored", "customer_name", "customer_institutional_id", "cancelled_by", "verified_by"),
        "order_items": ("reserved_quantity", "name", "price"),
    }.items():
        assert set(fields) <= set(models[table]["fields"])
    assert models["reviews"]["fields"]["rating"]["type"] == "Int?"
    assert models["product_reviews"]["fields"]["rating"]["type"] == "Int"
    assert models["orders"]["fields"]["subtotal"]["type"] == "Decimal?"
    assert models["media_files"]["fields"]["owner_id"]["type"] == "String?"
    assert "@db.Text" in models["users"]["fields"]["id"]["line"]
    assert "@db.VarChar(32)" in models["outbox_events"]["fields"]["event_id"]["line"]
    assert "@default(autoincrement())" in models["outbox_events"]["fields"]["id"]["line"]
    assert "@db.Json" in models["outbox_events"]["fields"]["data"]["line"]
    assert "@db.JsonB" not in content and "@updatedAt" not in content and "@default(now())" not in content
    for model in models.values():
        assert not {"averageRating", "totalRatings", "totalOrders", "isRated", "fueCalificado"} & {
            field["name"] for field in model["fields"].values()
        }
