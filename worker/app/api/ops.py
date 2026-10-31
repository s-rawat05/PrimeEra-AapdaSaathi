"""Command centre endpoints (admin/operator). Every state change is validated, transactional and audited."""

from __future__ import annotations

from datetime import timedelta

from fastapi import APIRouter, Depends, Query
from fastapi.responses import PlainTextResponse
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app import schemas as S
from app.api.common import PageParams, finalize, paged
from app.audit.log import audit, timeline
from app.auth.deps import actor_of, get_ctx, ops_user
from app.core import AppContext, DomainError, NotFound
from app.db import get_session
from app.dispatch import service as dispatch
from app.escalation import rules
from app.integrations import sachet_ingest
from app.matching.ward_matcher import WardMatch
from app.models import AuditLog, CapMessage, FeedState, Incident, Task, TimelineEvent, User, Ward
from app.reporting.report import build_report, report_csv
from app.repositories.queries import get_delivery_ctx
from app.services import incidents as incidents_svc
from app.services import views

router = APIRouter(tags=["command centre"])


@router.get("/incidents", response_model=S.Page[S.IncidentOut])
async def list_incidents(status: str | None = Query(None, pattern="^(active|closed|cancelled)$"),
                         demo: bool | None = None, page: PageParams = Depends(), _: User = Depends(ops_user),
                         session: AsyncSession = Depends(get_session)):
    q = select(Incident).order_by(Incident.created_at.desc())
    if status:
        q = q.where(Incident.status == status)
    if demo is not None:
        q = q.where(Incident.is_demo.is_(demo))
    rows, total = await paged(session, q, page)
    return S.Page(items=[await views.incident_out(session, i) for i in rows], total=total, limit=page.limit,
                  offset=page.offset)


@router.post("/incidents", response_model=S.IncidentOut, status_code=201,
             summary="Manually create an incident (e.g. from a district control-room phone call)")
async def create_incident(body: S.IncidentCreateIn, user: User = Depends(ops_user),
                          session: AsyncSession = Depends(get_session), ctx: AppContext = Depends(get_ctx)):
    wards = (await session.execute(select(Ward).where(Ward.id.in_(body.ward_ids)))).scalars().all()
    if len(wards) != len(set(body.ward_ids)):
        raise NotFound("Ward")
    now = ctx.now()
    inc = await incidents_svc.create_incident(
        session, ctx, title=body.title, hazard_type=body.hazard_type, source="manual", is_demo=body.is_demo,
        ward_matches=[WardMatch(w, "manual", "Selected by operator") for w in wards], actor=actor_of(user),
        severity=body.severity, urgency=body.urgency, sent=now,
        onset=now + timedelta(minutes=body.onset_in_minutes) if body.onset_in_minutes is not None else None,
        headline=body.headline, instruction=body.instruction, cap_sender=f"{user.full_name} (operator entry)",
    )
    await finalize(session, ctx)
    return await views.incident_out(session, inc)


@router.get("/incidents/{incident_id}", response_model=S.IncidentOut)
async def get_incident(incident_id: str, _: User = Depends(ops_user), session: AsyncSession = Depends(get_session)):
    return await views.incident_out(session, await incidents_svc.get_incident(session, incident_id))


@router.patch("/incidents/{incident_id}", response_model=S.IncidentOut)
async def patch_incident(incident_id: str, body: S.IncidentPatchIn, user: User = Depends(ops_user),
                         session: AsyncSession = Depends(get_session), ctx: AppContext = Depends(get_ctx)):
    inc = await incidents_svc.get_incident(session, incident_id)
    before = {"title": inc.title, "severity": inc.severity, "onset": str(inc.onset),
              "approval": inc.requires_dispatch_approval}
    if body.title:
        inc.title = body.title
    if body.severity:
        inc.severity = body.severity
    if body.onset_in_minutes is not None:
        inc.onset = ctx.now() + timedelta(minutes=body.onset_in_minutes)
        inc.onset_fallback_used = True
        inc.onset_fallback_note = f"Onset set by operator {user.full_name}: {body.reason}"
        inc.escalation_mode = rules.select_mode(inc.onset, ctx.now())
    if body.requires_dispatch_approval is not None:
        inc.requires_dispatch_approval = body.requires_dispatch_approval
    after = {"title": inc.title, "severity": inc.severity, "onset": str(inc.onset),
             "approval": inc.requires_dispatch_approval}
    audit(session, actor_of(user), "incident.update", "incident", inc.id, reason=body.reason, before=before,
          after=after)
    timeline(session, inc.id, "incident_updated", f"Operator updated incident: {body.reason}", actor=actor_of(user),
             at=ctx.now())
    await finalize(session, ctx)
    return await views.incident_out(session, inc)


