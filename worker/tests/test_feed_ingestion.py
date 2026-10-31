"""SACHET ingestion: conditional GET (ETag/304), idempotency, backoff, live-alert safety switch,
geometry and LGD-code ward matching, and official Update/Cancel handling."""

from __future__ import annotations

from datetime import timedelta

import httpx
from sqlalchemy import func, select

from app.db import db
from app.integrations import sachet_ingest
from app.models import CapMessage, Delivery, FeedState, Incident, NotificationAttempt, TimelineEvent
from tests.conftest import FIXTURES
from tests.helpers import API

URL = "https://sachet.ndma.gov.in/cap_public_website/rss/rss_uttarakhand.xml"
RSS = (FIXTURES / "cap" / "sachet_rss_uttarakhand_sample.xml").read_text(encoding="utf-8")
CAP = (FIXTURES / "cap" / "sachet_uttarakhand_real_1793430002314009.xml").read_text(encoding="utf-8")


class FakeSachet:
    def __init__(self, rss_status: int = 200):
        self.rss_status = rss_status
        self.seen_headers: list[dict] = []
        self.cap_fetches = 0

    def handler(self, req: httpx.Request) -> httpx.Response:
        if req.url.path.endswith(".xml"):
            self.seen_headers.append(dict(req.headers))
            if self.rss_status != 200:
                return httpx.Response(self.rss_status)
            if req.headers.get("if-none-match") == 'W/"v1"':
                return httpx.Response(304)
            return httpx.Response(200, text=RSS, headers={"ETag": 'W/"v1"'})
        self.cap_fetches += 1
        if "1793430002314009" in str(req.url):
            return httpx.Response(200, text=CAP)
        return httpx.Response(403, text="Error Code: 403")  # SACHET sometimes refuses

    def client(self) -> httpx.AsyncClient:
        return httpx.AsyncClient(transport=httpx.MockTransport(self.handler))


async def test_etag_304_and_idempotent_items(env):
    fake = FakeSachet()
    async with fake.client() as c:
        first = await sachet_ingest.poll_feed(env.ctx, URL, force=True, client=c)
        second = await sachet_ingest.poll_feed(env.ctx, URL, force=True, client=c)
    assert first["status"] == 200 and first["new"] == 1 and first["items"] == 10
    assert len(first["errors"]) == 5  # 9 CAP files returned 403 — recorded (summary capped at 5), not fatal
    assert second == {"url": URL, "status": 304, "new": 0}
    assert fake.seen_headers[1]["if-none-match"] == 'W/"v1"'
    async with db.session() as s:
        st = await s.get(FeedState, URL)
        n = await s.scalar(select(func.count()).select_from(CapMessage))
    assert st.etag == 'W/"v1"' and st.last_status_code == 304 and st.consecutive_failures == 0
    assert n == 1


async def test_duplicate_items_are_not_refetched(env):
    fake = FakeSachet()
    async with fake.client() as c:
        await sachet_ingest.poll_feed(env.ctx, URL, force=True, client=c)
        async with db.session() as s:
            (await s.get(FeedState, URL)).etag = None  # force a full 200 again
            await s.commit()
        before = fake.cap_fetches
        r = await sachet_ingest.poll_feed(env.ctx, URL, force=True, client=c)
    assert r["new"] == 0
    assert fake.cap_fetches - before == 9  # only the previously failed items are retried


async def test_failure_backoff_is_persisted(env):
    fake = FakeSachet(rss_status=503)
    async with fake.client() as c:
        r1 = await sachet_ingest.poll_feed(env.ctx, URL, force=True, client=c)
        r2 = await sachet_ingest.poll_feed(env.ctx, URL, force=True, client=c)
        skipped = await sachet_ingest.poll_feed(env.ctx, URL, client=c)  # not forced → respects backoff
    assert r1["retry_in_seconds"] == 45 and r2["retry_in_seconds"] == 90
    assert skipped["skipped"]
    op = await env.login("Arjun Mehta")
    status = (await env.client.get(f"{API}/feed/status", headers=op)).json()["feeds"][0]
    assert not status["healthy"] and status["consecutive_failures"] == 2 and status["last_error"] == "HTTP 503"


async def _real_ward(env, code: str, geometry: dict, lgd: str | None = None) -> str:
    admin = await env.login("Priya Nair")
    r = await env.client.post(
        f"{API}/admin/wards",
        headers=admin,
        json={
            "code": code,
            "name": f"Test ward {code}",
            "district": "Nainital",
            "lgd_district_code": lgd,
            "boundary_geojson": geometry,
            "is_demo": False,
        },
    )
    assert r.status_code == 201, r.text
    ward_id = r.json()["id"]
    r = await env.client.post(
        f"{API}/admin/residents",
        headers=admin,
        json={
            "full_name": "Real Person (test)",
            "ward_id": ward_id,
            "phone": "+919876500001",
            "consent_registry": True,
            "has_smartphone": False,
            "needs": ["feature_phone"],
            "is_demo": False,
        },
    )
    assert r.status_code == 201, r.text
    return ward_id


SQUARE = {
    "type": "Polygon",
    "coordinates": [[[79.552, 29.346], [79.566, 29.346], [79.566, 29.356], [79.552, 29.356], [79.552, 29.346]]],
}


