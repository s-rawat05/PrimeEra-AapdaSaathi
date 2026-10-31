"""Authentication, role enforcement, ownership/assignment checks and exact-location privacy."""

from __future__ import annotations

from sqlalchemy import select

from app.db import db
from app.models import AuditLog
from tests.helpers import API, simulate


async def test_unauthenticated_and_bad_tokens(env):
    assert (await env.client.get(f"{API}/me")).status_code == 401
    r = await env.client.get(f"{API}/me", headers={"Authorization": "Bearer not-a-jwt"})
    assert r.status_code == 401 and r.json()["error"]["code"] == "unauthenticated"


async def test_role_enforcement_on_server(env):
    resident = await env.login("Ramesh Joshi")
    volunteer = await env.login("Aman Verma")
    operator = await env.login("Arjun Mehta")
    for path in ("/incidents", "/feed/status", "/audit", "/admin/volunteers", "/demo/status"):
        assert (await env.client.get(f"{API}{path}", headers=resident)).status_code == 403, path
        assert (await env.client.get(f"{API}{path}", headers=volunteer)).status_code == 403, path
    assert (await env.client.get(f"{API}/admin/residents", headers=operator)).status_code == 403  # admin only
    assert (await env.client.get(f"{API}/volunteer/tasks", headers=resident)).status_code == 403
    assert (await env.client.get(f"{API}/caregiver/residents", headers=volunteer)).status_code == 403


async def test_resident_cannot_answer_someone_elses_alert(env):
    await simulate(env, onset=20)
    ramesh = await env.login("Ramesh Joshi")
    anita = await env.login("Anita Negi")
    a_alert = (await env.client.get(f"{API}/alerts/active", headers=anita)).json()[0]
    r = await env.client.post(f"{API}/alerts/{a_alert['delivery_id']}/respond", json={"status": "SAFE"}, headers=ramesh)
    assert r.status_code == 403
    assert (await env.client.get(f"{API}/alerts/{a_alert['delivery_id']}", headers=ramesh)).status_code == 403


async def test_caregiver_sees_only_linked_residents(env):
    await simulate(env, onset=20)
    neha = await env.login("Neha Bisht")
    linked = (await env.client.get(f"{API}/caregiver/residents", headers=neha)).json()
    assert {x["resident"]["full_name"] for x in linked} == {"Kamla Devi Bisht", "Saroj Pandey"}
    assert all(x["exact_location"] for x in linked)  # consented caregiver_share + can_view_location
    kamla = next(x for x in linked if x["resident"]["full_name"] == "Kamla Devi Bisht")
    did = kamla["active_alerts"][0]["delivery_id"]
    r = await env.client.post(
        f"{API}/caregiver/alerts/{did}/respond", json={"status": "SAFE", "note": "On phone"}, headers=neha
    )
    assert r.status_code == 200 and r.json()["status"] == "SAFE"
    ramesh = await env.login("Ramesh Joshi")
    ramesh_alert = (await env.client.get(f"{API}/alerts/active", headers=ramesh)).json()[0]
    r = await env.client.post(
        f"{API}/caregiver/alerts/{ramesh_alert['delivery_id']}/respond", json={"status": "SAFE"}, headers=neha
    )
    assert r.status_code == 403


