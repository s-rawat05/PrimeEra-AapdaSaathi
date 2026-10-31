"""End-to-end smoke test of the mandatory 3-minute judge demo, entirely through the HTTP API and
persisted state (no frontend shortcuts). External services are mocked: SACHET via httpx.MockTransport,
SMS via the simulator."""

from __future__ import annotations

import httpx

from app.integrations import sachet_ingest
from app.notifications.dispatcher import flush_outbox
from tests.conftest import FIXTURES

API = "/api/v1"
RSS_URL = "https://sachet.ndma.gov.in/cap_public_website/rss/rss_uttarakhand.xml"


def sachet_mock() -> httpx.AsyncClient:
    rss = (FIXTURES / "cap" / "sachet_rss_uttarakhand_sample.xml").read_text(encoding="utf-8")
    cap = (FIXTURES / "cap" / "sachet_uttarakhand_real_1793430002314009.xml").read_text(encoding="utf-8")

    def handler(req: httpx.Request) -> httpx.Response:
        if req.url.path.endswith("rss_uttarakhand.xml"):
            return httpx.Response(200, text=rss, headers={"ETag": 'W/"demo-1"'})
        if "FetchXMLFile" in str(req.url) and "1793430002314009" in str(req.url):
            return httpx.Response(200, text=cap)
        return httpx.Response(404)

    return httpx.AsyncClient(transport=httpx.MockTransport(handler))


