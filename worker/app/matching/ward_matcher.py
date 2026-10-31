"""Match CAP areas to wards.

1. Geometry (precise): CAP polygons/circles intersect ward boundaries.
   Postgres → PostGIS ST_Intersects / ST_DWithin; SQLite → Shapely (same semantics).
2. LGD district code (coarse): every ward in the district. Labelled as NOT a precise match.
Never claims more precision than the source geometry supports.
"""

from __future__ import annotations

import json
from dataclasses import dataclass

from shapely.geometry import Point, Polygon, shape
from sqlalchemy import select, text
from sqlalchemy.ext.asyncio import AsyncSession

from app.db import db
from app.models import Ward


@dataclass(frozen=True)
class WardMatch:
    ward: Ward
    method: str  # geometry | lgd_code | manual
    note: str


async def _geometry_matches_postgres(
    session: AsyncSession, polygons: list, circles: list, ward_filter_demo: bool | None
) -> set[str]:
    ids: set[str] = set()
    demo_clause = "" if ward_filter_demo is None else " AND is_demo = :demo"
    for ring in polygons:
        gj = json.dumps({"type": "Polygon", "coordinates": [ring]})
        rows = await session.execute(
            text(
                "SELECT id FROM wards WHERE ST_Intersects(geom, ST_SetSRID(ST_GeomFromGeoJSON(:g), 4326))" + demo_clause
            ),
            {"g": gj, "demo": ward_filter_demo},
        )
        ids.update(r[0] for r in rows)
    for c in circles:
        rows = await session.execute(
            text(
                "SELECT id FROM wards WHERE ST_DWithin(geom::geography, "
                "ST_SetSRID(ST_MakePoint(:lng, :lat), 4326)::geography, :m)" + demo_clause
            ),
            {"lng": c["lng"], "lat": c["lat"], "m": c["radius_km"] * 1000.0, "demo": ward_filter_demo},
        )
        ids.update(r[0] for r in rows)
    return ids


def _geometry_matches_shapely(wards: list[Ward], polygons: list, circles: list) -> set[str]:
    ids: set[str] = set()
    shapes = [Polygon(ring) for ring in polygons]
    # Circle → buffer in degrees (≈111 km per degree). Approximation is adequate for ward-scale matching.
    shapes += [Point(c["lng"], c["lat"]).buffer(c["radius_km"] / 111.0) for c in circles]
    for w in wards:
        geom = shape(w.boundary_geojson)
        if any(geom.intersects(s) for s in shapes):
            ids.add(w.id)
    return ids


async def match_wards(
    session: AsyncSession,
    *,
    polygons: list,
    circles: list,
    lgd_codes: set[str],
    is_demo: bool | None = False,
) -> list[WardMatch]:
    q = select(Ward)
    if is_demo is not None:
        q = q.where(Ward.is_demo.is_(is_demo))
    wards = list((await session.execute(q)).scalars().all())
    by_id = {w.id: w for w in wards}

    if polygons or circles:
        if db.is_postgres:
            ids = await _geometry_matches_postgres(session, polygons, circles, is_demo)
        else:
            ids = _geometry_matches_shapely(wards, polygons, circles)
        matches = [
            WardMatch(by_id[i], "geometry", "Official alert area intersects ward boundary") for i in ids if i in by_id
        ]
        if matches:
            return matches

    if lgd_codes:
        return [
            WardMatch(
                w,
                "lgd_code",
                f"District-level match (LGD district code {w.lgd_district_code}). The official alert gives no "
                "polygon, so every ward in the district is included — this is not a precise geographic match.",
            )
            for w in wards
            if w.lgd_district_code and w.lgd_district_code in lgd_codes
        ]
    return []
