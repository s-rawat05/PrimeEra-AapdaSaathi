"""Audit log (who changed what, and why) and incident timeline (what happened to whom, when)."""

from __future__ import annotations

from sqlalchemy.ext.asyncio import AsyncSession

from app.core import Actor
from app.models import AuditLog, TimelineEvent

_PII_KEYS = {"phone", "password", "password_hash", "lat", "lng", "address_text", "fcm_token", "code"}


def _scrub(d: dict | None) -> dict | None:
    if d is None:
        return None
    return {k: ("[redacted]" if k in _PII_KEYS else v) for k, v in d.items()}


def audit(
    session: AsyncSession,
    actor: Actor,
    action: str,
    entity_type: str,
    entity_id: str | None,
    *,
    reason: str | None = None,
    before: dict | None = None,
    after: dict | None = None,
) -> AuditLog:
    row = AuditLog(
        actor_user_id=actor.user_id,
        actor_role=actor.role or actor.kind,
        action=action,
        entity_type=entity_type,
        entity_id=entity_id,
        reason=reason,
        before=_scrub(before),
        after=_scrub(after),
    )
    session.add(row)
    return row


def timeline(
    session: AsyncSession,
    incident_id: str,
    event_type: str,
    message: str,
    *,
    actor: Actor,
    delivery_id: str | None = None,
    resident_id: str | None = None,
    data: dict | None = None,
    at=None,
) -> TimelineEvent:
    row = TimelineEvent(
        incident_id=incident_id,
        delivery_id=delivery_id,
        resident_id=resident_id,
        event_type=event_type,
        message=message,
        actor_kind=actor.kind,
        actor_user_id=actor.user_id,
        data=data or {},
    )
    if at is not None:
        row.created_at = at
    session.add(row)
    return row
