"""Escalation engine: ladder timing, mode transitions, restart recovery, duplicate workers,
reply/timer races, cancellation and unaccepted-task timeouts."""

from __future__ import annotations

import asyncio
from collections import Counter
from datetime import timedelta

from sqlalchemy import func, select

from app.db import db
from app.escalation import engine
from app.main import build_context
from app.models import Delivery, NotificationAttempt, Task, TimelineEvent  # noqa: F401
from tests.helpers import API, all_open_tasks_by_delivery, delivery_of, simulate, tasks_of


async def _isolate(incident_id: str, keep: str) -> None:
    """Test setup: park every other delivery so volunteer scarcity doesn't interfere with the ladder."""
    keep_d = await delivery_of(incident_id, keep)
    async with db.session() as s:
        for d in (
            (await s.execute(select(Delivery).where(Delivery.incident_id == incident_id, Delivery.id != keep_d.id)))
            .scalars()
            .all()
        ):
            d.status, d.next_action_at = "SAFE", None
        await s.commit()


async def test_mode_b_sequential_ladder(env):
    inc = await simulate(env, onset=90)
    assert inc["escalation_mode"] == "B" and inc["requires_dispatch_approval"]  # Severe fixture
    await _isolate(inc["id"], "Sunita Rawat")
    d = await delivery_of(inc["id"], "Sunita Rawat")
    assert d.status == "NO_REPLY" and d.escalation_level == 0
    assert d.next_action_at == env.clock.now() + timedelta(seconds=30)  # demo interval override
    assert await tasks_of(d.id) == []  # Mode B: nothing parallel at alert time

    assert await engine.tick(env.ctx) == 0  # not yet due
    env.clock.advance(seconds=31)
    await engine.tick(env.ctx)
    d = await delivery_of(inc["id"], "Sunita Rawat")
    t = await tasks_of(d.id)
    assert d.escalation_level == 1 and d.reminders_sent == 1
    assert [x.kind for x in t] == ["neighbour_check"] and t[0].status == "ASSIGNED"

    env.clock.advance(seconds=31)
    await engine.tick(env.ctx)
    d = await delivery_of(inc["id"], "Sunita Rawat")
    kinds = {x.kind: x.status for x in await tasks_of(d.id)}
    assert d.escalation_level == 2 and kinds["volunteer_assist"] == "PENDING_APPROVAL"  # severe → approval

    env.clock.advance(seconds=31)
    await engine.tick(env.ctx)
    d = await delivery_of(inc["id"], "Sunita Rawat")
    assert d.escalation_level == 3 and d.needs_operator and d.next_action_at is None


async def test_no_neighbour_goes_straight_to_volunteer(env):
    inc = await simulate(env, onset=90)
    env.clock.advance(seconds=31)
    await engine.tick(env.ctx)
    d = await delivery_of(inc["id"], "Harish Pant")  # no linked neighbour
    assert d.escalation_level == 2
    async with db.session() as s:
        msgs = (
            (await s.execute(select(TimelineEvent.event_type).where(TimelineEvent.delivery_id == d.id))).scalars().all()
        )
    assert "no_neighbour" in msgs


async def test_elderly_alone_get_shorter_interval_and_repeat_reminders(env):
    inc = await simulate(env, onset=90)
    d = await delivery_of(inc["id"], "Meena Kumari")
    assert d.next_action_at - d.alerted_at == timedelta(seconds=15)
    for _ in range(8):
        env.clock.advance(seconds=16)
        await engine.tick(env.ctx)
    d = await delivery_of(inc["id"], "Meena Kumari")
    assert d.escalation_level == 3 and d.reminders_sent >= 3  # keeps reminding until acknowledged
    assert d.next_action_at is not None or d.reminders_sent == engine.MAX_REPEAT_REMINDERS


async def test_mode_transition_b_to_c_as_onset_nears(env):
    inc = await simulate(env, onset=35)
    assert inc["escalation_mode"] == "B"
    env.clock.advance(minutes=6)
    await engine.tick(env.ctx)
    r = await env.client.get(f"{API}/incidents/{inc['id']}", headers=await env.login("Arjun Mehta"))
    assert r.json()["escalation_mode"] == "C"
    async with db.session() as s:
        n = await s.scalar(
            select(func.count())
            .select_from(TimelineEvent)
            .where(TimelineEvent.incident_id == inc["id"], TimelineEvent.event_type == "mode_changed")
        )
    assert n == 1  # logged once, not per delivery


async def test_restart_recovers_overdue_actions(env):
    inc = await simulate(env, onset=90)
    env.clock.advance(minutes=10)  # worker was down for several intervals
    fresh_ctx = build_context(env.settings, env.clock)  # "restart": new process state, same database
    steps = await engine.tick(fresh_ctx)
    assert steps >= 14
    async with db.session() as s:
        overdue = await s.scalar(
            select(func.count())
            .select_from(Delivery)
            .where(Delivery.incident_id == inc["id"], Delivery.next_action_at <= env.clock.now())
        )
    # Exactly one step per delivery per tick: recovered rows moved forward, none skipped or doubled.
    assert overdue == 0
    open_by_delivery = await all_open_tasks_by_delivery(inc["id"])
    for tasks in open_by_delivery.values():
        assert len([t for t in tasks if t.kind == "neighbour_check"]) <= 1


