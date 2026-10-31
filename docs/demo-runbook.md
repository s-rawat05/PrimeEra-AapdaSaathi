# Demo runbook — the 3-minute judge demo

Everything below runs against **persisted backend state**; the screens only display what the API returns.
All people, phone numbers, wards and relief posts are fictional. Real residents are never notified
(`NOTIFY_REAL_RESIDENTS=false`).

## Before the judges arrive (T-15 min)

1. `powershell -ExecutionPolicy Bypass -File scripts\run_demo.ps1 -Fresh` (add `-ApiPort 8010 -Rebuild` if
   port 8000 is busy). It prints three URLs.
2. Laptop screen: **Command centre** (`http://localhost:8080`) → *Demo accounts* → **Arjun Mehta (Control Room)**.
3. Phone or second browser window: **Resident app** (`http://localhost:8081`, or the APK pointed at the laptop
   IP) → *Demo personas*. Keep tabs ready for **Ramesh Joshi**, **Sunita Rawat**, **Vikram Rawat** and the
   volunteer **Sneha Karki (NCC)**.
4. Command centre → Demo controls → **Reset** (proves a clean slate; real data untouched).
5. Internet check: SACHET panel → **Fetch now**. If the venue has no internet, use **Simulate →
   demo_flash_flood_alert** in step 2 instead (same pipeline, fixture labelled SIMULATED).

## The 3 minutes

| t | Say | Do (screen) | What the judges see |
|---|---|---|---|
| 0:00 | "SACHET already tells people. Nobody tells the control room who is safe." | SACHET panel → Fetch now | Real Uttarakhand-SDMA alert, sender/severity, original XML view; feed health green; ETag 304 on refetch |
| 0:20 | "We replay this real alert into a fictional drill ward — real residents are never notified." | Replay → onset 20 min | Incident labelled **REPLAY (drill)**, Mode C *parallel* because onset < 30 min; 16 residents, amber markers; Kishan turns gray (phone off) |
| 0:40 | "Each person gets the alert their body can receive." | Resident app as **Ramesh** (deaf) | Screen flashes, vibration, torch (phone), large text; official text shown separately from our presentation |
| 0:55 | "One tap." | Ramesh → **SAFE** | Marker turns green, counter SAFE 1 |
| 1:05 | "No smartphone? One digit." | Feature-phone simulator: Govind → send `1` | SMS acknowledgement in his inbox; SAFE 2 |
| 1:20 | "Sunita uses a wheelchair." | Resident app as **Sunita** → **HELP** | Red marker; priority list: 40 mobility + 30 help + minutes = top; neighbour + volunteer requested |
| 1:35 | "A human for those who don't reply." | App as **Vikram** (neighbour) → Mohan → **Cannot reach** | Timeline: neighbour could not reach → volunteer escalation; if no helper can arrive safely, *"No helper can safely arrive in time — prioritise rescue"* with the reason |
| 1:55 | "Severe alerts need a human to approve dispatch." | Command centre → approve Sunita's task (if pending) → app as **Sneha** → **Accept** | Task ACCEPTED; exact location visible to Sneha only now (audited); walk time shown as an *estimate* |
| 2:15 | "Reached." | Sneha → **Reached — resident safe** | Sunita green; counters SAFE 3; task closed; Sneha loses location access |
| 2:30 | "And the control room gets accountability, not guesswork." | Incident → **Closing report** | Alert-to-safe median/p90 by channel, unresolved list (Mohan, Kamla …) with reasons, CSV download |
| 2:50 | "Transparent rules, no AI in safety decisions, privacy by default." | Point at score breakdown + audit log | |

Backup: if any UI step misbehaves, run `worker\.venv\Scripts\python scripts\demo_smoke.py http://localhost:8000
--pace 3` — it performs the identical flow through the API while the command centre updates live.

## Personas (fictional)

| Persona | Role | Use in demo |
|---|---|---|
| Arjun Mehta (Control Room) | operator | Command centre |
| Priya Nair (Demo Admin) | admin | Registry, wards, volunteers, templates |
| Ramesh Joshi | resident — deaf | Visual/vibration/torch alert → SAFE in app |
| Govind Singh Negi | resident — feature phone | SMS `1` |
| Sunita Rawat | resident — wheelchair | HELP |
| Mohan Lal Arya | resident — bedridden, alone, feature phone | No reply → neighbour cannot reach |
| Kishan Ram | resident — phone switched off | UNREACHABLE (gray) |
| Anita Negi / Bhuwan Chandra / Deepa Kandpal | vision / cognitive / hearing+elderly | Text-to-speech, easy-read, combined modes |
| Prakash Rana | resident — consent expired | Not alerted (consent enforcement) |
| Neha Bisht | caregiver of Kamla & Saroj | Caregiver dashboard |
| Vikram Rawat, Pooja Joshi | neighbours | Neighbour checks |
| Aman Verma (NSS), Sneha Karki (NCC) | volunteers | Tasks; Dev Bisht is outside radius (shows ineligibility reason) |

## Q&A crib

* **Why not AI for prioritising?** Safety decisions must be explainable and auditable; every score component is
  shown and every rule is a unit-tested function.
* **What if the phone is on silent?** Android cannot universally bypass DND; we use high-importance channels and
  full-screen intents where permitted, SMS in parallel, and a human (neighbour/volunteer) for non-responders.
* **What if SMS replies don't reach you?** The app never shows "delivered" for a queued action; the escalation
  ladder still sends a human.
* **Is this live?** Feed ingestion and ETag handling were verified against the real SACHET service. Real-resident
  notification is deliberately off until a district authorises it.
