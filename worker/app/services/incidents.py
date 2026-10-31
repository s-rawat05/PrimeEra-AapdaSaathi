"""Incident lifecycle: creation (manual / live CAP / replay / simulation), official updates and
cancellations, delivery fan-out, resend, override and closure."""

from __future__ import annotations

from datetime import timedelta

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.audit.log import audit, timeline
from app.core import SYSTEM, Actor, AppContext, Conflict, DomainError, NotFound
from app.escalation import rules
from app.escalation.engine import activate_delivery
from app.integrations import cap_parser
from app.matching.ward_matcher import WardMatch, match_wards
from app.models import (
    OPEN_DELIVERY_STATUSES,
    CapMessage,
    ConsentRecord,
    Delivery,
    Incident,
    IncidentWard,
    Resident,
    Ward,
)
from app.notifications import dispatcher
from app.repositories.queries import DeliveryCtx, get_delivery_ctx
from app.services.realtime import emit

SOURCE_LABEL = {
    "live": "LIVE official alert",
    "replay": "REPLAY of an official alert (drill)",
    "simulated": "SIMULATED alert (drill)",
    "exercise": "EXERCISE/TEST alert",
    "manual": "Manually created incident",
}

HAZARD_KEYWORDS = [
    ("flood", "Flood"),
    ("cloudburst", "Cloudburst"),
    ("landslide", "Landslide"),
    ("thunder", "Thunderstorm"),
    ("lightning", "Thunderstorm"),
    ("rain", "Heavy Rain"),
    ("earthquake", "Earthquake"),
    ("fire", "Fire"),
    ("snow", "Snowfall"),
    ("avalanche", "Avalanche"),
    ("cyclone", "Cyclone"),
    ("heat", "Heat Wave"),
    ("cold", "Cold Wave"),
]


def hazard_from_event(event: str | None) -> str:
    e = (event or "").lower()
    for key, label in HAZARD_KEYWORDS:
        if key in e:
            return label
    return (event or "Hazard").strip()[:60] or "Hazard"


async def _consented_residents(session: AsyncSession, ward_ids: list[str], is_demo: bool, now) -> tuple[list, int]:
    residents = (
        (
            await session.execute(
                select(Resident).where(
                    Resident.ward_id.in_(ward_ids),
                    Resident.is_demo.is_(is_demo),
                    Resident.registration_status == "active",
                )
            )
        )
        .scalars()
        .all()
    )
    ok, skipped = [], 0
    for r in residents:
        consent = await session.scalar(
            select(ConsentRecord.id)
            .where(
                ConsentRecord.resident_id == r.id,
                ConsentRecord.consent_type == "registry",
                ConsentRecord.granted.is_(True),
                ConsentRecord.withdrawn_at.is_(None),
                ConsentRecord.expires_at > now,
            )
            .limit(1)
        )
        if consent:
            ok.append(r)
        else:
            skipped += 1
    return ok, skipped


async def create_deliveries(session: AsyncSession, ctx: AppContext, inc: Incident, ward_ids: list[str]) -> int:
    now = ctx.now()
    residents, skipped = await _consented_residents(session, ward_ids, inc.is_demo, now)
    if not inc.is_demo and not ctx.settings.notify_real_residents:
        timeline(
            session,
            inc.id,
            "delivery_suppressed",
            f"Resident notifications disabled (NOTIFY_REAL_RESIDENTS=false). {len(residents)} registered "
            "resident(s) in matched wards were NOT notified.",
            actor=SYSTEM,
            at=now,
        )
        return 0
    if skipped:
        timeline(
            session,
            inc.id,
            "consent_skipped",
            f"{skipped} resident(s) skipped: consent missing, withdrawn or expired (re-verification due)",
            actor=SYSTEM,
            at=now,
        )
    created = 0
    # Highest static priority first, so scarce helpers are allocated to those who need them most.
    residents.sort(
        key=lambda r: -rules.priority_score(
            needs=r.needs or [], lives_alone=r.lives_alone, status="NO_REPLY", alerted_at=None, now=now
        ).total
    )
    for r in residents:
        exists = await session.scalar(
            select(Delivery.id).where(Delivery.incident_id == inc.id, Delivery.resident_id == r.id)
        )
        if exists:
            continue
        d = Delivery(incident_id=inc.id, resident_id=r.id, status="PENDING", created_at=now)
        session.add(d)
        await session.flush()
        await activate_delivery(session, ctx, DeliveryCtx(d, inc, r))
        created += 1
    return created


