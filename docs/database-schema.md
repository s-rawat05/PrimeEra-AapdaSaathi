# Database schema

Source of truth for production: [`supabase/migrations/`](../supabase/migrations). The ORM in
`worker/app/models/__init__.py` mirrors it (checked by `worker/tests/test_schema_parity.py` on Postgres).

## Entity overview

```
users ─┬─< residents ──< resident_locations (1:1, exact coords, guarded)
       │        ├──< consent_records (registry/location/caregiver_share, 90-day expiry)
       │        ├──< caregiver_links >── users (caregivers)
       │        ├──< neighbour_links >── users (neighbours, priority order)
       │        └──< pre_assigned_helpers >── volunteers ── users
       ├──< volunteers
       └──< device_registrations (FCM tokens)

wards (GeoJSON + generated PostGIS geom) ──< shelters (official relief posts)

cap_messages (raw XML verbatim) ──< incidents ──< incident_wards >── wards
                                       ├──< deliveries (1 per resident: status + escalation state)
                                       │       ├──< tasks (neighbour_check / volunteer_assist / preevac_assist)
                                       │       ├──< notification_attempts (outbox; idempotency_key unique)
                                       │       └──< incident_timeline
                                       └── demo_sessions
feed_state · audit_log (append-only) · alert_templates · sms_inbound · otp_challenges · idempotency_keys
worker_heartbeats
```

## Key tables

| Table | Purpose | Notable constraints / indexes |
|---|---|---|
| `wards` | Ward boundary (GeoJSON) + `geom geometry` **generated** from it | GiST on `geom`; geometry type must be (Multi)Polygon; `access_status ∈ open/restricted/blocked` |
| `residents` | Registry (coarse location only) | `registration_status ∈ active/expired/withdrawn`; `needs` jsonb |
| `resident_locations` | Exact coordinates, separate table | unique per resident; RLS restricts reads |
| `consent_records` | Auditable consent with expiry/withdrawal | type and grantor checks |
| `cap_messages` | Every CAP message, raw XML unchanged, parsed JSON, validation errors, `superseded_by` | unique `identifier`; index on RSS `feed_guid` |
| `feed_state` | Per-feed ETag/Last-Modified, health, failures, next fetch (backoff) | PK = URL |
| `incidents` | Official fields verbatim + escalation mode + onset assumption note | `source ∈ live/replay/simulated/exercise/manual`; a demo incident can never be `live` |
| `deliveries` | One per resident per incident: response status **and persisted escalation state** | unique (incident, resident); index `(next_action_at)` partial for the worker; status check |
| `tasks` | Neighbour checks and volunteer tasks | **partial unique index**: one open task per (delivery, kind) → no duplicate assignment; CANT_GO requires a reason |
| `notification_attempts` | Outbox + delivery log per channel | unique `idempotency_key`; queue index `(status, next_retry_at)` |
| `incident_timeline` | Per-incident / per-resident event history | index `(incident_id, created_at)` |
| `audit_log` | Who did what, why, before/after | trigger: append-only |
| `sms_inbound` | Every inbound SMS and how it was resolved | unique `provider_message_id` (webhook idempotency) |
| `idempotency_keys` | Replay-safe client retries | unique (user, key) |

## Transactions and locking

Replies, task transitions, escalation steps and status overrides each run in a single transaction that first
locks the delivery/task row (`SELECT … FOR UPDATE`; the escalation worker uses `SKIP LOCKED`). Optimistic
`version` columns are incremented on every change for client-side conflict detection.

## Repeatable setup

```bash
# Vanilla Postgres/PostGIS (local or CI) — includes a tiny auth shim that Supabase already provides:
worker/.venv/Scripts/python scripts/apply_migrations.py postgresql://postgres:PW@localhost:5432/aapda --local-shim --seed

# Supabase:
supabase link --project-ref <ref>
supabase db push            # applies supabase/migrations
psql "$SUPABASE_DB_URL" -f supabase/seed.sql

# Fictional demo data (only with DEMO_MODE_ENABLED=true):
cd worker && DATABASE_URL=postgresql+asyncpg://... .venv/Scripts/python -m app.demo.seed
```

SQLite (local demo) needs no setup: the API creates tables from the ORM and seeds demo data on first start.
