from logging.config import fileConfig
from pathlib import Path

from alembic import context
from sqlalchemy import create_engine, pool

from snackup.config import Settings
from snackup.db import Base
from snackup import admin_models, identity_models, operation_models  # noqa: F401

config = context.config
if config.config_file_name:
    fileConfig(config.config_file_name)
url = Settings().database_url
if url.startswith('sqlite:///'):
    Path(url.removeprefix('sqlite:///')).parent.mkdir(parents=True, exist_ok=True)
target_metadata = Base.metadata

if context.is_offline_mode():
    context.configure(url=url, target_metadata=target_metadata, literal_binds=True, dialect_opts={'paramstyle': 'named'})
    with context.begin_transaction():
        context.run_migrations()
else:
    connectable = create_engine(url, poolclass=pool.NullPool)
    with connectable.connect() as connection:
        context.configure(connection=connection, target_metadata=target_metadata, compare_type=True)
        with context.begin_transaction():
            context.run_migrations()
