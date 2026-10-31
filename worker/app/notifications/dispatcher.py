"""Notification outbox.

Messages are QUEUED inside the business transaction (so a rolled-back reply never sends a
message) and SENT afterwards by `flush_outbox`, which leases rows so two workers never send the
same message, retries failures with exponential backoff, and marks a delivery UNREACHABLE when
every external channel to the resident has finally failed.

SAFETY: `may_notify` blocks every message to a non-demo recipient unless NOTIFY_REAL_RESIDENTS=true.
Blocked attempts are still recorded (status 'blocked') so operators can see what would have gone out.
"""

from __future__ import annotations

import hashlib
import logging
from datetime import timedelta

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core import AppContext
from app.db import db
from app.models import (
    ConsentRecord,
    Delivery,
    DeviceRegistration,
    Incident,
    NotificationAttempt,
    Resident,
    User,
)
from app.notifications import templates
from app.services.realtime import commit, emit

log = logging.getLogger(__name__)
LEASE = timedelta(seconds=60)


def may_notify(ctx: AppContext, incident: Incident, recipient_is_demo: bool) -> bool:
    if ctx.settings.notify_real_residents:
        return True
    return bool(incident.is_demo and recipient_is_demo)


async def _existing(session: AsyncSession, key: str) -> NotificationAttempt | None:
    return await session.scalar(select(NotificationAttempt).where(NotificationAttempt.idempotency_key == key))


async def queue(
    session: AsyncSession,
    ctx: AppContext,
    *,
    incident: Incident,
    channel: str,
    recipient_kind: str,
    recipient_is_demo: bool,
    key: str,
    body: str,
    title: str | None = None,
    recipient_user_id: str | None = None,
    phone: str | None = None,
    data: dict | None = None,
    delivery_id: str | None = None,
    task_id: str | None = None,
    round_: str = "initial",
) -> NotificationAttempt:
    """Idempotent: the same key never produces a second message."""
    found = await _existing(session, key)
    if found is not None:
        return found
    now = ctx.now()
    attempt = NotificationAttempt(
        delivery_id=delivery_id,
        task_id=task_id,
        incident_id=incident.id,
        channel=channel,
        recipient_kind=recipient_kind,
        recipient_user_id=recipient_user_id,
        recipient_phone=phone,
        title=title,
        body=body,
        data={**(data or {}), "demo": bool(incident.is_demo)},
        status="queued",
        round=round_,
        idempotency_key=key,
        created_at=now,
    )
    if not may_notify(ctx, incident, recipient_is_demo):
        attempt.status = "blocked"
        attempt.error = "Blocked by NOTIFY_REAL_RESIDENTS=false (real recipients are never notified)"
    elif channel == "in_app":
        # Served from the API/WebSocket; 'sent' means available to the app, not 'read'.
        attempt.status = "sent"
        attempt.provider = "in_app"
        attempt.sent_at = now
    session.add(attempt)
    await session.flush()
    return attempt


async def _sms_consent(session: AsyncSession, resident_id: str, now) -> bool:
    rows = (
        await session.execute(
            select(ConsentRecord).where(
                ConsentRecord.resident_id == resident_id,
                ConsentRecord.consent_type.in_(["registry", "sms"]),
                ConsentRecord.granted.is_(True),
                ConsentRecord.withdrawn_at.is_(None),
                ConsentRecord.expires_at > now,
            )
        )
    ).scalars().all()
    return any(r.consent_type == "registry" for r in rows)


def _token_key(token: str) -> str:
    return hashlib.sha256(token.encode()).hexdigest()[:16]


