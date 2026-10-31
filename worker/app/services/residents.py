"""Resident registry: registration, consent (90-day validity), trusted contacts, withdrawal, expiry."""

from __future__ import annotations

from datetime import timedelta

from sqlalchemy import delete, select
from sqlalchemy.ext.asyncio import AsyncSession

from app import schemas as S
from app.audit.log import audit
from app.core import Actor, AppContext, Conflict, DomainError, NotFound
from app.integrations.sms_gateway import normalize_phone
from app.models import CaregiverLink, ConsentRecord, Resident, ResidentLocation, User, Ward


def coarse(v: float | None) -> float | None:
    """≈110 m grid. Exact coordinates are stored only in resident_locations."""
    return None if v is None else round(v, 3)


async def _get_or_create_contact(session: AsyncSession, c: S.TrustedContactIn, is_demo: bool) -> User:
    phone = normalize_phone(c.phone)
    user = await session.scalar(select(User).where(User.phone == phone))
    if user is None:
        user = User(full_name=c.full_name, phone=phone, role="caregiver", language="hi", is_demo=is_demo)
        session.add(user)
        await session.flush()
    return user


async def register(
    session: AsyncSession,
    ctx: AppContext,
    data: S.RegistrationIn,
    *,
    user: User | None,
    phone: str | None,
    registered_via: str,
    actor: Actor,
    is_demo: bool,
) -> Resident:
    ward = await session.get(Ward, data.ward_id)
    if ward is None:
        raise NotFound("Ward")
    if ward.is_demo != is_demo:
        raise DomainError("ward_mismatch", "Demo residents must be registered in demo wards", 422)
    if data.granted_by == "guardian" and not data.guardian_name:
        raise DomainError("guardian_required", "Guardian name is required for guardian consent", 422)
    if user is not None:
        existing = await session.scalar(select(Resident).where(Resident.user_id == user.id))
        if existing is not None:
            raise Conflict("already_registered", "This account already has a resident profile")
    norm_phone = normalize_phone(phone) if phone else None
    now = ctx.now()
    needs = sorted(set(data.needs))
    r = Resident(
        user_id=user.id if user else None,
        full_name=data.full_name,
        phone=norm_phone,
        ward_id=ward.id,
        language=data.language,
        needs=needs,
        lives_alone=data.lives_alone,
        has_smartphone=data.has_smartphone and "feature_phone" not in needs,
        coarse_lat=coarse(data.lat) if data.lat is not None else ward.centroid_lat,
        coarse_lng=coarse(data.lng) if data.lng is not None else ward.centroid_lng,
        registered_via=registered_via,
        reverify_due_at=now + timedelta(days=ctx.settings.consent_validity_days),
        is_demo=is_demo,
        created_at=now,
    )
    session.add(r)
    await session.flush()
    if data.consent_location and data.lat is not None and data.lng is not None:
        session.add(ResidentLocation(resident_id=r.id, lat=data.lat, lng=data.lng, address_text=data.address_text,
                                     landmark=data.landmark, source=registered_via))
    expires = now + timedelta(days=ctx.settings.consent_validity_days)
    for ctype, granted in (("registry", True), ("location", data.consent_location),
                           ("caregiver_share", data.consent_caregiver_share)):
        session.add(ConsentRecord(resident_id=r.id, consent_type=ctype, granted=granted, granted_by=data.granted_by,
                                  guardian_name=data.guardian_name, recorded_by_user_id=actor.user_id,
                                  granted_at=now, expires_at=expires))
    for c in data.trusted_contacts:
        contact = await _get_or_create_contact(session, c, is_demo)
        session.add(CaregiverLink(caregiver_user_id=contact.id, resident_id=r.id, relationship=c.relationship,
                                  can_view_location=c.can_view_location and data.consent_caregiver_share))
    if user is not None and user.role != "resident" and user.role not in ("admin", "operator"):
        user.role = "resident"
    audit(session, actor, "resident.register", "resident", r.id,
          after={"ward": ward.code, "needs": needs, "via": registered_via, "granted_by": data.granted_by})
    return r


