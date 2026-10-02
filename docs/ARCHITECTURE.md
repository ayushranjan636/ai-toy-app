# Zivoo architecture

Status: working draft, written before implementation and kept current.
Starting point: empty repository. No existing app, backend, firmware, brand
assets, CI or deployment configuration were found, so the default stack applies.

## 1. Assumptions (reversible)

| # | Assumption | Why | How to reverse |
|---|------------|-----|----------------|
| A1 | Identity provider is **Supabase Auth (GoTrue)**, called over its REST API from a small client. | Managed passwords, email OTP verification and recovery; asymmetric JWTs verifiable via JWKS. Calling REST directly lets us keep tokens in platform secure storage instead of the SDK's default storage. | App: `AuthRepository` interface. Backend: `JwksVerifier` accepts any OIDC issuer (Auth0, Firebase, Cognito). |
| A2 | Email verification and password reset use **6-digit email codes**, not deep links. | Works without universal-link setup and on a second phone. | Swap the screen; the API is unchanged. |
| A3 | Firmware is **not yet available**. Provisioning follows the ESP-IDF `network_provisioning` model (BLE transport, Security 2 / SRP6a + AES-GCM) with a custom `zivoo-claim` endpoint. | It is the maintained Espressif path for ESP32-S3. | `ProvisioningTransport` interface; see `PROVISIONING_PROTOCOL.md`. |
| A4 | Device-to-cloud transport in v1 is HTTPS polling with per-device bearer credentials. A persistent connection (MQTT over TLS or WebSocket) is the target for production. | Smallest thing that exercises commands, acknowledgments and idempotency end to end. | The command/ack tables are transport-agnostic. |
| A5 | No brand logo or product photos were supplied. The app uses a **clearly marked placeholder** wordmark and simple leaf shapes. | We must not invent product imagery. | Drop the real files into `app/assets/brand/` (see README there). |
| A6 | Speech recognition, pronunciation assessment, TTS and LLM providers are **not chosen yet**. The learning engine works on transcripts plus confidence. Explanations use deterministic templates. | No credentials. We will not fake pronunciation scoring. | Provider interfaces in `backend/app/learning/providers.py`. |
| A7 | Raw audio is **not retained**. Transcripts are stored only if the parent enables them (default off). | Data minimisation for children. | `parent.data_choices.store_transcripts`. |

## 2. System overview

```
 Parent phone (Flutter)                Cloud (FastAPI modular monolith)          Toy (ESP32-S3)
 ┌──────────────────────┐   HTTPS/JWT  ┌───────────────────────────────┐  HTTPS   ┌──────────────┐
 │ UI (widgets)         │─────────────▶│ /v1 parent API                │◀────────│ device API   │
 │ Riverpod controllers │              │   auth: IdP JWT (JWKS)        │ per-dev  │ wake word,   │
 │ Repositories         │              │ /v1/device API                │ bearer   │ audio, BLE   │
 │ ProvisioningService ─┼── BLE (enc) ──────────────────────────────────────────▶│ prov. mode   │
 └──────────────────────┘  Wi-Fi creds + claim token never touch the cloud        └──────────────┘
                                       │ PostgreSQL (Alembic migrations)
```

The parent app never relays conversation audio. After provisioning, the toy
talks to the cloud directly.

Backend modules (`backend/app/`): `auth` (parent JWT), `device_auth`
(per-device credentials), `routers/*` (HTTP), `services/*` (ownership, claims,
commands, config sync), `learning/*` (activity controller, assessors), `models`
(SQLAlchemy), `schemas` (Pydantic). Each module has its own boundaries, so it can
be split out later if load requires it. There is no Redis or queue: no current
requirement needs one.

## 3. Screen inventory

Onboarding (one primary action each): Welcome · Create account · Verify email ·
Sign in · Forgot password · Reset password (code + new password) · Parent intro
and data choices · Connect toy (power on → setup mode → Bluetooth permission →
scan or enter code → find device → choose Wi-Fi → password → connecting →
online and claimed → test greeting → done) · Child profile · Learning
preferences.

