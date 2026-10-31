"""Authentication, profile and device registration."""

from __future__ import annotations

from datetime import timedelta

from fastapi import APIRouter, Depends
from sqlalchemy import or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app import schemas as S
from app.api.common import finalize
from app.audit.log import audit
from app.auth.deps import actor_of, current_user, get_ctx
from app.auth.security import generate_otp, hash_otp, issue_token, verify_password
from app.core import Actor, AppContext, DomainError, Forbidden
from app.db import get_session
from app.demo.seed import persona_descriptions
from app.integrations.sms_gateway import normalize_phone
from app.models import DeviceRegistration, OtpChallenge, Resident, User, Volunteer
from app.services import views

router = APIRouter(prefix="/auth", tags=["auth"])
me_router = APIRouter(tags=["profile"])


def _token(ctx: AppContext, user: User, new: bool = False) -> S.TokenOut:
    token, ttl = issue_token(ctx.settings, user.id)
    return S.TokenOut(access_token=token, expires_in=ttl, user=views.user_out(user), is_new_user=new)


@router.post("/login", response_model=S.TokenOut, summary="Password login (admin/operator accounts)")
async def login(body: S.LoginIn, session: AsyncSession = Depends(get_session), ctx: AppContext = Depends(get_ctx)):
    ident = body.identifier.strip().lower()
    try:
        phone = normalize_phone(ident)
    except ValueError:
        phone = None
    user = await session.scalar(select(User).where(or_(User.email == ident, User.phone == phone)))
    if user is None or not user.is_active or not verify_password(body.password, user.password_hash):
        raise DomainError("invalid_credentials", "Invalid credentials", 401)
    if user.is_demo and not ctx.settings.demo_mode_enabled:
        raise DomainError("invalid_credentials", "Invalid credentials", 401)
    audit(session, actor_of(user), "auth.login", "user", user.id)
    await session.commit()
    return _token(ctx, user)


@router.post("/otp/request", response_model=S.OtpRequestOut, summary="Send a 6-digit verification code by SMS")
async def otp_request(
    body: S.OtpRequestIn, session: AsyncSession = Depends(get_session), ctx: AppContext = Depends(get_ctx)
):
    if ctx.settings.auth_mode != "local":
        raise DomainError("use_supabase", "OTP is handled by Supabase Auth in this deployment", 400)
    try:
        phone = normalize_phone(body.phone)
    except ValueError as exc:
        raise DomainError("invalid_phone", "Enter a valid mobile number", 422) from exc
    now = ctx.now()
    recent = (
        (
            await session.execute(
                select(OtpChallenge).where(
                    OtpChallenge.phone == phone, OtpChallenge.created_at > now - timedelta(minutes=10)
                )
            )
        )
        .scalars()
        .all()
    )
    if len(recent) >= 5:
        raise DomainError("rate_limited", "Too many codes requested. Try again in 10 minutes.", 429)
    code = generate_otp()
    session.add(
        OtpChallenge(
            phone=phone,
            code_hash=hash_otp(phone, code, ctx.settings.jwt_secret),
            expires_at=now + timedelta(seconds=ctx.settings.otp_ttl_seconds),
            created_at=now,
        )
    )
    user = await session.scalar(select(User).where(User.phone == phone))
    is_demo_number = user is not None and user.is_demo
    gateway = ctx.extras["sim_sms"] if (is_demo_number or ctx.settings.sms_provider == "simulator") else ctx.sms
    result = await gateway.send(phone, f"AapdaSaathi verification code: {code}. Valid 5 minutes. Do not share it.")
    if result.simulated:
        # Simulator only: keep the code retrievable from the demo SMS inbox (never in production).
        ctx.extras.setdefault("sim_inbox", []).append(
            {"to": phone, "body": f"AapdaSaathi code: {code}", "at": now.isoformat()}
        )
        ctx.extras["sim_inbox"] = ctx.extras["sim_inbox"][-200:]
    await session.commit()
    return S.OtpRequestOut(
        sent=result.ok,
        expires_in=ctx.settings.otp_ttl_seconds,
        channel=gateway.name,
        note="Code delivered to the SMS simulator inbox (demo)." if result.simulated else "Code sent by SMS.",
    )


