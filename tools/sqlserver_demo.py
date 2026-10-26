"""SQL Server adaptation of the pinned backend's schema, for the local demo only."""
import json
from pathlib import Path

from sqlalchemy import CheckConstraint, Index, Text, Unicode, UniqueConstraint, create_engine, text
from sqlalchemy.dialects.mssql import NVARCHAR
from sqlalchemy.engine import URL
from sqlalchemy.ext.compiler import compiles
from sqlalchemy.sql import operators
from sqlalchemy.sql.elements import BinaryExpression, False_, True_
from sqlalchemy.sql.functions import Function
from sqlalchemy.sql.selectable import Join, Select


@compiles(BinaryExpression, 'mssql')
def sqlserver_boolean_comparison(expression, compiler, **kwargs):
    # SQL Server BIT supports = 1/0, not PostgreSQL-style IS TRUE/FALSE.
    if expression.operator in (operators.is_, operators.is_not) and isinstance(expression.right, (True_, False_)):
        operation = ' = ' if expression.operator is operators.is_ else ' <> '
        value = '1' if isinstance(expression.right, True_) else '0'
        return compiler.process(expression.left, **kwargs) + operation + value
    return compiler.visit_binary(expression, **kwargs)


@compiles(Function, 'mssql')
def sqlserver_average(function, compiler, **kwargs):
    # AVG(integer) truncates fractions on SQL Server; star averages need them.
    if function.name.lower() == 'avg':
        return 'AVG(CAST(' + compiler.process(function.clauses, **kwargs) + ' AS FLOAT))'
    return compiler.visit_function(function, **kwargs)


@compiles(Select, 'mssql')
def sqlserver_row_locks(statement, compiler, **kwargs):
    # SQL Server uses table hints rather than SELECT ... FOR UPDATE. Preserve
    # the backend's write locks for inventory, sessions and order transitions.
    if statement._for_update_arg is not None:
        def tables(source):
            if isinstance(source, Join):
                yield from tables(source.left)
                yield from tables(source.right)
            else:
                yield source
        for source in statement.get_final_froms():
            for table in tables(source):
                statement = statement.with_hint(table, 'WITH (UPDLOCK, ROWLOCK)', dialect_name='mssql')
    return compiler.visit_select(statement, **kwargs)


def connection_url(server, database):
    return URL.create('mssql+pyodbc', host=server, database=database,
                      query={'driver': 'ODBC Driver 17 for SQL Server',
                             'Trusted_Connection': 'yes', 'TrustServerCertificate': 'yes'})


def adapt_schema(metadata):
    """Keep ORM mappings and API contracts; use SQL Server-compatible DDL."""
    if metadata.info.get('snackup_mssql'):
        return
    metadata.info['snackup_mssql'] = True
    for table in metadata.tables.values():
        indexed = {c.name for index in table.indexes for c in index.columns}
        indexed.update(c.name for constraint in table.constraints
                       if isinstance(constraint, UniqueConstraint) for c in constraint.columns)
        for column in table.columns:
            if isinstance(column.type, Text):
                column.type = Unicode(128) if column.primary_key or column.foreign_keys or column.name in indexed else NVARCHAR(None)
            elif getattr(column.type, 'length', None):
                column.type = Unicode(column.type.length)
        for constraint in list(table.constraints):
            if isinstance(constraint, CheckConstraint):
                sql = str(constraint.sqltext).replace('NOT is_master', 'is_master = 0').replace('NOT is_available', 'is_available = 0')
                constraint.sqltext = text(sql)
            # SQL Server rejects RESTRICT and multiple cascading paths. Keep
            # referential integrity with NO ACTION; no hard-delete demo flow.
            if getattr(constraint, 'elements', None):
                constraint.ondelete = 'NO ACTION'
                for foreign in constraint.elements:
                    foreign.ondelete = 'NO ACTION'
            if isinstance(constraint, UniqueConstraint) and any(c.nullable for c in constraint.columns):
                table.constraints.remove(constraint)
                columns = list(constraint.columns)
                Index(constraint.name or 'uq_' + table.name + '_' + '_'.join(c.name for c in columns),
                      *columns, unique=True,
                      mssql_where=text(' AND '.join('[' + c.name + '] IS NOT NULL' for c in columns if c.nullable)))
        for index in table.indexes:
            if index.name == 'uq_active_business_operator':
                index.dialect_options['mssql']['where'] = text("role = 'business' AND is_active = 1 AND approval_status = 'approved' AND business_id IS NOT NULL")
            elif index.name == 'uq_orders_v3_pickup_code':
                # All new demo codes must be unique, including the six-digit
                # codes. No historical eight-digit fixtures are imported.
                index.dialect_options['mssql']['where'] = text('pickup_code IS NOT NULL')


def prepare_database(private, metadata):
    configuration = json.loads((private / 'database.json').read_text(encoding='utf-8-sig'))
    server = configuration['server']
    name = configuration.get('database', 'SnackUP_Local')
    if name != 'SnackUP_Local':
        raise ValueError('This demo may only create/use SnackUP_Local.')
    engine = create_engine(connection_url(server, 'master'), isolation_level='AUTOCOMMIT', connect_args={'timeout': 8})
    try:
        with engine.connect() as connection:
            if not connection.scalar(text("SELECT DB_ID(N'SnackUP_Local')")):
                connection.execute(text('CREATE DATABASE [SnackUP_Local]'))
    finally:
        engine.dispose()
    adapt_schema(metadata)
    url = connection_url(server, name)
    return url.render_as_string(hide_password=False)


def export_schema(metadata, path):
    """Export reproducible T-SQL, including keys, checks and filtered indexes."""
    from sqlalchemy import create_mock_engine
    statements = []
    def emit(statement, *args, **kwargs):
        sql = str(statement.compile(dialect=engine.dialect)).strip()
        statements.append('\n'.join(line.rstrip() for line in sql.splitlines()) + ';\nGO')
    engine = create_mock_engine('mssql+pyodbc://', emit)
    metadata.create_all(engine, checkfirst=False)
    Path(path).write_text('-- SQL Server schema for a NEW, empty SnackUP_Local database.\n'
                          '-- Generated from the pinned API models by tools/sqlserver_demo.py.\n'
                          "USE [master];\nGO\nIF DB_ID(N'SnackUP_Local') IS NULL CREATE DATABASE [SnackUP_Local];\nGO\n"
                          'USE [SnackUP_Local];\nGO\nSET ANSI_NULLS ON;\nSET QUOTED_IDENTIFIER ON;\nGO\n\n'
                          + '\n\n'.join(statements) + '\n', encoding='utf-8')
