"""Time-aware escalation engine.

All state lives in `deliveries` (escalation_level, next_action_at, version). The worker loop picks
due rows with `FOR UPDATE SKIP LOCKED` (Postgres) / a serialised write transaction (SQLite),
RE-CHECKS status under the lock, performs exactly one step and moves `next_action_at` forward.
That makes every step idempotent, safe with several workers, and recoverable after a restart:
overdue rows are simply picked up on the next tick.

Ladder for NO_REPLY / UNREACHABLE (Mode A and B):
  level 0 → reminder + neighbour check      (no neighbour → straight to volunteer)
  level 1 → volunteer escalation
  level 2 → command centre involvement      (needs_operator)
  level 3 → repeated reminders for elderly-alone residents, otherwise wait for operator
Mode C/D perform the neighbour + helper steps in PARALLEL at alert time (see activate_delivery).
"""

from __future__ import annotations

import logging
import socket
from datetime import timedelta

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.audit.log import timeline
from app.core import SYSTEM, Actor, AppContext
from app.db import db
from app.escalation import rules
from app.models import Delivery, Incident, Resident, WorkerHeartbeat
from app.notifications import dispatcher
from app.notifications.templates import accessibility_modes
from app.repositories.queries import DeliveryCtx, caregivers_of, get_delivery_ctx, open_tasks
from app.services.realtime import commit, emit

log = logging.getLogger(__name__)
MAX_REPEAT_REMINDERS = 5
WORKER_ID = f"{socket.gethostname()}"
STEP_NAMES = {0: "alerted", 1: "neighbour_check", 2: "volunteer", 3: "command_centre"}


def interval_for(ctx: AppContext, incident: Incident, resident: Resident) -> timedelta:
    if incident.interval_override_seconds:
        seconds = float(incident.interval_override_seconds)
        if "elderly_alone" in (resident.needs or []):
            seconds = max(seconds / 2, 10.0)
        return timedelta(seconds=seconds)
    return rules.escalation_interval(incident.onset, ctx.now(), resident.needs)


async def _notify_caregivers(session: AsyncSession, ctx: AppContext, dc: DeliveryCtx) -> None:
    d, inc, res = dc.delivery, dc.incident, dc.resident
    for cg in await caregivers_of(session, res.id):
        if cg.is_demo != inc.is_demo:
            continue
        await dispatcher.notify_user(
            session,
            ctx,
            inc,
            cg,
            recipient_kind="caregiver",
            key=f"d:{d.id}:caregiver:{cg.id}",
            title=f"AapdaSaathi: {inc.hazard_type} alert for {res.full_name.split(' ')[0]}",
            body=f"{res.full_name.split(' ')[0]} has been alerted. Please help them respond or confirm they are safe.",
            sms_body=f"AapdaSaathi: {inc.hazard_type} alert for {res.full_name.split(' ')[0]}. Please check on them.",
            data={"type": "caregiver", "delivery_id": d.id},
            delivery_id=d.id,
        )
    if await caregivers_of(session, res.id):
        timeline(
            session,
            inc.id,
            "caregiver_alerted",
            "Caregiver alerted in parallel",
            actor=SYSTEM,
            delivery_id=d.id,
            resident_id=res.id,
            at=ctx.now(),
        )


