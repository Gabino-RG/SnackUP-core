"""Offline SQL Server portability checks; these do not replace live SQL tests."""
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / '.local/snackup-demo/source/backend'))
from sqlalchemy import func, select
from sqlalchemy.dialects import mssql
from sqlalchemy.schema import CreateTable, CreateIndex
from snackup import identity_models, operation_models, admin_models, push_models, review_models
from snackup.db import Base
from sqlserver_demo import adapt_schema, export_schema

adapt_schema(Base.metadata)
dialect = mssql.dialect()

class PortabilityTests(unittest.TestCase):
    def test_bit_conditions_and_nulls(self):
        user = identity_models.User
        query = select(user.id).where(user.is_active.is_(True), user.is_master.is_(False), user.business_id.is_(None))
        sql = str(query.compile(dialect=dialect))
        self.assertIn('users.is_active = 1', sql)
        self.assertIn('users.is_master = 0', sql)
        self.assertIn('users.business_id IS NULL', sql)

    def test_inventory_write_locks(self):
        product = operation_models.Product
        sql = str(select(product).with_for_update().compile(dialect=dialect))
        self.assertIn('WITH (UPDLOCK, ROWLOCK)', sql)

    def test_fractional_star_averages(self):
        sql = str(select(func.avg(review_models.ProductReview.rating)).compile(dialect=dialect))
        self.assertIn('AVG(CAST(', sql)
        self.assertIn('AS FLOAT)', sql)

    def test_all_tables_compile_with_valid_keys(self):
        self.assertEqual(len(Base.metadata.tables), 23)
        for table in Base.metadata.tables.values():
            sql = str(CreateTable(table).compile(dialect=dialect))
            self.assertNotIn('ON DELETE RESTRICT', sql)
            self.assertNotIn('NOT is_master', sql)
            self.assertNotIn('NOT is_available', sql)
            self.assertNotIn('NTEXT', sql)
            for column in table.primary_key:
                if column.type.python_type is str:
                    self.assertLessEqual(column.type.length, 128)

    def test_nullable_unique_values_are_filtered(self):
        user = Base.metadata.tables['users']
        index = next(i for i in user.indexes if any(c.name == 'numero_de_control' for c in i.columns))
        self.assertIn('[numero_de_control] IS NOT NULL', str(CreateIndex(index).compile(dialect=dialect)))
        operator = next(i for i in user.indexes if i.name == 'uq_active_business_operator')
        self.assertIn("role = 'business'", str(CreateIndex(operator).compile(dialect=dialect)))

if __name__ == '__main__':
    unittest.main()
