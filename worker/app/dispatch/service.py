"""Task lifecycle for neighbour checks and volunteer assistance.

Volunteer task: [PENDING_APPROVAL →] ASSIGNED → ACCEPTED → REACHED
                 ASSIGNED/ACCEPTED → CANT_GO (reason required) → automatic reassignment
Neighbour check: ASSIGNED → COMPLETED (outcome SAFE | HELP | CANNOT_REACH)
"""

from __future__ import annotations

from sqlalchemy import func, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.audit.log import audit, timeline
from app.core import Actor, AppContext, Conflict, DomainError, Forbidden, NotFound
from app.dispatch.eligibility import Candidate, DispatchParams, Evaluation, evaluate, rank
from app.models import (
    OPEN_TASK_STATUSES,
    PreAssignedHelper,
    Task,
    User,
    Volunteer,
    Ward,
)
from app.notifications import dispatcher, templates
from app.repositories.queries import DeliveryCtx, get_delivery_ctx, get_task, neighbours_of, open_tasks, resident_point
from app.services.realtime import emit

CANT_GO_REASONS = {
    "route_blocked": "Route blocked",
    "too_far": "Too far",
    "unsafe": "Unsafe conditions",
    "unavailable": "Unavailable",
}
REACHED_OUTCOMES = {
    "resident_safe": "Reached — resident safe",
    "evacuated": "Reached — resident evacuated / supported",
    "needs_rescue": "Reached — needs professional rescue",
    "not_found": "Resident not found at location",
}
VOLUNTEER_KINDS = ("volunteer_assist", "preevac_assist")


def params(ctx: AppContext) -> DispatchParams:
    s = ctx.settings
    return DispatchParams(
        walking_speed_m_per_min=s.walking_speed_m_per_min,
        hill_terrain_factor=s.hill_terrain_factor,
        assist_buffer_minutes=s.assist_buffer_minutes,
        max_walk_minutes_active_hazard=s.max_walk_minutes_active_hazard,
    )


def _first_name(name: str) -> str:
    return (name or "").split(" ")[0]


async def evaluate_candidates(session: AsyncSession, ctx: AppContext, dc: DeliveryCtx) -> list[Evaluation]:
    inc, res, d = dc.incident, dc.resident, dc.delivery
    rows = (
        await session.execute(
            select(Volunteer, User)
            .join(User, User.id == Volunteer.user_id)
            .where(Volunteer.is_demo == inc.is_demo, Volunteer.verified.is_(True), User.is_active.is_(True))
        )
    ).all()
    busy = set(
        (
            await session.execute(
                select(Task.volunteer_id).where(
                    Task.kind.in_(VOLUNTEER_KINDS),
                    Task.status.in_(OPEN_TASK_STATUSES),
                    Task.volunteer_id.is_not(None),
                )
            )
        )
        .scalars()
        .all()
    )
    declined = set(
        (
            await session.execute(
                select(Task.volunteer_id).where(
                    Task.delivery_id == d.id,
                    Task.kind.in_(VOLUNTEER_KINDS),
                    Task.status.in_(("CANT_GO", "REJECTED", "CANCELLED")),
                    Task.outcome.is_distinct_from("stood_down"),
                )
            )
        )
        .scalars()
        .all()
    )
    pre = {
        p.volunteer_id: p.priority
        for p in (await session.execute(select(PreAssignedHelper).where(PreAssignedHelper.resident_id == res.id)))
        .scalars()
        .all()
    }
    lat, lng, _ = await resident_point(session, res)
    ward = await session.get(Ward, res.ward_id)
    evals = [
        evaluate(
            Candidate(
                volunteer_id=v.id,
                user_id=u.id,
                name=u.full_name,
                lat=v.base_lat,
                lng=v.base_lng,
                max_radius_m=v.max_radius_m,
                is_available=v.is_available,
                busy=v.id in busy,
                declined_this_case=v.id in declined,
                pre_assigned_priority=pre.get(v.id),
            ),
            resident_lat=lat,
            resident_lng=lng,
            onset=inc.onset,
            now=ctx.now(),
            ward_access=ward.access_status,
            params=params(ctx),
        )
        for v, u in rows
    ]
    return rank(evals)


