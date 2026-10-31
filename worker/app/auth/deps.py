"""FastAPI dependencies: current user, role enforcement, shared context, idempotency."""

from __future__ import annotations

from collections.abc import Callable

import jwt
from fastapi import Depends, Header, Request
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth.security import decode_token
from app.core import Actor, AppContext, DomainError, Forbidden
from app.db import get_session
from app.models import IdempotencyKey, User


def get_ctx(request: Request) -> AppContext:
    return request.app.state.ctx


async def current_user(
    request: Request,
    session: AsyncSession = Depends(get_session),
    authorization: str | None = Header(default=None),
) -> User:
    if not authorization or not authorization.lower().startswith("bearer "):
        raise DomainError("unauthenticated", "Missing bearer token", 401)
    ctx: AppContext = request.app.state.ctx
    try:
        claims = decode_token(ctx.settings, authorization[7:])
    except jwt.PyJWTError:
        raise DomainError("unauthenticated", "Invalid or expired token", 401) from None
    if claims["kind"] == "supabase":
        user = await session.scalar(select(User).where(User.auth_user_id == claims["sub"]))
    else:
        user = await session.get(User, claims["sub"])
    if user is None or not user.is_active:
        raise DomainError("unauthenticated", "Account not found or disabled", 401)
    if user.is_demo and not ctx.settings.demo_mode_enabled:
        raise DomainError("unauthenticated", "Demo accounts are disabled on this deployment", 401)
    return user


def actor_of(user: User) -> Actor:
    return Actor("user", user.id, user.role, user.full_name)


def require_roles(*roles: str) -> Callable:
    async def _dep(user: User = Depends(current_user)) -> User:
        if user.role not in roles:
            raise Forbidden(f"Requires role: {', '.join(roles)}")
        return user

    return _dep


OPS = ("admin", "operator")
ops_user = require_roles(*OPS)
admin_user = require_roles("admin")


async def idempotent_replay(session: AsyncSession, user: User, key: str | None, endpoint: str) -> dict | None:
    if not key:
        return None
    row = await session.scalar(
        select(IdempotencyKey).where(IdempotencyKey.user_id == user.id, IdempotencyKey.key == key)
    )
    if row is None:
        return None
    if row.endpoint != endpoint:
        raise DomainError("idempotency_conflict", "Idempotency-Key reused for a different request", 409)
    return row.response


def remember_idempotent(session: AsyncSession, user: User, key: str | None, endpoint: str, response: dict) -> None:
    if key:
        session.add(IdempotencyKey(user_id=user.id, key=key[:100], endpoint=endpoint, response=response))
