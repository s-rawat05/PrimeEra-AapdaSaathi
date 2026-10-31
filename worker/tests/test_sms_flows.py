"""Inbound SMS: signed webhook, duplicates, ambiguity, stale replies, unknown senders, HELP after SAFE."""

from __future__ import annotations

import jwt

from tests.helpers import API, delivery_of, simulate

WEBHOOK = f"{API}/sms/webhook"


def signed(env) -> dict:
    token = jwt.encode({"iss": "httpsms"}, env.settings.sms_webhook_secret, algorithm="HS256")
    return {"Authorization": f"Bearer {token}"}


def event(msg_id: str, phone: str, body: str) -> dict:
    return {
        "type": "message.phone.received",
        "id": "evt",
        "data": {"message_id": msg_id, "contact": phone, "content": body},
    }


async def test_webhook_requires_signature(env):
    r = await env.client.post(WEBHOOK, json=event("m1", "+919000000003", "1"))
    assert r.status_code == 401
    r = await env.client.post(
        WEBHOOK, json=event("m1", "+919000000003", "1"), headers={"Authorization": "Bearer forged.token.value"}
    )
    assert r.status_code == 401


async def test_webhook_reply_and_duplicate_delivery(env):
    inc = await simulate(env, onset=20)
    r1 = await env.client.post(WEBHOOK, json=event("m1", "+919000000003", "1"), headers=signed(env))
    r2 = await env.client.post(WEBHOOK, json=event("m1", "+919000000003", "1"), headers=signed(env))
    assert r1.json()["result"] == "applied" and r2.json()["result"] == "duplicate"
    d = await delivery_of(inc["id"], "Govind Singh Negi")
    assert d.status == "SAFE" and d.reply_channel == "sms"
    other = await env.client.post(WEBHOOK, json={"type": "message.phone.sent", "data": {}}, headers=signed(env))
    assert other.json()["result"] == "ignored"


async def test_unrecognised_ambiguous_stale_and_unknown(env):
    inc = await simulate(env, onset=20)  # Mode C → Vikram gets several neighbour checks at once
    op = await env.login("Arjun Mehta")

    async def sim(phone, body):
        return (
            await env.client.post(f"{API}/demo/sms/inbound", json={"from_phone": phone, "body": body}, headers=op)
        ).json()

    assert (await sim("+919000000003", "maybe"))["result"] == "unrecognised"
    assert (await sim("+919000000202", "1"))["result"] == "rejected_ambiguous"
    assert (await sim("+919000000003", "3"))["result"] == "rejected_no_context"
    unknown = await env.client.post(WEBHOOK, json=event("u1", "+919811111111", "1"), headers=signed(env))
    assert unknown.json()["result"] == "rejected_unknown_sender"
    forbidden = await env.client.post(
        f"{API}/demo/sms/inbound", json={"from_phone": "+919811111111", "body": "1"}, headers=op
    )
    assert forbidden.status_code == 403  # simulator only speaks for fictional numbers

    await env.client.post(f"{API}/incidents/{inc['id']}/close", json={"note": "done"}, headers=op)
    assert (await sim("+919000000003", "1"))["result"] == "rejected_stale"


async def test_help_after_safe_and_neighbour_sms(env):
    inc = await simulate(env, onset=20)
    op = await env.login("Arjun Mehta")

    async def sim(phone, body):
        return (
            await env.client.post(f"{API}/demo/sms/inbound", json={"from_phone": phone, "body": body}, headers=op)
        ).json()

    assert (await sim("+919000000003", "SAFE"))["result"] == "applied"
    assert (await sim("+919000000003", "1"))["result"] == "already_safe"
    assert (await sim("+919000000003", "HELP"))["result"] == "applied"
    d = await delivery_of(inc["id"], "Govind Singh Negi")
    assert d.status == "HELP" and d.needs_operator
    # Pooja has a single pending check? She has Leela and Deepa in Mode C → ambiguous; resolve one in-app first.
    pooja = await env.login("Pooja Joshi")
    checks = (await env.client.get(f"{API}/neighbour/checks", headers=pooja)).json()
    assert len(checks) == 2
    await env.client.post(f"{API}/neighbour/checks/{checks[0]['id']}/respond", json={"outcome": "SAFE"}, headers=pooja)
    res = await sim("+919000000203", "3")
    assert res["result"] == "applied" and res["task_id"] == checks[1]["id"]