async def _notify_volunteer(session: AsyncSession, ctx: AppContext, dc: DeliveryCtx, task: Task) -> None:
    user = await session.get(User, task.assignee_user_id)
    needs = ", ".join(dc.resident.needs) or "no declared needs"
    title = "AapdaSaathi: assistance task"
    body = (
        f"Assist {_first_name(dc.resident.full_name)} ({needs}) — {dc.incident.hazard_type}. "
        f"Est. walk {task.est_walk_minutes:.0f} min (estimate, route not hazard-checked). Open the app to accept."
    )
    sms = f"AapdaSaathi TASK: assist {_first_name(dc.resident.full_name)} ({needs}). Open app to accept/decline."
    await dispatcher.notify_user(
        session,
        ctx,
        dc.incident,
        user,
        recipient_kind="volunteer",
        key=f"t:{task.id}:assigned",
        title=title,
        body=body,
        sms_body=sms,
        data={"type": "task", "task_id": task.id},
        delivery_id=dc.delivery.id,
        task_id=task.id,
    )


async def request_volunteer(
    session: AsyncSession,
    ctx: AppContext,
    dc: DeliveryCtx,
    *,
    reason: str,
    actor: Actor,
    kind: str = "volunteer_assist",
    only_volunteer_id: str | None = None,
    pre_assigned_only: bool = False,
) -> Task | None:
    """Assign the best eligible helper, or flag the case for prioritised rescue with the reason.

    pre_assigned_only: Mode C/D minute-zero alert to the resident's pre-assigned helper. If that
    helper is not eligible nothing is flagged — the normal escalation ladder continues.
    """
    d, inc = dc.delivery, dc.incident
    existing = await open_tasks(session, d.id, kind)
    if existing:
        return existing[0]
    evals = await evaluate_candidates(session, ctx, dc)
    if only_volunteer_id:
        evals = [e for e in evals if e.candidate.volunteer_id == only_volunteer_id]
        if not evals:
            raise NotFound("Volunteer")
    if pre_assigned_only:
        evals = [e for e in evals if e.candidate.pre_assigned_priority is not None]
        if not any(e.eligible for e in evals):
            if evals:
                timeline(
                    session,
                    inc.id,
                    "pre_assigned_unavailable",
                    "Pre-assigned helper cannot go: " + "; ".join(e.reason for e in evals[:2]),
                    actor=actor,
                    delivery_id=d.id,
                    resident_id=d.resident_id,
                    at=ctx.now(),
                )
            return None
    best = next((e for e in evals if e.eligible), None)
    now = ctx.now()
    if best is None:
        details = "; ".join(f"{e.candidate.name}: {e.reason}" for e in evals[:3]) or "no registered volunteers"
        if only_volunteer_id:
            raise Conflict("volunteer_ineligible", f"Volunteer not eligible: {details}")
        d.needs_rescue = True
        d.needs_operator = True
        d.rescue_reason = f"No helper can safely arrive in time — prioritise rescue. ({details})"
        d.version += 1
        timeline(
            session,
            inc.id,
            "dispatch_blocked",
            d.rescue_reason,
            actor=actor,
            delivery_id=d.id,
            resident_id=d.resident_id,
            at=now,
            data={"evaluations": [e.reason for e in evals[:5]]},
        )
        emit(session, "delivery.updated", incident_id=inc.id, delivery_id=d.id, status=d.status)
        return None

    ward = await session.get(Ward, dc.resident.ward_id)
    needs_approval = inc.requires_dispatch_approval or ward.access_status == "restricted"
    attempt_no = (
        await session.scalar(select(func.count()).select_from(Task).where(Task.delivery_id == d.id, Task.kind == kind))
    ) + 1
    task = Task(
        incident_id=inc.id,
        delivery_id=d.id,
        resident_id=d.resident_id,
        kind=kind,
        status="PENDING_APPROVAL" if needs_approval else "ASSIGNED",
        assignee_user_id=best.candidate.user_id,
        volunteer_id=best.candidate.volunteer_id,
        reason=reason,
        distance_m=round(best.distance_m),
        est_walk_minutes=best.walk_minutes,
        attempt_no=attempt_no,
        created_at=now,
    )
    try:
        async with session.begin_nested():
            session.add(task)
    except IntegrityError:
        # Another worker created the open task first — never double-assign.
        return (await open_tasks(session, d.id, kind) or [None])[0]
    msg = (
        f"{'Awaiting operator approval: ' if needs_approval else ''}{best.candidate.name} "
        f"({best.reason}). Reason: {reason}"
    )
    timeline(
        session,
        inc.id,
        "task_created",
        msg,
        actor=actor,
        delivery_id=d.id,
        resident_id=d.resident_id,
        at=now,
        data={"task_id": task.id, "kind": kind, "status": task.status},
    )
    if not needs_approval:
        await _notify_volunteer(session, ctx, dc, task)
    emit(session, "task.updated", audience=[task.assignee_user_id], incident_id=inc.id, task_id=task.id)
    return task


