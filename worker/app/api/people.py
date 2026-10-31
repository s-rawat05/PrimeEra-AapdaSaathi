"""Resident, caregiver, neighbour and volunteer endpoints (the Android app)."""

from __future__ import annotations

from fastapi import APIRouter, Depends, Header
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app import schemas as S
from app.api.common import PageParams, finalize, paged
from app.auth.deps import actor_of, current_user, get_ctx, idempotent_replay, remember_idempotent, require_roles
from app.core import AppContext, DomainError, Forbidden, NotFound
from app.db import get_session
from app.dispatch import service as dispatch
from app.models import (
    OPEN_TASK_STATUSES,
    CaregiverLink,
    Delivery,
    Incident,
    Resident,
    ResidentLocation,
    Task,
    User,
    Volunteer,
    Ward,
)
from app.services import residents as residents_svc
from app.services import responses, views

router = APIRouter(tags=["resident app"])


async def _my_resident(session: AsyncSession, user: User) -> Resident:
    r = await session.scalar(select(Resident).where(Resident.user_id == user.id))
    if r is None:
        raise NotFound("Resident profile")
    return r


@router.get("/wards/public", response_model=list[S.WardOut], summary="Wards a resident can register in")
async def public_wards(user: User = Depends(current_user), session: AsyncSession = Depends(get_session)):
    q = select(Ward).order_by(Ward.is_demo.desc(), Ward.name)
    if not user.is_demo:
        q = q.where(Ward.is_demo.is_(False))
    return [views.ward_out(w) for w in (await session.execute(q)).scalars().all()]


@router.post("/residents/me/registration", response_model=S.ResidentOut, status_code=201)
async def register_me(body: S.RegistrationIn, user: User = Depends(current_user),
                      session: AsyncSession = Depends(get_session), ctx: AppContext = Depends(get_ctx)):
    if user.role not in ("resident", "caregiver", "neighbour"):
        raise Forbidden("Operations and volunteer accounts cannot register as residents")
    r = await residents_svc.register(session, ctx, body, user=user, phone=user.phone, registered_via="self",
                                     actor=actor_of(user), is_demo=user.is_demo)
    await finalize(session, ctx)
    return await views.resident_out(session, r)


@router.get("/residents/me", response_model=S.ResidentOut)
async def get_me_resident(user: User = Depends(current_user), session: AsyncSession = Depends(get_session)):
    return await views.resident_out(session, await _my_resident(session, user))


@router.get("/residents/me/location", response_model=S.ExactLocationOut | None)
async def my_location(user: User = Depends(current_user), session: AsyncSession = Depends(get_session)):
    r = await _my_resident(session, user)
    loc = await session.scalar(select(ResidentLocation).where(ResidentLocation.resident_id == r.id))
    return S.ExactLocationOut(lat=loc.lat, lng=loc.lng, address_text=loc.address_text, landmark=loc.landmark,
                              source=loc.source) if loc else None


@router.patch("/residents/me", response_model=S.ResidentOut)
async def patch_me_resident(body: S.ResidentPatch, user: User = Depends(current_user),
                            session: AsyncSession = Depends(get_session), ctx: AppContext = Depends(get_ctx)):
    r = await residents_svc.update_profile(session, ctx, await _my_resident(session, user), body, actor_of(user))
    if body.language:
        user.language = body.language
    await finalize(session, ctx)
    return await views.resident_out(session, r)


@router.post("/residents/me/consent/withdraw", response_model=S.ResidentOut)
async def withdraw_consent(user: User = Depends(current_user), session: AsyncSession = Depends(get_session),
                           ctx: AppContext = Depends(get_ctx)):
    r = await residents_svc.withdraw(session, ctx, await _my_resident(session, user), actor_of(user),
                                     "withdrawn by resident")
    await finalize(session, ctx)
    return await views.resident_out(session, r)


@router.post("/residents/me/consent/renew", response_model=S.ResidentOut)
async def renew_consent(user: User = Depends(current_user), session: AsyncSession = Depends(get_session),
                        ctx: AppContext = Depends(get_ctx)):
    r = await residents_svc.reverify(session, ctx, await _my_resident(session, user), actor_of(user))
    await finalize(session, ctx)
    return await views.resident_out(session, r)


# ----------------------------------------------------------------------------- alerts
@router.get("/alerts/active", response_model=list[S.AlertOut], summary="My alerts for active incidents")
async def active_alerts(user: User = Depends(current_user), session: AsyncSession = Depends(get_session),
                        ctx: AppContext = Depends(get_ctx)):
    r = await session.scalar(select(Resident).where(Resident.user_id == user.id))
    if r is None:
        return []
    rows = (await session.execute(
        select(Delivery).join(Incident, Incident.id == Delivery.incident_id)
        .where(Delivery.resident_id == r.id, Incident.status == "active").order_by(Delivery.alerted_at.desc())
    )).scalars().all()
    changed = False
    for d in rows:
        if d.seen_at is None and d.alerted_at is not None:
            d.seen_at = ctx.now()  # in-app delivery receipt
            changed = True
    out = [await views.alert_out(session, ctx, d) for d in rows]
    if changed:
        await finalize(session, ctx)
    return out


