from datetime import timedelta

from conftest import add_child, claim, dev_auth, make_device

from app import db as dbm
from app.models import ClaimAttempt, utcnow


def _start(client, headers, device, code=None):
    return client.post("/v1/claims", headers=headers,
                       json={"serial": device["serial"],
                             "setup_code": code or device["setup_code"]})  # fmt: skip


def test_full_claim_binds_ownership_and_rotates_credential(client, alice):
    add_child(client, alice)
    device = make_device(client)
    c, cred = claim(client, alice, device)
    assert client.get(f"/v1/claims/{c['id']}", headers=alice).json()["status"] == "completed"
    devices = client.get("/v1/devices", headers=alice).json()
    assert [d["id"] for d in devices] == [device["device_id"]]
    assert devices[0]["online"] is True
    assert devices[0]["wifi_ssid"] == "Home"
    assert devices[0]["active_child_id"] is not None
    # Rotated credential is active; the factory credential no longer works.
    assert client.post("/v1/device/heartbeat", headers=dev_auth(cred), json={}).status_code == 200
    r = client.post("/v1/device/heartbeat", headers=dev_auth(device["factory_credential"]),
                    json={})
    assert r.status_code == 401


def test_claim_token_not_returned_on_status(client, alice):
    device = make_device(client)
    c = _start(client, alice, device).json()
    assert c["claim_token"].startswith("zcl_")
    assert client.get(f"/v1/claims/{c['id']}", headers=alice).json()["claim_token"] is None


def test_serial_alone_is_not_enough(client, alice):
    device = make_device(client)
    r = _start(client, alice, device, code="WRONGCODE123")
    assert r.status_code == 400
    assert r.json()["error"]["code"] == "setup_code_invalid"
    # Unknown serial gives the identical response.
    r = client.post("/v1/claims", headers=alice,
                    json={"serial": "SIM-NOPE", "setup_code": "WRONGCODE123"})
    assert r.status_code == 400 and r.json()["error"]["code"] == "setup_code_invalid"


def test_setup_code_is_case_and_separator_insensitive(client, alice):
    device = make_device(client)
    code = device["setup_code"]
    pretty = f"{code[:4].lower()}-{code[4:8]} {code[8:]}"
    assert _start(client, alice, device, code=pretty).status_code == 201


def test_failed_attempts_are_rate_limited(client, alice):
    device = make_device(client)
    for _ in range(5):
        assert _start(client, alice, device, code="BADBADBAD").status_code == 400
    r = _start(client, alice, device)
    assert r.status_code == 429


def test_duplicate_device_claim_is_idempotent(client, alice):
    """Toy retries after a lost response: same ownership, a new pending credential,
    and the previous credential keeps working until the new one is used."""
    device = make_device(client)
    c = _start(client, alice, device).json()
    body = {"claim_token": c["claim_token"], "firmware_version": "sim-0.1.0"}
    factory = dev_auth(device["factory_credential"])
    first = client.post("/v1/device/claim", headers=factory, json=body)
    second = client.post("/v1/device/claim", headers=factory, json=body)  # lost-response retry
    assert first.status_code == second.status_code == 200
    assert first.json()["credential"] != second.json()["credential"]
    # The first pending credential was superseded; the second one activates.
    assert client.post("/v1/device/heartbeat", headers=dev_auth(first.json()["credential"]),
                       json={}).status_code == 401
    assert client.post("/v1/device/heartbeat", headers=dev_auth(second.json()["credential"]),
                       json={}).status_code == 200
    assert len(client.get("/v1/devices", headers=alice).json()) == 1


def test_second_family_cannot_claim_owned_device(client, alice, bob):
    device = make_device(client)
    claim(client, alice, device)
    r = _start(client, bob, device)
    assert r.status_code == 409
    assert r.json()["error"]["code"] == "device_owned_elsewhere"


def test_claim_token_bound_to_device(client, alice):
    d1, d2 = make_device(client), make_device(client)
    c = _start(client, alice, d1).json()
    r = client.post("/v1/device/claim", headers=dev_auth(d2["factory_credential"]),
                    json={"claim_token": c["claim_token"], "firmware_version": "x"})
    assert r.status_code == 400


def test_expired_and_cancelled_claims_fail(client, alice):
    device = make_device(client)
    c = _start(client, alice, device).json()
    assert client.post(f"/v1/claims/{c['id']}/cancel", headers=alice).json()["status"] == (
        "cancelled"
    )
    r = client.post("/v1/device/claim", headers=dev_auth(device["factory_credential"]),
                    json={"claim_token": c["claim_token"], "firmware_version": "x"})
    assert r.status_code == 410 and r.json()["error"]["code"] == "claim_cancelled"

    c2 = _start(client, alice, device).json()
    with dbm._SessionLocal() as db:
        db.get(ClaimAttempt, __import__("uuid").UUID(c2["id"])).expires_at = (
            utcnow() - timedelta(seconds=1)
        )
        db.commit()
    assert client.get(f"/v1/claims/{c2['id']}", headers=alice).json()["status"] == "expired"
    r = client.post("/v1/device/claim", headers=dev_auth(device["factory_credential"]),
                    json={"claim_token": c2["claim_token"], "firmware_version": "x"})
    assert r.status_code == 410


def test_new_attempt_cancels_previous_pending(client, alice):
    device = make_device(client)
    c1 = _start(client, alice, device).json()
    _start(client, alice, device)
    assert client.get(f"/v1/claims/{c1['id']}", headers=alice).json()["status"] == "cancelled"


def test_same_owner_reprovision_keeps_ownership(client, alice):
    """Change Wi-Fi re-runs setup for an owned toy; ownership and child stay."""
    child = add_child(client, alice)
    device = make_device(client)
    _c, cred = claim(client, alice, device)
    c = _start(client, alice, device).json()
    r = client.post("/v1/device/claim", headers=dev_auth(cred),
                    json={"claim_token": c["claim_token"], "firmware_version": "sim-0.1.0",
                          "wifi_ssid": "NewNetwork"})
    assert r.status_code == 200
    d = client.get(f"/v1/devices/{device['device_id']}", headers=alice).json()
    assert d["wifi_ssid"] == "NewNetwork"
    assert d["active_child_id"] == child["id"]


def test_remove_ownership_cuts_off_family_data(client, alice, bob):
    add_child(client, alice)
    device = make_device(client)
    _c, cred = claim(client, alice, device)
    assert client.delete(f"/v1/devices/{device['device_id']}/ownership",
                         headers=alice).status_code == 204
    assert client.get("/v1/devices", headers=alice).json() == []
    sync = client.post("/v1/device/heartbeat", headers=dev_auth(cred), json={}).json()
    assert sync == {"desired_config_version": 0, "config": None, "commands": []}
    r = client.post("/v1/device/sessions", headers=dev_auth(cred),
                    json={"client_session_id": "abcdefgh", "activity_key": "maths"})
    assert r.status_code == 403
    # A new family can set it up with the physical setup code.
    c = _start(client, bob, device).json()
    r = client.post("/v1/device/claim", headers=dev_auth(cred),
                    json={"claim_token": c["claim_token"], "firmware_version": "x"})
    assert r.status_code == 200
    assert len(client.get("/v1/devices", headers=bob).json()) == 1


def test_revoked_credential_is_rejected(client, alice):
    from app.device_auth import revoke_all

    device = make_device(client)
    _c, cred = claim(client, alice, device)
    with dbm._SessionLocal() as db:
        revoke_all(db, __import__("uuid").UUID(device["device_id"]))
        db.commit()
    assert client.post("/v1/device/heartbeat", headers=dev_auth(cred), json={}).status_code == 401
