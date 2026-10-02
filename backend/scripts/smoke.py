"""End-to-end smoke test against a running dev backend (over real HTTP).

Usage: python scripts/smoke.py http://localhost:8000
Exercises: parent auth, child, simulated toy claim, config sync, idempotent
command, a maths session, and the parent report.
"""

import sys
import uuid

import httpx

base = sys.argv[1] if len(sys.argv) > 1 else "http://localhost:8000"
c = httpx.Client(base_url=base, timeout=10)


def ok(r: httpx.Response, code: int = 200) -> dict:
    assert r.status_code == code, f"{r.request.method} {r.request.url} -> {r.status_code} {r.text}"
    return r.json() if r.content else {}


assert ok(c.get("/healthz"))["status"] == "ok"
assert ok(c.get("/readyz"))["status"] == "ready"

email = f"smoke-{uuid.uuid4().hex[:6]}@example.com"
token = ok(c.post("/dev/auth/token", json={"email": email}))["access_token"]
P = {"authorization": f"Bearer {token}"}

ok(c.patch("/v1/me", headers=P, json={"onboarding_step": "connect_toy"}))
child = ok(c.post("/v1/children", headers=P, json={"display_name": "Maya"}), 201)

toy = ok(c.post("/dev/simulated-devices"), 201)
claim = ok(c.post("/v1/claims", headers=P, json={"serial": toy["serial"],
                                                  "setup_code": toy["setup_code"]}), 201)
D = {"authorization": f"Bearer {toy['factory_credential']}"}
res = ok(c.post("/v1/device/claim", headers=D, json={"claim_token": claim["claim_token"],
                                                      "firmware_version": "sim-0.1.0",
                                                      "wifi_ssid": "Home"}))
D = {"authorization": f"Bearer {res['credential']}"}
assert ok(c.get(f"/v1/claims/{claim['id']}", headers=P))["status"] == "completed"

sync = ok(c.post("/v1/device/heartbeat", headers=D, json={}))
for cmd in sync["commands"]:
    ok(c.post(f"/v1/device/commands/{cmd['id']}/ack", headers=D, json={"result": "ok"}))
dev = ok(c.get("/v1/devices", headers=P))[0]
assert dev["online"] and dev["config_sync"] == "applied", dev

cid = str(uuid.uuid4())
ok(c.post(f"/v1/devices/{dev['id']}/commands", headers=P, json={"id": cid, "kind": "play_greeting"}), 201)
ok(c.post(f"/v1/devices/{dev['id']}/commands", headers=P, json={"id": cid, "kind": "play_greeting"}))

sid = "smoke-" + uuid.uuid4().hex[:8]
reply = ok(c.post("/v1/device/sessions", headers=D,
                  json={"client_session_id": sid, "activity_key": "maths"}))
turns = 0
import re  # noqa: E402

while not reply["done"]:
    m = re.findall(r"What is (\d+) (plus|take away) (\d+)\?", reply["say"])
    a, op, b = m[-1]
    answer = int(a) + int(b) if op == "plus" else int(a) - int(b)
    said = str(answer) if turns != 1 else str(answer + 1)
    reply = ok(c.post(f"/v1/device/sessions/{sid}/turns", headers=D,
                      json={"turn_id": f"t{turns}", "transcript": said, "stt_confidence": 0.9}))
    turns += 1

page = ok(c.get(f"/v1/sessions?child_id={child['id']}", headers=P))
s = page["items"][0]
print("session:", s["summary"], f"(correct={s['correct']}, revisit={s['needs_practice']})")
assert s["status"] == "completed" and s["correct"] >= 1

other = {"authorization": "Bearer " + ok(c.post("/dev/auth/token",
                                                 json={"email": "x" + email}))["access_token"]}
assert c.get(f"/v1/sessions/{s['id']}", headers=other).status_code == 404
print("SMOKE OK")
