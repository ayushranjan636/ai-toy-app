"""Create a ready-to-use LOCAL TEST account (development backend only).

Usage: python scripts/seed_demo.py [http://localhost:8000]

Account (dev sign-in only; never valid against a real identity provider):
    email:    demo@example.com
    password: zivoo-test-123   (checked by the app's dev auth)

Creates, through the real API:
- the parent, with onboarding finished
- a child profile "Maya"
- a simulated Zivoo claimed via the normal claim handshake
- two maths sessions with correct, to-revisit and couldn't-hear results

Safe to re-run: existing data is reused, and a new session is added.
"""

import re
import sys
import uuid

import httpx

BASE = sys.argv[1] if len(sys.argv) > 1 else "http://localhost:8000"
EMAIL = "demo@example.com"
c = httpx.Client(base_url=BASE, timeout=15)


def ok(r: httpx.Response, *codes: int) -> dict:
    assert r.status_code in (codes or (200,)), f"{r.request.method} {r.request.url}: {r.text}"
    return r.json() if r.content else {}


token = ok(c.post("/dev/auth/token", json={"email": EMAIL, "ttl_seconds": 600}))["access_token"]
P = {"authorization": f"Bearer {token}"}

ok(c.patch("/v1/me", headers=P, json={
    "display_name": "Sam", "onboarding_step": "done", "data_choices_confirmed": True,
    "store_transcripts": True,
}))
children = ok(c.get("/v1/children", headers=P))
child = children[0] if children else ok(
    c.post("/v1/children", headers=P, json={"display_name": "Maya", "birth_year": 2020}), 201)

devices = ok(c.get("/v1/devices", headers=P))
cred_file = ".demo_device_credential"
if devices:
    try:
        cred = open(cred_file).read().strip()
    except FileNotFoundError:
        cred = None
else:
    toy = ok(c.post("/dev/simulated-devices"), 201)
    claim = ok(c.post("/v1/claims", headers=P,
                      json={"serial": toy["serial"], "setup_code": toy["setup_code"]}), 201)
    res = ok(c.post("/v1/device/claim",
                    headers={"authorization": f"Bearer {toy['factory_credential']}"},
                    json={"claim_token": claim["claim_token"], "firmware_version": "sim-0.1.0",
                          "wifi_ssid": "Home Wi-Fi"}))
    cred = res["credential"]
    with open(cred_file, "w") as f:
        f.write(cred)
    ok(c.patch(f"/v1/devices/{res['device_id']}", headers=P, json={"name": "Zivoo"}))

if cred:
    D = {"authorization": f"Bearer {cred}"}
    sync = ok(c.post("/v1/device/heartbeat", headers=D, json={}))
    for cmd in sync["commands"]:
        ok(c.post(f"/v1/device/commands/{cmd['id']}/ack", headers=D, json={"result": "ok"}))

    def run_session(wrong_at: int, unclear_at: int) -> None:
        sid = "demo-" + uuid.uuid4().hex[:10]
        reply = ok(c.post("/v1/device/sessions", headers=D,
                          json={"client_session_id": sid, "activity_key": "maths"}))
        i = 0
        last = None
        while not reply["done"] and i < 40:
            m = re.findall(r"What is (\d+) (plus|take away) (\d+)\?", reply["say"])
            if m:
                last = m[-1]
            a, op, b = last  # "didn't catch that" replies don't repeat the question
            ans = int(a) + int(b) if op == "plus" else int(a) - int(b)
            if i in (wrong_at, wrong_at + 1):
                body = {"transcript": str(ans + 1), "audio_quality": "good"}
            elif i in range(unclear_at, unclear_at + 3):
                body = {"transcript": "", "audio_quality": "noisy"}
            else:
                body = {"transcript": f"it's {ans}", "audio_quality": "good"}
            reply = ok(c.post(f"/v1/device/sessions/{sid}/turns", headers=D,
                              json={"turn_id": f"t{i}", "stt_confidence": 0.9, **body}))
            i += 1

    run_session(wrong_at=1, unclear_at=4)
    run_session(wrong_at=99, unclear_at=99)  # all correct
else:
    print("Device exists but its credential file is missing; skipped sessions.")

print(f"""
Local test account ready
  email:    {EMAIL}
  password: zivoo-test-123
  code:     123456 (if asked to verify)
Run the app with --dart-define=ZIVOO_AUTH=dev
""")
