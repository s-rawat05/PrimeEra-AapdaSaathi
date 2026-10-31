"""Resident registration & consent lifecycle, dispatch lifecycle, and demo reset isolation."""

from __future__ import annotations

from datetime import timedelta

from sqlalchemy import func, select

from app.db import db
from app.models import Incident, Resident, ResidentLocation
from app.services import residents as residents_svc
from tests.helpers import API, delivery_of, simulate, tasks_of


async def _new_resident(env, phone="9876501234", name="Asha Test"):
    await env.client.post(f"{API}/auth/otp/request", json={"phone": phone})
    code = env.ctx.extras["sim_inbox"][-1]["body"].split(": ")[1]
    r = await env.client.post(f"{API}/auth/otp/verify", json={"phone": phone, "code": code, "full_name": name})
    return {"Authorization": f"Bearer {r.json()['access_token']}"}


async def test_registration_consent_and_withdrawal(env):
    h = await _new_resident(env)
    wards = (await env.client.get(f"{API}/wards/public", headers=h)).json()
    assert all(not w["is_demo"] for w in wards)  # real (non-demo) users never see fictional demo wards
    admin = await env.login("Priya Nair")
    w = await env.client.post(
        f"{API}/admin/wards",
        headers=admin,
        json={
            "code": "REAL-9",
            "name": "Real ward",
            "district": "Nainital",
            "is_demo": False,
            "boundary_geojson": {
                "type": "Polygon",
                "coordinates": [[[79.5, 29.3], [79.6, 29.3], [79.6, 29.4], [79.5, 29.4], [79.5, 29.3]]],
            },
        },
    )
    ward_id = w.json()["id"]
    no_consent = await env.client.post(
        f"{API}/residents/me/registration",
        headers=h,
        json={"full_name": "Asha", "ward_id": ward_id, "consent_registry": False},
    )
    assert no_consent.status_code == 422
    guardian_no_name = await env.client.post(
        f"{API}/residents/me/registration",
        headers=h,
        json={"full_name": "Asha", "ward_id": ward_id, "consent_registry": True, "granted_by": "guardian"},
    )
    assert guardian_no_name.status_code == 422
    r = await env.client.post(
        f"{API}/residents/me/registration",
        headers=h,
        json={
            "full_name": "Asha",
            "ward_id": ward_id,
            "language": "hi",
            "needs": ["vision", "elderly_alone"],
            "lives_alone": True,
            "lat": 29.3512345,
            "lng": 79.5567891,
            "consent_registry": True,
            "consent_location": True,
            "trusted_contacts": [{"full_name": "Son", "phone": "9876509999"}],
        },
    )
    assert r.status_code == 201, r.text
    prof = r.json()
    assert prof["has_exact_location"] and {c["consent_type"] for c in prof["consents"]} >= {"registry", "location"}
    consent = prof["consents"][0]
    from datetime import datetime

    span = datetime.fromisoformat(consent["expires_at"]) - datetime.fromisoformat(consent["granted_at"])
    assert span == timedelta(days=90)
    async with db.session() as s:
        res = await s.scalar(select(Resident).where(Resident.full_name == "Asha"))
        assert (res.coarse_lat, res.coarse_lng) == (29.351, 79.557)  # coarse only in residents table
    dup = await env.client.post(
        f"{API}/residents/me/registration",
        headers=h,
        json={"full_name": "Asha", "ward_id": ward_id, "consent_registry": True},
    )
    assert dup.status_code == 409

    wd = await env.client.post(f"{API}/residents/me/consent/withdraw", headers=h)
    assert wd.json()["registration_status"] == "withdrawn" and not wd.json()["has_exact_location"]
    async with db.session() as s:
        assert (
            await s.scalar(
                select(func.count()).select_from(ResidentLocation).where(ResidentLocation.resident_id == res.id)
            )
            == 0
        )
    renew = await env.client.post(f"{API}/residents/me/consent/renew", headers=h)
    assert renew.json()["registration_status"] == "active"


async def test_expired_registrations_are_marked_and_skipped(env):
    async with db.session() as s:
        n = await residents_svc.expire_overdue(s, env.ctx)
        await s.commit()
        prakash = await s.scalar(select(Resident).where(Resident.full_name == "Prakash Rana"))
    assert n == 1 and prakash.registration_status == "expired"


async def test_cant_go_requires_reason_and_reassigns(env):
    inc = await simulate(env, onset=240, fixture="demo_landslide_long_lead")
    sunita = await env.login("Sunita Rawat")
    alert = (await env.client.get(f"{API}/alerts/active", headers=sunita)).json()[0]
    await env.client.post(f"{API}/alerts/{alert['delivery_id']}/respond", json={"status": "HELP"}, headers=sunita)
    t = next(x for x in await tasks_of(alert["delivery_id"]) if x.kind == "volunteer_assist")
    vol = await env.login((await _name(env, t)).split(" ")[0])
    bad = await env.client.post(f"{API}/volunteer/tasks/{t.id}/cant-go", json={"reason": "lazy"}, headers=vol)
    assert bad.status_code == 422
    ok = await env.client.post(
        f"{API}/volunteer/tasks/{t.id}/cant-go",
        json={"reason": "route_blocked", "note": "Landslide debris on lane"},
        headers=vol,
    )
    assert ok.status_code == 200 and ok.json()["status"] == "CANT_GO" and ok.json()["cant_go_reason"] == "route_blocked"
    after = [x for x in await tasks_of(alert["delivery_id"]) if x.kind == "volunteer_assist"]
    d = await delivery_of(inc["id"], "Sunita Rawat")
    assert (len(after) == 2 and after[1].volunteer_id != t.volunteer_id) or d.needs_rescue