@router.get("/alerts/history", response_model=S.Page[S.AlertOut])
async def alert_history(user: User = Depends(current_user), page: PageParams = Depends(),
                        session: AsyncSession = Depends(get_session), ctx: AppContext = Depends(get_ctx)):
    r = await session.scalar(select(Resident).where(Resident.user_id == user.id))
    if r is None:
        return S.Page(items=[], total=0, limit=page.limit, offset=page.offset)
    rows, total = await paged(session, select(Delivery).where(Delivery.resident_id == r.id)
                              .order_by(Delivery.created_at.desc()), page)
    return S.Page(items=[await views.alert_out(session, ctx, d) for d in rows], total=total, limit=page.limit,
                  offset=page.offset)


@router.get("/alerts/{delivery_id}", response_model=S.AlertOut)
async def alert_detail(delivery_id: str, user: User = Depends(current_user),
                       session: AsyncSession = Depends(get_session), ctx: AppContext = Depends(get_ctx)):
    d = await session.get(Delivery, delivery_id)
    if d is None:
        raise NotFound("Alert")
    r = await session.get(Resident, d.resident_id)
    if r.user_id != user.id:
        raise Forbidden("This alert does not belong to you")
    return await views.alert_out(session, ctx, d)


@router.post("/alerts/{delivery_id}/respond", response_model=S.RespondOut,
             summary="One-tap SAFE / HELP. Send Idempotency-Key when retrying queued offline actions.")
async def respond(delivery_id: str, body: S.RespondIn, user: User = Depends(current_user),
                  session: AsyncSession = Depends(get_session), ctx: AppContext = Depends(get_ctx),
                  idempotency_key: str | None = Header(default=None)):
    key = idempotency_key or body.client_request_id
    endpoint = f"respond:{delivery_id}"
    replay = await idempotent_replay(session, user, key, endpoint)
    if replay:
        return replay
    d = await session.get(Delivery, delivery_id)
    if d is None:
        raise NotFound("Alert")
    before = d.status
    d = await responses.respond_as_resident(session, ctx, delivery_id, body.status, actor_of(user))
    out = S.RespondOut(delivery_id=d.id, status=d.status, changed=d.status != before, server_time=ctx.now())
    remember_idempotent(session, user, key, endpoint, out.model_dump(mode="json"))
    await finalize(session, ctx)
    return out


# ----------------------------------------------------------------------------- caregiver
caregiver = require_roles("caregiver")


@router.get("/caregiver/residents", response_model=list[S.CaregiverResidentOut])
async def caregiver_residents(user: User = Depends(caregiver), session: AsyncSession = Depends(get_session),
                              ctx: AppContext = Depends(get_ctx)):
    links = (await session.execute(select(CaregiverLink).where(CaregiverLink.caregiver_user_id == user.id)))\
        .scalars().all()
    out = []
    for link in links:
        r = await session.get(Resident, link.resident_id)
        active = (await session.execute(
            select(Incident.id).join(Delivery, Delivery.incident_id == Incident.id)
            .where(Delivery.resident_id == r.id, Incident.status == "active"))).scalars().all()
        items = []
        for inc_id in active:
            items += [p for p in await views.priority_list(session, ctx, inc_id) if p.resident_id == r.id]
        loc = None
        if link.can_view_location:
            row = await session.scalar(select(ResidentLocation).where(ResidentLocation.resident_id == r.id))
            if row:
                loc = S.ExactLocationOut(lat=row.lat, lng=row.lng, address_text=row.address_text,
                                         landmark=row.landmark, source=row.source)
        out.append(S.CaregiverResidentOut(resident=await views.resident_out(session, r, include_consents=False),
                                          active_alerts=items, exact_location=loc))
    return out


@router.post("/caregiver/alerts/{delivery_id}/respond", response_model=S.RespondOut,
             summary="Caregiver confirms SAFE or requests HELP on behalf of a linked resident")
async def caregiver_respond(delivery_id: str, body: S.RespondIn, user: User = Depends(caregiver),
                            session: AsyncSession = Depends(get_session), ctx: AppContext = Depends(get_ctx)):
    d = await responses.respond_as_caregiver(session, ctx, delivery_id, body.status, body.note, actor_of(user))
    out = S.RespondOut(delivery_id=d.id, status=d.status, changed=True, server_time=ctx.now())
    await finalize(session, ctx)
    return out