@router.post("/incidents/{incident_id}/close", response_model=S.IncidentOut)
async def close_incident(incident_id: str, body: S.CloseIn, user: User = Depends(ops_user),
                         session: AsyncSession = Depends(get_session), ctx: AppContext = Depends(get_ctx)):
    inc = await incidents_svc.get_incident(session, incident_id)
    await incidents_svc.finish_incident(session, ctx, inc, "closed", body.note, actor_of(user))
    await finalize(session, ctx)
    return await views.incident_out(session, inc)


@router.get("/incidents/{incident_id}/priority", response_model=list[S.PriorityItem],
            summary="Residents ranked by transparent priority score")
async def priority(incident_id: str, status: str | None = None, include_safe: bool = True,
                   _: User = Depends(ops_user), session: AsyncSession = Depends(get_session),
                   ctx: AppContext = Depends(get_ctx)):
    await incidents_svc.get_incident(session, incident_id)
    return await views.priority_list(session, ctx, incident_id, status=status, include_safe=include_safe)


@router.get("/incidents/{incident_id}/map", response_model=S.MapOut)
async def incident_map(incident_id: str, _: User = Depends(ops_user), session: AsyncSession = Depends(get_session),
                       ctx: AppContext = Depends(get_ctx)):
    return await views.map_out(session, ctx, await incidents_svc.get_incident(session, incident_id))


@router.get("/incidents/{incident_id}/timeline", response_model=list[S.TimelineOut])
async def incident_timeline(incident_id: str, limit: int = Query(200, ge=1, le=1000), _: User = Depends(ops_user),
                            session: AsyncSession = Depends(get_session)):
    rows = (await session.execute(select(TimelineEvent).where(TimelineEvent.incident_id == incident_id)
                                  .order_by(TimelineEvent.created_at.desc()).limit(limit))).scalars().all()
    return await views.timeline_out(session, list(rows))


@router.get("/incidents/{incident_id}/tasks", response_model=list[S.TaskOut])
async def incident_tasks(incident_id: str, _: User = Depends(ops_user), session: AsyncSession = Depends(get_session)):
    rows = (await session.execute(select(Task).where(Task.incident_id == incident_id)
                                  .order_by(Task.created_at.desc()))).scalars().all()
    return [await views.task_out(session, t) for t in rows]


@router.get("/incidents/{incident_id}/report", summary="Closing report (JSON)")
async def report(incident_id: str, _: User = Depends(ops_user), session: AsyncSession = Depends(get_session),
                 ctx: AppContext = Depends(get_ctx)) -> dict:
    return await build_report(session, ctx, incident_id)


@router.get("/incidents/{incident_id}/report.csv", response_class=PlainTextResponse)
async def report_as_csv(incident_id: str, _: User = Depends(ops_user), session: AsyncSession = Depends(get_session),
                        ctx: AppContext = Depends(get_ctx)):
    return PlainTextResponse(report_csv(await build_report(session, ctx, incident_id)), media_type="text/csv",
                             headers={"Content-Disposition": f'attachment; filename="report-{incident_id}.csv"'})


# ----------------------------------------------------------------------------- deliveries
@router.get("/deliveries/{delivery_id}/timeline", response_model=list[S.TimelineOut])
async def delivery_timeline(delivery_id: str, _: User = Depends(ops_user), session: AsyncSession = Depends(get_session)):
    rows = (await session.execute(select(TimelineEvent).where(TimelineEvent.delivery_id == delivery_id)
                                  .order_by(TimelineEvent.created_at))).scalars().all()
    return await views.timeline_out(session, list(rows))


@router.get("/deliveries/{delivery_id}/location", response_model=S.ExactLocationOut | None,
            summary="Exact location for operators during an active incident (audited)")
async def delivery_location(delivery_id: str, user: User = Depends(ops_user),
                            session: AsyncSession = Depends(get_session), ctx: AppContext = Depends(get_ctx)):
    from app.models import ResidentLocation

    dc = await get_delivery_ctx(session, delivery_id, lock=False)
    if dc.incident.status != "active":
        raise DomainError("incident_closed", "Exact locations are only available during an active incident", 403)
    loc = await session.scalar(select(ResidentLocation).where(ResidentLocation.resident_id == dc.resident.id))
    audit(session, actor_of(user), "location.view", "resident", dc.resident.id, reason=f"incident {dc.incident.id}")
    await session.commit()
    return S.ExactLocationOut(lat=loc.lat, lng=loc.lng, address_text=loc.address_text, landmark=loc.landmark,
                              source=loc.source) if loc else None


