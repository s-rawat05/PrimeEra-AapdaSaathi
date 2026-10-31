# AapdaSaathi API contract (v1)

Base path: `/api/v1`. Machine-readable spec: [`openapi.json`](openapi.json) (also live at `/docs` and `/openapi.json`
on a running backend). This page explains the conventions and the flows; the OpenAPI file is authoritative for
field names and types.

## Conventions

| Topic | Rule |
|---|---|
| Auth | `Authorization: Bearer <access_token>`. Roles are read from the database on every request — never trusted from the client. |
| Errors | Non-2xx bodies are `{"error": {"code": "snake_case", "message": "Human readable"}}`. `401` unauthenticated, `403` forbidden, `404` not found, `409` state conflict (e.g. task already closed), `422` validation, `429` rate limited. |
| Time | All timestamps are UTC ISO-8601 with offset (e.g. `2026-07-14T10:30:00Z`). Clients convert to local time for display. |
| Pagination | List endpoints that can grow return `{"items": [...], "total", "limit", "offset"}` and accept `?limit=&offset=`. |
| Idempotency | `POST /alerts/{id}/respond` accepts an `Idempotency-Key` header (or `client_request_id` in the body). Replaying the same key returns the original response — safe for offline retry queues. All Safe/Help transitions are also naturally idempotent. |
| Privacy | Phone numbers are masked (`+91••••••0003`) except in an *active* task detail. Exact resident coordinates are returned only by `GET /tasks/{id}` while that task is ASSIGNED/ACCEPTED, by `GET /residents/me/location` to the resident, to consented caregivers, and to operators during an active incident (`GET /deliveries/{id}/location`) — every access is audited. |
| Official text | `official.*` fields and incident `headline/description/instruction` are the CAP text verbatim. `presentation.*` is AapdaSaathi's framing and is labelled as such (`presentation.label`). Never present framing as official. |

## Authentication

| Endpoint | Use |
|---|---|
| `POST /auth/otp/request {phone}` | Sends a 6-digit code by SMS. In demo mode the code lands in the SMS simulator inbox (`GET /demo/sms/outbox`). |
| `POST /auth/otp/verify {phone, code, full_name?}` | Returns a token. `is_new_user=true` → go to onboarding. `full_name` required for first sign-up. |
| `POST /auth/login {identifier, password}` | Admin/operator password login. |
| `GET /auth/demo-personas` | Fictional demo accounts (empty list when demo mode is off). |
| `POST /auth/demo-login {user_id}` | Sign in as a demo persona (demo mode only, demo accounts only). |
| `GET /me` | `{user, resident?, volunteer?, demo_mode, notify_real_residents}` — use `user.role` for navigation. |
| `PATCH /me {language}` | `en` or `hi`. |
| `POST /me/devices {fcm_token, platform}` | Register for push. |
| `POST /realtime/ticket` | One-time ticket (60 s) for the WebSocket. |

## Realtime

`GET ws(s)://<host>/api/v1/realtime?ticket=<ticket>` → JSON events. Operators/admins receive every event; other
users receive events addressed to them. Events are *hints to refetch* — the API stays the source of truth.

```json
{"type": "delivery.updated", "incident_id": "...", "delivery_id": "...", "status": "SAFE"}
{"type": "task.updated", "incident_id": "...", "task_id": "..."}
{"type": "incident.updated", "incident_id": "..."}
{"type": "notification.created", "incident_id": "...", "task_id": null}
{"type": "feed.updated", "url": "..."} / {"type": "feed.message", "cap_message_id": "..."}
{"type": "demo.reset"} / {"type": "ping"} / {"type": "hello", "role": "operator"}
```

Clients must also poll (e.g. every 10–15 s) as a fallback when the socket is down.

## Resident app flows

1. **Onboarding:** `GET /wards/public` → `POST /residents/me/registration` (needs, language, location + consents,
   trusted contacts). Registry consent is mandatory; consent lasts 90 days (`reverify_due_at`).
2. **Home:** `GET /me` + `GET /alerts/active` (also records the in-app "seen" receipt).
3. **Respond:** `POST /alerts/{delivery_id}/respond {status: SAFE|HELP}` → `{status, changed, server_time}`.
4. **History:** `GET /alerts/history`.
5. **Consent:** `POST /residents/me/consent/withdraw` (deletes exact location), `POST /residents/me/consent/renew`.

