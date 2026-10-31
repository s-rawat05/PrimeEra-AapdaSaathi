# Architecture

AapdaSaathi closes the gap between *an official alert being delivered* and *a person being confirmed safe or
helped*. Principle: **App where possible. SMS everywhere. A human for those who don't reply.**

```
 SACHET (NDMA) RSS + CAP XML ──► ingestion (ETag, backoff) ──► cap_messages (raw XML kept verbatim)
                                         │
                                         ▼
                              ward matching (PostGIS / Shapely, LGD fallback)
                                         │
             ┌───────────────────────────┴──────────────────────────┐
             ▼                                                      ▼
   incidents + deliveries (1 per resident)            NOTIFY_REAL_RESIDENTS=false → no
             │                                         deliveries for real people (shown only)
             ▼
   notification outbox ──► in-app (WebSocket/poll) · FCM push · SMS gateway (httpSMS / simulator)
             │
   replies: app tap · SMS "1/2/3" · caregiver · neighbour · volunteer · operator override
             │
             ▼
   escalation engine (persisted deadlines, row locks) ──► neighbour check ──► volunteer ──► command centre
             │
             ▼
   command centre (live map, priority list, approvals, timeline) ──► closing report
```

## Components

| Component | Tech | Responsibility |
|---|---|---|
| `worker/` | Python 3.13, FastAPI, SQLAlchemy 2 (async), asyncpg / aiosqlite | REST API, auth, business rules, SACHET ingestion, escalation and notification workers, realtime WebSocket. One process runs both API and background loops (`RUN_BACKGROUND_JOBS`). |
| `app/` | Flutter (Android + web) | Role-aware app for residents, caregivers, neighbours, volunteers. Accessibility effects, offline queue, SMS fallback. |
| `dashboard/` | Flutter Web | Admin portal + command centre (flutter_map/OSM). |
| `supabase/` | PostgreSQL 17 + PostGIS 3, RLS | Production schema, row-level security, seed templates. |
| `fixtures/` | CAP XML, GeoJSON | Real SACHET samples for tests; fictional demo ward and drill alerts. |

### Why one database abstraction with two dialects

The production target is Supabase PostgreSQL + PostGIS. The demo laptop has no Docker or Postgres, so the same
code also runs on SQLite. Business rules are written once; only two things switch on dialect:

* **Spatial matching** — `ST_Intersects`/`ST_DWithin` on Postgres; Shapely with identical semantics on SQLite.
* **Row locks** — `SELECT … FOR UPDATE [SKIP LOCKED]` on Postgres; on SQLite every transaction starts with
  `BEGIN IMMEDIATE`, which serialises writers and gives the same correctness guarantee (less concurrency).

`worker/tests/test_schema_parity.py` fails if the ORM and `supabase/migrations` drift apart.

## Escalation

All timing state is persisted on `deliveries` (`escalation_level`, `escalation_step`, `next_action_at`,
`version`). The engine (`worker/app/escalation/engine.py`) runs every `ESCALATION_TICK_SECONDS`:

1. Snapshot due deliveries and order them by priority score (scarce helpers go to the most at-risk first).
2. For each: lock the row (`SKIP LOCKED` on Postgres), **re-check** it is still due and not SAFE, perform
   exactly one step, move `next_action_at` forward, commit. A failing row is deferred 60 s and logged —
   it never stalls the loop.

This makes each step idempotent, safe with several workers, and recoverable after a crash: overdue rows are
simply processed on the next tick (tested in `test_restart_recovers_overdue_actions`).

`time_window = onset − now` (`worker/app/escalation/rules.py`):

| Mode | Window | Behaviour | Interval |
|---|---|---|---|
| A — pre-evacuation | > 6 h | Arrange `preevac_assist` volunteer tasks for mobility/bedridden residents; relaxed check-ins. | 10 % of window, 15–60 min |
| B — scaled sequential | 30 min – 6 h | reminder + neighbour check → volunteer → command centre | 10 % of window, clamped 1–15 min |
| C — parallel | < 30 min | at alert time: resident + caregiver + neighbour check + pre-assigned helper | 1 min |
| D — accountability | onset passed | live safe/unaccounted list; all dispatch needs approval; 15-min walk cap | 5 min |

* Elderly residents living alone: half interval (≥ 1 min) and repeated reminders (max 5) until acknowledged.
* Missing `<onset>`: assumed from urgency (Immediate 15 min, Expected 120, Future 720, Past 0, Unknown 60).
  The assumption is stored in `onset_fallback_note` and shown to operators.
* The mode is re-evaluated on every tick, so an incident moves A → B → C → D as onset approaches (logged once).
* Demo incidents use `DEMO_ESCALATION_INTERVAL_SECONDS` so a drill is watchable in minutes.

