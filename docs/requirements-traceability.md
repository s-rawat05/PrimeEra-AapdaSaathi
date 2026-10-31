# Requirements traceability

**Source note.** The "AapdaSaathi Master PRD" referenced in the build brief was **not provided** in the
workspace. Requirements below are traced to the numbered sections of the *Master Build Prompt* (§) — which
restates the PRD's rules (escalation modes, priority formula, SMS codes, data model, demo script) — and to the UI
reference image. When the PRD is added to `docs/`, reconcile any rule it states differently.

Status legend: **✅ tested** (automated test) · **🔵 verified live** (checked against the real service) ·
**🟡 implemented, not verified** against the real external service · **🟣 simulated** for the demo ·
**⬜ not implemented**.

Backend paths are relative to `worker/app/`; tests to `worker/tests/`.

## §8 SACHET and CAP

| Requirement | Implementation | Test / evidence | Status |
|---|---|---|---|
| Uttarakhand RSS URL from the official listing | `config.py` default; taken from https://sachet.ndma.gov.in/CapFeed and the feed's `atom:link self` | — | 🔵 |
| Polling 30–60 s, timeouts | `integrations/sachet_ingest.py`, `FEED_POLL_SECONDS` (15–600, default 45), connect/read timeouts | `test_feed_ingestion` | ✅ |
| ETag / If-None-Match, 200 vs 304 | `poll_feed` | `test_etag_304_and_idempotent_items`; live run returned 304 from SACHET | ✅🔵 |
| Retry with backoff after failures (persisted) | `_failure`, `feed_state.next_fetch_at` | `test_failure_backoff_is_persisted` | ✅ |
| DB-backed CAP cache, raw XML unchanged | `cap_messages.raw_xml`, `GET /feed/messages/{id}/xml` | e2e test asserts verbatim prefix | ✅ |
| CAP 1.2 validation, defusedxml | `integrations/cap_parser.py` | `test_cap_parser` (XXE, entity bomb, malformed, invalid enums) | ✅ |
| All listed CAP fields incl. info/area blocks, multiple languages | `parse_cap` | real SACHET fixture + bilingual fixture | ✅ |
| Alert / Update / Cancel / Exercise / Test | `services/incidents.apply_live_cap` | `test_exercise_alert_update_and_cancel_by_geometry` | ✅ |
| Idempotent ingestion | unique identifier + RSS guid check | `test_duplicate_items_are_not_refetched` | ✅ |
| Feed-health indicator | `GET /feed/status` (+ dashboard chip) | `test_failure_backoff_is_persisted` | ✅ |
| Never invent instructions; label presentation | `notifications/templates.py` (`NO_INSTRUCTION`, `presentation.label`), template CHECK requires `{headline}` | e2e asserts label + official sender | ✅ |
| `NOTIFY_REAL_RESIDENTS=false` default; live alert never notifies real residents | `config.py`, `dispatcher.may_notify`, `incidents.create_deliveries` | `test_live_alert_never_notifies_real_residents_by_default`, `test_safety_switch_enabled_notifies_real_residents` | ✅ |
| Replay real alert into demo ward (demo residents only) | `POST /feed/messages/{id}/replay`, `incidents.replay_into_demo` | `test_replay_requires_demo_wards_and_keeps_official_text`, e2e | ✅🔵 |

## §9 Matching and delivery