async def create_incident(
    session: AsyncSession,
    ctx: AppContext,
    *,
    title: str,
    hazard_type: str,
    source: str,
    is_demo: bool,
    ward_matches: list[WardMatch],
    actor: Actor,
    severity: str = "Unknown",
    urgency: str = "Unknown",
    certainty: str = "Unknown",
    sent=None,
    effective=None,
    onset=None,
    expires=None,
    headline: str | None = None,
    description: str | None = None,
    instruction: str | None = None,
    area_desc: str | None = None,
    official_url: str | None = None,
    cap_message: CapMessage | None = None,
    cap_sender: str | None = None,
    onset_note: str | None = None,
    demo_session_id: str | None = None,
) -> Incident:
    now = ctx.now()
    if not ward_matches:
        raise DomainError("no_wards", "Incident must cover at least one ward", 422)
    if any(m.ward.is_demo != is_demo for m in ward_matches):
        raise DomainError("ward_mismatch", "Demo incidents may only target demo wards (and vice versa)", 422)
    resolved = rules.resolve_onset(onset, urgency, sent or now)
    mode = rules.select_mode(resolved.onset, now)
    inc = Incident(
        title=title[:300],
        hazard_type=hazard_type,
        source=source,
        is_demo=is_demo,
        demo_session_id=demo_session_id,
        cap_message_id=cap_message.id if cap_message else None,
        cap_identifier=cap_message.identifier if cap_message else None,
        cap_sender=cap_sender,
        severity=severity or "Unknown",
        urgency=urgency or "Unknown",
        certainty=certainty or "Unknown",
        sent=sent,
        effective=effective,
        onset=resolved.onset,
        expires=expires,
        onset_fallback_used=resolved.fallback_used or bool(onset_note),
        onset_fallback_note=onset_note or resolved.note,
        headline=headline,
        description=description,
        instruction=instruction,
        area_desc=area_desc,
        official_url=official_url,
        escalation_mode=mode,
        requires_dispatch_approval=rules.requires_dispatch_approval(severity, mode),
        interval_override_seconds=ctx.settings.demo_escalation_interval_seconds if is_demo else None,
        created_by_user_id=actor.user_id,
        created_at=now,
    )
    session.add(inc)
    await session.flush()
    for m in ward_matches:
        session.add(IncidentWard(incident_id=inc.id, ward_id=m.ward.id, match_method=m.method, match_note=m.note))
    window = int((resolved.onset - now).total_seconds() // 60)
    timeline(
        session,
        inc.id,
        "incident_created",
        f"{SOURCE_LABEL[source]}: {hazard_type}. Mode {mode} — {rules.mode_label(mode)}; "
        f"{'onset in ' + str(window) + ' min' if window > 0 else 'hazard ongoing'}; "
        f"{len(ward_matches)} ward(s) matched ({', '.join(sorted({m.method for m in ward_matches}))}).",
        actor=actor,
        at=now,
        data={"mode": mode, "onset_fallback": inc.onset_fallback_used, "approval": inc.requires_dispatch_approval},
    )
    if actor.user_id:
        audit(session, actor, "incident.create", "incident", inc.id, after={"source": source, "title": title})
    await session.flush()
    n = await create_deliveries(session, ctx, inc, [m.ward.id for m in ward_matches])
    timeline(session, inc.id, "deliveries_created", f"{n} resident alert(s) created", actor=SYSTEM, at=now)
    emit(session, "incident.updated", incident_id=inc.id)
    return inc


async def store_cap_message(
    session: AsyncSession,
    xml: str,
    *,
    feed_url: str | None,
    feed_guid: str | None,
    official_url: str | None,
    is_fixture: bool = False,
    now=None,
) -> tuple[CapMessage, cap_parser.CapAlert, bool]:
    """Parse and persist a CAP message idempotently. Returns (row, parsed, created)."""
    alert = cap_parser.parse_cap(xml)
    existing = await session.scalar(select(CapMessage).where(CapMessage.identifier == alert.identifier))
    if existing is not None:
        return existing, alert, False
    info = alert.primary_info("en")
    row = CapMessage(
        identifier=alert.identifier,
        feed_guid=feed_guid,
        feed_url=feed_url,
        official_url=official_url,
        sender=alert.sender,
        sent=alert.sent,
        status=alert.status,
        msg_type=alert.msg_type,
        references_raw=alert.references_raw,
        event=info.event if info else None,
        severity=info.severity if info else None,
        urgency=info.urgency if info else None,
        certainty=info.certainty if info else None,
        onset=info.onset if info else None,
        expires=info.expires if info else None,
        headline=info.headline if info else None,
        area_desc="; ".join(a.area_desc for a in info.areas) if info else None,
        raw_xml=xml if isinstance(xml, str) else xml.decode("utf-8"),
        parsed=alert.to_dict(),
        is_valid=alert.is_valid,
        validation_errors=alert.validation_errors,
        is_fixture=is_fixture,
    )
    if now is not None:
        row.fetched_at = now
    session.add(row)
    await session.flush()
    for ref in alert.references:
        prev = await session.scalar(select(CapMessage).where(CapMessage.identifier == ref.identifier))
        if prev is not None:
            prev.superseded_by = alert.identifier
    return row, alert, True


def _official_fields(alert: cap_parser.CapAlert) -> dict:
    info = alert.primary_info("en")
    if info is None:
        return {}
    return {
        "hazard_type": hazard_from_event(info.event),
        "severity": info.severity,
        "urgency": info.urgency,
        "certainty": info.certainty,
        "effective": info.effective,
        "onset": info.onset,
        "expires": info.expires,
        "headline": info.headline,
        "description": info.description,
        "instruction": info.instruction,
        "area_desc": "; ".join(a.area_desc for a in info.areas if a.area_desc),
        "official_url": info.web,
    }


async def _incidents_referenced(session: AsyncSession, alert: cap_parser.CapAlert) -> list[Incident]:
    ids = [r.identifier for r in alert.references]
    if not ids:
        return []
    return list(
        (await session.execute(select(Incident).where(Incident.cap_identifier.in_(ids), Incident.status == "active")))
        .scalars()
        .all()
    )


async def apply_live_cap(
    session: AsyncSession, ctx: AppContext, row: CapMessage, alert: cap_parser.CapAlert
) -> Incident | None:
    """Turn a live CAP message into incident changes. Live incidents never notify real residents
    unless NOTIFY_REAL_RESIDENTS=true (enforced again in the notification outbox)."""
    if alert.status in ("Test", "System", "Draft") or not alert.is_valid:
        return None
    now = ctx.now()
    if alert.msg_type == "Cancel":
        for inc in await _incidents_referenced(session, alert):
            await finish_incident(session, ctx, inc, "cancelled", f"Officially cancelled by {alert.sender}", SYSTEM)
        return None
    fields = _official_fields(alert)
    if alert.msg_type == "Update":
        prior = await _incidents_referenced(session, alert)
        if prior:
            for inc in prior:
                before = {"severity": inc.severity, "onset": str(inc.onset), "expires": str(inc.expires)}
                for k in (
                    "severity",
                    "urgency",
                    "certainty",
                    "expires",
                    "headline",
                    "description",
                    "instruction",
                    "area_desc",
                    "effective",
                ):
                    if fields.get(k) is not None:
                        setattr(inc, k, fields[k])
                if fields.get("onset"):
                    inc.onset, inc.onset_fallback_used, inc.onset_fallback_note = fields["onset"], False, None
                inc.cap_identifier, inc.cap_message_id = alert.identifier, row.id
                inc.escalation_mode = rules.select_mode(inc.onset, now)
                inc.requires_dispatch_approval = inc.requires_dispatch_approval or rules.requires_dispatch_approval(
                    inc.severity, inc.escalation_mode
                )
                timeline(
                    session,
                    inc.id,
                    "official_update",
                    f"Official update from {alert.sender} applied",
                    actor=SYSTEM,
                    at=now,
                    data={"before": before},
                )
                emit(session, "incident.updated", incident_id=inc.id)
            return prior[0]
    if alert.msg_type not in ("Alert", "Update"):
        return None
    matches = await match_wards(
        session,
        polygons=cap_parser.area_polygons(alert),
        circles=[c for i in alert.infos for a in i.areas for c in a.circles],
        lgd_codes=cap_parser.lgd_district_codes(alert),
        is_demo=False,
    )
    if not matches:
        return None
    return await create_incident(
        session,
        ctx,
        title=fields.get("headline") or fields.get("hazard_type") or "Official alert",
        source="exercise" if alert.status == "Exercise" else "live",
        is_demo=False,
        ward_matches=matches,
        actor=SYSTEM,
        sent=alert.sent,
        cap_message=row,
        cap_sender=alert.sender,
        official_url=fields.pop("official_url", None) or row.official_url,
        **{k: v for k, v in fields.items() if k != "official_url"},
    )


async def replay_into_demo(
    session: AsyncSession,
    ctx: AppContext,
    row: CapMessage,
    *,
    ward_ids: list[str],
    onset_in_minutes: int,
    source: str,
    actor: Actor,
    demo_session_id: str | None = None,
) -> Incident:
    """Replay an official (or fixture) CAP message into fictional demo wards.
    Official text is copied unchanged; only timing is shifted, and that is labelled."""
    if source not in ("replay", "simulated"):
        raise DomainError("bad_source", "source must be replay or simulated", 422)
    alert = cap_parser.parse_cap(row.raw_xml)
    fields = _official_fields(alert)
    wards = list((await session.execute(select(Ward).where(Ward.id.in_(ward_ids)))).scalars().all())
    if not wards or any(not w.is_demo for w in wards):
        raise DomainError("demo_wards_only", "Replays may only target demo wards", 422)
    now = ctx.now()
    official_onset = fields.get("onset")
    onset = now + timedelta(minutes=onset_in_minutes)
    note = (
        f"DRILL TIMING: onset set to now + {onset_in_minutes} min for this {source}. "
        f"Official onset was {official_onset.isoformat() if official_onset else 'not stated'}."
    )
    matches = [WardMatch(w, "manual", f"{source.title()} into fictional demo ward") for w in wards]
    return await create_incident(
        session,
        ctx,
        title=f"[{source.upper()}] " + (fields.get("headline") or fields.get("hazard_type") or "Alert"),
        source=source,
        is_demo=True,
        ward_matches=matches,
        actor=actor,
        sent=alert.sent,
        cap_message=row,
        cap_sender=alert.sender,
        onset_note=note,
        demo_session_id=demo_session_id,
        hazard_type=fields.get("hazard_type", "Hazard"),
        severity=fields.get("severity", "Unknown"),
        urgency=fields.get("urgency", "Unknown"),
        certainty=fields.get("certainty", "Unknown"),
        effective=fields.get("effective"),
        onset=onset,
        expires=now + timedelta(hours=6),
        headline=fields.get("headline"),
        description=fields.get("description"),
        instruction=fields.get("instruction"),
        area_desc=fields.get("area_desc"),
        official_url=row.official_url,
    )


async def finish_incident(
    session: AsyncSession, ctx: AppContext, inc: Incident, status: str, note: str, actor: Actor
) -> Incident:
    from app.dispatch import service as dispatch

    if inc.status != "active":
        raise Conflict("already_closed", f"Incident is already {inc.status}")
    now = ctx.now()
    deliveries = (await session.execute(select(Delivery).where(Delivery.incident_id == inc.id))).scalars().all()
    for d in deliveries:
        res = await session.get(Resident, d.resident_id)
        await dispatch.cancel_open_tasks(
            session, ctx, DeliveryCtx(d, inc, res), reason=f"incident {status}", actor=actor
        )
        d.next_action_at = None
    inc.status, inc.closed_at, inc.closed_by_user_id, inc.close_note = status, now, actor.user_id, note
    timeline(session, inc.id, f"incident_{status}", f"Incident {status}: {note}", actor=actor, at=now)
    if actor.user_id:
        audit(session, actor, f"incident.{status}", "incident", inc.id, reason=note)
    emit(session, "incident.updated", incident_id=inc.id)
    return inc


async def resend(session: AsyncSession, ctx: AppContext, delivery_id: str, actor: Actor) -> Delivery:
    dc = await get_delivery_ctx(session, delivery_id)
    if dc.incident.status != "active":
        raise Conflict("incident_closed", "Incident is not active")
    if dc.delivery.status == "SAFE":
        raise Conflict("already_safe", "Resident is already confirmed safe")
    n = dc.delivery.reminders_sent + 1
    await dispatcher.alert_resident(session, ctx, dc.incident, dc.delivery, dc.resident, f"resend-{n}")
    dc.delivery.reminders_sent = n
    if dc.delivery.status == "UNREACHABLE":
        dc.delivery.status = "NO_REPLY"
    dc.delivery.version += 1
    audit(session, actor, "delivery.resend", "delivery", delivery_id)
    timeline(
        session,
        dc.incident.id,
        "resend",
        f"Operator re-sent the alert (#{n})",
        actor=actor,
        delivery_id=delivery_id,
        resident_id=dc.resident.id,
        at=ctx.now(),
    )
    emit(
        session, "delivery.updated", audience=[dc.resident.user_id], incident_id=dc.incident.id, delivery_id=delivery_id
    )
    return dc.delivery


async def override_status(
    session: AsyncSession, ctx: AppContext, delivery_id: str, status: str, reason: str, actor: Actor
) -> Delivery:
    from app.services.responses import apply_status

    if not reason or len(reason.strip()) < 5:
        raise DomainError("reason_required", "A reason (at least 5 characters) is required", 422)
    if status not in ("SAFE", "HELP", "NO_REPLY", "UNREACHABLE"):
        raise DomainError("invalid_status", "Invalid status", 422)
    dc = await get_delivery_ctx(session, delivery_id)
    before = {"status": dc.delivery.status}
    if status in ("SAFE", "HELP"):
        await apply_status(session, ctx, dc, status, channel="operator", actor=actor, note=reason)
    else:
        if dc.incident.status != "active":
            raise Conflict("incident_closed", "Incident is not active")
        dc.delivery.status = status
        dc.delivery.resolved_at = dc.delivery.resolved_by = None
        dc.delivery.needs_operator = True
        dc.delivery.version += 1
        timeline(
            session,
            dc.incident.id,
            "override",
            f"Operator set status to {status}: {reason}",
            actor=actor,
            delivery_id=delivery_id,
            resident_id=dc.resident.id,
            at=ctx.now(),
        )
        emit(session, "delivery.updated", incident_id=dc.incident.id, delivery_id=delivery_id)
    dc.delivery.override_reason = reason
    audit(
        session,
        actor,
        "delivery.override",
        "delivery",
        delivery_id,
        reason=reason,
        before=before,
        after={"status": status},
    )
    return dc.delivery


async def get_incident(session: AsyncSession, incident_id: str) -> Incident:
    inc = await session.get(Incident, incident_id)
    if inc is None:
        raise NotFound("Incident")
    return inc


def is_open(status: str) -> bool:
    return status in OPEN_DELIVERY_STATUSES
