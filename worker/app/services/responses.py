"""Safe / Help responses from every channel. One code path (`apply_status`) changes delivery status.

Concurrency: callers load the delivery with a row lock, so a SAFE reply and a due escalation
timer can never both act on stale state — the escalation engine re-checks status under the lock.
"""

from __future__ import annotations

from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.audit.log import timeline
from app.core import Actor, AppContext, Conflict, DomainError, Forbidden
from app.escalation.engine import interval_for
from app.integrations.sms_gateway import CANNOT_REACH, HELP, SAFE, normalize_phone, parse_sms_reply
from app.models import CaregiverLink, Delivery, Incident, Resident, SmsInbound, Task, User
from app.notifications import dispatcher, templates
from app.repositories.queries import DeliveryCtx, caregivers_of, get_delivery_ctx, get_task
from app.services.realtime import emit

CHANNEL_LABEL = {
    "app": "the app",
    "sms": "SMS",
    "caregiver": "caregiver",
    "neighbour": "neighbour check",
    "volunteer": "volunteer on site",
    "operator": "operator override",
}


async def apply_status(
    session: AsyncSession,
    ctx: AppContext,
    dc: DeliveryCtx,
    new_status: str,
    *,
    channel: str,
    actor: Actor,
    note: str | None = None,
) -> bool:
    """Apply SAFE or HELP. Returns False when it is a no-op (duplicate)."""
    from app.dispatch import service as dispatch

    d, inc, res = dc.delivery, dc.incident, dc.resident
    if inc.status != "active":
        raise Conflict("incident_closed", "This alert is no longer active")
    if new_status not in (SAFE, HELP):
        raise DomainError("invalid_status", "status must be SAFE or HELP", 422)
    if d.status == new_status:
        return False
    now = ctx.now()
    old = d.status
    first_reply = d.replied_at is None and channel in ("app", "sms", "caregiver")
    if first_reply:
        d.replied_at, d.reply_channel = now, channel

    if new_status == SAFE:
        d.status = SAFE
        d.resolved_at, d.resolved_by = now, channel
        d.next_action_at = None
        d.needs_operator = d.needs_rescue = False
        d.rescue_reason = None
        d.escalation_step = "resolved"
        d.version += 1
        timeline(
            session,
            inc.id,
            "safe",
            f"Confirmed SAFE via {CHANNEL_LABEL.get(channel, channel)}" + (f" ({note})" if note else ""),
            actor=actor,
            delivery_id=d.id,
            resident_id=res.id,
            at=now,
            data={"from": old, "channel": channel},
        )
        await dispatch.cancel_open_tasks(session, ctx, dc, reason="resident confirmed safe", actor=actor)
    else:
        d.status = HELP
        d.help_requested_at = now
        d.resolved_at = d.resolved_by = None
        d.needs_operator = True
        d.escalation_step = "help_dispatch"
        d.next_action_at = now + interval_for(ctx, inc, res)
        d.version += 1
        timeline(
            session,
            inc.id,
            "help",
            f"HELP requested via {CHANNEL_LABEL.get(channel, channel)}" + (f" ({note})" if note else ""),
            actor=actor,
            delivery_id=d.id,
            resident_id=res.id,
            at=now,
            data={"from": old, "channel": channel},
        )
        await session.flush()
        if channel != "neighbour":
            await dispatch.request_neighbour_check(
                session,
                ctx,
                dc,
                reason=f"Resident requested help via {CHANNEL_LABEL.get(channel, channel)}",
                actor=Actor.system("help-workflow"),
            )
        await dispatch.request_volunteer(
            session,
            ctx,
            dc,
            reason=f"HELP via {CHANNEL_LABEL.get(channel, channel)}",
            actor=Actor.system("help-workflow"),
            kind="volunteer_assist",
        )
        for cg in await caregivers_of(session, res.id):
            await dispatcher.notify_user(
                session,
                ctx,
                inc,
                cg,
                recipient_kind="caregiver",
                key=f"d:{d.id}:help:{d.version}:cg:{cg.id}",
                title="AapdaSaathi: help requested",
                body=f"{res.full_name.split(' ')[0]} needs help ({inc.hazard_type}). The control room is notified.",
                sms_body=f"AapdaSaathi: {res.full_name.split(' ')[0]} requested HELP. Control room notified.",
                data={"type": "caregiver", "delivery_id": d.id},
                delivery_id=d.id,
            )
    caregiver_ids = [c.id for c in await caregivers_of(session, res.id)]
    emit(
        session,
        "delivery.updated",
        audience=[res.user_id, *caregiver_ids],
        incident_id=inc.id,
        delivery_id=d.id,
        status=d.status,
    )
    return True


