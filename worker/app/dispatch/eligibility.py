"""Volunteer eligibility: pure, deterministic travel-time safety checks.

Walking time is an ESTIMATE: great-circle distance × hill-terrain factor ÷ walking speed.
No routing or hazard data is used, so routes are never presented as hazard-validated.
"""

from __future__ import annotations

import math
from dataclasses import dataclass
from datetime import datetime


def haversine_m(lat1: float, lng1: float, lat2: float, lng2: float) -> float:
    r = 6_371_000.0
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dp = p2 - p1
    dl = math.radians(lng2 - lng1)
    a = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * r * math.asin(math.sqrt(a))


def estimate_walk_minutes(distance_m: float, speed_m_per_min: float, hill_factor: float) -> float:
    return round(distance_m * hill_factor / speed_m_per_min, 1)


@dataclass(frozen=True)
class DispatchParams:
    walking_speed_m_per_min: float
    hill_terrain_factor: float
    assist_buffer_minutes: float
    max_walk_minutes_active_hazard: float


@dataclass(frozen=True)
class Candidate:
    volunteer_id: str
    user_id: str
    name: str
    lat: float
    lng: float
    max_radius_m: float
    is_available: bool
    busy: bool
    declined_this_case: bool
    pre_assigned_priority: int | None = None


@dataclass(frozen=True)
class Evaluation:
    candidate: Candidate
    eligible: bool
    distance_m: float
    walk_minutes: float
    reason: str


def evaluate(
    c: Candidate,
    *,
    resident_lat: float,
    resident_lng: float,
    onset: datetime,
    now: datetime,
    ward_access: str,
    params: DispatchParams,
) -> Evaluation:
    dist = haversine_m(c.lat, c.lng, resident_lat, resident_lng)
    walk = estimate_walk_minutes(dist, params.walking_speed_m_per_min, params.hill_terrain_factor)

    def no(reason: str) -> Evaluation:
        return Evaluation(c, False, dist, walk, reason)

    if not c.is_available:
        return no("Marked unavailable")
    if c.busy:
        return no("Already on an active task")
    if c.declined_this_case:
        return no("Already declined this case")
    if ward_access == "blocked":
        return no("Ward access marked BLOCKED by operator — no automatic dispatch")
    if dist > c.max_radius_m:
        return no(f"Outside service radius ({dist:.0f} m > {c.max_radius_m:.0f} m)")
    remaining = (onset - now).total_seconds() / 60.0
    if remaining <= 0:
        if walk > params.max_walk_minutes_active_hazard:
            return no(
                f"Hazard ongoing: est. walk {walk:.0f} min exceeds the "
                f"{params.max_walk_minutes_active_hazard:.0f} min limit for active hazards"
            )
        return Evaluation(c, True, dist, walk, f"Hazard ongoing; est. walk {walk:.0f} min (needs approval)")
    needed = walk + params.assist_buffer_minutes
    if needed > remaining:
        return no(
            f"Cannot arrive safely in time: est. walk {walk:.0f} min + {params.assist_buffer_minutes:.0f} min "
            f"assist buffer > {remaining:.0f} min before onset"
        )
    return Evaluation(c, True, dist, walk, f"Est. walk {walk:.0f} min; {remaining:.0f} min before onset")


def rank(evals: list[Evaluation]) -> list[Evaluation]:
    """Eligible first; pre-assigned helpers before others; then shortest estimated walk."""

    def key(e: Evaluation):
        pre = e.candidate.pre_assigned_priority
        return (not e.eligible, pre is None, pre or 0, e.walk_minutes)

    return sorted(evals, key=key)