async def request_neighbour_check(
    session: AsyncSession, ctx: AppContext, dc: DeliveryCtx, *, reason: str, actor: Actor
) -> Task | None:
    d, inc, res = dc.delivery, dc.incident, dc.resident
    existing = await open_tasks(session, d.id, "neighbour_check")
    if existing:
        return existing[0]
    tried = set(
        (
            await session.execute(
                select(Task.assignee_user_id).where(Task.delivery_id == d.id, Task.kind == "neighbour_check")
            )
        )
        .scalars()
        .all()
    )
    for link, user in await neighbours_of(session, res.id):
        if user.id in tried or user.is_demo != inc.is_demo:
            continue
        now = ctx.now()
        task = Task(
            incident_id=inc.id,
            delivery_id=d.id,
            resident_id=res.id,
            kind="neighbour_check",
            status="ASSIGNED",
            assignee_user_id=user.id,
            reason=reason,
            distance_m=link.distance_m,
            attempt_no=len(tried) + 1,
            created_at=now,
        )
        try:
            async with session.begin_nested():
                session.add(task)
        except IntegrityError:
            return (await open_tasks(session, d.id, "neighbour_check") or [None])[0]
        lang = user.language if user.language in ("en", "hi") else "en"
        await dispatcher.notify_user(
            session,
            ctx,
            inc,
            user,
            recipient_kind="neighbour",
            key=f"t:{task.id}:assigned",
            title="AapdaSaathi: please check on your neighbour",
            body=f"Please check on {_first_name(res.full_name)} only if it is safe for you. "
            "Then tell us: Safe, Needs help, or Cannot reach.",
            sms_body=templates.neighbour_check_sms(lang, _first_name(res.full_name), inc.hazard_type),
            data={"type": "neighbour_check", "task_id": task.id},
            delivery_id=d.id,
            task_id=task.id,
        )
        timeline(
            session,
            inc.id,
            "neighbour_check",
            f"Neighbour check requested from {user.full_name}. {reason}",
            actor=actor,
            delivery_id=d.id,
            resident_id=res.id,
            at=now,
            data={"task_id": task.id},
        )
        emit(session, "task.updated", audience=[user.id], incident_id=inc.id, task_id=task.id)
        return task
    return None


async def cancel_open_tasks(
    session: AsyncSession,
    ctx: AppContext,
    dc: DeliveryCtx,
    *,
    reason: str,
    actor: Actor,
    kinds: tuple[str, ...] | None = None,
) -> int:
    n = 0
    for t in await open_tasks(session, dc.delivery.id):
        if kinds and t.kind not in kinds:
            continue
        was_engaged = t.status in ("ASSIGNED", "ACCEPTED")
        t.status, t.outcome, t.outcome_note, t.closed_at = "CANCELLED", "stood_down", reason, ctx.now()
        t.version += 1
        n += 1
        if was_engaged and t.assignee_user_id:
            user = await session.get(User, t.assignee_user_id)
            await dispatcher.notify_user(
                session,
                ctx,
                dc.incident,
                user,
                recipient_kind=t.kind.split("_")[0],
                key=f"t:{t.id}:stand_down",
                title="AapdaSaathi: task closed",
                body=f"You can stand down: {reason}.",
                sms_body=f"AapdaSaathi: task closed — {reason}. Thank you.",
                data={"type": "task", "task_id": t.id},
                task_id=t.id,
            )
        emit(session, "task.updated", audience=[t.assignee_user_id], incident_id=t.incident_id, task_id=t.id)
    if n:
        timeline(
            session,
            dc.incident.id,
            "tasks_cancelled",
            f"{n} open task(s) closed: {reason}",
            actor=actor,
            delivery_id=dc.delivery.id,
            resident_id=dc.delivery.resident_id,
            at=ctx.now(),
        )
    return n


def _require_assignee(task: Task, actor: Actor) -> None:
    if actor.role in ("admin", "operator"):
        return
    if task.assignee_user_id != actor.user_id:
        raise Forbidden("This task is not assigned to you")


