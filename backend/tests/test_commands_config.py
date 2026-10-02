"""Commands are idempotent; desired config is tracked separately from what the
toy acknowledged; an offline toy applies only the latest version once."""

from conftest import add_child, claim, dev_auth, make_device, new_id


def _setup(client, alice):
    child = add_child(client, alice)
    device = make_device(client)
    _c, cred = claim(client, alice, device)
    return child, device, cred


def _sync(client, cred):
    r = client.post("/v1/device/heartbeat", headers=dev_auth(cred), json={})
    assert r.status_code == 200
    return r.json()


def _apply_all(client, cred):
    sync = _sync(client, cred)
    for cmd in sync["commands"]:
        client.post(f"/v1/device/commands/{cmd['id']}/ack", headers=dev_auth(cred),
                    json={"result": "ok"})
    return sync


def _device(client, alice, device):
    return client.get(f"/v1/devices/{device['device_id']}", headers=alice).json()


def _prefs_body(client, alice, child, **changes):
    current = client.get(f"/v1/children/{child['id']}/preferences", headers=alice).json()
    body = {k: v for k, v in current["payload"].items()}
    body.update(changes)
    body["base_version"] = current["version"]
    return body


def test_command_retry_is_idempotent(client, alice):
    _child, device, cred = _setup(client, alice)
    url = f"/v1/devices/{device['device_id']}/commands"
    cid = new_id()
    r1 = client.post(url, headers=alice, json={"id": cid, "kind": "play_greeting"})
    r2 = client.post(url, headers=alice, json={"id": cid, "kind": "play_greeting"})
    assert (r1.status_code, r2.status_code) == (201, 200)
    greetings = [c for c in _sync(client, cred)["commands"] if c["kind"] == "play_greeting"]
    assert len(greetings) == 1
    # Same id with a different kind is a conflict, not a second command.
    r3 = client.post(url, headers=alice, json={"id": cid, "kind": "factory_reset"})
    assert r3.status_code == 409


def test_duplicate_ack_has_no_second_effect(client, alice):
    _child, device, cred = _setup(client, alice)
    cid = new_id()
    client.post(f"/v1/devices/{device['device_id']}/commands", headers=alice,
                json={"id": cid, "kind": "play_greeting"})
    _sync(client, cred)
    ok = client.post(f"/v1/device/commands/{cid}/ack", headers=dev_auth(cred),
                     json={"result": "ok"})
    late_fail = client.post(f"/v1/device/commands/{cid}/ack", headers=dev_auth(cred),
                            json={"result": "failed", "error": "late"})
    assert ok.json()["status"] == late_fail.json()["status"] == "acknowledged"
    cmd = client.get(f"/v1/devices/{device['device_id']}/commands/{cid}", headers=alice).json()
    assert cmd["status"] == "acknowledged" and cmd["error"] is None
    # Delivered commands are not re-sent once acknowledged.
    assert all(c["id"] != cid for c in _sync(client, cred)["commands"])


def test_offline_toy_applies_only_latest_config_once(client, alice):
    child, device, cred = _setup(client, alice)
    _apply_all(client, cred)
    assert _device(client, alice, device)["config_sync"] == "applied"

    # Parent edits three times while the toy is offline.
    for minutes in (30, 45, 60):
        body = _prefs_body(client, alice, child, daily_limit_minutes=minutes)
        assert client.put(f"/v1/children/{child['id']}/preferences", headers=alice,
                          json=body).status_code == 200
    d = _device(client, alice, device)
    assert d["config_sync"] == "pending"
    assert d["desired_config_version"] > d["applied_config_version"]

    # Toy reconnects: exactly one apply command, carrying the latest version.
    sync = _sync(client, cred)
    applies = [c for c in sync["commands"] if c["kind"] == "apply_config"]
    assert len(applies) == 1
    assert applies[0]["config_version"] == sync["desired_config_version"]
    assert sync["config"]["preferences"]["daily_limit_minutes"] == 60
    client.post(f"/v1/device/commands/{applies[0]['id']}/ack", headers=dev_auth(cred),
                json={"result": "ok"})
    assert _device(client, alice, device)["config_sync"] == "applied"
    assert _sync(client, cred)["config"] is None  # nothing new to fetch