async def activate_delivery(session: AsyncSession, ctx: AppContext, dc: DeliveryCtx) -> None:
    """Initial alert + mode-specific parallel actions for a freshly created delivery."""
    from app.dispatch import service as dispatch

    d, inc, res = dc.delivery, dc.incident, dc.resident
    now = ctx.now()
    d.accessibility_modes = accessibility_modes(res.needs or [])
    attempts = await dispatcher.alert_resident(session, ctx, inc, d, res, "initial")
    d.alerted_at = now
    d.status = "NO_REPLY" if attempts else "UNREACHABLE"
    mode = inc.escalation_mode
    d.next_action_at = now + interval_for(ctx, inc, res)
    channels = ", ".join(d.channels) or "none"
    timeline(
        session,
        inc.id,
        "alerted",
        f"Alert sent via {channels}" + ("" if attempts else " — no registered channel, marked UNREACHABLE"),
        actor=SYSTEM,
        delivery_id=d.id,
        resident_id=res.id,
        at=now,
        data={"channels": d.channels, "modes": d.accessibility_modes},
    )
    await session.flush()

    if rules.caregiver_in_parallel(res.needs or [], mode):
        await _notify_caregivers(session, ctx, dc)
    if mode in ("C", "D"):
        await dispatch.request_neighbour_check(
            session, ctx, dc, reason=f"Mode {mode}: parallel neighbour check at alert time", actor=SYSTEM
        )
        if rules.needs_assisted_evacuation(res.needs or []):
            await dispatch.request_volunteer(
                session,
                ctx,
                dc,
                reason=f"Mode {mode}: minute-zero alert to pre-assigned helper",
                actor=SYSTEM,
                pre_assigned_only=True,
            )
        d.escalation_level = 1
        d.escalation_step = "parallel"
    elif mode == "A" and rules.needs_assisted_evacuation(res.needs or []):
        await dispatch.request_volunteer(
            session,
            ctx,
            dc,
            reason="Mode A: arrange assisted evacuation before onset",
            actor=SYSTEM,
            kind="preevac_assist",
        )
    d.version += 1
    emit(session, "delivery.updated", audience=[res.user_id], incident_id=inc.id, delivery_id=d.id, status=d.status)


async def _maybe_update_mode(session: AsyncSession, ctx: AppContext, inc: Incident) -> None:
    mode_now = rules.select_mode(inc.onset, ctx.now())
    if mode_now != inc.escalation_mode:
        old = inc.escalation_mode
        inc.escalation_mode = mode_now
        inc.requires_dispatch_approval = inc.requires_dispatch_approval or rules.requires_dispatch_approval(
            inc.severity, mode_now
        )
        timeline(
            session,
            inc.id,
            "mode_changed",
            f"Escalation mode {old} → {mode_now} ({rules.mode_label(mode_now)}) as onset approaches",
            actor=SYSTEM,
            at=ctx.now(),
        )
        emit(session, "incident.updated", incident_id=inc.id)


async def _expire_unaccepted(session: AsyncSession, ctx: AppContext, dc: DeliveryCtx, interval: timedelta) -> None:
    """A volunteer who neither accepts nor declines within 2 intervals is replaced."""
    from app.dispatch import service as dispatch

    now = ctx.now()
    for t in await open_tasks(session, dc.delivery.id):
        if t.kind == "neighbour_check" or t.status != "ASSIGNED":
            continue
        started = t.approved_at or t.created_at
        if started + 2 * interval <= now:
            t.status, t.outcome, t.closed_at = "CANCELLED", "timeout", now
            t.outcome_note = f"No response within {int((2 * interval).total_seconds() // 60) or 1} min"
            t.version += 1
            timeline(
                session,
                t.incident_id,
                "task_timeout",
                f"Volunteer did not respond — reassigning ({t.outcome_note})",
                actor=SYSTEM,
                delivery_id=t.delivery_id,
                resident_id=t.resident_id,
                at=now,
            )
            emit(session, "task.updated", audience=[t.assignee_user_id], incident_id=t.incident_id, task_id=t.id)
            await session.flush()
            await dispatch.request_volunteer(
                session, ctx, dc, reason="Previous volunteer did not respond", actor=SYSTEM, kind=t.kind
            )