@router.post("/deliveries/{delivery_id}/resend", response_model=S.PriorityItem)
async def resend(delivery_id: str, user: User = Depends(ops_user), session: AsyncSession = Depends(get_session),
                 ctx: AppContext = Depends(get_ctx)):
    d = await incidents_svc.resend(session, ctx, delivery_id, actor_of(user))
    await finalize(session, ctx)
    return next(p for p in await views.priority_list(session, ctx, d.incident_id) if p.delivery_id == d.id)


@router.post("/deliveries/{delivery_id}/override", response_model=S.PriorityItem,
             summary="Manual status override — reason required, audited")
async def override(delivery_id: str, body: S.OverrideIn, user: User = Depends(ops_user),
                   session: AsyncSession = Depends(get_session), ctx: AppContext = Depends(get_ctx)):
    d = await incidents_svc.override_status(session, ctx, delivery_id, body.status, body.reason, actor_of(user))
    await finalize(session, ctx)
    return next(p for p in await views.priority_list(session, ctx, d.incident_id) if p.delivery_id == d.id)


@router.post("/deliveries/{delivery_id}/dispatch", response_model=S.TaskOut | None,
             summary="Ask the dispatcher for the best eligible volunteer now")
async def dispatch_now(delivery_id: str, user: User = Depends(ops_user), session: AsyncSession = Depends(get_session),
                       ctx: AppContext = Depends(get_ctx)):
    dc = await get_delivery_ctx(session, delivery_id)
    if dc.delivery.status == "SAFE":
        raise DomainError("already_safe", "Resident is already confirmed safe", 409)
    t = await dispatch.request_volunteer(session, ctx, dc, reason=f"Requested by operator {user.full_name}",
                                         actor=actor_of(user))
    audit(session, actor_of(user), "dispatch.request", "delivery", delivery_id)
    await finalize(session, ctx)
    return await views.task_out(session, t) if t else None


@router.get("/deliveries/{delivery_id}/candidates", response_model=list[S.CandidateOut],
            summary="Volunteer eligibility with reasons (transparent dispatch)")
async def candidates(delivery_id: str, _: User = Depends(ops_user), session: AsyncSession = Depends(get_session),
                     ctx: AppContext = Depends(get_ctx)):
    dc = await get_delivery_ctx(session, delivery_id, lock=False)
    return [S.CandidateOut(volunteer_id=e.candidate.volunteer_id, name=e.candidate.name, eligible=e.eligible,
                           distance_m=round(e.distance_m), walk_minutes=e.walk_minutes, reason=e.reason)
            for e in await dispatch.evaluate_candidates(session, ctx, dc)]


# ----------------------------------------------------------------------------- tasks
@router.post("/tasks/{task_id}/approve", response_model=S.TaskOut)
async def approve(task_id: str, user: User = Depends(ops_user), session: AsyncSession = Depends(get_session),
                  ctx: AppContext = Depends(get_ctx)):
    t = await dispatch.approve(session, ctx, task_id, actor_of(user))
    await finalize(session, ctx)
    return await views.task_out(session, t)


@router.post("/tasks/{task_id}/reject", response_model=S.TaskOut)
async def reject(task_id: str, body: S.RejectIn, user: User = Depends(ops_user),
                 session: AsyncSession = Depends(get_session), ctx: AppContext = Depends(get_ctx)):
    t = await dispatch.reject(session, ctx, task_id, body.reason, actor_of(user))
    await finalize(session, ctx)
    return await views.task_out(session, t)


@router.post("/tasks/{task_id}/reassign", response_model=S.TaskOut | None)
async def reassign(task_id: str, body: S.ReassignIn, user: User = Depends(ops_user),
                   session: AsyncSession = Depends(get_session), ctx: AppContext = Depends(get_ctx)):
    t = await dispatch.reassign(session, ctx, task_id, body.to_volunteer_id, body.reason, actor_of(user))
    await finalize(session, ctx)
    return await views.task_out(session, t) if t else None


@router.get("/tasks/{task_id}/ops", response_model=S.TaskOut)
async def ops_task(task_id: str, _: User = Depends(ops_user), session: AsyncSession = Depends(get_session)):
    t = await session.get(Task, task_id)
    if t is None:
        raise NotFound("Task")
    return await views.task_out(session, t)


