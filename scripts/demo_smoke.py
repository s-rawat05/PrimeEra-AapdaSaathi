"""Scripted run of the 3-minute judge demo against a RUNNING backend (real HTTP, persisted state).

  worker/.venv/Scripts/python scripts/demo_smoke.py http://localhost:8000 [--pace 4] [--offline]

--pace N   pause N seconds between steps so the audience can watch the command centre update live.
--offline  skip the live SACHET fetch and replay a saved fixture instead (no internet at the venue).

Uses only fictional demo personas. Exits non-zero on the first failed step.
"""

from __future__ import annotations

import argparse
import sys
import time

import httpx

API = "/api/v1"


class Demo:
    def __init__(self, base: str, pace: float) -> None:
        self.c = httpx.Client(base_url=base.rstrip("/"), timeout=30)
        self.pace = pace
        self.step_no = 0
        self.personas = {p["full_name"]: p["user_id"] for p in self.get("/auth/demo-personas")}
        if not self.personas:
            sys.exit("Demo mode is disabled on this backend (DEMO_MODE_ENABLED=false).")
        self.tokens: dict[str, str] = {}

    def step(self, text: str) -> None:
        self.step_no += 1
        print(f"\n[{self.step_no:02d}] {text}")
        if self.pace:
            time.sleep(self.pace)

    def as_(self, name_part: str) -> dict:
        name = next(n for n in self.personas if name_part.lower() in n.lower())
        if name not in self.tokens:
            r = self.c.post(f"{API}/auth/demo-login", json={"user_id": self.personas[name]})
            r.raise_for_status()
            self.tokens[name] = r.json()["access_token"]
        return {"Authorization": f"Bearer {self.tokens[name]}"}

    def get(self, path: str, who: str | None = None, **params):
        r = self.c.get(API + path, headers=self.as_(who) if who else {}, params=params)
        self._check(r)
        return r.json()

    def post(self, path: str, who: str, body: dict | None = None):
        r = self.c.post(API + path, headers=self.as_(who), json=body or {})
        self._check(r)
        return r.json()

    @staticmethod
    def _check(r: httpx.Response) -> None:
        if r.status_code >= 400:
            sys.exit(f"   FAILED {r.request.method} {r.request.url.path}: {r.status_code} {r.text[:300]}")


def main() -> None:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")  # Windows consoles default to cp1252
    ap = argparse.ArgumentParser()
    ap.add_argument("base", nargs="?", default="http://localhost:8000")
    ap.add_argument("--pace", type=float, default=0)
    ap.add_argument("--offline", action="store_true")
    args = ap.parse_args()
    d = Demo(args.base, args.pace)
    op = "Arjun Mehta"

    d.step("Reset demo data (real data untouched)")
    print("  ", d.post("/demo/reset", op))

    d.step("Show a REAL SACHET alert in the feed panel")
    msg = None
    if not args.offline:
        for res in d.post("/feed/poll", op):
            print("   poll:", {k: res.get(k) for k in ("status", "items", "new", "error")})
        items = d.get("/feed/messages", op)["items"]
        msg = items[0] if items else None
    if msg:
        print(f"   {msg['sender']} · {msg['event']} · {msg['severity']} · {(msg['headline'] or '')[:90]}")
        d.step("Replay it into the fictional demo ward (onset in 20 min → Mode C)")
        inc = d.post(f"/feed/messages/{msg['id']}/replay", op, {"onset_in_minutes": 20})
    else:
        print("   no live message available — using saved CAP fixture instead")
        d.step("Simulate the saved flash-flood CAP fixture (onset in 20 min → Mode C)")
        inc = d.post("/demo/simulate", op, {"fixture": "demo_flash_flood_alert", "onset_in_minutes": 20})
    iid = inc["id"]
    print(f"   incident {inc['source_label']} · mode {inc['escalation_mode']} ({inc['mode_label']})")

    d.step("Affected demo residents and personalised alerts")
    c = d.get(f"/incidents/{iid}", op)["counts"]
    print(f"   {c['total']} residents alerted · no reply {c['NO_REPLY']} · unreachable {c['UNREACHABLE']}")
    alert = d.get("/alerts/active", "Ramesh Joshi")[0]
    print(f"   Ramesh (deaf) modes: {', '.join(alert['accessibility_modes'])}")

    d.step("Ramesh confirms SAFE in the app")
    print("  ", d.post(f"/alerts/{alert['delivery_id']}/respond", "Ramesh Joshi", {"status": "SAFE"}))

    d.step("Govind (feature phone) replies '1' by SMS")
    print("  ", d.post("/demo/sms/inbound", op, {"from_phone": "+919000000003", "body": "1"}))

    d.step("Sunita (wheelchair user) taps HELP")
    s_alert = d.get("/alerts/active", "Sunita Rawat")[0]
    print("  ", d.post(f"/alerts/{s_alert['delivery_id']}/respond", "Sunita Rawat", {"status": "HELP"}))

    d.step("Neighbour Vikram receives check requests and cannot reach Mohan")
    checks = d.get("/neighbour/checks", "Vikram Rawat")
    mohan = next(t for t in checks if t["resident_first_name"] == "Mohan")
    print(
        "  ",
        d.post(
            f"/neighbour/checks/{mohan['id']}/respond", "Vikram Rawat", {"outcome": "CANNOT_REACH", "note": "Door locked"}
        )["outcome"],
    )

    d.step("Volunteer task for Sunita: approve (Severe incidents need approval) and accept")
    tasks = d.get(f"/incidents/{iid}/tasks", op)
    t = next(x for x in tasks if x["resident_first_name"] == "Sunita" and x["kind"] == "volunteer_assist")
    if t["status"] == "PENDING_APPROVAL":
        d.post(f"/tasks/{t['id']}/approve", op)
        print("   operator approved dispatch")
    vol = t["assignee_name"].split(" ")[0]
    print(f"   {t['assignee_name']} · est. walk {t['est_walk_minutes']} min (estimate)")
    print("  ", d.post(f"/volunteer/tasks/{t['id']}/accept", vol)["status"])

    d.step("Volunteer reaches Sunita — she is safe")
    print("  ", d.post(f"/volunteer/tasks/{t['id']}/reached", vol, {"outcome": "resident_safe"})["status"])

    d.step("Command centre: counters, priority list and timeline from persisted state")
    c = d.get(f"/incidents/{iid}", op)["counts"]
    print(f"   SAFE {c['SAFE']} · HELP {c['HELP']} · NO REPLY {c['NO_REPLY']} · UNREACHABLE {c['UNREACHABLE']}")
    for p in d.get(f"/incidents/{iid}/priority", op, include_safe="false")[:3]:
        parts = " + ".join(f"{x['points']}" for x in p["priority_components"])
        print(f"   #{p['priority_total']:>3} {p['resident_name']:<20} {p['status']:<11} ({parts})")

    d.step("Closing report")
    rep = d.get(f"/incidents/{iid}/report", op)
    a = rep["alert_to_safe"]
    print(f"   safe {rep['counts']['SAFE']}/{rep['counts']['total']} · alert→safe median {a['median_seconds']} s")
    print(f"   unresolved: {', '.join(u['resident_name'] for u in rep['unresolved'][:5])} …")
    print("\nDEMO FLOW COMPLETED against persisted backend state.")


if __name__ == "__main__":
    main()