async def accept(session: AsyncSession, ctx: AppContext, task_id: str, actor: Actor) -> Task:
    task = await get_task(session, task_id)
    _require_assignee(task, actor)
    if task.status == "ACCEPTED":
        return task
    if task.status != "ASSIGNED" or task.kind not in VOLUNTEER_KINDS:
        raise Conflict("invalid_transition", f"Cannot accept a task in status {task.status}")
    dc = await get_delivery_ctx(session, task.delivery_id)
    if dc.incident.status != "active":
        raise Conflict("incident_closed", "Incident is no longer active")
    task.status, task.accepted_at = "ACCEPTED", ctx.now()
    task.version += 1
    user = await session.get(User, task.assignee_user_id)
    timeline(
        session,
        task.incident_id,
        "task_accepted",
        f"{user.full_name} accepted the task",
        actor=actor,
        delivery_id=task.delivery_id,
        resident_id=task.resident_id,
        at=ctx.now(),
    )
    emit(session, "task.updated", audience=[task.assignee_user_id], incident_id=task.incident_id, task_id=task.id)
    return task


async def cant_go(
    session: AsyncSession, ctx: AppContext, task_id: str, reason: str, note: str | None, actor: Actor
) -> tuple[Task, Task | None]:
    if reason not in CANT_GO_REASONS:
        raise DomainError("invalid_reason", f"reason must be one of {sorted(CANT_GO_REASONS)}", 422)
    task = await get_task(session, task_id)
    _require_assignee(task, actor)
    if task.status not in ("ASSIGNED", "ACCEPTED") or task.kind not in VOLUNTEER_KINDS:
        raise Conflict("invalid_transition", f"Cannot decline a task in status {task.status}")
    now = ctx.now()
    task.status, task.cant_go_reason, task.outcome_note, task.closed_at = "CANT_GO", reason, note, now
    task.version += 1
    if reason == "unavailable" and task.volunteer_id:
        vol = await session.get(Volunteer, task.volunteer_id)
        vol.is_available = False
    if reason == "route_blocked":
        dc0 = await get_delivery_ctx(session, task.delivery_id)
        ward = await session.get(Ward, dc0.resident.ward_id)
        ward.access_note = f"Volunteer reported route blocked at {now:%H:%M} UTC" + (f": {note}" if note else "")
    user = await session.get(User, task.assignee_user_id)
    dc = await get_delivery_ctx(session, task.delivery_id)
    timeline(
        session,
        task.incident_id,
        "task_cant_go",
        f"{user.full_name} cannot go: {CANT_GO_REASONS[reason]}" + (f" — {note}" if note else ""),
        actor=actor,
        delivery_id=task.delivery_id,
        resident_id=task.resident_id,
        at=now,
    )
    emit(session, "task.updated", audience=[task.assignee_user_id], incident_id=task.incident_id, task_id=task.id)
    new_task = None
    if dc.incident.status == "active" and dc.delivery.status != "SAFE":
        await session.flush()
        new_task = await request_volunteer(
            session,
            ctx,
            dc,
            reason=f"Reassigned: previous helper could not go ({CANT_GO_REASONS[reason]})",
            actor=Actor.system("dispatch"),
            kind=task.kind,
        )
    return task, new_task


async def reached(
    session: AsyncSession, ctx: AppContext, task_id: str, outcome: str, note: str | None, actor: Actor
) -> Task:
    from app.services import responses

    if outcome not in REACHED_OUTCOMES:
        raise DomainError("invalid_outcome", f"outcome must be one of {sorted(REACHED_OUTCOMES)}", 422)
    task = await get_task(session, task_id)
    _require_assignee(task, actor)
    if task.status == "REACHED":
        return task
    if task.status != "ACCEPTED":
        raise Conflict("invalid_transition", "Accept the task before marking it reached")
    now = ctx.now()
    task.status, task.outcome, task.outcome_note, task.reached_at, task.closed_at = "REACHED", outcome, note, now, now
    task.version += 1
    dc = await get_delivery_ctx(session, task.delivery_id)
    timeline(
        session,
        task.incident_id,
        "task_reached",
        REACHED_OUTCOMES[outcome] + (f" — {note}" if note else ""),
        actor=actor,
        delivery_id=task.delivery_id,
        resident_id=task.resident_id,
        at=now,
    )
    if outcome in ("resident_safe", "evacuated"):
        await responses.apply_status(session, ctx, dc, "SAFE", channel="volunteer", actor=actor)
    else:
        dc.delivery.needs_rescue = True
        dc.delivery.needs_operator = True
        dc.delivery.rescue_reason = REACHED_OUTCOMES[outcome] + (f": {note}" if note else "")
        dc.delivery.version += 1
        emit(session, "delivery.updated", incident_id=dc.incident.id, delivery_id=dc.delivery.id)
    emit(session, "task.updated", audience=[task.assignee_user_id], incident_id=task.incident_id, task_id=task.id)
    return task


