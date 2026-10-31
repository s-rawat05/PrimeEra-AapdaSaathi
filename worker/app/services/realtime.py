"""In-process realtime event bus feeding the /api/v1/realtime WebSocket.

Events are published only AFTER the database transaction commits (see `emit` / `commit`), so
clients never see a change that was rolled back. Clients treat events as "refetch" hints and
always read state from the API — the database stays the single source of truth.

Multi-instance deployments should replace this with Supabase Realtime or Postgres LISTEN/NOTIFY
(documented in docs/architecture.md); the publish interface stays the same.
"""

from __future__ import annotations

import asyncio
import secrets
import time
from dataclasses import dataclass

from sqlalchemy.ext.asyncio import AsyncSession

OPS_ROLES = {"admin", "operator"}


@dataclass
class Subscriber:
    user_id: str
    role: str
    queue: asyncio.Queue


class EventBus:
    def __init__(self) -> None:
        self._subs: set[Subscriber] = set()
        self._tickets: dict[str, tuple[str, str, float]] = {}

    def __hash__(self):  # pragma: no cover
        return id(self)

    def subscribe(self, user_id: str, role: str) -> Subscriber:
        sub = Subscriber(user_id, role, asyncio.Queue(maxsize=500))
        self._subs.add(sub)
        return sub

    def unsubscribe(self, sub: Subscriber) -> None:
        self._subs.discard(sub)

    def publish(self, event: dict) -> None:
        audience = set(event.get("audience") or [])
        for sub in list(self._subs):
            if sub.role in OPS_ROLES or sub.user_id in audience:
                payload = {k: v for k, v in event.items() if k != "audience"}
                try:
                    sub.queue.put_nowait(payload)
                except asyncio.QueueFull:
                    pass  # slow client; it will resync on its next refetch

    # One-time tickets keep long-lived JWTs out of WebSocket URLs.
    def issue_ticket(self, user_id: str, role: str, ttl: float = 60.0) -> str:
        now = time.monotonic()
        self._tickets = {k: v for k, v in self._tickets.items() if v[2] > now}
        ticket = secrets.token_urlsafe(24)
        self._tickets[ticket] = (user_id, role, now + ttl)
        return ticket

    def redeem_ticket(self, ticket: str) -> tuple[str, str] | None:
        entry = self._tickets.pop(ticket, None)
        if not entry or entry[2] < time.monotonic():
            return None
        return entry[0], entry[1]

    @property
    def subscriber_count(self) -> int:
        return len(self._subs)


def emit(session: AsyncSession, event_type: str, audience: list[str | None] | None = None, **data) -> None:
    """Queue an event on the session; it is published after a successful commit."""
    pending = session.info.setdefault("pending_events", [])
    pending.append({"type": event_type, "audience": [a for a in (audience or []) if a], **data})


async def commit(session: AsyncSession, bus: EventBus) -> None:
    await session.commit()
    events = session.info.pop("pending_events", [])
    for e in events:
        bus.publish(e)