async def test_duplicate_workers_do_not_double_act(env):
    inc = await simulate(env, onset=90)
    env.clock.advance(seconds=31)
    ctx2 = build_context(env.settings, env.clock)
    await asyncio.gather(engine.tick(env.ctx), engine.tick(ctx2), engine.tick(env.ctx))
    async with db.session() as s:
        ds = (await s.execute(select(Delivery).where(Delivery.incident_id == inc["id"]))).scalars().all()
        rounds = Counter(
            (a.delivery_id, a.task_id, a.round, a.channel, a.recipient_kind, a.recipient_user_id, a.recipient_phone)
            for a in (await s.execute(select(NotificationAttempt).where(NotificationAttempt.incident_id == inc["id"])))
            .scalars()
            .all()
        )
        tasks = (await s.execute(select(Task).where(Task.incident_id == inc["id"]))).scalars().all()
    assert all(d.reminders_sent <= 1 for d in ds)
    assert all(v == 1 for v in rounds.values())  # no duplicate notification for any round/channel
    per_kind = Counter((t.delivery_id, t.kind) for t in tasks if t.status in ("ASSIGNED", "PENDING_APPROVAL"))
    assert all(v == 1 for v in per_kind.values())


async def test_safe_reply_racing_due_timer(env):
    inc = await simulate(env, onset=90)
    ramesh = await env.login("Ramesh Joshi")
    alert = (await env.client.get(f"{API}/alerts/active", headers=ramesh)).json()[0]
    env.clock.advance(seconds=31)  # Ramesh's escalation is now due
    resp, _ = await asyncio.gather(
        env.client.post(f"{API}/alerts/{alert['delivery_id']}/respond", json={"status": "SAFE"}, headers=ramesh),
        engine.tick(env.ctx),
    )
    assert resp.status_code == 200
    d = await delivery_of(inc["id"], "Ramesh Joshi")
    assert d.status == "SAFE" and d.next_action_at is None
    assert not [t for t in await tasks_of(d.id) if t.status in ("ASSIGNED", "ACCEPTED", "PENDING_APPROVAL")]


async def test_concurrent_duplicate_and_conflicting_replies(env):
    inc = await simulate(env, onset=20)
    sunita = await env.login("Sunita Rawat")
    op = await env.login("Arjun Mehta")
    alert = (await env.client.get(f"{API}/alerts/active", headers=sunita)).json()[0]
    url = f"{API}/alerts/{alert['delivery_id']}/respond"
    rs = await asyncio.gather(*[env.client.post(url, json={"status": "SAFE"}, headers=sunita) for _ in range(4)])
    assert all(r.status_code == 200 for r in rs)
    assert sum(r.json()["changed"] for r in rs) == 1  # exactly one state change
    # Conflicting: app HELP and SMS SAFE at the same time — final state is one of them, never corrupted.
    await asyncio.gather(
        env.client.post(url, json={"status": "HELP"}, headers=sunita),
        env.client.post(f"{API}/demo/sms/inbound", json={"from_phone": "+919000000004", "body": "1"}, headers=op),
    )
    d = await delivery_of(inc["id"], "Sunita Rawat")
    open_t = [t for t in await tasks_of(d.id) if t.status in ("ASSIGNED", "ACCEPTED", "PENDING_APPROVAL")]
    assert d.status in ("SAFE", "HELP")
    if d.status == "SAFE":
        assert open_t == []
    async with db.session() as s:
        safes = await s.scalar(
            select(func.count())
            .select_from(TimelineEvent)
            .where(TimelineEvent.delivery_id == d.id, TimelineEvent.event_type == "safe")
        )
    assert safes in (1, 2)  # first SAFE, plus SMS SAFE only if it landed after HELP


async def test_closing_incident_stops_escalation(env):
    inc = await simulate(env, onset=20)
    op = await env.login("Arjun Mehta")
    r = await env.client.post(f"{API}/incidents/{inc['id']}/close", json={"note": "Drill ended"}, headers=op)
    assert r.json()["status"] == "closed"
    assert await all_open_tasks_by_delivery(inc["id"]) == {}
    env.clock.advance(minutes=30)
    assert await engine.tick(env.ctx) == 0
    r = await env.client.post(f"{API}/incidents/{inc['id']}/close", json={"note": "again"}, headers=op)
    assert r.status_code == 409


async def test_unaccepted_volunteer_task_times_out_and_reassigns(env):
    inc = await simulate(env, onset=240, fixture="demo_landslide_long_lead")  # Moderate → no approval
    await _isolate(inc["id"], "Sunita Rawat")
    sunita = await env.login("Sunita Rawat")
    alert = (await env.client.get(f"{API}/alerts/active", headers=sunita)).json()[0]
    await env.client.post(f"{API}/alerts/{alert['delivery_id']}/respond", json={"status": "HELP"}, headers=sunita)
    first = [t for t in await tasks_of(alert["delivery_id"]) if t.kind == "volunteer_assist"][0]
    assert first.status == "ASSIGNED"
    for _ in range(3):
        env.clock.advance(seconds=31)
        await engine.tick(env.ctx)
    vt = [t for t in await tasks_of(alert["delivery_id"]) if t.kind == "volunteer_assist"]
    assert vt[0].status == "CANCELLED" and vt[0].outcome == "timeout"
    assert len(vt) >= 2 and vt[1].volunteer_id != vt[0].volunteer_id


async def test_mode_a_arranges_pre_evacuation(env):
    inc = await simulate(env, onset=8 * 60, fixture="demo_landslide_long_lead")
    assert inc["escalation_mode"] == "A"
    d = await delivery_of(inc["id"], "Kamla Devi Bisht")
    kinds = [t.kind for t in await tasks_of(d.id)]
    assert "preevac_assist" in kinds
    assert d.next_action_at - d.alerted_at == timedelta(seconds=15)  # demo interval, halved for elderly