async def alert_resident(
    session: AsyncSession,
    ctx: AppContext,
    incident: Incident,
    delivery: Delivery,
    resident: Resident,
    round_: str,
) -> list[NotificationAttempt]:
    """Queue the alert on every channel the resident can receive. Returns the attempts."""
    lang = resident.language if resident.language in ("en", "hi") else "en"
    style = "easy_read" if "easy_read" in (delivery.accessibility_modes or []) else "standard"
    title, body = await templates.render(session, incident, lang, style)
    _, sms_body = await templates.render(session, incident, lang, "sms")
    if round_ != "initial":
        prefix = "REMINDER: " if lang == "en" else "अनुस्मारक: "
        title, sms_body = prefix + title, prefix + sms_body
    data = {"type": "alert", "delivery_id": delivery.id, "incident_id": incident.id, "round": round_}
    attempts: list[NotificationAttempt] = []
    channels: list[str] = []
    base = f"d:{delivery.id}:{round_}"

    if resident.user_id and resident.has_smartphone and "feature_phone" not in resident.needs:
        channels.append("in_app")
        attempts.append(
            await queue(
                session, ctx, incident=incident, channel="in_app", recipient_kind="resident",
                recipient_is_demo=resident.is_demo, key=f"{base}:in_app", title=title, body=body,
                recipient_user_id=resident.user_id, data=data, delivery_id=delivery.id, round_=round_,
            )
        )
        tokens = (
            await session.execute(
                select(DeviceRegistration.fcm_token).where(DeviceRegistration.user_id == resident.user_id)
            )
        ).scalars().all()
        for token in tokens:
            channels.append("push")
            attempts.append(
                await queue(
                    session, ctx, incident=incident, channel="push", recipient_kind="resident",
                    recipient_is_demo=resident.is_demo, key=f"{base}:push:{_token_key(token)}",
                    title=title, body=body, recipient_user_id=resident.user_id,
                    data={**data, "token": token}, delivery_id=delivery.id, round_=round_,
                )
            )
    if resident.phone and await _sms_consent(session, resident.id, ctx.now()):
        channels.append("sms")
        attempts.append(
            await queue(
                session, ctx, incident=incident, channel="sms", recipient_kind="resident",
                recipient_is_demo=resident.is_demo, key=f"{base}:sms", body=sms_body,
                recipient_user_id=resident.user_id, phone=resident.phone, data=data,
                delivery_id=delivery.id, round_=round_,
            )
        )
    delivery.channels = sorted(set((delivery.channels or []) + channels))
    return attempts


async def notify_user(
    session: AsyncSession,
    ctx: AppContext,
    incident: Incident,
    user: User,
    *,
    recipient_kind: str,
    key: str,
    title: str,
    body: str,
    sms_body: str | None = None,
    data: dict | None = None,
    delivery_id: str | None = None,
    task_id: str | None = None,
) -> list[NotificationAttempt]:
    """Notify a caregiver / neighbour / volunteer on app + push + SMS."""
    out = [
        await queue(
            session, ctx, incident=incident, channel="in_app", recipient_kind=recipient_kind,
            recipient_is_demo=user.is_demo, key=f"{key}:in_app", title=title, body=body,
            recipient_user_id=user.id, data=data, delivery_id=delivery_id, task_id=task_id,
        )
    ]
    tokens = (
        await session.execute(select(DeviceRegistration.fcm_token).where(DeviceRegistration.user_id == user.id))
    ).scalars().all()
    for token in tokens:
        out.append(
            await queue(
                session, ctx, incident=incident, channel="push", recipient_kind=recipient_kind,
                recipient_is_demo=user.is_demo, key=f"{key}:push:{_token_key(token)}", title=title,
                body=body, recipient_user_id=user.id, data={**(data or {}), "token": token},
                delivery_id=delivery_id, task_id=task_id,
            )
        )
    if user.phone and sms_body:
        out.append(
            await queue(
                session, ctx, incident=incident, channel="sms", recipient_kind=recipient_kind,
                recipient_is_demo=user.is_demo, key=f"{key}:sms", body=sms_body,
                recipient_user_id=user.id, phone=user.phone, data=data, delivery_id=delivery_id,
                task_id=task_id,
            )
        )
    emit(session, "notification.created", audience=[user.id], incident_id=incident.id, task_id=task_id)
    return out


