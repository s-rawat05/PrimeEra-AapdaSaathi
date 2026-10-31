"""Demo/drill operations: simulate a saved CAP fixture, replay a real SACHET message into the
fictional demo ward, and reset demo state without touching real operational data."""

from __future__ import annotations

from sqlalchemy import delete, func, select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.audit.log import audit
from app.core import Actor, AppContext, DomainError, NotFound
from app.demo.seed import FIXTURES_DIR
from app.integrations.cap_parser import CapParseError
from app.models import CapMessage, DemoSession, Incident, SmsInbound, Volunteer, Ward
from app.services import incidents


def list_fixtures() -> list[str]:
    return sorted(p.stem for p in (FIXTURES_DIR / "cap").glob("*.xml") if not p.stem.startswith("sachet_rss"))


async def _demo_ward_ids(session: AsyncSession, requested: list[str] | None) -> list[str]:
    if requested:
        rows = (await session.execute(select(Ward).where(Ward.id.in_(requested)))).scalars().all()
        if len(rows) != len(set(requested)) or any(not w.is_demo for w in rows):
            raise DomainError("demo_wards_only", "Drills may only target demo wards", 422)
        return [w.id for w in rows]
    ward = await session.scalar(select(Ward).where(Ward.is_demo.is_(True)).order_by(Ward.code).limit(1))
    if ward is None:
        raise DomainError("no_demo_ward", "No demo ward is seeded. Run the demo seed first.", 409)
    return [ward.id]


async def _new_session(session: AsyncSession, actor: Actor, scenario: str) -> DemoSession:
    ds = DemoSession(started_by_user_id=actor.user_id, scenario=scenario)
    session.add(ds)
    await session.flush()
    return ds


async def simulate(
    session: AsyncSession, ctx: AppContext, fixture: str, onset_in_minutes: int, ward_ids: list[str] | None,
    actor: Actor,
) -> Incident:
    if fixture not in list_fixtures():
        raise NotFound("Fixture")
    xml = (FIXTURES_DIR / "cap" / f"{fixture}.xml").read_text(encoding="utf-8")
    try:
        row, _, _ = await incidents.store_cap_message(
            session, xml, feed_url=None, feed_guid=None, official_url=None, is_fixture=True, now=ctx.now())
    except CapParseError as exc:
        raise DomainError("invalid_fixture", str(exc), 422) from exc
    ward_ids = await _demo_ward_ids(session, ward_ids)
    ds = await _new_session(session, actor, f"simulate:{fixture}")
    inc = await incidents.replay_into_demo(session, ctx, row, ward_ids=ward_ids, onset_in_minutes=onset_in_minutes,
                                           source="simulated", actor=actor, demo_session_id=ds.id)
    audit(session, actor, "demo.simulate", "incident", inc.id, after={"fixture": fixture})
    return inc


async def replay(
    session: AsyncSession, ctx: AppContext, cap_message_id: str, onset_in_minutes: int, ward_ids: list[str] | None,
    actor: Actor,
) -> Incident:
    row = await session.get(CapMessage, cap_message_id)
    if row is None:
        raise NotFound("CAP message")
    ward_ids = await _demo_ward_ids(session, ward_ids)
    ds = await _new_session(session, actor, f"replay:{row.identifier}")
    inc = await incidents.replay_into_demo(session, ctx, row, ward_ids=ward_ids, onset_in_minutes=onset_in_minutes,
                                           source="replay", actor=actor, demo_session_id=ds.id)
    audit(session, actor, "demo.replay", "incident", inc.id, after={"cap_identifier": row.identifier})
    return inc


async def reset(session: AsyncSession, ctx: AppContext, actor: Actor) -> dict:
    """Delete demo incidents (cascades to deliveries, tasks, timeline, notifications) and simulated SMS.
    Every statement is filtered on is_demo / is_simulated, and we verify real data is unchanged."""
    real_before = await session.scalar(select(func.count()).select_from(Incident).where(Incident.is_demo.is_(False)))
    n_inc = (await session.execute(delete(Incident).where(Incident.is_demo.is_(True)))).rowcount
    n_sms = (await session.execute(delete(SmsInbound).where(SmsInbound.is_simulated.is_(True)))).rowcount
    n_vol = (await session.execute(
        update(Volunteer).where(Volunteer.is_demo.is_(True)).values(is_available=True))).rowcount
    await session.execute(
        update(Ward).where(Ward.is_demo.is_(True)).values(access_status="open", access_note=None))
    await session.execute(update(DemoSession).where(DemoSession.reset_at.is_(None)).values(reset_at=ctx.now()))
    real_after = await session.scalar(select(func.count()).select_from(Incident).where(Incident.is_demo.is_(False)))
    if real_after != real_before:
        raise RuntimeError("Demo reset would modify real incidents — aborted")
    audit(session, actor, "demo.reset", "demo", None, after={"incidents": n_inc, "sms": n_sms})
    return {"incidents_removed": n_inc or 0, "sms_removed": n_sms or 0, "volunteers_reset": n_vol or 0,
            "real_data_untouched": True}
