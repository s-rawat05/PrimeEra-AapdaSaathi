# Security and privacy

The resident registry holds sensitive personal information about some of the most vulnerable people in a
district. This page lists what is implemented, where, and what still needs review before any real deployment.

> **Not a compliance claim.** Implementing these controls does not make the system compliant with the Digital
> Personal Data Protection Act, 2023 or any other law. A legal/privacy review, a data-protection impact
> assessment and an agreement with the district authority are required before registering real people.

## Implemented controls

| Area | Control | Where |
|---|---|---|
| Consent | Explicit registry consent required to register; location and caregiver-sharing consents are separate; each record stores who granted it (self / guardian / assisted), guardian name, recorder, timestamp and a **90-day expiry**. | `services/residents.py`, `consent_records` |
| Re-verification | Registrations past `reverify_due_at` become `expired` (hourly job) and receive no alerts until renewed. Residents can renew in-app; admins can re-verify assisted registrations. | `residents.expire_overdue`, `/residents/me/consent/renew` |
| Withdrawal | Withdrawing consent stops future alerts and **deletes the exact location immediately**. | `residents.withdraw` |
| Erasure | Admin erasure of a registry record with a mandatory, audited reason. | `DELETE /admin/residents/{id}` |
| Data minimisation | Accessibility *needs* (e.g. "mobility"), never diagnoses. Registry stores only a ~110 m coarse location; exact coordinates live in `resident_locations`. | models, `residents.coarse()` |
| Exact location access | Returned only to: the resident; caregivers with consent + `can_view_location`; a volunteer/neighbour **while their task is active**; operators during an active incident. Every access is written to `audit_log` (`location.view`). Closed tasks lose access automatically. | `views.task_detail`, `/deliveries/{id}/location`, RLS `locations_read` |
| Authorisation | Role and ownership checked server-side on every request; roles come from the database, never from the client or token. Caregivers only see linked residents; neighbours/volunteers only their assignments. | `auth/deps.py`, services, tests in `test_auth_and_access.py` |
| Row-level security | RLS enabled on **every** table; no write policies (all writes go through the backend); anon role sees nothing. | `supabase/migrations/…_row_level_security.sql`, `test_schema_parity.py` |
| Audit | Append-only audit log (DB trigger blocks UPDATE/DELETE) for logins, registry changes, overrides (with reason, before/after), approvals, reassignments, location views, demo actions. PII keys are scrubbed from before/after snapshots. | `audit/log.py` |
| Auth | Residents: SMS OTP (6 digits, HMAC-hashed, 5-minute expiry, max 5 attempts, max 5 requests/10 min). Ops: scrypt-hashed passwords (min 10 chars), no default admin. Demo personas only when `DEMO_MODE_ENABLED=true` and only for `is_demo` accounts; production refuses to boot with demo mode, simulator SMS or development secrets. | `api/auth.py`, `config.assert_safe_for_production` |
| Webhooks | Inbound SMS webhook requires an HS256-signed JWT (httpSMS signing key); payload validated; provider message id makes processing idempotent. | `/sms/webhook` |
| Input & abuse | Pydantic validation on every body; per-client rate limit; GeoJSON validated (type, validity, WGS84 range, 10 MB cap); defusedxml blocks XXE / entity expansion in CAP. | `schemas`, `main.py`, `admin.py`, `cap_parser.py` |
| Errors & logs | Uniform error body; unhandled errors return a generic message (no stack traces or tokens); structured JSON logs; phone numbers masked in API responses. | `main.py` |
| Secrets | No secrets in git (`.gitignore`, `.env.example` placeholders); Firebase key path points outside the repo. | — |
| Real-resident safety | `NOTIFY_REAL_RESIDENTS=false` by default; live alerts create no deliveries for real people; demo SMS never leaves the simulator unless allow-listed. | `notifications/dispatcher.py` |
| Synthetic data | All demo people, numbers, wards and relief posts are fictional and labelled. | `demo/seed.py`, `fixtures/` |

## Transport and storage

* Production must terminate TLS in front of the API (Render/Railway do this) and use `wss://` for realtime.
  Android cleartext HTTP is allowed **only** for local development hosts.
* Supabase encrypts data at rest; backups follow the Supabase plan. The SQLite demo database is for drills only.

## Retention (proposed — confirm with the district authority)

| Data | Retention |
|---|---|
| Registry + consent | Until withdrawn or 90 days without re-verification, then `expired`; purge expired records after a further 90 days. |
| Exact locations | Deleted on withdrawal; otherwise kept with the registry record. |
| Incidents, deliveries, tasks, timelines | 1 year after closure for after-action review, then aggregate and delete personal fields. |
| Audit log | Append-only; minimum 1 year. |
| OTP challenges, idempotency keys, simulated SMS | 30 days (operational). |

The purge jobs beyond `expire_overdue` are **not yet implemented** — they are listed here so the decision is
explicit, not forgotten.

## Known gaps before production

1. Legal/privacy review and DPIA; consent wording reviewed in Hindi and English.
2. Purge jobs for the retention table above.
3. Field-level encryption of phone numbers (currently protected by RLS + API masking only).
4. Penetration test; dependency scanning in CI.
5. Multi-instance realtime (see architecture) and a hosted rate limiter.
6. Supabase Auth integration tested against a real project (implemented, not verified — no credentials here).
