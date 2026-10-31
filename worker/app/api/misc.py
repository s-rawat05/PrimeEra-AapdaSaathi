"""SMS webhook, demo/drill controls, realtime WebSocket and health checks."""

from __future__ import annotations

import asyncio
import secrets
from datetime import timedelta

from fastapi import APIRouter, Depends, Header, Query, Request, WebSocket, WebSocketDisconnect
from sqlalchemy import func, select, text
from sqlalchemy.ext.asyncio import AsyncSession

from app import schemas as S
from app.api.common import finalize
from app.auth.deps import actor_of, get_ctx, ops_user
from app.core import AppContext, DomainError, Forbidden
from app.db import db, get_session
from app.demo import service as demo
from app.demo.seed import persona_descriptions, seed_demo
from app.integrations.sms_gateway import extract_inbound, normalize_phone, verify_httpsms_webhook
from app.models import Incident, NotificationAttempt, Resident, User, Ward, WorkerHeartbeat
from app.services import responses, views

router = APIRouter()


# ----------------------------------------------------------------------------- SMS
@router.post(
    "/sms/webhook",
    response_model=S.SmsResultOut,
    tags=["sms"],
    summary="Inbound SMS from the gateway (httpSMS 'message.phone.received'; HS256-signed)",
)
async def sms_webhook(
    request: Request,
    authorization: str | None = Header(default=None),
    session: AsyncSession = Depends(get_session),
    ctx: AppContext = Depends(get_ctx),
):
    if not verify_httpsms_webhook(authorization, ctx.settings.sms_webhook_secret):
        raise DomainError("bad_signature", "Webhook signature invalid", 401)
    try:
        payload = await request.json()
    except ValueError as exc:
        raise DomainError("bad_payload", "Body must be JSON", 400) from exc
    parsed = extract_inbound(payload if isinstance(payload, dict) else {})
    if parsed is None:
        return S.SmsResultOut(result="ignored", detail="Not an inbound-message event")
    msg_id, sender, body = parsed
    result = await responses.process_inbound_sms(
        session, ctx, provider_message_id=f"httpsms:{msg_id}", from_phone=sender, body=body, simulated=False
    )
    await finalize(session, ctx)
    return S.SmsResultOut(**result)


# ----------------------------------------------------------------------------- demo
def _require_demo(ctx: AppContext) -> None:
    if not ctx.settings.demo_mode_enabled:
        raise Forbidden("Demo mode is disabled on this deployment")


@router.get("/demo/status", response_model=S.DemoStatusOut, tags=["demo"])
async def demo_status(
    _: User = Depends(ops_user), session: AsyncSession = Depends(get_session), ctx: AppContext = Depends(get_ctx)
):
    wards = (await session.execute(select(Ward).where(Ward.is_demo.is_(True)).order_by(Ward.code))).scalars().all()
    n_res = await session.scalar(select(func.count()).select_from(Resident).where(Resident.is_demo.is_(True)))
    n_inc = await session.scalar(
        select(func.count()).select_from(Incident).where(Incident.is_demo.is_(True), Incident.status == "active")
    )
    desc = persona_descriptions()
    users = (
        (await session.execute(select(User).where(User.is_demo.is_(True)).order_by(User.role, User.full_name)))
        .scalars()
        .all()
    )
    return S.DemoStatusOut(
        demo_mode_enabled=ctx.settings.demo_mode_enabled,
        notify_real_residents=ctx.settings.notify_real_residents,
        demo_wards=[views.ward_out(w) for w in wards],
        demo_residents=n_res or 0,
        active_demo_incidents=n_inc or 0,
        escalation_interval_seconds=ctx.settings.demo_escalation_interval_seconds,
        fixtures=demo.list_fixtures(),
        personas=[
            S.DemoPersona(user_id=u.id, full_name=u.full_name, role=u.role, description=desc.get(u.phone, ""))
            for u in users
        ],
    )


@router.post("/demo/seed", tags=["demo"], summary="Create any missing fictional demo data (idempotent)")
async def demo_seed(user: User = Depends(ops_user), ctx: AppContext = Depends(get_ctx)) -> dict:
    _require_demo(ctx)
    return await seed_demo(ctx.now())


@router.post(
    "/demo/simulate",
    response_model=S.IncidentOut,
    status_code=201,
    tags=["demo"],
    summary="Simulate a saved CAP fixture in the demo ward",
)
async def demo_simulate(
    body: S.SimulateIn,
    user: User = Depends(ops_user),
    session: AsyncSession = Depends(get_session),
    ctx: AppContext = Depends(get_ctx),
):
    _require_demo(ctx)
    inc = await demo.simulate(session, ctx, body.fixture, body.onset_in_minutes, body.ward_ids, actor_of(user))
    await finalize(session, ctx)
    return await views.incident_out(session, inc)


@router.post(
    "/demo/reset",
    response_model=S.DemoResetOut,
    tags=["demo"],
    summary="Remove demo incidents, tasks and simulated SMS. Never touches real data.",
)
async def demo_reset(
    user: User = Depends(ops_user), session: AsyncSession = Depends(get_session), ctx: AppContext = Depends(get_ctx)
):
    _require_demo(ctx)
    out = await demo.reset(session, ctx, actor_of(user))
    await finalize(session, ctx)
    ctx.bus.publish({"type": "demo.reset"})
    return S.DemoResetOut(**out)


