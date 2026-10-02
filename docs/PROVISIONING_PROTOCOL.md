# Zivoo provisioning and device protocol (v1, proposed)

**Status: specification only.** No Zivoo firmware was available. Nothing here
has been tested on an ESP32-S3. The app implements this contract behind
`ProvisioningTransport`, and a development simulator satisfies it in debug
builds. Firmware must implement it exactly, or this document must be updated
together with `app/lib/features/provisioning/data/`.

## 1. Factory state (per unit)

Written at manufacturing and never shared across units:

| Item | Where | Notes |
|------|-------|-------|
| `serial` | eFuse/NVS, printed on base | Public identifier. **Not** proof of ownership. |
| `setup_code` | NVS (encrypted), QR label inside battery door + packaging | 12 chars from `ABCDEFGHJKLMNPQRSTUVWXYZ23456789`. Backend stores scrypt hash only. |
| `device_credential` | NVS (encrypted) | Unique per unit. Production target: X.509 cert + key for mTLS. |
| SRP6a salt/verifier for BLE Security 2 | NVS | Derived from `setup_code` (username `zivoo`). |

QR payload: `ZIVOO:1:<serial>:<setup_code>`. The app also accepts manual
entry of the serial and setup code.

Firmware requirements: flash encryption and secure boot v2 enabled.
Production units must not expose JTAG.

## 2. Entering setup mode (physical presence)

Proposed gesture: **hold the leaf button for 5 seconds until the light
pulses slowly**. The toy also enters setup mode on first boot or after factory
reset. It leaves setup mode after 10 minutes or on success. BLE advertising
happens **only** in setup mode.

> Hardware confirmation needed: button name/location, LED behaviour,
> timeouts. The app copy lives in `SetupStrings` and must be updated to match.

BLE advertisement: name `ZIVOO-<last 4 of serial>`, service UUID per ESP-IDF
`network_provisioning` (BLE scheme), manufacturer data contains the full serial
so the app can match the scanned QR to the advertising unit.

## 3. Secure session

ESP-IDF `network_provisioning` with **Security 2** (SRP6a + AES-256-GCM),
using the `setup_code` as the SRP password. A nearby attacker without the QR
code cannot complete the handshake. Wi-Fi credentials and the claim token are
only sent after the session is established.

## 4. Endpoints (protobuf-framed as in ESP-IDF, JSON shown for clarity)

| Endpoint | Request | Response |
|----------|---------|----------|
| `proto-ver` | – | `{"ver":"v1.0","zivoo":{"proto":1,"fw":"1.0.0","caps":["wifi_scan","claim","greeting"]}}` |
| `prov-scan` | standard | List of `{ssid, rssi, auth, channel}` (2.4 GHz only, ESP32-S3 has no 5 GHz radio). |
| `zivoo-claim` | `{"claim_token":"zcl_…","api_base":"https://api.zivoo…"}` | `{"status":"stored"}` |
| `prov-config` | standard `set_config {ssid, passphrase}` then `apply_config` | standard |
| `prov-config` `get_status` | – | `connecting` / `connected` / `failed{reason: auth_error|ap_not_found}` |
| `zivoo-status` | – | `{"wifi":"connected","cloud":"connecting|claimed|claim_failed","error":?}` |
| `zivoo-greet` | `{}` | `{"status":"played"}` after audio playback completes |

The toy never sends the Wi-Fi passphrase anywhere except its own NVS. The app
must not log it, persist it or send it to the backend.

## 5. Cloud claim (toy → backend, after Wi-Fi joins)

```
POST /v1/device/claim
Authorization: Bearer <factory device credential>
{"claim_token":"zcl_…","firmware_version":"1.0.0","wifi_ssid":"Home"}
→ 200 {"device_id":…, "credential":"zdv_…", "desired_config_version":n}
```

- The toy stores the returned `credential` and uses it from then on. The previous
  credential stays valid until the new one is first used (safe against a lost
  response). Retrying the same claim token is idempotent.
- `zivoo-status.cloud` becomes `claimed` only after this returns 200 and the
  first authenticated heartbeat with the new credential succeeds.
- Errors are mapped to `claim_failed` with `error`: `claim_expired`,
  `claim_cancelled`, `device_owned_elsewhere`, `claim_invalid`, `network`.

## 6. Steady state

Target transport: persistent TLS connection (MQTT 3.1.1/5 or WebSocket) with
the same messages as the HTTPS endpoints below, which are implemented now:

- `POST /v1/device/heartbeat` every 30 s (offline threshold 120 s). Response:
  `{desired_config_version, config|null, commands[]}`.
- `POST /v1/device/commands/{id}/ack {"result":"ok|failed","error"?}`. The toy
  must deduplicate by command id (persist the last 32 executed ids) and ack
  again if it receives a command it already executed.
- `apply_config` carries `config_version`. The toy applies it only if the version is
  greater than the one it holds, then acks.
- `factory_reset`: ack first, then wipe NVS (Wi-Fi, credential rotation
  state) and return to setup mode.

## 7. Learning sessions (toy ↔ cloud)

The parent app is not involved. Proposed audio path (not implemented):
on-device wake word, then VAD/AEC/NS (ESP-SR AFE), then streamed Opus over the
persistent connection to cloud STT. The cloud returns text and streamed TTS
audio. Barge-in sends `cancel` and stops playback.

Implemented today (text-level contract, used by the simulator):
`POST /v1/device/sessions`, `POST /v1/device/sessions/{id}/turns` with
`{turn_id, transcript, stt_confidence, audio_quality}`, `…/end`. `turn_id`
makes retries safe.

## 8. Timeouts used by the app state machine

| Step | Timeout | On timeout |
|------|---------|------------|
| BLE discovery | 30 s | "We couldn't find your Zivoo" + retry |
| Secure session | 15 s | retry; after 3 failures suggest re-entering setup mode |
| Wi-Fi scan | 15 s | retry scan |
| Wi-Fi connect | 45 s | ask to check password / 2.4 GHz |
| Cloud claim | 60 s | retry status; claim token valid 10 min |
| Greeting ack | 20 s | allow "I heard it" / "Try again" |