| Requirement | Implementation | Test | Status |
|---|---|---|---|
| PostGIS spatial matching | `matching/ward_matcher.py` (`ST_Intersects`, `ST_DWithin`); Shapely on SQLite | geometry match test; PostGIS geometry test in `test_schema_parity` | ✅ |
| LGD/district fallback, labelled as imprecise | `match_wards` lgd branch note | `test_live_alert_never_notifies…` asserts note | ✅ |
| CAP `lat,lon` → GeoJSON `[lon,lat]` | `parse_polygon` | `test_demo_fixture_multilingual_with_polygon` | ✅ |
| One delivery per resident per incident | unique constraint `uq_delivery_incident_resident` | e2e (16 deliveries) | ✅ |
| Channel selection by capability/consent/devices | `dispatcher.alert_resident` | e2e, feature-phone path | ✅ |
| Push (FCM) | `integrations/fcm_gateway.py`; app registers token `POST /me/devices` | — no Firebase project available | 🟡 |
| SMS via configurable gateway | `integrations/sms_gateway.py` (simulator, httpSMS) | simulator in tests | 🟣 (httpSMS 🟡) |
| Re-alerts, retries, duplicate protection, error states | outbox `flush_outbox` (lease, backoff, max 3), idempotency keys | `test_duplicate_workers_do_not_double_act`, Kishan UNREACHABLE in e2e | ✅ |
| Accessibility profiles combined (union) | `templates.NEED_MODES` / `accessibility_modes` | e2e asserts hearing modes | ✅ |
| Official text always accessible | `AlertOut.official` | e2e | ✅ |

## §10 Responses

| Requirement | Implementation | Test | Status |
|---|---|---|---|
| SAFE (app or SMS): status, timestamp, channel, map update, cancel unnecessary escalation, history | `services/responses.apply_status` | e2e, `test_safe_reply_racing_due_timer` | ✅ |
| HELP: immediate assistance workflow, neighbours/helpers, command centre, top of list | `apply_status` HELP branch | e2e, priority test | ✅ |
| No reply follows escalation mode, every action logged, no duplicates | `escalation/engine.py` | `test_escalation_engine` | ✅ |
| Unreachable tracked separately, priority-based | `refresh_reachability`, priority rule | e2e (Kishan), rules tests | ✅ |
| SMS `1/SAFE`, `2/HELP`, `3` cannot reach | `parse_sms_reply` | `test_parse_sms_reply` | ✅ |
| Reject ambiguous / duplicate / unauthorised / stale replies | `process_inbound_sms` | `test_sms_flows` | ✅ |
| Signed webhook | `/sms/webhook`, `verify_httpsms_webhook` | `test_webhook_requires_signature` | ✅ (live httpSMS 🟡) |

## §11 Escalation engine

| Requirement | Implementation | Test | Status |
|---|---|---|---|
| `time_window = onset − now`; urgency fallback visible | `rules.resolve_onset`, `onset_fallback_note` | `test_onset_fallback_is_flagged_and_documented` | ✅ |
| Mode A > 6 h pre-evacuation | `activate_delivery` → `preevac_assist` | `test_mode_a_arranges_pre_evacuation` | ✅ |
| Mode B: 10 % interval, min 1, max 15 min; neighbour → volunteer → command centre | `rules.escalation_interval`, ladder | `test_mode_b_interval_is_ten_percent_clamped`, `test_mode_b_sequential_ladder` | ✅ |
| Mode C < 30 min parallel (resident, caregiver, neighbour, pre-assigned helper) | `activate_delivery` | e2e (mode C), caregiver/neighbour tasks | ✅ |
| Mode D accountability, location only to authorised responders | mode D interval, approval policy, location rules | `test_dispatch_approval_policy`, access tests | ✅ |
| Priority formula with visible breakdown | `rules.priority_score`, `PriorityItem.priority_components` | rules tests, e2e | ✅ |
| Deadlines persisted; recovery after restart | `deliveries.next_action_at` | `test_restart_recovers_overdue_actions` | ✅ |
| `FOR UPDATE SKIP LOCKED`, idempotent steps, recheck before acting | `engine._lock_if_due`, `advance` | `test_duplicate_workers_do_not_double_act` | ✅ (SKIP LOCKED path exercised on Postgres run) |
| SAFE vs timer race | lock + recheck | `test_safe_reply_racing_due_timer` | ✅ |
| Concurrent replies, cancellation | | `test_concurrent_duplicate_and_conflicting_replies`, `test_closing_incident_stops_escalation` | ✅ |
| No ML in safety decisions | pure functions in `rules.py`, `eligibility.py` | — | ✅ |

