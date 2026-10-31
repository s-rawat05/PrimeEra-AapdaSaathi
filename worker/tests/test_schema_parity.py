"""The ORM (used by the API) and supabase/migrations (the production schema) must not drift.

Runs only when TEST_DATABASE_URL points at a Postgres database with the migrations applied.
"""

from __future__ import annotations

import os

import pytest
from sqlalchemy import text

from app import models  # noqa: F401
from app.db import Base, db

pytestmark = pytest.mark.skipif(
    not (os.environ.get("TEST_DATABASE_URL") or "").startswith("postgresql"),
    reason="needs TEST_DATABASE_URL (Postgres + migrations)",
)


async def test_every_orm_column_exists_in_migrations(env):
    async with db.session() as s:
        rows = (
            await s.execute(
                text("select table_name, column_name, is_nullable from information_schema.columns "
                     "where table_schema = 'public'")
            )
        ).all()
    pg = {(t, c): n for t, c, n in rows}
    missing, nullability = [], []
    for table in Base.metadata.sorted_tables:
        for col in table.columns:
            key = (table.name, col.name)
            if key not in pg:
                missing.append(key)
            elif not col.nullable and not col.primary_key and pg[key] == "YES":
                nullability.append(key)
    assert not missing, f"columns in ORM but not in migrations: {missing}"
    assert not nullability, f"NOT NULL in ORM but nullable in migrations: {nullability}"


async def test_postgis_generated_geometry_and_rls(env):
    async with db.session() as s:
        geom_type = await s.scalar(text("select geometrytype(geom) from wards where code = 'DW-01'"))
        inside = await s.scalar(
            text("select st_contains(geom, st_setsrid(st_makepoint(79.56, 29.35), 4326)) from wards where code='DW-01'")
        )
        rls_off = (
            await s.execute(
                text("select relname from pg_class c join pg_namespace n on n.oid = c.relnamespace "
                     "where n.nspname = 'public' and c.relkind = 'r' and not c.relrowsecurity "
                     "and relname not in ('schema_migrations', 'spatial_ref_sys')")
            )
        ).scalars().all()
    assert geom_type == "POLYGON" and inside is True
    assert rls_off == [], f"tables without RLS: {rls_off}"


async def test_rls_blocks_anonymous_and_scopes_residents(env):
    async with db.engine.connect() as conn:
        trans = await conn.begin()
        await conn.execute(text("set local role anon"))
        assert (await conn.execute(text("select count(*) from residents"))).scalar() == 0
        assert (await conn.execute(text("select count(*) from resident_locations"))).scalar() == 0
        await trans.rollback()


async def test_audit_log_is_append_only(env):
    async with db.engine.connect() as conn:
        trans = await conn.begin()
        await conn.execute(text(
            "insert into audit_log(id, action, entity_type, created_at) values "
            "('00000000-0000-4000-8000-0000000000aa', 't', 'test', now())"))
        with pytest.raises(Exception, match="append-only"):
            await conn.execute(text("delete from audit_log where id = '00000000-0000-4000-8000-0000000000aa'"))
        await trans.rollback()