Main tabs:
- **Home**: active child, device status, recent sessions, one suggestion, and empty/offline/error states.
- **Activities**: list → detail with difficulty, session length and save-to-device status.
- **Progress**: session list → session detail with items, assessments, summary, transcript and delete.
- **Settings**: children, device (rename, change Wi-Fi, firmware, remove from account, factory reset), learning limits, notifications, data controls, help, account (sign out, delete).

## 4. Data model

```
parent(id, idp_subject UNIQUE, email, display_name, marketing_opt_in,
       store_transcripts, onboarding_step, created_at, deletion_requested_at)
child(id, parent_id→parent, display_name, birth_year NULL, language, created_at)
device(id, serial UNIQUE, setup_code_hash, hardware_rev, firmware_version,
       name, last_seen_at, wifi_ssid_hint NULL, desired_config_version,
       applied_config_version, active_child_id NULL)
device_credential(id, device_id, secret_hash, created_at, revoked_at)
device_ownership(id, device_id, parent_id, claimed_at, released_at NULL)
    -- partial unique index: one active ownership per device
claim_attempt(id, device_id, parent_id, token_hash, status, expires_at,
              created_at, completed_at, failure_reason)
learning_preferences(child_id PK, version, payload JSONB, updated_at)
device_config_version(device_id, version, payload JSONB, created_at) PK(device_id, version)
activity_definition(key PK, kind, title, summary, min_age, max_age,
                    options_schema JSONB, enabled)
learning_session(id, device_id, child_id, activity_key, client_session_id,
                 started_at, ended_at, status, summary, UNIQUE(device_id, client_session_id))
conversation_turn(id, session_id, seq, speaker, text NULL, created_at)
assessment_result(id, session_id, seq, item_prompt, expected, response_text,
                  outcome {correct|needs_practice|uncertain}, source,
                  source_version, confidence, details JSONB)
device_command(id UUID (client idempotency key), device_id, parent_id, kind,
               payload JSONB, status {pending|delivered|acknowledged|failed|expired},
               config_version NULL, created_at, delivered_at, acked_at, error)
latency_sample(id, device_id, session_id, metric, value_ms, recorded_at)
```

Ownership rule: every parent-facing query joins through `parent_id` taken
from the verified token. Client-supplied owner fields are never accepted.

## 5. Key flows

**Claim.** The parent scans the QR code, which holds the device serial and a setup
code. The app calls `POST /v1/claims`. The backend verifies the setup code hash and
issues a 10-minute one-time claim token. The app sends Wi-Fi credentials and the
claim token over the encrypted BLE session, which is only open while the toy is in
physical setup mode. The toy joins Wi-Fi and calls `POST /v1/device/claim` with its
per-device credential and the token. The backend then binds ownership, rotates the
device credential and marks the attempt complete. The app shows success only after
`GET /v1/claims/{id}` returns `completed`.

**Config sync.** Parent edits create a new `learning_preferences` version. For
each device whose active child matches, the backend writes a `device_config_version`
and `desired_config_version += 1`. The device pulls the latest desired config and
acks with the version number. Stale or duplicate acks are no-ops. The app derives:
pending (applied < desired), applied (equal), failed (latest apply command failed).

**Commands.** The app sends a UUID command id. Re-sending the same id returns the
existing command (idempotent). The device acks by id. Acking twice is a no-op.

**Learning.** Activity controller states: `prompt → listen → assess → feedback
→ (retry | advance) → summary`. Assessors are deterministic per activity. The
language model (when added) only rewrites wording. It never chooses outcomes
or device commands.

## 6. Phased task list

1. **Phase 1**: design tokens and components, auth (dev and GoTrue), router guards,
   child profile, backend persistence and migrations, honest empty states.
2. **Phase 2**: provisioning state machine, claim API, ownership, device status,
   Wi-Fi change, labeled simulator (debug builds only).
3. **Phase 3**: maths activity end to end (simulated device → engine → storage
   → parent report).
4. **Phase 4**: remaining assessors (spelling, story; pronunciation stays
   `uncertain` until a provider exists), config sync UI, recovery flows,
   accessibility pass, instrumentation.