# ----------------------------------------------------------------------------- neighbour
@router.get("/neighbour/checks", response_model=list[S.TaskOut], summary="My neighbour check requests")
async def neighbour_checks(include_closed: bool = False, user: User = Depends(current_user),
                           session: AsyncSession = Depends(get_session)):
    q = select(Task).where(Task.assignee_user_id == user.id, Task.kind == "neighbour_check")
    if not include_closed:
        q = q.where(Task.status.in_(OPEN_TASK_STATUSES))
    rows = (await session.execute(q.order_by(Task.created_at.desc()).limit(100))).scalars().all()
    return [await views.task_out(session, t) for t in rows]


@router.post("/neighbour/checks/{task_id}/respond", response_model=S.TaskOut)
async def neighbour_respond(task_id: str, body: S.NeighbourRespondIn, user: User = Depends(current_user),
                            session: AsyncSession = Depends(get_session), ctx: AppContext = Depends(get_ctx)):
    t = await responses.respond_neighbour_check(session, ctx, task_id, body.outcome, actor_of(user), body.note)
    await finalize(session, ctx)
    return await views.task_out(session, t)


# ----------------------------------------------------------------------------- volunteer
volunteer = require_roles("volunteer")


async def _my_volunteer(session: AsyncSession, user: User) -> Volunteer:
    v = await session.scalar(select(Volunteer).where(Volunteer.user_id == user.id))
    if v is None:
        raise NotFound("Volunteer profile")
    return v


@router.get("/volunteer/me", response_model=S.VolunteerOut)
async def volunteer_me(user: User = Depends(volunteer), session: AsyncSession = Depends(get_session)):
    return await views.volunteer_out(session, await _my_volunteer(session, user))


@router.put("/volunteer/me/availability", response_model=S.VolunteerOut)
async def set_availability(body: S.AvailabilityIn, user: User = Depends(volunteer),
                           session: AsyncSession = Depends(get_session), ctx: AppContext = Depends(get_ctx)):
    v = await _my_volunteer(session, user)
    v.is_available = body.is_available
    from app.audit.log import audit
    audit(session, actor_of(user), "volunteer.availability", "volunteer", v.id, after={"available": body.is_available})
    await finalize(session, ctx)
    return await views.volunteer_out(session, v)


@router.get("/volunteer/tasks", response_model=list[S.TaskOut])
async def volunteer_tasks(include_closed: bool = False, user: User = Depends(volunteer),
                          session: AsyncSession = Depends(get_session)):
    q = select(Task).where(Task.assignee_user_id == user.id, Task.kind.in_(dispatch.VOLUNTEER_KINDS),
                           Task.status != "PENDING_APPROVAL")
    if not include_closed:
        q = q.where(Task.status.in_(OPEN_TASK_STATUSES))
    rows = (await session.execute(q.order_by(Task.created_at.desc()).limit(100))).scalars().all()
    return [await views.task_out(session, t) for t in rows]


async def _assigned_task(session: AsyncSession, user: User, task_id: str) -> Task:
    t = await session.get(Task, task_id)
    if t is None or t.assignee_user_id != user.id or t.status == "PENDING_APPROVAL":
        raise NotFound("Task")
    return t


@router.get("/tasks/{task_id}", response_model=S.TaskDetailOut,
            summary="Task detail. Exact resident location only while the task is active (audited).")
async def task_detail(task_id: str, user: User = Depends(current_user), session: AsyncSession = Depends(get_session),
                      ctx: AppContext = Depends(get_ctx)):
    t = await _assigned_task(session, user, task_id)
    out = await views.task_detail(session, ctx, t)
    await session.commit()  # persist the location-access audit record
    return out


@router.post("/volunteer/tasks/{task_id}/accept", response_model=S.TaskOut)
async def accept_task(task_id: str, user: User = Depends(volunteer), session: AsyncSession = Depends(get_session),
                      ctx: AppContext = Depends(get_ctx)):
    t = await dispatch.accept(session, ctx, task_id, actor_of(user))
    await finalize(session, ctx)
    return await views.task_out(session, t)


@router.post("/volunteer/tasks/{task_id}/cant-go", response_model=S.TaskOut)
async def cant_go(task_id: str, body: S.CantGoIn, user: User = Depends(volunteer),
                  session: AsyncSession = Depends(get_session), ctx: AppContext = Depends(get_ctx)):
    t, _ = await dispatch.cant_go(session, ctx, task_id, body.reason, body.note, actor_of(user))
    await finalize(session, ctx)
    return await views.task_out(session, t)


@router.post("/volunteer/tasks/{task_id}/reached", response_model=S.TaskOut)
async def reached(task_id: str, body: S.ReachedIn, user: User = Depends(volunteer),
                  session: AsyncSession = Depends(get_session), ctx: AppContext = Depends(get_ctx)):
    if body.outcome in ("needs_rescue", "not_found") and not body.note:
        raise DomainError("note_required", "Add a short note for the control room", 422)
    t = await dispatch.reached(session, ctx, task_id, body.outcome, body.note, actor_of(user))
    await finalize(session, ctx)
    return await views.task_out(session, t)
