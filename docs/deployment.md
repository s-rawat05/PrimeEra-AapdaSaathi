# Deployment and configuration

> Status: deployment configuration is **prepared but not deployed**. No public URL exists yet.

## 1. Local development (no Docker needed)

Prerequisites: Python 3.11+ (tested 3.13), Flutter 3.47+ (tested 3.47.9), Android SDK 36 + JDK 17/21 for APKs.

```bash
# Backend (SQLite, fictional demo data seeded automatically)
cd worker
python -m venv .venv
.venv/Scripts/python -m pip install -r requirements-dev.txt      # Windows; use .venv/bin/python on Linux/macOS
copy ..\.env.example .env                                        # then set JWT_SECRET etc.
.venv/Scripts/python -m uvicorn app.main:app --reload --port 8000
# → http://localhost:8000/docs  (OpenAPI)   http://localhost:8000/api/v1/ready
```

> Windows note: Flutter and the Android SDK must live in a path **without spaces** (e.g. `C:\dev\flutter`,
> `C:\dev\android-sdk`). The repository itself may contain spaces.

```bash
# Command centre (Flutter Web)
cd dashboard
flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:8000

# Resident/responder app
cd app
flutter run -d chrome  --dart-define=API_BASE_URL=http://localhost:8000          # web, for demos
flutter run -d <device> --dart-define=API_BASE_URL=http://<laptop-LAN-IP>:8000   # physical phone
```

Windows helpers: `scripts/run_demo.ps1` starts the backend and serves both web builds.

## 2. Environment variables

All variables are documented in [`.env.example`](../.env.example). The important ones:

| Variable | Default | Notes |
|---|---|---|
| `APP_ENV` | development | `production` enables boot-time safety checks (refuses demo mode, simulator SMS, dev secrets). |
| `NOTIFY_REAL_RESIDENTS` | **false** | Safety switch. Keep false until the deployment is formally authorised. |
| `DATABASE_URL` | SQLite file | `postgresql+asyncpg://…` for Supabase. |
| `AUTH_MODE` | local | `supabase` → verify Supabase JWTs with `SUPABASE_JWT_SECRET`. |
| `JWT_SECRET` | dev value | ≥ 32 random chars in any shared environment. |
| `DEMO_MODE_ENABLED` | true | Must be false in production. |
| `DEMO_ESCALATION_INTERVAL_SECONDS` | 30 | Escalation step interval for demo incidents. |
| `SACHET_RSS_URLS` | Uttarakhand feed | Comma-separated; from https://sachet.ndma.gov.in/CapFeed |
| `FEED_POLL_ENABLED` / `FEED_POLL_SECONDS` | false / 45 | Background polling (operators can always "Fetch now"). |
| `SMS_PROVIDER` | simulator | `httpsms` + `HTTPSMS_API_KEY`, `HTTPSMS_FROM_NUMBER`, `SMS_WEBHOOK_SECRET`. |
| `DEMO_SMS_ALLOWLIST` | empty | Real team phones allowed to receive demo SMS on stage. |
| `FIREBASE_CREDENTIALS_FILE` | empty | Path to a service-account JSON **outside** the repo. |
| `WALKING_SPEED_M_PER_MIN`, `HILL_TERRAIN_FACTOR`, `ASSIST_BUFFER_MINUTES`, `MAX_WALK_MINUTES_ACTIVE_HAZARD` | 75, 1.4, 10, 15 | Dispatch safety estimates. |

## 3. Supabase

1. Create a project (region: Mumbai). Enable the PostGIS extension (Database → Extensions).
2. `supabase link --project-ref <ref>` then `supabase db push` (applies `supabase/migrations`), then run
   `supabase/seed.sql` (templates only — no people).
3. Backend env: `DATABASE_URL=postgresql+asyncpg://postgres:<db-password>@db.<ref>.supabase.co:5432/postgres`,
   `AUTH_MODE=supabase`, `SUPABASE_URL`, `SUPABASE_JWT_SECRET` (Settings → API). Use the **direct** connection
   (port 5432), not the transaction pooler — the worker relies on row locks inside transactions.
4. Create operations users: insert a `users` row with `role='admin'` and `auth_user_id` = the Supabase user id,
   or use `POST /api/v1/admin/users` from an existing admin. There is **no** default admin account.
5. Never expose the service-role key to the apps; they talk only to the FastAPI backend.

## 4. Firebase Cloud Messaging (optional)

1. Create a Firebase project, add an Android app with package `in.primeera.aapda_saathi`.
2. Backend: download a service-account key, store it outside the repo, set `FIREBASE_CREDENTIALS_FILE`.
3. App: pass `--dart-define=FIREBASE_API_KEY=… FIREBASE_APP_ID=… FIREBASE_SENDER_ID=… FIREBASE_PROJECT_ID=…`.
   Without these the app skips Firebase and relies on in-app realtime + SMS.

## 5. SMS gateway (httpSMS)

1. Install the httpSMS Android app on a phone with a SIM (or self-host the server), get an API key.
2. Set `SMS_PROVIDER=httpsms`, `HTTPSMS_API_KEY`, `HTTPSMS_FROM_NUMBER` (E.164).
3. In httpSMS add a webhook → `https://<api-host>/api/v1/sms/webhook`, event `message.phone.received`, and set its
   signing key as `SMS_WEBHOOK_SECRET`. The backend rejects unsigned requests.
4. Verify the payload format against the current httpSMS docs (implemented from the documented CloudEvent shape;
   not verified against a live account here).

## 6. Backend hosting (Render / Railway)

* Render: `render.yaml` blueprint (Docker, health check `/api/v1/health`). Set secrets in the dashboard.
* Railway: deploy `worker/Dockerfile` with build context = repo root; same env vars; port from `$PORT`.
* Run **one** instance (in-process realtime bus and background loops; see architecture).
* Logs are JSON on stdout; `/api/v1/ready` reports DB status, worker heartbeats and the safety-switch state.

## 7. Flutter builds

```bash
cd app
flutter build apk --debug   --dart-define=API_BASE_URL=http://10.0.2.2:8000            # emulator
flutter build apk --release --dart-define=API_BASE_URL=https://api.example.org         # needs signing config
cd ../dashboard
flutter build web --release --dart-define=API_BASE_URL=https://api.example.org
```

Release APK signing: create a keystore outside the repo and reference it from `app/android/key.properties`
(git-ignored). Host `dashboard/build/web` on any static host (Netlify, Vercel, Firebase Hosting, Supabase
Storage); add its origin to `CORS_ORIGINS`.

## 8. Docker Compose (production-like local stack)

```bash
copy .env.example .env
docker compose up --build      # PostGIS 17 + migrations + API on :8000
```

Not run on the development machine (Docker is not installed there); CI runs the equivalent PostGIS job.
