"""Shared queries. `lock=True` takes a row lock on Postgres (SELECT … FOR UPDATE); on SQLite the
whole transaction already holds the write lock (BEGIN IMMEDIATE), giving the same guarantee."""

from __future__ import annotations

from dataclasses import dataclass

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core import NotFound
from app.models import (
    OPEN_TASK_STATUSES,
    CaregiverLink,
    Delivery,
    Incident,
    NeighbourLink,
    Resident,
    ResidentLocation,
    Task,
    User,
    Ward,
)


@dataclass
class DeliveryCtx:
    delivery: Delivery
    incident: Incident
    resident: Resident


async def get_delivery_ctx(session: AsyncSession, delivery_id: str, lock: bool = True) -> DeliveryCtx:
    q = select(Delivery).where(Delivery.id == delivery_id)
    if lock:
        # populate_existing: if this session already loaded the row, overwrite it with the locked,
        # current version — otherwise decisions would be made on stale status (lost-update race).
        q = q.with_for_update().execution_options(populate_existing=True)
    d = (await session.execute(q)).scalar_one_or_none()
    if d is None:
        raise NotFound("Delivery")
    inc = await session.get(Incident, d.incident_id, populate_existing=lock)
    res = await session.get(Resident, d.resident_id)
    return DeliveryCtx(d, inc, res)


async def get_task(session: AsyncSession, task_id: str, lock: bool = True) -> Task:
    q = select(Task).where(Task.id == task_id)
    if lock:
        q = q.with_for_update().execution_options(populate_existing=True)
    t = (await session.execute(q)).scalar_one_or_none()
    if t is None:
        raise NotFound("Task")
    return t


async def open_tasks(session: AsyncSession, delivery_id: str, kind: str | None = None) -> list[Task]:
    q = select(Task).where(Task.delivery_id == delivery_id, Task.status.in_(OPEN_TASK_STATUSES))
    if kind:
        q = q.where(Task.kind == kind)
    return list((await session.execute(q)).scalars().all())


async def caregivers_of(session: AsyncSession, resident_id: str) -> list[User]:
    q = (
        select(User)
        .join(CaregiverLink, CaregiverLink.caregiver_user_id == User.id)
        .where(CaregiverLink.resident_id == resident_id, User.is_active.is_(True))
    )
    return list((await session.execute(q)).scalars().all())


async def neighbours_of(session: AsyncSession, resident_id: str) -> list[tuple[NeighbourLink, User]]:
    q = (
        select(NeighbourLink, User)
        .join(User, User.id == NeighbourLink.neighbour_user_id)
        .where(NeighbourLink.resident_id == resident_id, User.is_active.is_(True))
        .order_by(NeighbourLink.priority)
    )
    return [(link, user) for link, user in (await session.execute(q)).all()]


async def resident_point(session: AsyncSession, resident: Resident) -> tuple[float, float, str]:
    """Best-known location for dispatch maths: exact → coarse → ward centroid (with provenance)."""
    loc = await session.scalar(select(ResidentLocation).where(ResidentLocation.resident_id == resident.id))
    if loc is not None:
        return loc.lat, loc.lng, "registered location"
    if resident.coarse_lat is not None and resident.coarse_lng is not None:
        return resident.coarse_lat, resident.coarse_lng, "approximate (coarse) location"
    ward = await session.get(Ward, resident.ward_id)
    return ward.centroid_lat, ward.centroid_lng, "ward centroid (no registered location)"
