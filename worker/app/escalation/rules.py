"""Deterministic escalation rules. Pure functions only — no I/O, no ML.

Every number here is documented in docs/architecture.md#escalation and shown to operators.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime, timedelta

SIX_HOURS = timedelta(hours=6)
THIRTY_MIN = timedelta(minutes=30)

# Used only when a CAP message has no <onset>. The assumption is stored on the incident and
# displayed to operators so nobody mistakes it for an official onset time.
URGENCY_ONSET_FALLBACK_MINUTES: dict[str, int | None] = {
    "Immediate": 15,
    "Expected": 120,
    "Future": 720,
    "Past": 0,
    "Unknown": 60,
}

PRIORITY_WEIGHTS = {
    "mobility_or_bedridden": 40,
    "lives_alone": 20,
    "help_response": 30,
    "no_reply": 15,
}
ELAPSED_POINTS_PER_MINUTE = 1
ELAPSED_POINTS_CAP = 60

# Needs that warrant a pre-assigned/assisted evacuation or minute-zero helper alert.
ASSISTED_EVACUATION_NEEDS = {"mobility", "bedridden"}
CAREGIVER_PARALLEL_NEEDS = {"hearing", "vision", "cognitive", "mobility", "bedridden", "elderly_alone"}


@dataclass(frozen=True)
class OnsetResolution:
    onset: datetime
    fallback_used: bool
    note: str | None


def resolve_onset(onset: datetime | None, urgency: str | None, reference: datetime) -> OnsetResolution:
    if onset is not None:
        return OnsetResolution(onset, False, None)
    key = urgency if urgency in URGENCY_ONSET_FALLBACK_MINUTES else "Unknown"
    minutes = URGENCY_ONSET_FALLBACK_MINUTES[key] or 0
    note = (
        f"CAP message has no onset. AapdaSaathi assumed onset = sent + {minutes} min "
        f"from urgency '{urgency or 'Unknown'}'. This is an operating assumption, not official data."
    )
    return OnsetResolution(reference + timedelta(minutes=minutes), True, note)


def select_mode(onset: datetime, now: datetime) -> str:
    """A: >6h pre-evacuation · B: 30min–6h scaled sequential · C: <30min parallel · D: happening."""
    window = onset - now
    if window <= timedelta(0):
        return "D"
    if window < THIRTY_MIN:
        return "C"
    if window <= SIX_HOURS:
        return "B"
    return "A"


def mode_label(mode: str) -> str:
    return {
        "A": "Pre-evacuation (>6 h)",
        "B": "Scaled sequential (30 min–6 h)",
        "C": "Parallel response (<30 min)",
        "D": "Accountability (hazard ongoing)",
    }[mode]


def escalation_interval(onset: datetime, now: datetime, needs: list[str] | None = None) -> timedelta:
    """Interval between escalation steps.

    Mode B rule from the PRD: 10% of the remaining window, clamped to [1, 15] minutes.
    Mode A uses relaxed check-ins (10% clamped to [15, 60] min). Mode C/D use the 1-minute floor.
    Elderly residents living alone get half the interval (still ≥ 1 minute).
    """
    mode = select_mode(onset, now)
    window_min = max((onset - now).total_seconds() / 60.0, 0.0)
    if mode == "A":
        minutes = min(max(window_min * 0.10, 15.0), 60.0)
    elif mode == "B":
        minutes = min(max(window_min * 0.10, 1.0), 15.0)
    else:
        minutes = 1.0 if mode == "C" else 5.0
    if needs and "elderly_alone" in needs:
        minutes = max(minutes / 2.0, 1.0)
    return timedelta(minutes=minutes)


@dataclass(frozen=True)
class PriorityBreakdown:
    total: int
    components: list[dict] = field(default_factory=list)


def priority_score(
    *,
    needs: list[str],
    lives_alone: bool,
    status: str,
    alerted_at: datetime | None,
    now: datetime,
) -> PriorityBreakdown:
    """Transparent priority score. Resolved (SAFE) cases score 0 and drop out of the ranking."""
    if status == "SAFE":
        return PriorityBreakdown(0, [{"factor": "Confirmed safe", "points": 0}])
    parts: list[dict] = []
    if ASSISTED_EVACUATION_NEEDS & set(needs):
        parts.append({"factor": "Mobility limitation / bedridden", "points": PRIORITY_WEIGHTS["mobility_or_bedridden"]})
    if lives_alone:
        parts.append({"factor": "Lives alone", "points": PRIORITY_WEIGHTS["lives_alone"]})
    if status == "HELP":
        parts.append({"factor": "Requested help", "points": PRIORITY_WEIGHTS["help_response"]})
    elif status in ("NO_REPLY", "UNREACHABLE", "PENDING"):
        label = "No reply (unreachable)" if status == "UNREACHABLE" else "No reply"
        parts.append({"factor": label, "points": PRIORITY_WEIGHTS["no_reply"]})
    if alerted_at is not None:
        minutes = int(max((now - alerted_at).total_seconds(), 0) // 60)
        pts = min(minutes * ELAPSED_POINTS_PER_MINUTE, ELAPSED_POINTS_CAP)
        parts.append({"factor": f"{minutes} min since alert (1/min, max {ELAPSED_POINTS_CAP})", "points": pts})
    return PriorityBreakdown(sum(p["points"] for p in parts), parts)


def requires_dispatch_approval(severity: str | None, mode: str) -> bool:
    """Severe/Extreme incidents and ongoing hazards need a human to approve volunteer dispatch."""
    return (severity or "").lower() in {"severe", "extreme"} or mode == "D"


def caregiver_in_parallel(needs: list[str], mode: str) -> bool:
    return mode in ("C", "D") or bool(CAREGIVER_PARALLEL_NEEDS & set(needs))


def needs_assisted_evacuation(needs: list[str]) -> bool:
    return bool(ASSISTED_EVACUATION_NEEDS & set(needs))
