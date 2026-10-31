# AapdaSaathi developer commands (GNU make; on Windows use scripts/*.ps1 equivalents).
PY      ?= worker/.venv/bin/python
FLUTTER ?= flutter
API     ?= http://localhost:8000

.PHONY: setup backend test lint format migrate seed web apk app-web dashboard-web flutter-test demo-smoke

setup:            ## Create the Python venv and fetch Flutter packages
	python3 -m venv worker/.venv && $(PY) -m pip install -r worker/requirements-dev.txt
	cd app && $(FLUTTER) pub get
	cd dashboard && $(FLUTTER) pub get

backend:          ## Run API + worker with auto-reload (SQLite demo DB, seeded automatically)
	cd worker && ../$(PY) -m uvicorn app.main:app --reload --port 8000

test:             ## Backend tests (SQLite). Set TEST_DATABASE_URL to run against Postgres+PostGIS.
	cd worker && ../$(PY) -m pytest -q

lint:
	cd worker && ../$(PY) -m ruff check app tests && ../$(PY) -m ruff format --check app tests
	cd app && $(FLUTTER) analyze
	cd dashboard && $(FLUTTER) analyze

format:
	cd worker && ../$(PY) -m ruff format app tests
	cd app && dart format lib test
	cd dashboard && dart format lib test

migrate:          ## make migrate DB=postgresql://user:pw@host:5432/db
	$(PY) scripts/apply_migrations.py $(DB)

seed:             ## Fictional demo data into DATABASE_URL (demo mode only)
	cd worker && ../$(PY) -m app.demo.seed

flutter-test:
	cd app && $(FLUTTER) test
	cd dashboard && $(FLUTTER) test

dashboard-web:
	cd dashboard && $(FLUTTER) build web --release --dart-define=API_BASE_URL=$(API)

app-web:
	cd app && $(FLUTTER) build web --release --dart-define=API_BASE_URL=$(API)

apk:              ## Android debug APK (emulator talks to the host on 10.0.2.2)
	cd app && $(FLUTTER) build apk --debug --dart-define=API_BASE_URL=http://10.0.2.2:8000

demo-smoke:       ## Run the scripted 3-minute demo against a running backend
	$(PY) scripts/demo_smoke.py $(API)
