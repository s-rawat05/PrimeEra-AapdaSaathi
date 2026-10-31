"""Database engine/session management for PostgreSQL (Supabase) and SQLite (local demo/tests).

Business logic never branches on the dialect except where noted (spatial queries, row locks).
"""

from __future__ import annotations

import os
import uuid
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
from datetime import UTC, datetime

from sqlalchemy import DateTime, event
from sqlalchemy.ext.asyncio import AsyncEngine, AsyncSession, async_sessionmaker, create_async_engine
from sqlalchemy.orm import DeclarativeBase
from sqlalchemy.types import TypeDecorator


def utcnow() -> datetime:
    return datetime.now(UTC)


def new_id() -> str:
    return str(uuid.uuid4())


class UTCDateTime(TypeDecorator):
    """Always stores UTC and always returns timezone-aware UTC datetimes (SQLite drops tzinfo)."""

    impl = DateTime(timezone=True)
    cache_ok = True

    def process_bind_param(self, value, dialect):
        if value is None:
            return None
        if value.tzinfo is None:
            raise ValueError("Naive datetimes are not allowed; use timezone-aware UTC")
        value = value.astimezone(UTC)
        return value.replace(tzinfo=None) if dialect.name == "sqlite" else value

    def process_result_value(self, value, dialect):
        if value is None:
            return None
        if value.tzinfo is None:
            return value.replace(tzinfo=UTC)
        return value.astimezone(UTC)


class Base(DeclarativeBase):
    pass


class Database:
    def __init__(self) -> None:
        self.engine: AsyncEngine | None = None
        self.sessionmaker: async_sessionmaker[AsyncSession] | None = None
        self.url: str = ""

    @property
    def is_sqlite(self) -> bool:
        return self.url.startswith("sqlite")

    @property
    def is_postgres(self) -> bool:
        return self.url.startswith("postgresql")

    def init(self, url: str) -> None:
        self.url = url
        if url.startswith("sqlite"):
            path = url.split("///", 1)[-1]
            if path and path != ":memory:":
                os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
            engine = create_async_engine(url, connect_args={"timeout": 30})

            @event.listens_for(engine.sync_engine, "connect")
            def _sqlite_connect(dbapi_conn, _record):  # pragma: no cover - driver hook
                # Hand transaction control to SQLAlchemy so we can issue BEGIN IMMEDIATE,
                # which serialises writers and gives the same safety as row locks.
                dbapi_conn.isolation_level = None
                cur = dbapi_conn.cursor()
                cur.execute("PRAGMA foreign_keys=ON")
                cur.execute("PRAGMA journal_mode=WAL")
                cur.execute("PRAGMA busy_timeout=30000")
                cur.close()

            @event.listens_for(engine.sync_engine, "begin")
            def _sqlite_begin(conn):  # pragma: no cover - driver hook
                conn.exec_driver_sql("BEGIN IMMEDIATE")

        else:
            engine = create_async_engine(url, pool_pre_ping=True, pool_size=10, max_overflow=10)
        self.engine = engine
        self.sessionmaker = async_sessionmaker(engine, expire_on_commit=False)

    async def create_all(self) -> None:
        """Create tables from ORM metadata. Used for SQLite only; Postgres uses supabase/migrations."""
        assert self.engine is not None
        from app import models  # noqa: F401 - register models

        async with self.engine.begin() as conn:
            await conn.run_sync(Base.metadata.create_all)

    async def dispose(self) -> None:
        if self.engine is not None:
            await self.engine.dispose()

    @asynccontextmanager
    async def session(self) -> AsyncIterator[AsyncSession]:
        assert self.sessionmaker is not None, "Database not initialised"
        async with self.sessionmaker() as s:
            yield s


db = Database()


async def get_session() -> AsyncIterator[AsyncSession]:
    async with db.session() as s:
        yield s
