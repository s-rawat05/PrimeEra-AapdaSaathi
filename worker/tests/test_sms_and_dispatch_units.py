"""SMS parsing/normalisation/webhook signing and volunteer eligibility (pure units)."""

from datetime import UTC, datetime, timedelta

import jwt
import pytest

from app.dispatch.eligibility import Candidate, DispatchParams, evaluate, haversine_m, rank
from app.integrations.sms_gateway import (
    extract_inbound,
    mask_phone,
    normalize_phone,
    parse_sms_reply,
    verify_httpsms_webhook,
)


@pytest.mark.parametrize(
    "body,expected",
    [
        ("1", "SAFE"),
        (" safe ", "SAFE"),
        ("SAFE thanks", "SAFE"),
        ("1.", "SAFE"),
        ("मदद", "HELP"),
        ("2", "HELP"),
        ("help", "HELP"),
        ("3", "CANNOT_REACH"),
        ("12", None),
        ("ok", None),
        ("", None),
        ("I am safe", None),  # only the first token counts — never guess
    ],
)
def test_parse_sms_reply(body, expected):
    assert parse_sms_reply(body) == expected


def test_normalize_and_mask_phone():
    assert normalize_phone("90000 00003") == "+919000000003"
    assert normalize_phone("09000000003") == "+919000000003"
    assert normalize_phone("+91-90000-00003") == "+919000000003"
    assert normalize_phone("00919000000003") == "+919000000003"
    with pytest.raises(ValueError):
        normalize_phone("12")
    assert mask_phone("+919000000003") == "+91••••••0003"


def test_webhook_signature():
    secret = "s" * 40
    good = jwt.encode({"iss": "httpsms"}, secret, algorithm="HS256")
    assert verify_httpsms_webhook(f"Bearer {good}", secret)
    assert not verify_httpsms_webhook(f"Bearer {good}", "other" * 10)
    assert not verify_httpsms_webhook(None, secret)
    assert not verify_httpsms_webhook("Basic abc", secret)


def test_extract_inbound_event():
    ev = {"type": "message.phone.received", "data": {"message_id": "m1", "contact": "+919000000003", "content": "1"}}
    assert extract_inbound(ev) == ("m1", "+919000000003", "1")
    assert extract_inbound({"type": "message.phone.sent", "data": {}}) is None
    assert extract_inbound({"type": "message.phone.received", "data": {"contact": "x"}}) is None


P = DispatchParams(
    walking_speed_m_per_min=75, hill_terrain_factor=1.4, assist_buffer_minutes=10, max_walk_minutes_active_hazard=15
)
NOW = datetime(2026, 7, 14, 10, 0, tzinfo=UTC)
RES = (29.3500, 79.5600)


def cand(name, lat, lng, **kw):
    base = dict(
        volunteer_id=name,
        user_id=name,
        name=name,
        lat=lat,
        lng=lng,
        max_radius_m=3000,
        is_available=True,
        busy=False,
        declined_this_case=False,
    )
    base.update(kw)
    return Candidate(**base)


def ev(c, onset_min=60, access="open"):
    return evaluate(
        c,
        resident_lat=RES[0],
        resident_lng=RES[1],
        onset=NOW + timedelta(minutes=onset_min),
        now=NOW,
        ward_access=access,
        params=P,
    )


def test_haversine_sanity():
    assert 1100 < haversine_m(29.35, 79.56, 29.36, 79.56) < 1120


def test_walk_estimate_uses_hill_factor():
    e = ev(cand("a", 29.3545, 79.5600))  # ~500 m
    assert e.eligible and 9 < e.walk_minutes < 10  # 500 * 1.4 / 75 ≈ 9.3


def test_ineligible_reasons():
    assert "unavailable" in ev(cand("a", *RES, is_available=False)).reason.lower()
    assert "active task" in ev(cand("a", *RES, busy=True)).reason
    assert "declined" in ev(cand("a", *RES, declined_this_case=True)).reason
    assert "BLOCKED" in ev(cand("a", *RES), access="blocked").reason
    assert "radius" in ev(cand("a", 29.40, 79.56)).reason


def test_cannot_arrive_in_time_is_never_dispatched():
    e = ev(cand("a", 29.3590, 79.5600), onset_min=20)  # ~1 km → ~21 min + 10 buffer > 20
    assert not e.eligible and "Cannot arrive safely in time" in e.reason


def test_active_hazard_limit():
    near = ev(cand("a", 29.3510, 79.5600), onset_min=-5)
    far = ev(cand("b", 29.3600, 79.5600), onset_min=-5)
    assert near.eligible and "approval" in near.reason
    assert not far.eligible and "Hazard ongoing" in far.reason


def test_rank_prefers_pre_assigned_then_nearest():
    a = ev(cand("near", 29.3505, 79.5600))
    b = ev(cand("pre", 29.3540, 79.5600, pre_assigned_priority=1))
    c = ev(cand("busy", 29.3500, 79.5600, busy=True))
    assert [e.candidate.name for e in rank([a, b, c])] == ["pre", "near", "busy"]