## §12 Dispatch and safety

| Requirement | Implementation | Test | Status |
|---|---|---|---|
| ASSIGNED → ACCEPTED → REACHED; CANT_GO with mandatory reason | `dispatch/service.py`; DB CHECK | `test_cant_go_requires_reason_and_reassigns` | ✅ |
| Reassign to next eligible | `cant_go` → `request_volunteer`; timeout → reassign | same + `test_unaccepted_volunteer_task_times_out_and_reassigns` | ✅ |
| Availability, ward, distance, walking time with hill factor, time before onset | `dispatch/eligibility.py` | `test_sms_and_dispatch_units` | ✅ |
| Approval for severe incidents | `rules.requires_dispatch_approval`, `/tasks/{id}/approve` | `test_severe_incident_dispatch_needs_approval…` | ✅ |
| Never send into too-slow/unsafe route; show reason; mark for rescue | `request_volunteer` → `needs_rescue` + reason; blocked wards | e2e, `test_cannot_arrive_in_time_is_never_dispatched` | ✅ |
| No LLM instructions; no invented shelters/routes; external maps not "validated" | shelters require official `source`; `walk_estimate_note` | — | ✅ |

## §13 Command centre and realtime

| Requirement | Backend | Status |
|---|---|---|
| Realtime updates | `/api/v1/realtime` WebSocket + one-time tickets (`services/realtime.py`) | ✅ unit + 🔵 live WebSocket check |
| Map, counters, priority, volunteers, tasks, timelines, approvals, reports | `api/ops.py` | ✅ e2e |
| Operator actions validated + audited (replay, simulate, resend, approve/reject, reassign, override, close, report, reset) | `api/ops.py`, `api/misc.py`, `audit/log.py` | ✅ |
| Dashboard UI | `dashboard/` — see "Frontend" section | see below |

## §14 Demo mode

| Requirement | Implementation | Status |
|---|---|---|
| Labelled Demo/Drill mode; source labels live/replay/simulated/exercise | `incidents.SOURCE_LABEL`, `is_demo` | ✅ |
| Fictional demo ward, ≥15–20 residents with mixed needs, caregiver, neighbour, volunteers, feature-phone path | `demo/seed.py` (2 wards, 19 residents, 1 caregiver, 2 neighbours, 3 volunteers) | ✅ |
| Saved CAP fixtures; repeatable simulations; shortened timers | `fixtures/cap/`, `/demo/simulate`, `DEMO_ESCALATION_INTERVAL_SECONDS` | ✅ |
| One-click reset that never modifies real data | `demo/service.reset` (+ invariant check) | `test_demo_reset_never_touches_real_data` ✅ |
| Full 13-step demo against persisted state | `tests/test_e2e_demo_flow.py`, `scripts/demo_smoke.py` | ✅🔵 |

## §6, §15 Auth, roles, privacy

| Requirement | Implementation | Test | Status |
|---|---|---|---|
| Real auth; server-side role enforcement | `auth/` (OTP + password + demo personas; Supabase JWT mode) | `test_auth_and_access` | ✅ (Supabase mode 🟡) |
| Ownership / assignment checks | services + `_require_assignee` | access tests | ✅ |
| Volunteers see exact location only while assigned | `views.task_detail` | e2e + access test | ✅ |
| RLS policies | `supabase/migrations/…_row_level_security.sql` | `test_schema_parity` (Postgres) | ✅ when run on Postgres |
| Consent with timestamp, guardian, 90-day expiry, withdrawal, re-verification | `services/residents.py` | `test_registration_consent_and_withdrawal`, `test_expired_registrations…` | ✅ |
| Coarse vs exact location separation | `residents.coarse_*`, `resident_locations` | registration test | ✅ |
| Audit sensitive access | `location.view`, overrides etc.; append-only trigger | access tests, parity test | ✅ |
| Rate limits, validation, no stack traces, no secrets in git | `main.py`, `.gitignore` | — | ✅ |
| Legal compliance | — | not claimed; see `security-and-privacy.md` | ⬜ review required |

