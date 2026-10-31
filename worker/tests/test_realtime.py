"""Realtime bus: tickets are single-use, events are filtered by audience, ops see everything."""

from __future__ import annotations

from app.services.realtime import EventBus


def test_tickets_are_single_use_and_identify_the_user():
    bus = EventBus()
    t = bus.issue_ticket("u1", "resident")
    assert bus.redeem_ticket(t) == ("u1", "resident")
    assert bus.redeem_ticket(t) is None
    assert bus.redeem_ticket("forged") is None


def test_audience_filtering_and_multiple_connections_per_user():
    bus = EventBus()
    op = bus.subscribe("op", "operator")
    me1 = bus.subscribe("me", "resident")
    me2 = bus.subscribe("me", "resident")  # same user, two devices — both must be kept
    other = bus.subscribe("other", "resident")
    assert bus.subscriber_count == 4
    bus.publish({"type": "delivery.updated", "audience": ["me"], "delivery_id": "d1"})
    assert op.queue.qsize() == 1 and me1.queue.qsize() == 1 and me2.queue.qsize() == 1
    assert other.queue.qsize() == 0
    assert "audience" not in me1.queue.get_nowait()  # recipients list is never leaked
    bus.unsubscribe(me1)
    assert bus.subscriber_count == 3