async def flush_outbox(ctx: AppContext, limit: int = 100) -> int:
    """Send queued messages. Safe to run from several workers at once. Returns messages processed."""
    now = ctx.now()
    async with db.session() as session:
        q = (
            select(NotificationAttempt)
            .where(
                NotificationAttempt.status == "queued",
                (NotificationAttempt.next_retry_at.is_(None)) | (NotificationAttempt.next_retry_at <= now),
            )
            .order_by(NotificationAttempt.created_at)
            .limit(limit)
        )
        if db.is_postgres:
            q = q.with_for_update(skip_locked=True)
        batch = (await session.execute(q)).scalars().all()
        for a in batch:
            a.next_retry_at = now + LEASE  # lease: other workers skip it until we finish
        claimed = [(a.id, a.channel, a.recipient_phone, a.title, a.body, dict(a.data or {})) for a in batch]
        await session.commit()

    results = []
    for att_id, channel, phone, title, body, data in claimed:
        is_demo = bool(data.pop("demo", False))
        if channel == "sms":
            gateway = ctx.sms
            if is_demo and phone not in ctx.settings.demo_sms_allowed:
                gateway = ctx.extras["sim_sms"]  # fictional numbers never reach a real gateway
            r = await gateway.send(phone, body or "")
            results.append((att_id, r.ok, r.provider, r.provider_message_id, r.error))
        elif channel == "push":
            token = data.pop("token", "")
            r = await ctx.fcm.send(token, title or "AapdaSaathi", body or "", {k: str(v) for k, v in data.items()})
            results.append((att_id, r.ok, "fcm", r.provider_message_id, r.error))

    if not results:
        return 0
    async with db.session() as session:
        touched_deliveries: set[str] = set()
        for att_id, ok, provider, pmid, error in results:
            a = await session.get(NotificationAttempt, att_id)
            if a is None or a.status != "queued":
                continue
            a.provider = provider
            if ok:
                a.status, a.provider_message_id, a.sent_at, a.error = "sent", pmid, ctx.now(), None
                a.next_retry_at = None
            else:
                a.retries += 1
                a.error = error
                if a.retries >= ctx.settings.notification_max_retries or error in (
                    "FCM not configured",
                    "httpSMS not configured",
                ):
                    a.status, a.next_retry_at = "failed", None
                else:
                    a.next_retry_at = ctx.now() + timedelta(seconds=10 * 2 ** a.retries)
            if a.delivery_id and a.recipient_kind == "resident":
                touched_deliveries.add(a.delivery_id)
        for delivery_id in touched_deliveries:
            await refresh_reachability(session, ctx, delivery_id)
        await commit(session, ctx.bus)
    return len(results)


async def refresh_reachability(session: AsyncSession, ctx: AppContext, delivery_id: str) -> None:
    """NO_REPLY → UNREACHABLE when every external channel finally failed and the app never showed it."""
    from app.audit.log import timeline
    from app.core import SYSTEM

    d = await session.get(Delivery, delivery_id)
    if d is None or d.status != "NO_REPLY":
        return
    attempts = (
        await session.execute(
            select(NotificationAttempt).where(
                NotificationAttempt.delivery_id == delivery_id,
                NotificationAttempt.recipient_kind == "resident",
            )
        )
    ).scalars().all()
    external = [a for a in attempts if a.channel in ("sms", "push")]
    has_app = any(a.channel == "in_app" and a.status == "sent" for a in attempts)
    if not external or any(a.status in ("queued", "sent") for a in external):
        return
    if has_app and d.seen_at is not None:
        return
    if all(a.status == "blocked" for a in external):
        return
    d.status = "UNREACHABLE"
    d.version += 1
    timeline(
        session, d.incident_id, "unreachable",
        "All external alert channels failed (" + ", ".join(sorted({a.channel for a in external})) + ")",
        actor=SYSTEM, delivery_id=d.id, resident_id=d.resident_id, at=ctx.now(),
    )
    emit(session, "delivery.updated", incident_id=d.incident_id, delivery_id=d.id, status=d.status)