async def approve(session: AsyncSession, ctx: AppContext, task_id: str, actor: Actor) -> Task:
    task = await get_task(session, task_id)
    if task.status != "PENDING_APPROVAL":
        raise Conflict("invalid_transition", f"Task is {task.status}, not awaiting approval")
    dc = await get_delivery_ctx(session, task.delivery_id)
    # Re-check safety at approval time — time has passed since the task was proposed.
    evals = {e.candidate.volunteer_id: e for e in await evaluate_candidates(session, ctx, dc)}
    ev = evals.get(task.volunteer_id)
    if ev is not None and not ev.eligible and "Already on an active task" not in ev.reason:
        raise Conflict("no_longer_safe", f"Dispatch is no longer safe: {ev.reason}. Reassign or reject.")
    now = ctx.now()
    task.status, task.approved_by_user_id, task.approved_at = "ASSIGNED", actor.user_id, now
    task.version += 1
    audit(session, actor, "dispatch.approve", "task", task.id)
    timeline(
        session,
        task.incident_id,
        "dispatch_approved",
        "Operator approved volunteer dispatch",
        actor=actor,
        delivery_id=task.delivery_id,
        resident_id=task.resident_id,
        at=now,
    )
    await _notify_volunteer(session, ctx, dc, task)
    emit(session, "task.updated", audience=[task.assignee_user_id], incident_id=task.incident_id, task_id=task.id)
    return task


async def reject(session: AsyncSession, ctx: AppContext, task_id: str, reason: str, actor: Actor) -> Task:
    task = await get_task(session, task_id)
    if task.status != "PENDING_APPROVAL":
        raise Conflict("invalid_transition", f"Task is {task.status}, not awaiting approval")
    task.status, task.outcome_note, task.closed_at = "REJECTED", reason, ctx.now()
    task.version += 1
    dc = await get_delivery_ctx(session, task.delivery_id)
    dc.delivery.needs_operator = True
    dc.delivery.version += 1
    audit(session, actor, "dispatch.reject", "task", task.id, reason=reason)
    timeline(
        session,
        task.incident_id,
        "dispatch_rejected",
        f"Operator rejected dispatch: {reason}",
        actor=actor,
        delivery_id=task.delivery_id,
        resident_id=task.resident_id,
        at=ctx.now(),
    )
    emit(session, "task.updated", incident_id=task.incident_id, task_id=task.id)
    return task


async def reassign(
    session: AsyncSession, ctx: AppContext, task_id: str, to_volunteer_id: str | None, reason: str, actor: Actor
) -> Task | None:
    task = await get_task(session, task_id)
    if task.status not in OPEN_TASK_STATUSES or task.kind not in VOLUNTEER_KINDS:
        raise Conflict("invalid_transition", f"Cannot reassign a task in status {task.status}")
    dc = await get_delivery_ctx(session, task.delivery_id)
    was_engaged = task.status in ("ASSIGNED", "ACCEPTED")
    task.status, task.outcome, task.outcome_note, task.closed_at = "CANCELLED", "reassigned", reason, ctx.now()
    task.version += 1
    if was_engaged:
        user = await session.get(User, task.assignee_user_id)
        await dispatcher.notify_user(
            session,
            ctx,
            dc.incident,
            user,
            recipient_kind="volunteer",
            key=f"t:{task.id}:reassigned",
            title="AapdaSaathi: task reassigned",
            body="The control room reassigned this task. You can stand down.",
            sms_body="AapdaSaathi: your task was reassigned by the control room. Thank you.",
            task_id=task.id,
        )
    await session.flush()
    audit(session, actor, "dispatch.reassign", "task", task.id, reason=reason, after={"to": to_volunteer_id})
    emit(session, "task.updated", audience=[task.assignee_user_id], incident_id=task.incident_id, task_id=task.id)
    return await request_volunteer(
        session,
        ctx,
        dc,
        reason=f"Operator reassignment: {reason}",
        actor=actor,
        kind=task.kind,
        only_volunteer_id=to_volunteer_id,
    )
