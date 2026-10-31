from __future__ import annotations

from sqlalchemy import select

from app.db import db
from app.models import Delivery, NotificationAttempt, Resident, Task

API = "/api/v1"


async def simulate(env, onset: int, fixture: str = "demo_flash_flood_alert", ward_ids=None) -> dict:
    op = await env.login("Arjun Mehta")
    body = {"fixture": fixture, "onset_in_minutes": onset}
    if ward_ids:
        body["ward_ids"] = ward_ids
    r = await env.client.post(f"{API}/demo/simulate", json=body, headers=op)
    assert r.status_code == 201, r.text
    return r.json()


async def delivery_of(incident_id: str, resident_name: str) -> Delivery:
    async with db.session() as s:
        return await s.scalar(
            select(Delivery)
            .join(Resident, Resident.id == Delivery.resident_id)
            .where(Delivery.incident_id == incident_id, Resident.full_name == resident_name)
        )


async def tasks_of(delivery_id: str) -> list[Task]:
    async with db.session() as s:
        return list(
            (await s.execute(select(Task).where(Task.delivery_id == delivery_id).order_by(Task.created_at)))
            .scalars()
            .all()
        )


async def attempts_of(delivery_id: str) -> list[NotificationAttempt]:
    async with db.session() as s:
        return list(
            (await s.execute(select(NotificationAttempt).where(NotificationAttempt.delivery_id == delivery_id)))
            .scalars()
            .all()
        )


async def all_open_tasks_by_delivery(incident_id: str) -> dict[str, list[Task]]:
    async with db.session() as s:
        rows = (
            (
                await s.execute(
                    select(Task).where(
                        Task.incident_id == incident_id, Task.status.in_(("PENDING_APPROVAL", "ASSIGNED", "ACCEPTED"))
                    )
                )
            )
            .scalars()
            .all()
        )
    out: dict[str, list[Task]] = {}
    for t in rows:
        out.setdefault(t.delivery_id, []).append(t)
    return out
