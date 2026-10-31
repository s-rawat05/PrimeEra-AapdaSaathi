"""Apply supabase/migrations/*.sql to a PostgreSQL database, in order, exactly once each.

Usage (from the repo root, using the worker virtualenv):
  worker/.venv/Scripts/python scripts/apply_migrations.py postgresql://postgres:pw@localhost:5432/aapda
  ... --local-shim   also apply supabase/local/*.sql first (vanilla Postgres without Supabase auth)
  ... --seed         also apply supabase/seed.sql afterwards

For Supabase itself prefer the CLI:  supabase link && supabase db push
"""

from __future__ import annotations

import argparse
import asyncio
import sys
from pathlib import Path

import asyncpg

ROOT = Path(__file__).resolve().parents[1]


async def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("url")
    ap.add_argument("--local-shim", action="store_true")
    ap.add_argument("--seed", action="store_true")
    args = ap.parse_args()
    url = args.url.replace("postgresql+asyncpg://", "postgresql://")
    conn = await asyncpg.connect(url)
    try:
        await conn.execute(
            "create table if not exists schema_migrations (version text primary key, applied_at timestamptz "
            "not null default now())"
        )
        files: list[Path] = []
        if args.local_shim:
            files += sorted((ROOT / "supabase" / "local").glob("*.sql"))
        files += sorted((ROOT / "supabase" / "migrations").glob("*.sql"))
        applied = {r["version"] for r in await conn.fetch("select version from schema_migrations")}
        for f in files:
            version = f.name
            if version in applied:
                print(f"skip   {version}")
                continue
            async with conn.transaction():
                await conn.execute(f.read_text(encoding="utf-8"))
                await conn.execute("insert into schema_migrations(version) values ($1)", version)
            print(f"apply  {version}")
        if args.seed:
            await conn.execute((ROOT / "supabase" / "seed.sql").read_text(encoding="utf-8"))
            print("seed   supabase/seed.sql")
    finally:
        await conn.close()
    return 0


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
