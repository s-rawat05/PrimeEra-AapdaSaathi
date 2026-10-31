"""SACHET (NDMA) public CAP feed ingestion.

Feed listing: https://sachet.ndma.gov.in/CapFeed — the Uttarakhand feed URL used by default
(rss_uttarakhand.xml) was taken from that official listing and its own atom:link self reference.

- Conditional GET with If-None-Match / If-Modified-Since; 304 = nothing new.
- Connect/read timeouts; exponential backoff persisted in feed_state (survives restarts).
- Each RSS <guid> is fetched once (idempotent); raw CAP XML stored unchanged in cap_messages.
- Network I/O happens outside database transactions.
"""

from __future__ import annotations

import logging
from datetime import timedelta

import feedparser
import httpx
from sqlalchemy import select

from app.core import AppContext
from app.db import db
from app.integrations.cap_parser import CapParseError
from app.models import CapMessage, FeedState
from app.services import incidents
from app.services.realtime import commit, emit

log = logging.getLogger(__name__)
MAX_NEW_ITEMS_PER_POLL = 30
USER_AGENT = "AapdaSaathi/1.0 (+https://github.com/; disaster-response research prototype)"


def _client(ctx: AppContext) -> httpx.AsyncClient:
    s = ctx.settings
    timeout = httpx.Timeout(s.feed_read_timeout, connect=s.feed_connect_timeout)
    return httpx.AsyncClient(timeout=timeout, headers={"User-Agent": USER_AGENT}, follow_redirects=True)


async def _load_state(url: str) -> dict:
    async with db.session() as session:
        st = await session.get(FeedState, url)
        if st is None:
            st = FeedState(url=url)
            session.add(st)
            await session.commit()
        return {
            "etag": st.etag,
            "last_modified": st.last_modified,
            "next_fetch_at": st.next_fetch_at,
            "failures": st.consecutive_failures,
        }


async def _save_state(ctx: AppContext, url: str, **changes) -> None:
    async with db.session() as session:
        st = await session.get(FeedState, url)
        for k, v in changes.items():
            setattr(st, k, v)
        emit(session, "feed.updated", url=url)
        await commit(session, ctx.bus)


async def poll_feed(ctx: AppContext, url: str, *, force: bool = False, client: httpx.AsyncClient | None = None) -> dict:
    now = ctx.now()
    state = await _load_state(url)
    if not force and state["next_fetch_at"] and state["next_fetch_at"] > now:
        return {"url": url, "skipped": True, "next_fetch_at": state["next_fetch_at"].isoformat()}

    headers = {}
    if state["etag"]:
        headers["If-None-Match"] = state["etag"]
    if state["last_modified"]:
        headers["If-Modified-Since"] = state["last_modified"]

    own = client is None
    client = client or _client(ctx)
    try:
        try:
            resp = await client.get(url, headers=headers)
        except httpx.HTTPError as exc:
            return await _failure(ctx, url, state["failures"], f"{type(exc).__name__}", None)
        if resp.status_code == 304:
            await _save_state(
                ctx,
                url,
                last_fetch_at=now,
                last_success_at=now,
                last_status_code=304,
                last_error=None,
                consecutive_failures=0,
                next_fetch_at=now + timedelta(seconds=ctx.settings.feed_poll_seconds),
            )
            return {"url": url, "status": 304, "new": 0}
        if resp.status_code != 200:
            return await _failure(ctx, url, state["failures"], f"HTTP {resp.status_code}", resp.status_code)

        parsed = feedparser.parse(resp.text)
        items = [(e.get("id") or e.get("guid"), e.get("link")) for e in parsed.entries]
        new, errors = 0, []
        for guid, link in items:
            if not guid or new >= MAX_NEW_ITEMS_PER_POLL:
                continue
            async with db.session() as session:
                seen = await session.scalar(select(CapMessage.id).where(CapMessage.feed_guid == guid).limit(1))
            if seen:
                continue
            cap_url = link or ctx.settings.sachet_cap_url_template.format(identifier=guid)
            try:
                cap_resp = await client.get(cap_url)
                if cap_resp.status_code != 200:
                    errors.append(f"{guid}: HTTP {cap_resp.status_code}")
                    continue
                await ingest_cap_xml(ctx, cap_resp.text, feed_url=url, feed_guid=guid, official_url=cap_url)
                new += 1
            except (httpx.HTTPError, CapParseError) as exc:
                errors.append(f"{guid}: {type(exc).__name__}")
        await _save_state(
            ctx,
            url,
            etag=resp.headers.get("ETag"),
            last_modified=resp.headers.get("Last-Modified"),
            last_fetch_at=now,
            last_success_at=now,
            last_status_code=200,
            last_error="; ".join(errors[:5]) or None,
            consecutive_failures=0,
            items_seen=len(items),
            next_fetch_at=now + timedelta(seconds=ctx.settings.feed_poll_seconds),
        )
        return {"url": url, "status": 200, "items": len(items), "new": new, "errors": errors[:5]}
    finally:
        if own:
            await client.aclose()


async def _failure(ctx: AppContext, url: str, failures: int, error: str, code: int | None) -> dict:
    failures += 1
    backoff = min(ctx.settings.feed_poll_seconds * (2 ** (failures - 1)), ctx.settings.feed_max_backoff_seconds)
    now = ctx.now()
    await _save_state(
        ctx,
        url,
        last_fetch_at=now,
        last_status_code=code,
        last_error=error,
        consecutive_failures=failures,
        next_fetch_at=now + timedelta(seconds=backoff),
    )
    log.warning("SACHET poll failed (%s), retry in %ss", error, backoff)
    return {"url": url, "error": error, "retry_in_seconds": backoff}


async def ingest_cap_xml(
    ctx: AppContext,
    xml: str,
    *,
    feed_url: str | None,
    feed_guid: str | None,
    official_url: str | None,
    is_fixture: bool = False,
    apply: bool = True,
) -> tuple[str, bool]:
    """Store a CAP message (idempotent) and apply it to live incidents. Returns (cap_message_id, created)."""
    async with db.session() as session:
        row, alert, created = await incidents.store_cap_message(
            session,
            xml,
            feed_url=feed_url,
            feed_guid=feed_guid,
            official_url=official_url,
            is_fixture=is_fixture,
            now=ctx.now(),
        )
        if created and apply and not is_fixture:
            await incidents.apply_live_cap(session, ctx, row, alert)
        emit(session, "feed.message", cap_message_id=row.id)
        await commit(session, ctx.bus)
        return row.id, created


async def poll_all(ctx: AppContext, force: bool = False) -> list[dict]:
    return [await poll_feed(ctx, url, force=force) for url in ctx.settings.rss_urls]
