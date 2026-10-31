"""Password/OTP hashing and JWT handling. Roles always come from the database, never the token."""

from __future__ import annotations

import base64
import hashlib
import hmac
import secrets
from datetime import timedelta

import jwt

from app.config import Settings
from app.db import utcnow

_SCRYPT = {"n": 2**14, "r": 8, "p": 1, "dklen": 32}


def hash_password(password: str) -> str:
    salt = secrets.token_bytes(16)
    dk = hashlib.scrypt(password.encode(), salt=salt, **_SCRYPT)
    return "scrypt$" + base64.b64encode(salt).decode() + "$" + base64.b64encode(dk).decode()


def verify_password(password: str, stored: str | None) -> bool:
    if not stored or not stored.startswith("scrypt$"):
        return False
    _, salt_b64, dk_b64 = stored.split("$")
    dk = hashlib.scrypt(password.encode(), salt=base64.b64decode(salt_b64), **_SCRYPT)
    return hmac.compare_digest(dk, base64.b64decode(dk_b64))


def hash_otp(phone: str, code: str, secret: str) -> str:
    return hmac.new(secret.encode(), f"{phone}:{code}".encode(), hashlib.sha256).hexdigest()


def generate_otp() -> str:
    return f"{secrets.randbelow(1_000_000):06d}"


def issue_token(settings: Settings, user_id: str) -> tuple[str, int]:
    ttl = settings.access_token_minutes * 60
    now = utcnow()
    payload = {"sub": user_id, "iat": now, "exp": now + timedelta(seconds=ttl), "iss": "aapdasaathi"}
    return jwt.encode(payload, settings.jwt_secret, algorithm="HS256"), ttl


def decode_token(settings: Settings, token: str) -> dict:
    """Returns {'sub': ..., 'kind': 'local'|'supabase'}. Raises jwt.PyJWTError on failure."""
    if settings.auth_mode == "supabase":
        claims = jwt.decode(token, settings.supabase_jwt_secret, algorithms=["HS256"], audience="authenticated")
        return {"sub": claims["sub"], "kind": "supabase"}
    claims = jwt.decode(token, settings.jwt_secret, algorithms=["HS256"], issuer="aapdasaathi")
    return {"sub": claims["sub"], "kind": "local"}
