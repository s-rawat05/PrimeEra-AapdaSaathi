"""A resident's reply can carry a note (the app sends "Confirmed by voice") that operators see in the timeline."""

from tests.helpers import API, simulate


async def test_voice_confirmed_reply_is_visible_to_operators(env):
    inc = await simulate(env, onset=20)
    anita = await env.login("Anita Negi")  # vision profile → voice reply in the app
    alert = (await env.client.get(f"{API}/alerts/active", headers=anita)).json()[0]
    assert {"text_to_speech", "voice_prompts"} <= set(alert["accessibility_modes"])

    r = await env.client.post(
        f"{API}/alerts/{alert['delivery_id']}/respond",
        json={"status": "SAFE", "note": "Confirmed by voice"},
        headers=anita,
    )
    assert r.status_code == 200 and r.json()["status"] == "SAFE"

    op = await env.login("Arjun Mehta")
    tl = (await env.client.get(f"{API}/deliveries/{alert['delivery_id']}/timeline", headers=op)).json()
    safe = next(e for e in tl if e["event_type"] == "safe")
    assert safe["message"] == "Confirmed SAFE via the app (Confirmed by voice)"
    assert inc["id"] == safe["incident_id"]


async def test_note_is_length_limited(env):
    await simulate(env, onset=20)
    anita = await env.login("Anita Negi")
    alert = (await env.client.get(f"{API}/alerts/active", headers=anita)).json()[0]
    r = await env.client.post(
        f"{API}/alerts/{alert['delivery_id']}/respond", json={"status": "HELP", "note": "x" * 301}, headers=anita
    )
    assert r.status_code == 422