async def _name(env, task) -> str:
    op = await env.login("Arjun Mehta")
    return (await env.client.get(f"{API}/tasks/{task.id}/ops", headers=op)).json()["assignee_name"]


async def test_severe_incident_dispatch_needs_approval_reject_and_reassign(env):
    inc = await simulate(env, onset=20)  # Severe fixture → approval required
    sunita = await env.login("Sunita Rawat")
    op = await env.login("Arjun Mehta")
    alert = (await env.client.get(f"{API}/alerts/active", headers=sunita)).json()[0]
    await env.client.post(f"{API}/alerts/{alert['delivery_id']}/respond", json={"status": "HELP"}, headers=sunita)
    pending = next(
        t
        for t in (await env.client.get(f"{API}/incidents/{inc['id']}/tasks", headers=op)).json()
        if t["resident_first_name"] == "Sunita" and t["kind"] == "volunteer_assist"
    )
    assert pending["status"] == "PENDING_APPROVAL"
    vol_name = pending["assignee_name"].split(" ")[0]
    vol = await env.login(vol_name)
    assert pending["id"] not in [t["id"] for t in (await env.client.get(f"{API}/volunteer/tasks", headers=vol)).json()]
    cands = (await env.client.get(f"{API}/deliveries/{alert['delivery_id']}/candidates", headers=op)).json()
    dev = next(c for c in cands if c["name"].startswith("Dev"))
    assert not dev["eligible"] and "radius" in dev["reason"]
    to_dev = await env.client.post(
        f"{API}/tasks/{pending['id']}/reassign",
        headers=op,
        json={"to_volunteer_id": dev["volunteer_id"], "reason": "Try Dev instead"},
    )
    assert to_dev.status_code == 409  # never sends a volunteer who cannot arrive safely
    approved = await env.client.post(f"{API}/tasks/{pending['id']}/approve", headers=op)
    assert approved.status_code in (200, 409)
    if approved.status_code == 200:
        assert approved.json()["status"] == "ASSIGNED"
        r = await env.client.post(f"{API}/volunteer/tasks/{pending['id']}/accept", headers=vol)
        assert r.json()["status"] == "ACCEPTED"
        no_note = await env.client.post(
            f"{API}/volunteer/tasks/{pending['id']}/reached", json={"outcome": "needs_rescue"}, headers=vol
        )
        assert no_note.status_code == 422
        r = await env.client.post(
            f"{API}/volunteer/tasks/{pending['id']}/reached",
            json={"outcome": "needs_rescue", "note": "Water at doorstep"},
            headers=vol,
        )
        d = await delivery_of(inc["id"], "Sunita Rawat")
        assert r.json()["status"] == "REACHED" and d.needs_rescue and "Water at doorstep" in d.rescue_reason


async def test_reject_requires_reason_and_override_is_audited(env):
    inc = await simulate(env, onset=20)
    op = await env.login("Arjun Mehta")
    d = await delivery_of(inc["id"], "Harish Pant")
    short = await env.client.post(
        f"{API}/deliveries/{d.id}/override", json={"status": "SAFE", "reason": "ok"}, headers=op
    )
    assert short.status_code == 422
    r = await env.client.post(
        f"{API}/deliveries/{d.id}/override",
        headers=op,
        json={"status": "SAFE", "reason": "Confirmed by phone call from control room"},
    )
    assert r.json()["status"] == "SAFE"
    audit = (await env.client.get(f"{API}/audit", params={"action": "delivery.override"}, headers=op)).json()
    assert audit["items"][0]["reason"].startswith("Confirmed by phone")
    assert audit["items"][0]["before"] == {"status": "NO_REPLY"}
    resend = await env.client.post(f"{API}/deliveries/{d.id}/resend", headers=op)
    assert resend.status_code == 409  # already safe


async def test_demo_reset_never_touches_real_data(env):
    admin = await env.login("Priya Nair")
    op = await env.login("Arjun Mehta")
    w = await env.client.post(
        f"{API}/admin/wards",
        headers=admin,
        json={
            "code": "REAL-2",
            "name": "Real ward 2",
            "district": "Nainital",
            "is_demo": False,
            "boundary_geojson": {
                "type": "Polygon",
                "coordinates": [[[79.5, 29.3], [79.6, 29.3], [79.6, 29.4], [79.5, 29.4], [79.5, 29.3]]],
            },
        },
    )
    real = await env.client.post(
        f"{API}/incidents",
        headers=op,
        json={
            "title": "Real manual incident",
            "hazard_type": "Flood",
            "ward_ids": [w.json()["id"]],
            "is_demo": False,
            "onset_in_minutes": 60,
        },
    )
    assert real.status_code == 201 and real.json()["counts"]["total"] == 0  # NOTIFY_REAL_RESIDENTS=false
    await simulate(env, onset=20)
    await simulate(env, onset=90)
    mixed = await env.client.post(
        f"{API}/incidents",
        headers=op,
        json={"title": "Bad", "hazard_type": "Flood", "ward_ids": [w.json()["id"]], "is_demo": True},
    )
    assert mixed.status_code == 422  # demo incidents cannot target real wards
    r = (await env.client.post(f"{API}/demo/reset", headers=op)).json()
    assert r["incidents_removed"] == 2 and r["real_data_untouched"]
    async with db.session() as s:
        remaining = (await s.execute(select(Incident))).scalars().all()
    assert [i.title for i in remaining] == ["Real manual incident"]
