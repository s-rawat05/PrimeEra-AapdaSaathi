# Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `'C:\Users\Sahil' is not recognized…` when running `flutter` or `sdkmanager` | Flutter/Android tools break on paths with spaces | Install them under `C:\dev\…` (no spaces). |
| `GET /api/v1/...` returns `{"detail":"Not Found"}` from a different "AapdaSaathi API" | Another server already listens on port 8000 | `netstat -ano | findstr :8000`, stop it or run this backend with `--port 8010` and pass `--dart-define=API_BASE_URL=http://localhost:8010`. |
| Browser shows CORS errors | Web origin not allowed | Add the origin to `CORS_ORIGINS` (comma separated). For local experiments `CORS_ORIGINS=*`. |
| Android emulator cannot reach the API | `localhost` is the emulator itself | Use `http://10.0.2.2:<port>`; on a phone use the laptop's LAN IP and allow the port in the firewall. |
| `database is locked` on SQLite | Very long transaction or a second process on the same file | Use one backend process per SQLite file; use Postgres for anything beyond a demo. |
| Feed status unhealthy, `HTTP 403` errors | SACHET occasionally refuses individual CAP files / rate-limits | Backoff is automatic; failed items are retried next poll. Use **Simulate** with a saved fixture during a demo without internet. |
| Real alert ingested but no incident | No registered ward matches its area | Upload ward GeoJSON with `lgd_district_code` (Admin → Wards). Unmatched alerts still appear in the feed panel and can be replayed into the demo ward. |
| Live incident shows 0 deliveries | Safety switch `NOTIFY_REAL_RESIDENTS=false` (by design) | Timeline explains it. Use replay into the demo ward for demonstrations. |
| Volunteer task stuck in `PENDING_APPROVAL` | Severe/Extreme incident, Mode D or restricted ward | An operator approves or rejects it in the command centre. |
| "No helper can safely arrive in time" | Dispatch safety check (walk estimate + buffer > time to onset) | Intended. The case stays top of the priority list for professional rescue. |
| Resident not alerted | Consent expired/withdrawn, registration expired, or ward not in incident | Check Admin → Residents (consent expiry) and the incident's matched wards. |
| Demo SMS not arriving on a real phone | Demo SMS always uses the simulator | Add the phone to `DEMO_SMS_ALLOWLIST` and set `SMS_PROVIDER=httpsms`. |
| Push notifications missing | Firebase not configured | Set `FIREBASE_CREDENTIALS_FILE` (backend) and the Firebase dart-defines (app). In-app + SMS still work. |
| Android does not ring in silent/DND mode | OS policy | The app cannot bypass DND universally. Ask the resident to allow notification access / full-screen alerts in Profile → Permissions; SMS and human follow-up remain. |
| Production boot fails with "Unsafe production configuration" | `APP_ENV=production` with demo mode, simulator SMS or dev secrets | Set real secrets, `DEMO_MODE_ENABLED=false`, `SMS_PROVIDER=httpsms`. |