async def advance(session: AsyncSession, ctx: AppContext, dc: DeliveryCtx) -> str:
    """Perform one escalation step for a due delivery. Caller holds the row lock."""
    from app.dispatch import service as dispatch

    d, inc, res = dc.delivery, dc.incident, dc.resident
    now = ctx.now()
    if inc.status != "active" or d.status == "SAFE":
        d.next_action_at = None
        return "resolved"
    if d.next_action_at is None or d.next_action_at > now:
        return "not_due"  # someone else already handled it

    await _maybe_update_mode(session, ctx, inc)
    interval = interval_for(ctx, inc, res)
    await _expire_unaccepted(session, ctx, dc, interval)

    if d.status == "HELP":
        vol_tasks = [t for t in await open_tasks(session, d.id) if t.kind != "neighbour_check"]
        if not vol_tasks and not d.needs_rescue:
            await dispatch.request_volunteer(session, ctx, dc, reason="Help still unassigned", actor=SYSTEM)
            vol_tasks = [t for t in await open_tasks(session, d.id) if t.kind != "neighbour_check"]
        accepted = any(t.status == "ACCEPTED" for t in vol_tasks)
        if not accepted and not d.needs_operator:
            d.needs_operator = True
            timeline(
                session,
                inc.id,
                "escalated_command_centre",
                "Help request not yet accepted by a helper",
                actor=SYSTEM,
                delivery_id=d.id,
                resident_id=res.id,
                at=now,
            )
        d.next_action_at = None if accepted or d.needs_rescue else now + interval
        d.version += 1
        emit(session, "delivery.updated", incident_id=inc.id, delivery_id=d.id, status=d.status)
        return "help_followup"

    level = d.escalation_level
    result = ""
    if level == 0:
        await dispatcher.alert_resident(session, ctx, inc, d, res, f"reminder-{d.reminders_sent + 1}")
        d.reminders_sent += 1
        task = await dispatch.request_neighbour_check(
            session,
            ctx,
            dc,
            reason=f"No reply {int((now - d.alerted_at).total_seconds() // 60)} min after alert",
            actor=SYSTEM,
        )
        if task is None:
            timeline(
                session,
                inc.id,
                "no_neighbour",
                "No linked neighbour available — escalating to volunteer",
                actor=SYSTEM,
                delivery_id=d.id,
                resident_id=res.id,
                at=now,
            )
            await dispatch.request_volunteer(
                session, ctx, dc, reason="No reply and no neighbour available", actor=SYSTEM
            )
            d.escalation_level = 2
        else:
            d.escalation_level = 1
        result = "neighbour"
    elif level == 1:
        await dispatch.request_volunteer(session, ctx, dc, reason="No reply; neighbour check unresolved", actor=SYSTEM)
        d.escalation_level = 2
        result = "volunteer"
    elif level == 2:
        d.needs_operator = True
        d.escalation_level = 3
        timeline(
            session,
            inc.id,
            "escalated_command_centre",
            f"Still {d.status.replace('_', ' ').lower()} — command centre must act",
            actor=SYSTEM,
            delivery_id=d.id,
            resident_id=res.id,
            at=now,
        )
        result = "command_centre"
    else:
        await dispatcher.alert_resident(session, ctx, inc, d, res, f"reminder-{d.reminders_sent + 1}")
        d.reminders_sent += 1
        timeline(
            session,
            inc.id,
            "reminder",
            f"Repeat reminder #{d.reminders_sent} (elderly, lives alone)",
            actor=SYSTEM,
            delivery_id=d.id,
            resident_id=res.id,
            at=now,
        )
        result = "reminder"

    repeat = "repeat_reminders" in (d.accessibility_modes or []) and d.reminders_sent < MAX_REPEAT_REMINDERS
    d.next_action_at = None if d.escalation_level >= 3 and not repeat else now + interval
    d.escalation_step = STEP_NAMES.get(min(d.escalation_level, 3), "command_centre")
    d.version += 1
    emit(session, "delivery.updated", audience=[res.user_id], incident_id=inc.id, delivery_id=d.id, status=d.status)
    return result


_DUE_STATUSES = ("NO_REPLY", "UNREACHABLE", "HELP", "PENDING", "SAFE")


