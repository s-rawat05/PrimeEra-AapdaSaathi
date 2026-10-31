# AapdaSaathi Command (Flutter Web)

Admin portal + live command centre for the AapdaSaathi backend (`worker/`). Every control calls the real API
(`docs/api-contract.md`); realtime events only trigger refetches, with a 10 s polling fallback.

## Run

```powershell
$env:Path = "C:\dev\flutter\bin;" + $env:Path
flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:8102   # default: http://localhost:8000
flutter build web --dart-define=API_BASE_URL=https://api.example.org     # output: build/web
```

The backend must allow the dashboard origin (`CORS_ORIGINS`). In demo mode the login page offers the fictional
admin/operator personas.

## Layout

- `lib/core` – config (`API_BASE_URL`), `AapdaApi` interface + `HttpAapdaApi`, error model, WebSocket realtime hub, session store
- `lib/models` – typed models matching `docs/openapi.json`
- `lib/services` – auth/session controller, dependency scope, CSV file saver (Blob download on web)
- `lib/routing` – responsive shell (NavigationRail ≥ 1000 px, drawer below) and role-based sections
- `lib/features/*` – authentication, overview (command centre), live_map, dispatch (case panel, tasks), incidents
  (list, dialogs, timeline, SACHET feed), residents, wards, volunteers, neighbour_links, audit, reports, settings
  (templates, users), demo_controls (drills, SMS simulator)

## Tests

`flutter test` – widget tests use `test/support/fake_api.dart`, which serves JSON captured from a real backend
(`test/fixtures/live/`) through the app's parsers; `test/models_live_test.dart` parses every captured response.