## §7 Database

| Requirement | Where | Status |
|---|---|---|
| Core entities + caregiver links, consent, templates, devices, attempts, timeline, idempotency, job coordination, demo sessions | `supabase/migrations/20261031000001_core_schema.sql` | ✅ |
| Transactions + indexes (status, due escalations, ward geometry GiST, task assignment) | same | ✅ |
| Repeatable setup | `scripts/apply_migrations.py`, `supabase db push` | ✅ |

## §16 API

OpenAPI at `/docs`, exported to `docs/openapi.json`; conventions in `docs/api-contract.md`. Pagination, UTC,
uniform errors, `Idempotency-Key` on responses. ✅

## Frontend (§5, §17)

### Resident mobile app (`app/lib/`)

| Requirement / Screen | Implementation | Test / evidence | Status |
|---|---|---|---|
| Splash & Intro onboarding | `features/splash/intro_screen.dart`, `features/onboarding/resident_onboarding_screen.dart` | `app_flow_test.dart` ("first launch shows intro") | ✅ |
| Role-based authentication & demo persona selection | `features/auth/login_screen.dart`, `routing/root_gate.dart`, `routing/role_shell.dart` | `app_flow_test.dart` ("auth states logged out shows login; demo personas listed") | ✅ |
| Language switching (Hindi / English) | `features/onboarding/language_screen.dart`, `l10n/strings.dart` | `app_flow_test.dart` ("language switching changes strings instantly") | ✅ |
| Need categories & Accessibility profiles | `accessibility/modes.dart`, `accessibility/alert_effects.dart`, `widgets/flash_overlay.dart` | `app_flow_test.dart` ("flash_screen shows overlay", "vibrate starts") | ✅ |
| Resident home dashboard (Reference Design Screen 1) | `features/resident/resident_home_screen.dart` (`_Header`, `_WeatherDisasterCard`, `AlertStatusCard`, `_CommunityStats`, `_CommunityActions`) | `app_flow_test.dart` ("no active alerts", "active alert card") | ✅ |
| Weather & flood disaster info card with illustration | `features/resident/resident_home_screen.dart` (`_WeatherDisasterCard`, `_FloodIllustrationPainter`) | UI reference parity; widget tests pass | ✅ |
| Disaster threat meter (Speedometer Arc Gauge) | `features/resident/resident_home_screen.dart` (`_SpeedometerGaugePainter`) | UI reference parity (Green→Yellow→Orange→Red arc with needle) | ✅ |
| Active disaster alert & official text viewer | `features/alerts/alert_detail_screen.dart`, `features/alerts/easy_read_screen.dart` | `app_flow_test.dart` ("official-section", "officialText") | ✅ |
| Full-screen emergency response (SAFE / HELP / SOS) | `features/alerts/emergency_response_screen.dart` | `app_flow_test.dart` ("SAFE/HELP/SOS have semantics labels") | ✅ |
| Evacuation route & shelter map (Reference Design Screen 2 & 3) | `features/evacuation/evacuation_screen.dart` (`_Map`, `_Sheet`, `_InstructionList`) | `app_flow_test.dart` ("evacuation shows relief post, direction-only line") | ✅ |
| SAFE confirmation workflow | `features/alerts/safe_confirmation_screen.dart` | `app_flow_test.dart` ("SAFE needs confirmation, calls API") | ✅ |
| HELP request workflow & status tracking | `features/alerts/help_status_screen.dart` | `app_flow_test.dart` ("HELP confirmation calls API, shows status") | ✅ |
| Offline / SMS fallback mechanism | `features/alerts/sms_reply.dart`, `services/offline_queue.dart`, `widgets/connection_banner.dart` | `app_flow_test.dart` ("reply queued when offline; Reply by SMS opens sms:") | ✅ |
| Persistent round red SOS button (`SosFab` / `SosPillButton`) | `widgets/sos_button.dart` | `app_flow_test.dart` ("sos-pill", "sos-fab", 112 fallback) | ✅ |
| Alert history & stats | `features/alerts/alert_history_screen.dart` | `app_flow_test.dart` | ✅ |
| Caregiver dashboard & behalf actions | `features/caregiver/caregiver_screen.dart` | `app_flow_test.dart` ("caregiver responds on behalf") | ✅ |
| Neighbour check requests & response | `features/neighbour/neighbour_checks_screen.dart` | `app_flow_test.dart` ("neighbour answers a check") | ✅ |
| Volunteer task dashboard, accept, cant-go & outcome | `features/volunteer/volunteer_tasks_screen.dart`, `features/volunteer/task_detail_screen.dart`, `features/volunteer/task_actions.dart` | `app_flow_test.dart` ("volunteer accept, cant go, toggle availability, reached") | ✅ |
| Profile & preferences management | `features/profile/profile_screen.dart` | `app_flow_test.dart` | ✅ |