async def _due_snapshot(ctx: AppContext, limit: int) -> list[str]:
    """Due delivery ids ordered by priority (highest first), so scarce helpers go to those most at risk.
    Read without locks; each row is locked and re-checked individually before acting."""
    now = ctx.now()
    async with db.session() as session:
        rows = (
            await session.execute(
                select(Delivery.id, Delivery.status, Delivery.alerted_at, Resident.needs, Resident.lives_alone)
                .join(Incident, Incident.id == Delivery.incident_id)
                .join(Resident, Resident.id == Delivery.resident_id)
                .where(
                    Delivery.next_action_at.is_not(None),
                    Delivery.next_action_at <= now,
                    Delivery.status.in_(_DUE_STATUSES),
                    Incident.status == "active",
                )
                .order_by(Delivery.next_action_at)
                .limit(limit)
            )
        ).all()
    scored = [
        (
            -rules.priority_score(
                needs=needs or [], lives_alone=alone, status=status, alerted_at=alerted, now=now
            ).total,
            i,
            did,
        )
        for i, (did, status, alerted, needs, alone) in enumerate(rows)
    ]
    return [did for _, _, did in sorted(scored)]


async def _lock_if_due(session: AsyncSession, delivery_id: str, now) -> bool:
    q = select(Delivery.id).where(
        Delivery.id == delivery_id,
        Delivery.next_action_at.is_not(None),
        Delivery.next_action_at <= now,
        Delivery.status.in_(_DUE_STATUSES),
    )
    if db.is_postgres:
        q = q.with_for_update(skip_locked=True)  # another worker holds it → skip, it is being handled
    return (await session.execute(q)).scalar_one_or_none() is not None


async def tick(ctx: AppContext, max_steps: int = 500) -> int:
    """Process every due delivery once, highest priority first, one short transaction each."""
    steps = 0
    for delivery_id in await _due_snapshot(ctx, max_steps):
        async with db.session() as session:
            try:
                if not await _lock_if_due(session, delivery_id, ctx.now()):
                    await session.rollback()
                    continue
                dc = await get_delivery_ctx(session, delivery_id, lock=True)
                if await advance(session, ctx, dc) != "not_due":
                    steps += 1
                await commit(session, ctx.bus)
            except Exception:  # noqa: BLE001 - one bad row must not stall the engine
                log.exception("escalation step failed for delivery %s", delivery_id)
                await session.rollback()
                await _defer(ctx, delivery_id)
    await _heartbeat(ctx, f"steps={steps}")
    if steps:
        await dispatcher.flush_outbox(ctx)
    return steps


async def _defer(ctx: AppContext, delivery_id: str) -> None:
    async with db.session() as session:
        d = await session.get(Delivery, delivery_id)
        if d is not None and d.next_action_at is not None:
            d.next_action_at = ctx.now() + timedelta(seconds=60)
            timeline(
                session,
                d.incident_id,
                "escalation_error",
                "Escalation step failed; retrying in 60 s (see worker logs)",
                actor=SYSTEM,
                delivery_id=d.id,
                resident_id=d.resident_id,
                at=ctx.now(),
            )
        await session.commit()


async def _heartbeat(ctx: AppContext, result: str) -> None:
    async with db.session() as session:
        hb = await session.get(WorkerHeartbeat, f"{WORKER_ID}:escalation")
        if hb is None:
            session.add(
                WorkerHeartbeat(
                    worker_id=f"{WORKER_ID}:escalation", job="escalation", last_beat_at=ctx.now(), last_result=result
                )
            )
        else:
            hb.last_beat_at, hb.last_result = ctx.now(), result
        await session.commit()


async def run_step_for(ctx: AppContext, delivery_id: str, actor: Actor = SYSTEM) -> str:
    """Testing/ops helper: advance a single delivery if due."""
    async with db.session() as session:
        dc = await get_delivery_ctx(session, delivery_id, lock=True)
        r = await advance(session, ctx, dc)
        await commit(session, ctx.bus)
        return r