async def update_profile(session: AsyncSession, ctx: AppContext, r: Resident, data: S.ResidentPatch,
                         actor: Actor) -> Resident:
    before = {"needs": list(r.needs or []), "language": r.language}
    if data.language is not None:
        r.language = data.language
    if data.needs is not None:
        r.needs = sorted(set(data.needs))
        if "feature_phone" in r.needs:
            r.has_smartphone = False
    if data.lives_alone is not None:
        r.lives_alone = data.lives_alone
    if data.has_smartphone is not None:
        r.has_smartphone = data.has_smartphone and "feature_phone" not in (r.needs or [])
    if data.lat is not None and data.lng is not None:
        consent = await _active_consent(session, ctx, r.id, "location")
        if consent is None:
            raise DomainError("location_consent_required", "Location consent is required to store a location", 422)
        loc = await session.scalar(select(ResidentLocation).where(ResidentLocation.resident_id == r.id))
        if loc is None:
            session.add(ResidentLocation(resident_id=r.id, lat=data.lat, lng=data.lng, address_text=data.address_text,
                                         landmark=data.landmark, source="self"))
        else:
            loc.lat, loc.lng = data.lat, data.lng
            loc.address_text, loc.landmark = data.address_text or loc.address_text, data.landmark or loc.landmark
        r.coarse_lat, r.coarse_lng = coarse(data.lat), coarse(data.lng)
    audit(session, actor, "resident.update", "resident", r.id, before=before,
          after={"needs": list(r.needs or []), "language": r.language})
    return r


async def _active_consent(session: AsyncSession, ctx: AppContext, resident_id: str, ctype: str):
    return await session.scalar(
        select(ConsentRecord).where(
            ConsentRecord.resident_id == resident_id, ConsentRecord.consent_type == ctype,
            ConsentRecord.granted.is_(True), ConsentRecord.withdrawn_at.is_(None),
            ConsentRecord.expires_at > ctx.now(),
        ).order_by(ConsentRecord.granted_at.desc()).limit(1)
    )


async def withdraw(session: AsyncSession, ctx: AppContext, r: Resident, actor: Actor, reason: str | None) -> Resident:
    """Consent withdrawal stops future alerts and deletes the exact location immediately."""
    now = ctx.now()
    for c in (await session.execute(select(ConsentRecord).where(
            ConsentRecord.resident_id == r.id, ConsentRecord.withdrawn_at.is_(None)))).scalars().all():
        c.withdrawn_at = now
    await session.execute(delete(ResidentLocation).where(ResidentLocation.resident_id == r.id))
    r.registration_status = "withdrawn"
    audit(session, actor, "resident.consent_withdrawn", "resident", r.id, reason=reason)
    return r


async def reverify(session: AsyncSession, ctx: AppContext, r: Resident, actor: Actor, granted_by: str = "self",
                   location: bool | None = None) -> Resident:
    now = ctx.now()
    expires = now + timedelta(days=ctx.settings.consent_validity_days)
    prev_loc = await _active_consent(session, ctx, r.id, "location")
    for ctype, granted in (("registry", True), ("location", prev_loc is not None if location is None else location)):
        session.add(ConsentRecord(resident_id=r.id, consent_type=ctype, granted=granted, granted_by=granted_by,
                                  recorded_by_user_id=actor.user_id, granted_at=now, expires_at=expires))
    r.registration_status = "active"
    r.reverify_due_at = expires
    audit(session, actor, "resident.reverified", "resident", r.id)
    return r


async def expire_overdue(session: AsyncSession, ctx: AppContext) -> int:
    """Mark registrations past their 90-day re-verification date as expired (no alerts until renewed)."""
    rows = (await session.execute(select(Resident).where(
        Resident.registration_status == "active", Resident.reverify_due_at.is_not(None),
        Resident.reverify_due_at < ctx.now()))).scalars().all()
    for r in rows:
        r.registration_status = "expired"
        audit(session, Actor.system("retention"), "resident.registration_expired", "resident", r.id)
    return len(rows)