def test_unchanged_preferences_do_not_bump_version(client, alice):
    child, device, cred = _setup(client, alice)
    _apply_all(client, cred)
    before = _device(client, alice, device)["desired_config_version"]
    body = _prefs_body(client, alice, child)
    r = client.put(f"/v1/children/{child['id']}/preferences", headers=alice, json=body)
    assert r.status_code == 200
    assert _device(client, alice, device)["desired_config_version"] == before


def test_stale_ack_cannot_regress_applied_version(client, alice):
    child, device, cred = _setup(client, alice)
    old_apply = [c for c in _sync(client, cred)["commands"] if c["kind"] == "apply_config"][0]
    body = _prefs_body(client, alice, child, daily_limit_minutes=50)
    client.put(f"/v1/children/{child['id']}/preferences", headers=alice, json=body)
    new_apply = [c for c in _sync(client, cred)["commands"] if c["kind"] == "apply_config"][0]
    client.post(f"/v1/device/commands/{new_apply['id']}/ack", headers=dev_auth(cred),
                json={"result": "ok"})
    applied = _device(client, alice, device)["applied_config_version"]
    # Old command was superseded; acking it now is a no-op.
    client.post(f"/v1/device/commands/{old_apply['id']}/ack", headers=dev_auth(cred),
                json={"result": "ok"})
    assert _device(client, alice, device)["applied_config_version"] == applied


def test_failed_apply_reports_failed_and_resend_recovers(client, alice):
    _child, device, cred = _setup(client, alice)
    apply = [c for c in _sync(client, cred)["commands"] if c["kind"] == "apply_config"][0]
    client.post(f"/v1/device/commands/{apply['id']}/ack", headers=dev_auth(cred),
                json={"result": "failed", "error": "storage_full"})
    assert _device(client, alice, device)["config_sync"] == "failed"
    r = client.post(f"/v1/devices/{device['device_id']}/config/resend", headers=alice)
    assert r.json()["config_sync"] == "pending"
    _apply_all(client, cred)
    assert _device(client, alice, device)["config_sync"] == "applied"


def test_preferences_version_conflict_between_phones(client, alice):
    child, _device_, _cred = _setup(client, alice)
    phone_a = _prefs_body(client, alice, child, daily_limit_minutes=40)
    phone_b = _prefs_body(client, alice, child, daily_limit_minutes=20)
    assert client.put(f"/v1/children/{child['id']}/preferences", headers=alice,
                      json=phone_a).status_code == 200
    r = client.put(f"/v1/children/{child['id']}/preferences", headers=alice, json=phone_b)
    assert r.status_code == 409 and r.json()["error"]["code"] == "version_conflict"


def test_preferences_validate_curated_options(client, alice):
    child = add_child(client, alice)
    body = _prefs_body(client, alice, child)
    body["spelling"] = {"words": ["cat", "rm -rf"]}
    assert client.put(f"/v1/children/{child['id']}/preferences", headers=alice,
                      json=body).status_code == 422
    body["spelling"] = {"words": ["cat"]}
    body["maths"] = {"operations": ["division"], "max_number": 10}
    assert client.put(f"/v1/children/{child['id']}/preferences", headers=alice,
                      json=body).status_code == 422


def test_factory_reset_ack_releases_ownership(client, alice):
    _child, device, cred = _setup(client, alice)
    cid = new_id()
    client.post(f"/v1/devices/{device['device_id']}/commands", headers=alice,
                json={"id": cid, "kind": "factory_reset"})
    _sync(client, cred)
    client.post(f"/v1/device/commands/{cid}/ack", headers=dev_auth(cred), json={"result": "ok"})
    assert client.get("/v1/devices", headers=alice).json() == []


def test_sync_payload_has_no_family_extras(client, alice):
    _child, _device_, cred = _setup(client, alice)
    config = _sync(client, cred)["config"]
    assert set(config["child"]) == {"id", "name", "language"}  # no birth year, no email
