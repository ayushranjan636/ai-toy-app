# Zivoo

Parent companion app (Flutter) and cloud backend (FastAPI + PostgreSQL) for
the Zivoo learning toy.

> **Status:** development build. Nothing here has been tested with real Zivoo
> hardware or firmware, and it is not production ready. See
> [docs/INTEGRATION_STATUS.md](docs/INTEGRATION_STATUS.md) for exactly what
> works, what is simulated, and what still needs credentials or hardware.

```
app/        Flutter app (Android, iOS) — Riverpod, GoRouter, material_ui
backend/    FastAPI modular monolith — SQLAlchemy 2, Alembic, PostgreSQL
docs/       Architecture, provisioning protocol, API contract, status, ops
```

## Quick start (local, no external credentials)

Requirements: Python 3.12+, PostgreSQL 15+, Flutter 3.47+ (Dart 3.13).

### 1. Backend

```bash
cd backend
python3 -m venv .venv && .venv/bin/pip install -e ".[dev]"
cp .env.example .env            # edit the database URL
createdb zivoo
.venv/bin/alembic upgrade head
.venv/bin/python -m app.seed    # curated activity definitions
.venv/bin/uvicorn app.main:app --reload --port 8000
```

- API docs (generated): http://localhost:8000/docs
- Contract snapshot: [docs/API.md](docs/API.md) and `docs/api/openapi.json`
- `ZIVOO_ENV=development` enables `/dev/*` routes: a stand-in for the
  identity provider, and the simulated device registry. These routes are
  **not mounted** in staging or production. The app refuses to start
  there without JWKS auth.

Tests (need a Postgres database named `zivoo_test`; they run the real migrations):

```bash
ZIVOO_DATABASE_URL=postgresql+psycopg://USER@localhost:5432/zivoo_test .venv/bin/pytest
.venv/bin/ruff check app tests
.venv/bin/python scripts/smoke.py http://localhost:8000   # end-to-end over HTTP
```

### 2. App

```bash
cd app
flutter pub get
# Development: dev sign-in (code 123456) + device simulator
flutter run --dart-define=ZIVOO_AUTH=dev --dart-define=ZIVOO_API_BASE=http://10.0.2.2:8000   # Android emulator
flutter run --dart-define=ZIVOO_AUTH=dev --dart-define=ZIVOO_API_BASE=http://localhost:8000  # iOS simulator
flutter analyze && flutter test
```

To try the full flow without hardware, open setup and choose **Use development
simulator** on the "setup mode" step. A simulated toy is registered with the
dev backend. It joins "Wi-Fi", claims itself with its own credential, and
heartbeats. On Home, **Simulate a maths session** produces a real session
report. Type `wrong` as the Wi-Fi password to exercise the failure path.

Staging/production app builds:

```bash
flutter build apk --release \
  --dart-define=ZIVOO_API_BASE=https://api.example.com \
  --dart-define=ZIVOO_SUPABASE_URL=https://<ref>.supabase.co \
  --dart-define=ZIVOO_SUPABASE_ANON_KEY=<public anon key>
```

In release builds `ZIVOO_AUTH=dev` is ignored and the simulator is compiled
out (`AppConfig.simulatorEnabled` is a const `false`).

iOS: on the first `flutter build ios`, add the permission_handler macros to
`ios/Podfile` (`PERMISSION_BLUETOOTH=1`, `PERMISSION_CAMERA=1`). See
[docs/OPERATIONS.md](docs/OPERATIONS.md).

## Documents

- [Architecture, screens, data model, phases](docs/ARCHITECTURE.md)
- [Provisioning and device protocol (firmware contract)](docs/PROVISIONING_PROTOCOL.md)
- [Integration status: what works, what is simulated](docs/INTEGRATION_STATUS.md)
- [Design system](docs/DESIGN.md)
- [Operations, privacy, performance measurement](docs/OPERATIONS.md)
# ai-toy-app
