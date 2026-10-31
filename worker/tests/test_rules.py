"""Deterministic escalation rules: mode boundaries, intervals, onset fallback, priority score."""

from datetime import UTC, datetime, timedelta

import pytest

from app.escalation import rules

NOW = datetime(2026, 7, 14, 10, 0, tzinfo=UTC)


@pytest.mark.parametrize(
    "minutes,mode",
    [
        (-5, "D"),
        (0, "D"),
        (1, "C"),
        (29, "C"),
        (29.99, "C"),
        (30, "B"),
        (31, "B"),
        (359, "B"),
        (360, "B"),
        (361, "A"),
        (1440, "A"),
    ],
)
def test_mode_boundaries(minutes, mode):
    assert rules.select_mode(NOW + timedelta(minutes=minutes), NOW) == mode


@pytest.mark.parametrize(
    "window_min,expected_min",
    [
        (30, 3.0),  # 10% of 30 min
        (60, 6.0),
        (150, 15.0),  # 10% = 15 → at the cap
        (300, 15.0),  # 10% = 30 → capped at 15
        (360, 15.0),
    ],
)
def test_mode_b_interval_is_ten_percent_clamped(window_min, expected_min):
    iv = rules.escalation_interval(NOW + timedelta(minutes=window_min), NOW)
    assert iv == timedelta(minutes=expected_min)


def test_mode_b_interval_minimum_one_minute_boundary():
    # Mode B starts at 30 min, so the 1-minute floor is only reachable via the elderly halving rule.
    iv = rules.escalation_interval(NOW + timedelta(minutes=30), NOW, ["elderly_alone"])
    assert iv == timedelta(minutes=1.5)
    iv_c = rules.escalation_interval(NOW + timedelta(minutes=10), NOW, ["elderly_alone"])
    assert iv_c == timedelta(minutes=1)  # never below 1 minute


def test_mode_a_relaxed_and_mode_c_d_intervals():
    assert rules.escalation_interval(NOW + timedelta(hours=8), NOW) == timedelta(minutes=48)
    assert rules.escalation_interval(NOW + timedelta(hours=20), NOW) == timedelta(minutes=60)
    assert rules.escalation_interval(NOW + timedelta(minutes=10), NOW) == timedelta(minutes=1)
    assert rules.escalation_interval(NOW - timedelta(minutes=10), NOW) == timedelta(minutes=5)


def test_onset_fallback_is_flagged_and_documented():
    res = rules.resolve_onset(None, "Expected", NOW)
    assert res.fallback_used and res.onset == NOW + timedelta(minutes=120)
    assert "not official" in res.note
    assert rules.resolve_onset(None, "Bogus", NOW).onset == NOW + timedelta(minutes=60)
    official = NOW + timedelta(minutes=7)
    res2 = rules.resolve_onset(official, "Immediate", NOW)
    assert res2.onset == official and not res2.fallback_used and res2.note is None


def test_priority_score_components_are_transparent():
    pb = rules.priority_score(
        needs=["mobility"], lives_alone=True, status="HELP", alerted_at=NOW - timedelta(minutes=12, seconds=30), now=NOW
    )
    assert pb.total == 40 + 20 + 30 + 12
    assert [c["points"] for c in pb.components] == [40, 20, 30, 12]
    assert all("factor" in c for c in pb.components)


def test_priority_no_reply_and_elapsed_cap():
    pb = rules.priority_score(
        needs=["bedridden"], lives_alone=False, status="NO_REPLY", alerted_at=NOW - timedelta(hours=5), now=NOW
    )
    assert pb.total == 40 + 15 + 60


def test_priority_unreachable_counts_as_no_reply_and_safe_is_zero():
    un = rules.priority_score(needs=[], lives_alone=False, status="UNREACHABLE", alerted_at=NOW, now=NOW)
    assert un.total == 15 and "unreachable" in un.components[0]["factor"]
    safe = rules.priority_score(needs=["mobility"], lives_alone=True, status="SAFE", alerted_at=NOW, now=NOW)
    assert safe.total == 0


def test_dispatch_approval_policy():
    assert rules.requires_dispatch_approval("Severe", "B")
    assert rules.requires_dispatch_approval("Extreme", "C")
    assert rules.requires_dispatch_approval("Moderate", "D")
    assert not rules.requires_dispatch_approval("Moderate", "C")
    assert not rules.requires_dispatch_approval(None, "A")


def test_caregiver_parallel_policy():
    assert rules.caregiver_in_parallel(["hearing"], "B")
    assert rules.caregiver_in_parallel([], "C")
    assert not rules.caregiver_in_parallel([], "B")