@router.post(
    "/demo/sms/inbound",
    response_model=S.SmsResultOut,
    tags=["demo"],
    summary="Feature-phone simulator: send an SMS reply through the real reply pipeline",
)
async def demo_sms_inbound(
    body: S.SimSmsIn,
    user: User = Depends(ops_user),
    session: AsyncSession = Depends(get_session),
    ctx: AppContext = Depends(get_ctx),
):
    _require_demo(ctx)
    phone = normalize_phone(body.from_phone)
    sender = await session.scalar(select(User.is_demo).where(User.phone == phone)) or await session.scalar(
        select(Resident.is_demo).where(Resident.phone == phone)
    )
    if not sender:
        raise Forbidden("The simulator can only send from fictional demo numbers")
    result = await responses.process_inbound_sms(
        session,
        ctx,
        provider_message_id=f"sim:{secrets.token_hex(8)}",
        from_phone=phone,
        body=body.body,
        simulated=True,
    )
    await finalize(session, ctx)
    return S.SmsResultOut(**result)


@router.get(
    "/demo/sms/outbox",
    response_model=list[S.OutboxItem],
    tags=["demo"],
    summary="Messages the simulated phones received (demo incidents only)",
)
async def demo_outbox(
    phone: str | None = None,
    limit: int = Query(100, ge=1, le=500),
    _: User = Depends(ops_user),
    session: AsyncSession = Depends(get_session),
    ctx: AppContext = Depends(get_ctx),
):
    _require_demo(ctx)
    q = (
        select(NotificationAttempt)
        .join(Incident, Incident.id == NotificationAttempt.incident_id)
        .where(Incident.is_demo.is_(True), NotificationAttempt.channel == "sms")
        .order_by(NotificationAttempt.created_at.desc())
        .limit(limit)
    )
    if phone:
        q = q.where(NotificationAttempt.recipient_phone == normalize_phone(phone))
    rows = (await session.execute(q)).scalars().all()
    out = [
        S.OutboxItem(
            id=a.id,
            channel=a.channel,
            recipient_kind=a.recipient_kind,
            recipient_phone=a.recipient_phone,
            title=a.title,
            body=a.body,
            status=a.status,
            provider=a.provider,
            error=a.error,
            round=a.round,
            created_at=a.created_at,
            sent_at=a.sent_at,
        )
        for a in rows
    ]
    for i, m in enumerate(reversed(ctx.extras.get("sim_inbox", []))):
        if phone and m["to"] != normalize_phone(phone):
            continue
        out.append(
            S.OutboxItem(
                id=f"otp-{i}",
                channel="sms",
                recipient_kind="login",
                recipient_phone=m["to"],
                title=None,
                body=m["body"],
                status="sent",
                provider="simulator",
                error=None,
                round="otp",
                created_at=m["at"],
                sent_at=m["at"],
            )
        )
    return sorted(out, key=lambda o: o.created_at, reverse=True)[:limit]


# ----------------------------------------------------------------------------- realtime
@router.websocket("/realtime")
async def realtime(ws: WebSocket, ticket: str = Query(...)):
    ctx: AppContext = ws.app.state.ctx
    who = ctx.bus.redeem_ticket(ticket)
    if who is None:
        await ws.close(code=4401)
        return
    await ws.accept()
    sub = ctx.bus.subscribe(*who)
    try:
        await ws.send_json({"type": "hello", "role": who[1]})
        while True:
            try:
                event = await asyncio.wait_for(sub.queue.get(), timeout=25)
                await ws.send_json(event)
            except TimeoutError:
                await ws.send_json({"type": "ping"})
    except (WebSocketDisconnect, RuntimeError):
        pass
    finally:
        ctx.bus.unsubscribe(sub)


# ----------------------------------------------------------------------------- health
@router.get("/health", tags=["health"], summary="Liveness")
async def health() -> dict:
    return {"status": "ok"}


@router.get("/ready", tags=["health"], summary="Readiness: database + worker heartbeat")
async def ready(ctx: AppContext = Depends(get_ctx)) -> dict:
    async with db.session() as s:
        await s.execute(text("SELECT 1"))
        beats = (await s.execute(select(WorkerHeartbeat))).scalars().all()
    stale = [b.worker_id for b in beats if ctx.now() - b.last_beat_at > timedelta(minutes=2)]
    return {
        "status": "ok",
        "database": "ok",
        "dialect": "postgresql" if db.is_postgres else "sqlite",
        "workers": [
            {"id": b.worker_id, "last_beat_at": b.last_beat_at.isoformat(), "result": b.last_result} for b in beats
        ],
        "stale_workers": stale,
        "notify_real_residents": ctx.settings.notify_real_residents,
        "demo_mode": ctx.settings.demo_mode_enabled,
        "realtime_subscribers": ctx.bus.subscriber_count,
    }
