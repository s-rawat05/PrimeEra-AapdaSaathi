# AapdaSaathi — आपदा साथी

**From "alert delivered" to "person confirmed safe or helped."**
App where possible. SMS everywhere. A human for those who don't reply.

Team **PRIME ERA** · Graphic Era Hill University, Bhimtal · SAARTHI'26 (Smart Cities, Mobility & Public Safety)
Sahil Rawat (lead) · Udit Joshi · Ayush Mahara · Saksham Pantola

---

India's SACHET system already delivers official CAP alerts. What is missing is the **last mile of
accountability**: who acknowledged the alert, who needs help, and who has not answered — especially people who
are deaf, blind, bedridden, elderly and alone, or who own only a feature phone. AapdaSaathi:

1. **Ingests official alerts** from the SACHET (NDMA) CAP feeds — raw XML kept verbatim, ETag-aware polling.
2. **Matches them to wards** (PostGIS polygon intersection, LGD-district fallback that is labelled as imprecise).
3. **Delivers personalised, accessible alerts** — vibration, screen flash, torch blink, text-to-speech, easy-read
   pictograms, Hindi/English, combined for people with several needs — by app, push and SMS.
4. **Collects one-tap / one-digit replies** — SAFE / HELP in the app, `1` / `2` by SMS, `3` = "cannot reach"
   for neighbour checks.
5. **Escalates deterministically** based on time to onset (modes A–D): neighbour → volunteer → command centre,
   with a transparent priority score and travel-time safety checks before any volunteer is sent.
6. **Runs a live command centre** (map, counters, ranked cases with score breakdowns, approvals, overrides,
   timelines) and produces a **closing report** with alert-to-safe times and unresolved cases.

No machine learning is used for any safety decision. No instruction, shelter or route is ever generated.

## Repository

| Path | What |
|---|---|
| [`worker/`](worker) | FastAPI backend + background worker (Python 3.13) — API, SACHET ingestion, escalation, dispatch, SMS, reports |
| [`app/`](app) | Flutter Android app (also runs on web) for residents, caregivers, neighbours, volunteers |
| [`dashboard/`](dashboard) | Flutter Web admin portal + command centre |
| [`supabase/`](supabase) | PostgreSQL/PostGIS migrations, row-level security, seed |
| [`fixtures/`](fixtures) | Real SACHET CAP samples (public domain) and fictional demo ward/alerts |
| [`docs/`](docs) | Architecture, API contract, schema, security & privacy, deployment, demo runbook, traceability |
| [`scripts/`](scripts) | Migrations runner, scripted demo, Windows helpers |

## Quick start (local demo, ~5 minutes)

```bash
# 1. Backend — SQLite + fictional demo data, no other services needed
cd worker
python -m venv .venv
.venv/Scripts/python -m pip install -r requirements-dev.txt        # Linux/macOS: .venv/bin/python
.venv/Scripts/python -m uvicorn app.main:app --port 8000
#    API docs: http://localhost:8000/docs

# 2. Command centre (new terminal)
cd dashboard && flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:8000

# 3. Resident app (new terminal; or install the APK on a phone/emulator)
cd app && flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:8000

# 4. Optional: scripted end-to-end demo against the running backend
worker/.venv/Scripts/python scripts/demo_smoke.py http://localhost:8000 --pace 3
```

Sign in with the **Demo accounts** picker (fictional personas). The judge walkthrough is in
[`docs/demo-runbook.md`](docs/demo-runbook.md).

## Tests

```bash
cd worker && .venv/Scripts/python -m pytest -q                 # backend (SQLite)
# Postgres + PostGIS + RLS:
python scripts/apply_migrations.py postgresql://postgres:PW@localhost:5432/aapda_test --local-shim --seed
TEST_DATABASE_URL=postgresql+asyncpg://postgres:PW@localhost:5432/aapda_test pytest -q
cd app && flutter test
cd dashboard && flutter test
```

CI (`.github/workflows/ci.yml`) runs backend tests on SQLite and on PostGIS, plus Flutter analyze/test/build.

## Safety switches

* `NOTIFY_REAL_RESIDENTS=false` (default everywhere): live government alerts are ingested and shown, but **no
  real resident is notified**. Real alerts can be replayed into the fictional demo ward.
* `DEMO_MODE_ENABLED`: demo personas, simulator and reset exist only when true; production refuses to start
  with it on.
* Demo SMS never leaves the simulator unless a number is explicitly allow-listed.

## Documentation

* [Architecture](docs/architecture.md) — components, escalation modes, priority score, dispatch safety
* [API contract](docs/api-contract.md) + [`openapi.json`](docs/openapi.json)
* [Database schema](docs/database-schema.md)
* [Security & privacy](docs/security-and-privacy.md) — controls, retention, known gaps
* [Deployment](docs/deployment.md) — Supabase, Firebase, httpSMS, Render/Railway, Flutter builds
* [Demo runbook](docs/demo-runbook.md) — the 3-minute judge demo
* [Requirements traceability](docs/requirements-traceability.md)
* [Troubleshooting](docs/troubleshooting.md)

## Status and limitations (honest summary)

See the "Verification status" section of [`docs/requirements-traceability.md`](docs/requirements-traceability.md)
for what is implemented and tested, implemented but not verified against a real external service (FCM, httpSMS,
Supabase Auth), simulated for the demo, and not implemented.

## License

MIT — see [LICENSE](LICENSE). SACHET CAP samples in `fixtures/cap/sachet_*` are published by NDMA as public domain.
OpenStreetMap tiles © OpenStreetMap contributors.