async def test_three_minute_demo(env):
    c = env.client
    op = await env.login("Arjun Mehta")

    # 1. A real SACHET alert appears in the feed panel (stored verbatim, no real resident notified).
    async with sachet_mock() as mock:
        res = await sachet_ingest.poll_feed(env.ctx, RSS_URL, force=True, client=mock)
    assert res["status"] == 200 and res["new"] == 1
    feed = (await c.get(f"{API}/feed/messages", headers=op)).json()
    real = feed["items"][0]
    assert real["sender"] == "Uttarakhand-SDMA" and real["msg_type"] == "Update"
    raw = (await c.get(f"{API}/feed/messages/{real['id']}/xml", headers=op)).text
    assert raw.startswith('<cap:alert xmlns:cap="urn:oasis:names:tc:emergency:cap:1.2">')
    status = (await c.get(f"{API}/feed/status", headers=op)).json()
    assert status["feeds"][0]["healthy"] and status["notify_real_residents"] is False

    # 2-3. Replay it into the fictional demo ward → incident with affected demo residents.
    r = await c.post(f"{API}/feed/messages/{real['id']}/replay", json={"onset_in_minutes": 20}, headers=op)
    assert r.status_code == 201, r.text
    inc = r.json()
    assert inc["source"] == "replay" and inc["is_demo"] and inc["escalation_mode"] == "C"
    assert inc["headline"].startswith("Thunderstorm accompanied")  # official text unchanged
    assert "DRILL TIMING" in inc["onset_fallback_note"]
    iid = inc["id"]
    pri = (await c.get(f"{API}/incidents/{iid}/priority", headers=op)).json()
    names = {p["resident_name"]: p for p in pri}
    assert "Prakash Rana" not in names  # consent expired → not alerted
    assert len(pri) == 16 and all(p["status"] in ("NO_REPLY", "UNREACHABLE") for p in pri)
    assert names["Kishan Ram"]["status"] == "NO_REPLY"  # SMS failure is retried before giving up
    for _ in range(3):  # retries back off 20 s, 40 s → final failure
        env.clock.advance(seconds=45)
        await flush_outbox(env.ctx)
    pri = (await c.get(f"{API}/incidents/{iid}/priority", headers=op)).json()
    names = {p["resident_name"]: p for p in pri}
    assert names["Kishan Ram"]["status"] == "UNREACHABLE"  # simulated switched-off phone
    top = pri[0]
    assert top["priority_total"] >= 75 and any("Mobility" in comp["factor"] for comp in top["priority_components"])

    # 4. Personalised alert reaches the resident app (hearing profile → flash/vibrate/torch).
    ramesh = await env.login("Ramesh Joshi")
    alerts = (await c.get(f"{API}/alerts/active", headers=ramesh)).json()
    assert len(alerts) == 1
    a = alerts[0]
    assert {"flash_screen", "vibrate", "torch_blink"} <= set(a["accessibility_modes"])
    assert a["presentation"]["label"].startswith("AapdaSaathi presentation")
    assert a["official"]["sender"] == "Uttarakhand-SDMA"
    assert a["shelters"] and a["shelters"][0]["est_walk_minutes"] is not None

    # 5. Ramesh confirms SAFE in the app (idempotent on retry).
    r = await c.post(
        f"{API}/alerts/{a['delivery_id']}/respond",
        json={"status": "SAFE"},
        headers={**ramesh, "Idempotency-Key": "k-1"},
    )
    assert r.status_code == 200 and r.json()["status"] == "SAFE" and r.json()["changed"]
    r2 = await c.post(
        f"{API}/alerts/{a['delivery_id']}/respond",
        json={"status": "SAFE"},
        headers={**ramesh, "Idempotency-Key": "k-1"},
    )
    assert r2.json() == r.json()

    # 6. Govind (feature phone) replies "1" by SMS → SAFE, and gets an acknowledgement SMS.
    r = await c.post(f"{API}/demo/sms/inbound", json={"from_phone": "+919000000003", "body": "1"}, headers=op)
    assert r.json()["result"] == "applied", r.text
    outbox = (await c.get(f"{API}/demo/sms/outbox", params={"phone": "+919000000003"}, headers=op)).json()
    assert any("Marked SAFE" in (m["body"] or "") or "सुरक्षित" in (m["body"] or "") for m in outbox)

    # 7. Sunita (wheelchair) asks for HELP in the app.
    sunita = await env.login("Sunita Rawat")
    s_alert = (await c.get(f"{API}/alerts/active", headers=sunita)).json()[0]
    r = await c.post(f"{API}/alerts/{s_alert['delivery_id']}/respond", json={"status": "HELP"}, headers=sunita)
    assert r.json()["status"] == "HELP"

    # 8-9. Neighbour Vikram has check requests; he cannot reach Mohan (bedridden, no reply).
    vikram = await env.login("Vikram Rawat")
    checks = (await c.get(f"{API}/neighbour/checks", headers=vikram)).json()
    by_name = {t["resident_first_name"]: t for t in checks}
    assert {"Sunita", "Mohan"} <= set(by_name)
    r = await c.post(
        f"{API}/neighbour/checks/{by_name['Mohan']['id']}/respond",
        json={"outcome": "CANNOT_REACH", "note": "Gate locked"},
        headers=vikram,
    )
    assert r.status_code == 200 and r.json()["outcome"] == "cannot_reach"

    # 10. A volunteer task for Sunita is assigned → the volunteer accepts it.
    tasks = (await c.get(f"{API}/incidents/{iid}/tasks", headers=op)).json()
    sunita_task = next(
        t
        for t in tasks
        if t["resident_first_name"] == "Sunita" and t["kind"] == "volunteer_assist" and t["status"] == "ASSIGNED"
    )
    vol_name = sunita_task["assignee_name"].split(" ")[0]
    vol = await env.login(vol_name)
    detail = (await c.get(f"{API}/tasks/{sunita_task['id']}", headers=vol)).json()
    assert detail["exact_location"] is not None and "ESTIMATE" in detail["walk_estimate_note"]
    r = await c.post(f"{API}/volunteer/tasks/{sunita_task['id']}/accept", headers=vol)
    assert r.json()["status"] == "ACCEPTED"

    # 11. Volunteer reaches Sunita; she is safe.
    r = await c.post(
        f"{API}/volunteer/tasks/{sunita_task['id']}/reached", json={"outcome": "resident_safe"}, headers=vol
    )
    assert r.json()["status"] == "REACHED"
    after = (await c.get(f"{API}/tasks/{sunita_task['id']}", headers=vol)).json()
    assert after["exact_location"] is None  # location access ends with the task

    # 12. Counters, markers and timeline reflect persisted state.
    inc_now = (await c.get(f"{API}/incidents/{iid}", headers=op)).json()
    assert inc_now["counts"]["SAFE"] == 3 and inc_now["counts"]["HELP"] == 0
    mp = (await c.get(f"{API}/incidents/{iid}/map", headers=op)).json()
    assert sum(1 for m in mp["markers"] if m["status"] == "SAFE") == 3 and mp["wards"][0]["boundary_geojson"]
    tl = (await c.get(f"{API}/incidents/{iid}/timeline", headers=op)).json()
    types = {e["event_type"] for e in tl}
    assert {
        "incident_created",
        "alerted",
        "safe",
        "help",
        "neighbour_cannot_reach",
        "task_accepted",
        "task_reached",
    } <= types
    mohan = next(
        p
        for p in (await c.get(f"{API}/incidents/{iid}/priority", headers=op)).json()
        if p["resident_name"] == "Mohan Lal Arya"
    )
    assert mohan["status"] == "NO_REPLY"
    assert mohan["open_tasks"] or mohan["needs_rescue"]  # helper on the way, or flagged for rescue with reason

    # 13. Closing report with alert-to-safe times and unresolved cases.
    rep = (await c.get(f"{API}/incidents/{iid}/report", headers=op)).json()
    assert rep["counts"]["SAFE"] == 3 and rep["alert_to_safe"]["count"] == 3
    assert any(u["resident_name"] == "Mohan Lal Arya" for u in rep["unresolved"])
    assert set(rep["alert_to_safe_by_channel"]) == {"app", "sms", "volunteer"}
    csv = (await c.get(f"{API}/incidents/{iid}/report.csv", headers=op)).text
    assert "Alert-to-safe" in csv
    r = await c.post(f"{API}/incidents/{iid}/close", json={"note": "Drill complete"}, headers=op)
    assert r.json()["status"] == "closed"

    # Reset leaves no demo incidents behind.
    r = await c.post(f"{API}/demo/reset", headers=op)
    assert r.json()["real_data_untouched"] and r.json()["incidents_removed"] == 1