**Ladder for no reply (A/B):** level 0 → reminder + neighbour check (no neighbour → straight to volunteer) →
level 1 → volunteer → level 2 → command centre (`needs_operator`) → level 3 (elderly: repeat reminders).

**HELP:** immediately neighbour check + volunteer request + caregiver notification + command centre flag; a
volunteer who neither accepts nor declines within 2 intervals is replaced.

**First valid response wins without losing help:** SAFE resolves the case and stands down open tasks (assignees
are told). A later HELP from the same person re-opens assistance. A SAFE never silently overrides an accepted
in-person outcome — every transition is in the timeline.

### Priority score (transparent, no ML)

| Factor | Points |
|---|---|
| Mobility limitation or bedridden | +40 |
| Lives alone | +20 |
| HELP response | +30 |
| No reply / unreachable | +15 |
| Minutes since alert | +1 per minute, max +60 |

SAFE scores 0. The command centre shows every component and the total.

## Dispatch safety (`worker/app/dispatch/`)

Walking time is an **estimate**: great-circle distance × `HILL_TERRAIN_FACTOR` (1.4) ÷ `WALKING_SPEED_M_PER_MIN`
(75). A volunteer is eligible only if available, verified, not on another task, has not declined this case,
within their service radius, the ward is not marked *blocked*, and `walk + ASSIST_BUFFER_MINUTES ≤ minutes to
onset` (or, once the hazard is ongoing, `walk ≤ MAX_WALK_MINUTES_ACTIVE_HAZARD` and approval is required).
Pre-assigned helpers rank first, then shortest walk.

If nobody qualifies the case is **not** dispatched: `needs_rescue = true` with the reasons
("Sneha: est. walk 26 min + 10 min buffer > 18 min before onset"), and it stays at the top of the command centre.
Severe/Extreme incidents, Mode D and *restricted* wards require operator approval; approval re-checks safety
because time has passed. No route is ever described as hazard-validated, and no instruction, shelter or route is
generated — relief posts come only from the `shelters` table, which requires an official source.

## Notifications (`worker/app/notifications/`)

Outbox pattern: messages are inserted as `queued` **inside** the business transaction (a rolled-back reply sends
nothing), then sent **after** commit by `flush_outbox`, which leases rows (no double sends across workers),
retries failures with exponential backoff (max 3), and marks a delivery UNREACHABLE when every external channel
finally failed and the app never showed the alert. Idempotency keys make every logical message unique.

Safety switch: `may_notify()` refuses any message to a non-demo recipient unless `NOTIFY_REAL_RESIDENTS=true`
(the attempt is still recorded as `blocked`). Live incidents additionally create **no deliveries** for real
residents while the switch is off. Demo-incident SMS always goes to the simulator unless the number is in
`DEMO_SMS_ALLOWLIST`, so fictional seed numbers can never reach a real gateway.

Channels per resident: in-app (always for app users) + FCM push (if a device is registered and Firebase is
configured) + SMS (if a phone is registered and registry consent is valid). Presentation modes are the **union**
of all declared needs (`worker/app/notifications/templates.py::NEED_MODES`).

## Realtime

`/api/v1/realtime` WebSocket with one-time tickets (no JWT in URLs). Events are published only after commit and
are "refetch" hints; clients also poll. The bus is in-process, so production runs **one** API instance; scaling
out requires swapping the bus for Postgres `LISTEN/NOTIFY` or Supabase Realtime (the publication for `incidents`,
`deliveries`, `tasks`, `feed_state` is already created by the RLS migration).

## Source map

| Concern | File |
|---|---|
| Config | `worker/app/config.py` |
| Data model | `worker/app/models/__init__.py`, `supabase/migrations/*.sql` |
| CAP parsing | `worker/app/integrations/cap_parser.py` |
| SACHET ingestion | `worker/app/integrations/sachet_ingest.py` |
| Ward matching | `worker/app/matching/ward_matcher.py` |
| Incidents (create/update/cancel/replay/close) | `worker/app/services/incidents.py` |
| Responses + SMS replies | `worker/app/services/responses.py` |
| Escalation | `worker/app/escalation/rules.py`, `engine.py` |
| Dispatch | `worker/app/dispatch/eligibility.py`, `service.py` |
| Notifications | `worker/app/notifications/dispatcher.py`, `templates.py` |
| Gateways | `worker/app/integrations/sms_gateway.py`, `fcm_gateway.py` |
| Audit + timeline | `worker/app/audit/log.py` |
| Reports | `worker/app/reporting/report.py` |
| Demo | `worker/app/demo/seed.py`, `service.py` |
| API routers | `worker/app/api/*.py` |