async def test_neighbour_and_volunteer_assignment_checks(env):
    inc = await simulate(env, onset=20)
    vikram = await env.login("Vikram Rawat")
    pooja = await env.login("Pooja Joshi")
    v_check = (await env.client.get(f"{API}/neighbour/checks", headers=vikram)).json()[0]
    r = await env.client.post(
        f"{API}/neighbour/checks/{v_check['id']}/respond", json={"outcome": "SAFE"}, headers=pooja
    )
    assert r.status_code == 403
    op = await env.login("Arjun Mehta")
    tasks = (await env.client.get(f"{API}/incidents/{inc['id']}/tasks", headers=op)).json()
    vt = next(t for t in tasks if t["kind"] == "volunteer_assist")
    owner = await env.login(vt["assignee_name"].split(" ")[0])
    other = await env.login("Sneha" if "Aman" in vt["assignee_name"] else "Aman")
    assert vt["status"] == "PENDING_APPROVAL"  # Severe incident
    assert (await env.client.get(f"{API}/tasks/{vt['id']}", headers=owner)).status_code == 404  # not before approval
    assert (await env.client.post(f"{API}/tasks/{vt['id']}/approve", headers=op)).status_code == 200
    assert (await env.client.get(f"{API}/tasks/{vt['id']}", headers=other)).status_code == 404
    assert (await env.client.post(f"{API}/volunteer/tasks/{vt['id']}/accept", headers=other)).status_code == 403
    detail = (await env.client.get(f"{API}/tasks/{vt['id']}", headers=owner)).json()
    assert detail["exact_location"] and detail["resident_phone"].startswith("+91")
    async with db.session() as s:
        logged = await s.scalar(select(AuditLog.id).where(AuditLog.action == "location.view"))
    assert logged  # access to an exact location is audited


async def test_otp_signup_and_lockout(env):
    r = await env.client.post(f"{API}/auth/otp/request", json={"phone": "98765 43210"})
    assert r.status_code == 200 and r.json()["channel"] == "simulator"
    code = env.ctx.extras["sim_inbox"][-1]["body"].split(": ")[1]
    wrong = "000000" if code != "000000" else "111111"
    bad = await env.client.post(f"{API}/auth/otp/verify", json={"phone": "9876543210", "code": wrong})
    assert bad.status_code == 401
    need_name = await env.client.post(f"{API}/auth/otp/verify", json={"phone": "9876543210", "code": code})
    assert need_name.status_code == 422 and need_name.json()["error"]["code"] == "name_required"
    ok = await env.client.post(
        f"{API}/auth/otp/verify", json={"phone": "9876543210", "code": code, "full_name": "New Resident"}
    )
    assert ok.status_code == 200 and ok.json()["is_new_user"] and ok.json()["user"]["role"] == "resident"
    reuse = await env.client.post(f"{API}/auth/otp/verify", json={"phone": "9876543210", "code": code})
    assert reuse.status_code == 401  # single use
    await env.client.post(f"{API}/auth/otp/request", json={"phone": "9876543210"})
    code = env.ctx.extras["sim_inbox"][-1]["body"].split(": ")[1]
    for _ in range(6):
        await env.client.post(f"{API}/auth/otp/verify", json={"phone": "9876543210", "code": "111111"})
    r = await env.client.post(f"{API}/auth/otp/verify", json={"phone": "9876543210", "code": code})
    assert r.status_code in (401, 429)


async def test_password_login_for_ops_accounts(env):
    admin = await env.login("Priya Nair")
    r = await env.client.post(
        f"{API}/admin/users",
        headers=admin,
        json={
            "full_name": "Real Operator",
            "role": "operator",
            "email": "ops@example.org",
            "password": "correct-horse-9",
        },
    )
    assert r.status_code == 201, r.text
    ok = await env.client.post(
        f"{API}/auth/login", json={"identifier": "ops@example.org", "password": "correct-horse-9"}
    )
    assert ok.status_code == 200 and ok.json()["user"]["role"] == "operator"
    bad = await env.client.post(f"{API}/auth/login", json={"identifier": "ops@example.org", "password": "wrong-pass"})
    assert bad.status_code == 401
    weak = await env.client.post(
        f"{API}/admin/users",
        headers=admin,
        json={"full_name": "No Password", "role": "admin", "email": "x@example.org"},
    )
    assert weak.status_code == 422
    # Ops accounts cannot sign in through resident OTP.
    nonops = await env.client.post(f"{API}/auth/demo-login", json={"user_id": ok.json()["user"]["id"]})
    assert nonops.status_code == 403  # not a demo account


async def test_demo_mode_off_disables_demo_accounts(env):
    persona_token = await env.login("Ramesh Joshi")
    env.ctx.settings.demo_mode_enabled = False
    try:
        assert (await env.client.get(f"{API}/auth/demo-personas")).json() == []
        assert (await env.client.get(f"{API}/me", headers=persona_token)).status_code == 401
    finally:
        env.ctx.settings.demo_mode_enabled = True