async def test_live_alert_never_notifies_real_residents_by_default(env):
    await _real_ward(env, "NTL-TEST", SQUARE, lgd="49")
    fake = FakeSachet()
    async with fake.client() as c:
        await sachet_ingest.poll_feed(env.ctx, URL, force=True, client=c)
    async with db.session() as s:
        inc = await s.scalar(select(Incident).where(Incident.source == "live"))
        assert inc is not None and not inc.is_demo
        n_del = await s.scalar(select(func.count()).select_from(Delivery).where(Delivery.incident_id == inc.id))
        n_msg = await s.scalar(select(func.count()).select_from(NotificationAttempt))
        note = await s.scalar(select(TimelineEvent.message).where(TimelineEvent.event_type == "delivery_suppressed"))
    assert n_del == 0 and n_msg == 0
    assert "NOTIFY_REAL_RESIDENTS=false" in note and "1 registered" in note
    op = await env.login("Arjun Mehta")
    detail = (await env.client.get(f"{API}/incidents/{inc.id}", headers=op)).json()
    assert detail["wards"][0]["match_method"] == "lgd_code"
    assert "not a precise geographic match" in detail["wards"][0]["match_note"]


async def test_safety_switch_enabled_notifies_real_residents(env):
    await _real_ward(env, "NTL-TEST", SQUARE, lgd="49")
    env.ctx.settings.notify_real_residents = True
    try:
        async with FakeSachet().client() as c:
            await sachet_ingest.poll_feed(env.ctx, URL, force=True, client=c)
    finally:
        env.ctx.settings.notify_real_residents = False
    async with db.session() as s:
        n_sms = await s.scalar(
            select(func.count())
            .select_from(NotificationAttempt)
            .where(NotificationAttempt.channel == "sms", NotificationAttempt.recipient_kind == "resident")
        )
    assert n_sms == 1


async def test_exercise_alert_update_and_cancel_by_geometry(env, cap_xml):
    await _real_ward(env, "GEO-TEST", SQUARE)
    common = dict(feed_url=None, feed_guid=None, official_url=None)
    await sachet_ingest.ingest_cap_xml(
        env.ctx,
        cap_xml("demo_flash_flood_alert"),
        feed_guid="g1",
        **{k: v for k, v in common.items() if k != "feed_guid"},
    )
    async with db.session() as s:
        inc = await s.scalar(select(Incident).where(Incident.cap_identifier == "AAPDASAATHI-DEMO-FLOOD-0001"))
    assert inc.source == "exercise" and inc.severity == "Severe"
    op = await env.login("Arjun Mehta")
    detail = (await env.client.get(f"{API}/incidents/{inc.id}", headers=op)).json()
    assert detail["wards"][0]["match_method"] == "geometry"

    await sachet_ingest.ingest_cap_xml(
        env.ctx, cap_xml("demo_flash_flood_update"), feed_guid="g2", feed_url=None, official_url=None
    )
    async with db.session() as s:
        inc = await s.get(Incident, inc.id)
        superseded = await s.scalar(
            select(CapMessage.superseded_by).where(CapMessage.identifier == "AAPDASAATHI-DEMO-FLOOD-0001")
        )
    assert inc.severity == "Extreme" and inc.requires_dispatch_approval and inc.status == "active"
    assert inc.cap_identifier == "AAPDASAATHI-DEMO-FLOOD-0002" and superseded == "AAPDASAATHI-DEMO-FLOOD-0002"

    _, created = await sachet_ingest.ingest_cap_xml(
        env.ctx, cap_xml("demo_flash_flood_update"), feed_guid="g2", feed_url=None, official_url=None
    )
    assert not created  # same identifier → idempotent

    await sachet_ingest.ingest_cap_xml(
        env.ctx, cap_xml("demo_flash_flood_cancel"), feed_guid="g3", feed_url=None, official_url=None
    )
    async with db.session() as s:
        inc = await s.get(Incident, inc.id)
    assert inc.status == "cancelled" and "Officially cancelled" in inc.close_note


async def test_alert_outside_registered_wards_creates_no_incident(env, cap_xml):
    await sachet_ingest.ingest_cap_xml(
        env.ctx, cap_xml("demo_flash_flood_alert"), feed_guid="x", feed_url=None, official_url=None
    )
    async with db.session() as s:
        assert await s.scalar(select(func.count()).select_from(Incident)) == 0  # demo wards never match live
        assert await s.scalar(select(func.count()).select_from(CapMessage)) == 1  # still shown in feed panel


async def test_replay_requires_demo_wards_and_keeps_official_text(env):
    async with FakeSachet().client() as c:
        await sachet_ingest.poll_feed(env.ctx, URL, force=True, client=c)
    op = await env.login("Arjun Mehta")
    msg = (await env.client.get(f"{API}/feed/messages", headers=op)).json()["items"][0]
    real_ward = await _real_ward(env, "REAL-1", SQUARE)
    bad = await env.client.post(
        f"{API}/feed/messages/{msg['id']}/replay", headers=op, json={"onset_in_minutes": 20, "ward_ids": [real_ward]}
    )
    assert bad.status_code == 422 and bad.json()["error"]["code"] == "demo_wards_only"
    ok = await env.client.post(f"{API}/feed/messages/{msg['id']}/replay", headers=op, json={"onset_in_minutes": 45})
    inc = ok.json()
    assert inc["escalation_mode"] == "B" and inc["instruction"] == "Please follow SDMA guidelines."
    onset_delta = abs(
        (env.clock.now() + timedelta(minutes=45)).timestamp()
        - __import__("datetime").datetime.fromisoformat(inc["onset"]).timestamp()
    )
    assert onset_delta < 1
