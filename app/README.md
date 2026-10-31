# AapdaSaathi app (Flutter, Android + web)

Resident and responder app for the AapdaSaathi backend (`worker/`). Roles come from `GET /api/v1/me`:
resident, caregiver, neighbour and volunteer each get their own home; admin/operator are sent to the web
command centre.

## Configuration (`--dart-define`)

| Key | Default | Use |
|---|---|---|
| `API_BASE_URL` | `http://10.0.2.2:8000` (Android emulator), `http://localhost:8000` (web) | Backend origin; API at `/api/v1`, realtime at `ws(s)://…/api/v1/realtime` |
| `SMS_GATEWAY_NUMBER` | empty | Number used by "Reply by SMS" (`sms:` URI with body `1`/`2`) |
| `FIREBASE_API_KEY`, `FIREBASE_APP_ID`, `FIREBASE_SENDER_ID`, `FIREBASE_PROJECT_ID` | empty | Optional FCM; skipped when any is missing |
| `SUPABASE_URL`, `SUPABASE_ANON_KEY` | empty | Optional Supabase phone-OTP sign-in (unverified path) |

```
flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:8101
flutter build apk --debug --dart-define=API_BASE_URL=http://10.0.2.2:8101
```

Android debug builds allow cleartext HTTP (`res/xml/network_security_config.xml`) for local development only.

## Layout

`lib/core` (config, typed API client + `ApiException`), `lib/models`, `lib/services` (session, connectivity,
Hive offline queue, realtime, notifications, device), `lib/repositories`, `lib/state` (AppController),
`lib/accessibility` (modes + alert effects), `lib/routing`, `lib/l10n` (English/Hindi strings), `lib/features/*`.

## Tests

- `flutter test` — widget/unit tests with a fake API (`test/helpers.dart`); fixtures in `test/fixtures` are real
  JSON captured from the demo backend.
- `flutter test integration_live/live_backend_test.dart --dart-define=LIVE_API=http://localhost:8101` — runs
  the app's HTTP client against a live backend in demo mode (resets demo data and simulates the demo alert).