# ----------------------------------------------------------------------------- SACHET feed
@router.get("/feed/status", response_model=S.FeedStatusOut)
async def feed_status(_: User = Depends(ops_user), session: AsyncSession = Depends(get_session),
                      ctx: AppContext = Depends(get_ctx)):
    rows = {f.url: f for f in (await session.execute(select(FeedState))).scalars().all()}
    feeds = []
    for url in ctx.settings.rss_urls:
        f = rows.get(url)
        healthy = bool(f and f.last_success_at and f.consecutive_failures == 0
                       and ctx.now() - f.last_success_at < timedelta(seconds=ctx.settings.feed_poll_seconds * 4))
        feeds.append(S.FeedHealth(
            url=url, healthy=healthy, last_fetch_at=f.last_fetch_at if f else None,
            last_success_at=f.last_success_at if f else None, last_status_code=f.last_status_code if f else None,
            last_error=f.last_error if f else None, consecutive_failures=f.consecutive_failures if f else 0,
            next_fetch_at=f.next_fetch_at if f else None, items_seen=f.items_seen if f else 0,
            etag=f.etag if f else None))
    return S.FeedStatusOut(polling_enabled=ctx.settings.feed_poll_enabled,
                           notify_real_residents=ctx.settings.notify_real_residents, feeds=feeds)


@router.post("/feed/poll", summary="Fetch the SACHET feed now (conditional GET)")
async def feed_poll(user: User = Depends(ops_user), ctx: AppContext = Depends(get_ctx),
                    session: AsyncSession = Depends(get_session)) -> list[dict]:
    audit(session, actor_of(user), "feed.poll", "feed", None)
    await session.commit()
    results = await sachet_ingest.poll_all(ctx, force=True)
    from app.notifications.dispatcher import flush_outbox
    await flush_outbox(ctx)
    return results


@router.get("/feed/messages", response_model=S.Page[S.CapMessageOut])
async def feed_messages(include_fixtures: bool = False, page: PageParams = Depends(), _: User = Depends(ops_user),
                        session: AsyncSession = Depends(get_session)):
    q = select(CapMessage).order_by(CapMessage.sent.desc().nulls_last(), CapMessage.fetched_at.desc())
    if not include_fixtures:
        q = q.where(CapMessage.is_fixture.is_(False))
    rows, total = await paged(session, q, page)
    return S.Page(items=[await views.cap_out(session, m) for m in rows], total=total, limit=page.limit,
                  offset=page.offset)


@router.get("/feed/messages/{message_id}/xml", response_class=PlainTextResponse,
            summary="Original CAP XML exactly as received")
async def feed_message_xml(message_id: str, _: User = Depends(ops_user), session: AsyncSession = Depends(get_session)):
    m = await session.get(CapMessage, message_id)
    if m is None:
        raise NotFound("CAP message")
    return PlainTextResponse(m.raw_xml, media_type="application/xml")


@router.post("/feed/messages/{message_id}/replay", response_model=S.IncidentOut, status_code=201,
             summary="Replay an official alert into the fictional demo ward (demo residents only)")
async def feed_replay(message_id: str, body: S.ReplayIn, user: User = Depends(ops_user),
                      session: AsyncSession = Depends(get_session), ctx: AppContext = Depends(get_ctx)):
    from app.demo import service as demo

    if not ctx.settings.demo_mode_enabled:
        raise DomainError("demo_disabled", "Demo mode is disabled on this deployment", 403)
    inc = await demo.replay(session, ctx, message_id, body.onset_in_minutes, body.ward_ids, actor_of(user))
    await finalize(session, ctx)
    return await views.incident_out(session, inc)


# ----------------------------------------------------------------------------- audit
@router.get("/audit", response_model=S.Page[S.AuditOut])
async def audit_log(entity_type: str | None = None, entity_id: str | None = None, action: str | None = None,
                    page: PageParams = Depends(), _: User = Depends(ops_user),
                    session: AsyncSession = Depends(get_session)):
    q = select(AuditLog).order_by(AuditLog.created_at.desc())
    if entity_type:
        q = q.where(AuditLog.entity_type == entity_type)
    if entity_id:
        q = q.where(AuditLog.entity_id == entity_id)
    if action:
        q = q.where(AuditLog.action.like(f"{action}%"))
    rows, total = await paged(session, q, page)
    names = dict((await session.execute(select(User.id, User.full_name))).all())
    return S.Page(items=[S.AuditOut(id=a.id, actor_user_id=a.actor_user_id, actor_name=names.get(a.actor_user_id),
                                    actor_role=a.actor_role, action=a.action, entity_type=a.entity_type,
                                    entity_id=a.entity_id, reason=a.reason, before=a.before, after=a.after,
                                    created_at=a.created_at) for a in rows],
                  total=total, limit=page.limit, offset=page.offset)
