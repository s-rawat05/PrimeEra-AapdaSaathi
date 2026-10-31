"""Closing report: alert-to-safe times, unresolved cases and assistance outcomes — all computed from
persisted deliveries, tasks and notification attempts."""

from __future__ import annotations

import csv
import io
import statistics
from collections import Counter

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core import AppContext
from app.models import Delivery, NotificationAttempt, Resident, Task, User
from app.services import views


def _pct(values: list[float], p: float) -> float | None:
    if not values:
        return None
    s = sorted(values)
    k = max(0, min(len(s) - 1, round(p / 100 * (len(s) - 1))))
    return round(s[k], 1)


def _stats(values: list[float]) -> dict:
    return {
        "count": len(values),
        "median_seconds": round(statistics.median(values), 1) if values else None,
        "p90_seconds": _pct(values, 90),
        "max_seconds": round(max(values), 1) if values else None,
    }


async def build_report(session: AsyncSession, ctx: AppContext, incident_id: str) -> dict:
    inc = await views.get_incident_or_404(session, incident_id)
    rows = (
        await session.execute(
            select(Delivery, Resident).join(Resident, Resident.id == Delivery.resident_id).where(
                Delivery.incident_id == incident_id)
        )
    ).all()
    safe_times, by_channel = [], {}
    unresolved = []
    priority = {p.delivery_id: p for p in await views.priority_list(session, ctx, incident_id)}
    for d, r in rows:
        if d.status == "SAFE" and d.alerted_at and d.resolved_at:
            secs = (d.resolved_at - d.alerted_at).total_seconds()
            safe_times.append(secs)
            by_channel.setdefault(d.resolved_by or "unknown", []).append(secs)
        elif d.status != "SAFE":
            p = priority.get(d.id)
            unresolved.append({
                "delivery_id": d.id, "resident_name": r.full_name, "status": d.status,
                "needs": list(r.needs or []), "priority": p.priority_total if p else None,
                "needs_rescue": d.needs_rescue, "rescue_reason": d.rescue_reason,
                "escalation_step": d.escalation_step,
            })
    unresolved.sort(key=lambda u: -(u["priority"] or 0))

    tasks = (await session.execute(select(Task).where(Task.incident_id == incident_id))).scalars().all()
    accept_times = [(t.accepted_at - (t.approved_at or t.created_at)).total_seconds() for t in tasks if t.accepted_at]
    reach_times = [(t.reached_at - t.accepted_at).total_seconds() for t in tasks if t.reached_at and t.accepted_at]
    names = dict((await session.execute(select(User.id, User.full_name))).all())
    attempts = (
        await session.execute(select(NotificationAttempt).where(NotificationAttempt.incident_id == incident_id))
    ).scalars().all()

    counts = await views.counts_for(session, incident_id)
    return {
        "generated_at": ctx.now().isoformat(),
        "incident": (await views.incident_out(session, inc)).model_dump(mode="json"),
        "counts": counts.model_dump(),
        "safe_rate": round(counts.SAFE / counts.total, 3) if counts.total else None,
        "alert_to_safe": _stats(safe_times),
        "alert_to_safe_by_channel": {k: _stats(v) for k, v in by_channel.items()},
        "unresolved": unresolved,
        "tasks": {
            "total": len(tasks),
            "by_kind_status": dict(Counter(f"{t.kind}:{t.status}" for t in tasks)),
            "outcomes": dict(Counter(t.outcome for t in tasks if t.outcome)),
            "cant_go_reasons": dict(Counter(t.cant_go_reason for t in tasks if t.cant_go_reason)),
            "time_to_accept": _stats(accept_times),
            "time_to_reach": _stats(reach_times),
            "items": [
                {"id": t.id, "kind": t.kind, "status": t.status, "assignee": names.get(t.assignee_user_id),
                 "outcome": t.outcome, "cant_go_reason": t.cant_go_reason, "attempt_no": t.attempt_no}
                for t in sorted(tasks, key=lambda t: t.created_at)
            ],
        },
        "notifications": {
            "by_channel_status": dict(Counter(f"{a.channel}:{a.status}" for a in attempts)),
            "blocked_by_safety_switch": sum(1 for a in attempts if a.status == "blocked"),
        },
        "notes": [
            "Times are measured from the first alert to the moment the resident was confirmed safe "
            "(by the resident, caregiver, neighbour, volunteer or operator).",
            "Walking-time estimates are approximations and were not validated against hazard data.",
        ] + (["This is a DEMO/DRILL incident using fictional residents."] if inc.is_demo else []),
    }


def report_csv(report: dict) -> str:
    buf = io.StringIO()
    w = csv.writer(buf)
    inc = report["incident"]
    w.writerow(["AapdaSaathi closing report", inc["title"]])
    w.writerow(["Source", inc["source_label"], "Status", inc["status"], "Generated", report["generated_at"]])
    w.writerow([])
    w.writerow(["Status", "Count"])
    for k in ("SAFE", "HELP", "NO_REPLY", "UNREACHABLE", "PENDING", "total"):
        w.writerow([k, report["counts"][k]])
    w.writerow([])
    a = report["alert_to_safe"]
    w.writerow(["Alert-to-safe", "count", "median_s", "p90_s", "max_s"])
    w.writerow(["all", a["count"], a["median_seconds"], a["p90_seconds"], a["max_seconds"]])
    for ch, s in report["alert_to_safe_by_channel"].items():
        w.writerow([ch, s["count"], s["median_seconds"], s["p90_seconds"], s["max_seconds"]])
    w.writerow([])
    w.writerow(["Unresolved", "status", "priority", "needs", "needs_rescue", "reason"])
    for u in report["unresolved"]:
        w.writerow([u["resident_name"], u["status"], u["priority"], " ".join(u["needs"]), u["needs_rescue"],
                    u["rescue_reason"] or ""])
    return buf.getvalue()