async def respond_as_resident(
    session: AsyncSession, ctx: AppContext, delivery_id: str, status: str, actor: Actor
) -> tuple[Delivery, bool]:
    """Returns (delivery, changed). `changed` is decided under the row lock."""
    dc = await get_delivery_ctx(session, delivery_id)
    if dc.resident.user_id != actor.user_id:
        raise Forbidden("This alert does not belong to you")
    changed = await apply_status(session, ctx, dc, status, channel="app", actor=actor)
    return dc.delivery, changed


async def respond_as_caregiver(
    session: AsyncSession, ctx: AppContext, delivery_id: str, status: str, note: str | None, actor: Actor
) -> Delivery:
    dc = await get_delivery_ctx(session, delivery_id)
    link = await session.scalar(
        select(CaregiverLink).where(
            CaregiverLink.resident_id == dc.resident.id, CaregiverLink.caregiver_user_id == actor.user_id
        )
    )
    if link is None:
        raise Forbidden("You are not a linked caregiver for this resident")
    await apply_status(session, ctx, dc, status, channel="caregiver", actor=actor, note=note)
    return dc.delivery


async def respond_neighbour_check(
    session: AsyncSession, ctx: AppContext, task_id: str, outcome: str, actor: Actor, note: str | None = None
) -> Task:
    from app.dispatch import service as dispatch

    if outcome not in (SAFE, HELP, CANNOT_REACH):
        raise DomainError("invalid_outcome", "outcome must be SAFE, HELP or CANNOT_REACH", 422)
    task = await get_task(session, task_id)
    if task.kind != "neighbour_check":
        raise DomainError("wrong_task", "Not a neighbour check", 422)
    if actor.role not in ("admin", "operator") and task.assignee_user_id != actor.user_id:
        raise Forbidden("This check is not assigned to you")
    if task.status == "COMPLETED" and task.outcome == outcome.lower():
        return task
    if task.status not in ("ASSIGNED", "ACCEPTED"):
        raise Conflict("task_closed", f"This check is already {task.status.lower()}")
    now = ctx.now()
    task.status, task.outcome, task.outcome_note, task.closed_at = "COMPLETED", outcome.lower(), note, now
    task.version += 1
    dc = await get_delivery_ctx(session, task.delivery_id)
    emit(session, "task.updated", audience=[task.assignee_user_id], incident_id=task.incident_id, task_id=task.id)
    if outcome == SAFE:
        await apply_status(session, ctx, dc, SAFE, channel="neighbour", actor=actor, note=note)
    elif outcome == HELP:
        await apply_status(session, ctx, dc, HELP, channel="neighbour", actor=actor, note=note)
    else:
        d = dc.delivery
        timeline(
            session,
            dc.incident.id,
            "neighbour_cannot_reach",
            "Neighbour could not reach the resident" + (f" ({note})" if note else ""),
            actor=actor,
            delivery_id=d.id,
            resident_id=d.resident_id,
            at=now,
        )
        d.escalation_level = max(d.escalation_level, 2)
        d.escalation_step = "volunteer"
        d.next_action_at = now + interval_for(ctx, dc.incident, dc.resident)
        d.version += 1
        await session.flush()
        if d.status != SAFE:
            await dispatch.request_volunteer(
                session, ctx, dc, reason="Neighbour could not reach the resident", actor=Actor.system("escalation")
            )
        emit(session, "delivery.updated", incident_id=dc.incident.id, delivery_id=d.id, status=d.status)
    return task