@router.post("/otp/verify", response_model=S.TokenOut, summary="Verify code; creates a resident account if new")
async def otp_verify(
    body: S.OtpVerifyIn, session: AsyncSession = Depends(get_session), ctx: AppContext = Depends(get_ctx)
):
    try:
        phone = normalize_phone(body.phone)
    except ValueError as exc:
        raise DomainError("invalid_phone", "Enter a valid mobile number", 422) from exc
    now = ctx.now()
    ch = await session.scalar(
        select(OtpChallenge)
        .where(
            OtpChallenge.phone == phone,
            OtpChallenge.consumed_at.is_(None),
            OtpChallenge.expires_at > now,
        )
        .order_by(OtpChallenge.created_at.desc())
        .limit(1)
    )
    if ch is None:
        raise DomainError("otp_invalid", "Code expired or not requested", 401)
    ch.attempts += 1
    if ch.attempts > 5:
        ch.consumed_at = now
        await session.commit()
        raise DomainError("otp_locked", "Too many attempts. Request a new code.", 429)
    if ch.code_hash != hash_otp(phone, body.code, ctx.settings.jwt_secret):
        await session.commit()
        raise DomainError("otp_invalid", "Incorrect code", 401)
    user = await session.scalar(select(User).where(User.phone == phone))
    if user is None and not body.full_name:
        await session.commit()  # code stays valid so the user can add their name and resubmit
        raise DomainError("name_required", "Enter your name to create an account", 422)
    ch.consumed_at = now
    new = False
    if user is None:
        user = User(full_name=body.full_name.strip(), phone=phone, role="resident", language="hi", created_at=now)
        session.add(user)
        await session.flush()
        new = True
    if user.role in ("admin", "operator"):
        await session.commit()
        raise Forbidden("Operations accounts must sign in with a password")
    audit(session, actor_of(user), "auth.otp_login", "user", user.id)
    await session.commit()
    return _token(ctx, user, new)


@router.get("/demo-personas", response_model=list[S.DemoPersona], summary="Fictional demo accounts (demo mode only)")
async def demo_personas(session: AsyncSession = Depends(get_session), ctx: AppContext = Depends(get_ctx)):
    if not ctx.settings.demo_mode_enabled:
        return []
    desc = persona_descriptions()
    users = (
        (
            await session.execute(
                select(User).where(User.is_demo.is_(True), User.is_active.is_(True)).order_by(User.role, User.full_name)
            )
        )
        .scalars()
        .all()
    )
    return [
        S.DemoPersona(user_id=u.id, full_name=u.full_name, role=u.role, description=desc.get(u.phone, ""))
        for u in users
    ]


@router.post("/demo-login", response_model=S.TokenOut, summary="Sign in as a fictional demo persona (demo mode only)")
async def demo_login(
    body: S.DemoLoginIn, session: AsyncSession = Depends(get_session), ctx: AppContext = Depends(get_ctx)
):
    if not ctx.settings.demo_mode_enabled:
        raise Forbidden("Demo mode is disabled")
    user = await session.get(User, body.user_id)
    if user is None or not user.is_demo or not user.is_active:
        raise Forbidden("Only fictional demo accounts can use demo login")
    audit(session, Actor("user", user.id, user.role, user.full_name), "auth.demo_login", "user", user.id)
    await session.commit()
    return _token(ctx, user)


@me_router.get("/me", response_model=S.MeOut)
async def me(
    user: User = Depends(current_user), session: AsyncSession = Depends(get_session), ctx: AppContext = Depends(get_ctx)
):
    r = await session.scalar(select(Resident).where(Resident.user_id == user.id))
    v = await session.scalar(select(Volunteer).where(Volunteer.user_id == user.id))
    return S.MeOut(
        user=views.user_out(user),
        resident=await views.resident_out(session, r) if r else None,
        volunteer=await views.volunteer_out(session, v) if v else None,
        demo_mode=ctx.settings.demo_mode_enabled,
        notify_real_residents=ctx.settings.notify_real_residents,
    )


@me_router.patch("/me", response_model=S.UserOut)
async def patch_me(body: S.MePatch, user: User = Depends(current_user), session: AsyncSession = Depends(get_session)):
    if body.language:
        user.language = body.language
        r = await session.scalar(select(Resident).where(Resident.user_id == user.id))
        if r:
            r.language = body.language
    if body.full_name:
        user.full_name = body.full_name
    await session.commit()
    return views.user_out(user)


@me_router.post("/me/devices", status_code=204, summary="Register an FCM token for push alerts")
async def register_device(
    body: S.DeviceIn,
    user: User = Depends(current_user),
    session: AsyncSession = Depends(get_session),
    ctx: AppContext = Depends(get_ctx),
):
    existing = await session.scalar(
        select(DeviceRegistration).where(
            DeviceRegistration.user_id == user.id, DeviceRegistration.fcm_token == body.fcm_token
        )
    )
    if existing:
        existing.last_seen_at = ctx.now()
    else:
        session.add(DeviceRegistration(user_id=user.id, fcm_token=body.fcm_token, platform=body.platform))
    await finalize(session, ctx)


@me_router.post("/realtime/ticket", summary="One-time ticket for the realtime WebSocket")
async def realtime_ticket(user: User = Depends(current_user), ctx: AppContext = Depends(get_ctx)) -> dict:
    return {"ticket": ctx.bus.issue_ticket(user.id, user.role), "expires_in": 60}