### Command centre & Admin portal (`dashboard/lib/`)

| Requirement / Section | Implementation | Test / evidence | Status |
|---|---|---|---|
| Ops Authentication & Demo persona switcher | `features/authentication/login_page.dart` | `widget_test.dart` ("demo persona login opens command centre") | ✅ |
| Live incident summary & SACHET feed health | `features/overview/incident_summary.dart`, `features/incidents/feed_panel.dart` | `widget_test.dart`, `test_feed_ingestion.py` | ✅ |
| Interactive ward map with PostGIS boundaries & markers | `features/live_map/incident_map.dart`, `features/live_map/geo.dart` | `models_live_test.dart`, manual browser verification | ✅ |
| Status counters (Safe, Help, No Reply, Unreachable) | `features/overview/command_centre_page.dart` | `widget_test.dart` ("command centre renders counters") | ✅ |
| Ranked priority list with transparent score breakdown | `features/overview/priority_list.dart` | `widget_test.dart` ("priority list and score breakdown") | ✅ |
| Dispatch approval for severe incidents | `features/dispatch/tasks_panel.dart`, `features/dispatch/case_panel.dart` | `widget_test.dart` ("approve and reject buttons call API") | ✅ |
| Manual status override with mandatory reason & audit | `features/dispatch/case_panel.dart` | `case_panel_test.dart` ("override button opens reason dialog") | ✅ |
| Realtime updates (WebSocket) | `core/realtime.dart` (`/api/v1/realtime`) | `test_realtime.py` | ✅ |
| Closing report with alert-to-safe statistics | `features/reports/report_page.dart` | `widget_test.dart` ("closing report renders") | ✅ |
| Demo drill panel & SMS simulator | `features/demo_controls/demo_panel.dart`, `features/demo_controls/sms_simulator.dart` | `models_live_test.dart`, `scripts/demo_smoke.py` | ✅ |

## Verification status (summary)

* **Implemented and tested:** everything marked ✅ above (backend test suite).
* **Verified against the real external service:** SACHET RSS + CAP fetch, ETag 304 (🔵).
* **Implemented, not verified against the real service:** FCM push, httpSMS sending/webhook, Supabase Auth JWT
  mode, Supabase-hosted deployment (🟡) — no credentials were available.
* **Simulated for the demo:** SMS delivery and replies (simulator, same pipeline), switched-off phone.
* **Not implemented:** retention purge jobs beyond registration expiry; field-level encryption of phone numbers;
  hazard-aware routing (deliberately not faked).