async def process_inbound_sms(
    session: AsyncSession,
    ctx: AppContext,
    *,
    provider_message_id: str,
    from_phone: str,
    body: str,
    simulated: bool,
) -> dict:
    """Associate an SMS reply with exactly one open context, or reject it safely."""
    try:
        phone = normalize_phone(from_phone)
    except ValueError:
        return {"result": "invalid_phone"}
    record = SmsInbound(
        provider_message_id=provider_message_id,
        from_phone=phone,
        body=body[:500],
        result="processing",
        is_simulated=simulated,
        received_at=ctx.now(),
    )
    try:
        async with session.begin_nested():
            session.add(record)
    except IntegrityError:
        return {"result": "duplicate", "detail": "This message was already processed"}

    action = parse_sms_reply(body)
    record.parsed_action = action

    neighbour_tasks = (
        await session.execute(
            select(Task, User, Incident)
            .join(User, User.id == Task.assignee_user_id)
            .join(Incident, Incident.id == Task.incident_id)
            .where(
                User.phone == phone,
                Task.kind == "neighbour_check",
                Task.status.in_(("ASSIGNED", "ACCEPTED")),
                Incident.status == "active",
            )
        )
    ).all()
    resident_rows = (
        await session.execute(
            select(Delivery, Resident, Incident)
            .join(Resident, Resident.id == Delivery.resident_id)
            .join(Incident, Incident.id == Delivery.incident_id)
            .where(Resident.phone == phone, Incident.status == "active")
        )
    ).all()
    # A later HELP must reach a resident who earlier said SAFE; a SAFE only matters if not yet safe.
    open_resident = [r for r in resident_rows if action == HELP or r[0].status != SAFE]

    async def ack(incident: Incident, is_demo: bool, lang: str, text: str, kind: str, user_id: str | None):
        await dispatcher.queue(
            session,
            ctx,
            incident=incident,
            channel="sms",
            recipient_kind=kind,
            recipient_is_demo=is_demo,
            key=f"sms-ack:{record.id}",
            body=text,
            phone=phone,
            recipient_user_id=user_id,
            round_="ack",
        )

    def finish(result: str, **extra) -> dict:
        record.result = result
        return {"result": result, "action": action, **extra}

    any_incident = (neighbour_tasks[0][2] if neighbour_tasks else None) or (
        resident_rows[0][2] if resident_rows else None
    )
    any_lang = (
        neighbour_tasks[0][1].language if neighbour_tasks else (resident_rows[0][1].language if resident_rows else "en")
    )
    any_demo = (
        neighbour_tasks[0][1].is_demo if neighbour_tasks else (resident_rows[0][1].is_demo if resident_rows else False)
    )

    if action is None:
        if any_incident:
            await ack(
                any_incident,
                any_demo,
                any_lang,
                templates.reply_reject_sms(any_lang, "not understood"),
                "resident",
                None,
            )
        return finish("unrecognised")

    if action == CANNOT_REACH:
        if len(neighbour_tasks) != 1:
            if any_incident:
                await ack(
                    any_incident,
                    any_demo,
                    any_lang,
                    templates.reply_reject_sms(any_lang, "no single pending neighbour check"),
                    "neighbour",
                    None,
                )
            return finish("rejected_no_context" if not neighbour_tasks else "rejected_ambiguous")
        task, user, inc = neighbour_tasks[0]
        await respond_neighbour_check(session, ctx, task.id, CANNOT_REACH, Actor("sms", user.id, "neighbour", "SMS"))
        record.task_id = task.id
        await ack(
            inc, user.is_demo, user.language, templates.reply_ack_sms(user.language, CANNOT_REACH), "neighbour", user.id
        )
        return finish("applied", task_id=task.id)

    if neighbour_tasks and open_resident:
        await ack(
            any_incident,
            any_demo,
            any_lang,
            templates.reply_reject_sms(any_lang, "ambiguous — use the app"),
            "resident",
            None,
        )
        return finish("rejected_ambiguous")
    if len(neighbour_tasks) > 1 or len(open_resident) > 1:
        await ack(
            any_incident,
            any_demo,
            any_lang,
            templates.reply_reject_sms(any_lang, "ambiguous — use the app"),
            "resident",
            None,
        )
        return finish("rejected_ambiguous")
    if len(neighbour_tasks) == 1:
        task, user, inc = neighbour_tasks[0]
        await respond_neighbour_check(session, ctx, task.id, action, Actor("sms", user.id, "neighbour", "SMS"))
        record.task_id = task.id
        await ack(
            inc, user.is_demo, user.language, templates.reply_ack_sms(user.language, action), "neighbour", user.id
        )
        return finish("applied", task_id=task.id)
    if open_resident:
        delivery, resident, inc = open_resident[0]
        dc = await get_delivery_ctx(session, delivery.id)
        await apply_status(
            session, ctx, dc, action, channel="sms", actor=Actor("sms", resident.user_id, "resident", "SMS")
        )
        record.delivery_id = delivery.id
        await ack(
            inc,
            resident.is_demo,
            resident.language,
            templates.reply_ack_sms(resident.language, action),
            "resident",
            resident.user_id,
        )
        return finish("applied", delivery_id=delivery.id)
    if resident_rows and action == SAFE:
        record.delivery_id = resident_rows[0][0].id
        return finish("already_safe")
    stale = await session.scalar(
        select(Delivery.id).join(Resident, Resident.id == Delivery.resident_id).where(Resident.phone == phone).limit(1)
    )
    return finish("rejected_stale" if stale else "rejected_unknown_sender")
