"""Shared runtime context, actors and domain errors."""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime, timedelta

from app.config import Settings
from app.db import utcnow


class Clock:
    """Injectable clock so escalation timing can be tested deterministically."""

    def now(self) -> datetime:
        return utcnow()


class FrozenClock(Clock):
    def __init__(self, start: datetime) -> None:
        self._now = start

    def now(self) -> datetime:
        return self._now

    def advance(self, **kwargs) -> datetime:
        self._now = self._now + timedelta(**kwargs)
        return self._now


@dataclass(frozen=True)
class Actor:
    kind: str  # user | system | sms
    user_id: str | None = None
    role: str | None = None
    label: str = "system"

    @staticmethod
    def system(label: str = "system") -> Actor:
        return Actor("system", None, None, label)


SYSTEM = Actor.system()


class DomainError(Exception):
    def __init__(self, code: str, message: str, status: int = 400) -> None:
        super().__init__(message)
        self.code = code
        self.message = message
        self.status = status


class NotFound(DomainError):
    def __init__(self, what: str) -> None:
        super().__init__("not_found", f"{what} not found", 404)


class Forbidden(DomainError):
    def __init__(self, message: str = "Not permitted") -> None:
        super().__init__("forbidden", message, 403)


class Conflict(DomainError):
    def __init__(self, code: str, message: str) -> None:
        super().__init__(code, message, 409)


@dataclass
class AppContext:
    settings: Settings
    clock: Clock
    sms: object  # SmsGateway
    fcm: object  # FcmGateway
    bus: object  # EventBus
    extras: dict = field(default_factory=dict)

    def now(self) -> datetime:
        return self.clock.now()
