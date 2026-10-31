"""Test fixtures: every test gets an isolated SQLite database (or TEST_DATABASE_URL Postgres),
fictional seed data, a frozen clock and an in-process ASGI client. No network, no real SMS."""

from __future__ import annotations

import os
from dataclasses import dataclass
from datetime import UTC, datetime
from pathlib import Path

import httpx
import pytest
import pytest_asyncio
from sqlalchemy import text

from app.config import Settings
from app.core import AppContext, FrozenClock
from app.db import db
from app.main import build_context, create_app, init_storage

FIXTURES = Path(__file__).resolve().parents[2] / "fixtures"
START = datetime(2026, 7, 14, 10, 30, tzinfo=UTC)


@dataclass
class Env:
    ctx: AppContext
    clock: FrozenClock
    client: httpx.AsyncClient
    settings: Settings

    async def login(self, name_part: str) -> dict:
        personas = (await self.client.get("/api/v1/auth/demo-personas")).json()
        match = [p for p in personas if name_part.lower() in p["full_name"].lower()]
        assert match, f"no persona matching {name_part}"
        r = await self.client.post("/api/v1/auth/demo-login", json={"user_id": match[0]["user_id"]})
        assert r.status_code == 200, r.text
        return {"Authorization": f"Bearer {r.json()['access_token']}"}


def make_settings(tmp_path: Path, **overrides) -> Settings:
    url = os.environ.get("TEST_DATABASE_URL") or f"sqlite+aiosqlite:///{tmp_path.as_posix()}/test.db"
    base = dict(
        database_url=url,
        run_background_jobs=False,
        demo_mode_enabled=True,
        feed_poll_enabled=False,
        demo_escalation_interval_seconds=30,
        rate_limit_per_minute=100000,
        sms_provider="simulator",
        notify_real_residents=False,
        jwt_secret="test-secret-" + "x" * 40,
    )
    base.update(overrides)
    return Settings(**base)


async def _reset_postgres() -> None:
    async with db.engine.begin() as conn:
        await conn.execute(
            text(
                "DO $$ DECLARE r record; BEGIN FOR r IN SELECT tablename FROM pg_tables WHERE schemaname='public' "
                "AND tablename NOT IN ('spatial_ref_sys') LOOP EXECUTE 'TRUNCATE TABLE ' || quote_ident(r.tablename) "
                "|| ' CASCADE'; END LOOP; END $$;"
            )
        )


@pytest_asyncio.fixture
async def env(tmp_path) -> Env:
    settings = make_settings(tmp_path)
    clock = FrozenClock(START)
    ctx = build_context(settings, clock)
    if settings.database_url.startswith("postgresql"):
        db.init(settings.database_url)
        await _reset_postgres()
        await db.dispose()
    await init_storage(settings, ctx)
    app = create_app(settings, ctx, manage_db=False)
    async with httpx.AsyncClient(transport=httpx.ASGITransport(app=app), base_url="http://test") as client:
        yield Env(ctx, clock, client, settings)
    await db.dispose()


@pytest.fixture
def cap_xml():
    def load(name: str) -> str:
        return (FIXTURES / "cap" / f"{name}.xml").read_text(encoding="utf-8")

    return load