`AlertOut.accessibility_modes` drives presentation and must be applied as a union:
`vibrate, flash_screen, torch_blink, large_text, pictograms, text_to_speech, voice_prompts, large_controls,
assistance_prompt, easy_read, step_by_step, repeat_reminders, no_voice_response, sms_only`.

## Caregiver / neighbour / volunteer

| Role | Endpoints |
|---|---|
| Caregiver | `GET /caregiver/residents` (linked residents, their active alert rows, location only if consented) · `POST /caregiver/alerts/{delivery_id}/respond {status, note}` |
| Neighbour | `GET /neighbour/checks[?include_closed=true]` · `POST /neighbour/checks/{task_id}/respond {outcome: SAFE|HELP|CANNOT_REACH, note}` |
| Volunteer | `GET /volunteer/me` · `PUT /volunteer/me/availability {is_available}` · `GET /volunteer/tasks` · `GET /tasks/{id}` (detail; exact location + phone only while active) · `POST /volunteer/tasks/{id}/accept` · `POST /volunteer/tasks/{id}/cant-go {reason: route_blocked|too_far|unsafe|unavailable, note}` · `POST /volunteer/tasks/{id}/reached {outcome: resident_safe|evacuated|needs_rescue|not_found, note}` (note required for the last two) |

Task lifecycle: `PENDING_APPROVAL → ASSIGNED → ACCEPTED → REACHED`; `ASSIGNED/ACCEPTED → CANT_GO` (auto-reassigns);
neighbour checks end `COMPLETED` with `outcome`. Closed states: `REACHED, COMPLETED, CANT_GO, CANCELLED, REJECTED`.

## Command centre (admin/operator)

| Area | Endpoints |
|---|---|
| Incidents | `GET /incidents?status=active` · `POST /incidents` (manual) · `GET/PATCH /incidents/{id}` · `POST /incidents/{id}/close {note}` |
| Live view | `GET /incidents/{id}/priority` (ranked, with `priority_components`) · `GET /incidents/{id}/map` (ward GeoJSON, markers, volunteers, relief posts) · `GET /incidents/{id}/timeline` · `GET /incidents/{id}/tasks` |
| Case actions | `GET /deliveries/{id}/timeline` · `POST /deliveries/{id}/resend` · `POST /deliveries/{id}/override {status, reason}` · `POST /deliveries/{id}/dispatch` · `GET /deliveries/{id}/candidates` (eligibility + reasons) · `GET /deliveries/{id}/location` (audited) |
| Dispatch | `POST /tasks/{id}/approve` · `POST /tasks/{id}/reject {reason}` · `POST /tasks/{id}/reassign {to_volunteer_id?, reason}` |
| Reports | `GET /incidents/{id}/report` (JSON) · `GET /incidents/{id}/report.csv` |
| SACHET | `GET /feed/status` · `POST /feed/poll` · `GET /feed/messages` · `GET /feed/messages/{id}/xml` · `POST /feed/messages/{id}/replay {onset_in_minutes, ward_ids?}` |
| Demo | `GET /demo/status` · `POST /demo/simulate {fixture, onset_in_minutes}` · `POST /demo/reset` · `POST /demo/sms/inbound {from_phone, body}` · `GET /demo/sms/outbox?phone=` · `POST /demo/seed` |
| Audit | `GET /audit?entity_type=&action=` |
| Admin | `/admin/wards` (+ `POST /admin/wards/geojson` multipart `file`, `PUT /admin/wards/{id}/access`) · `/admin/shelters` · `/admin/residents` (+ assisted registration, reverify, withdraw, erase) · `/admin/volunteers` · `/admin/neighbour-links` · `/admin/pre-assigned` · `/admin/templates` · `/admin/users` |

Delivery statuses: `PENDING`, `NO_REPLY` (alerted, awaiting reply), `SAFE`, `HELP`, `UNREACHABLE` (every external
channel failed). Map colours: SAFE green, HELP red, NO_REPLY amber, UNREACHABLE gray.

Escalation modes (shown as `escalation_mode` + `mode_label`): **A** pre-evacuation (>6 h), **B** scaled sequential
(30 min–6 h, interval = 10 % of window clamped 1–15 min), **C** parallel (<30 min), **D** accountability (ongoing).
