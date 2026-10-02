"""One family must never see or change another family's data."""

from conftest import add_child, claim, dev_auth, make_device, new_id


def _run_session(client, credential: str) -> None:
    sid = "sess-" + new_id()[:8]
    r = client.post("/v1/device/sessions", headers=dev_auth(credential),
                    json={"client_session_id": sid, "activity_key": "maths"})
    assert r.status_code == 200, r.text
    client.post(f"/v1/device/sessions/{sid}/end", headers=dev_auth(credential))


def test_cross_family_isolation(client, alice, bob):
    child = add_child(client, alice)
    device = make_device(client)
    _c, cred = claim(client, alice, device)
    _run_session(client, cred)
    session_id = client.get("/v1/sessions", headers=alice).json()["items"][0]["id"]
    did, cid = device["device_id"], child["id"]

    # Bob sees nothing in lists.
    assert client.get("/v1/children", headers=bob).json() == []
    assert client.get("/v1/devices", headers=bob).json() == []
    assert client.get("/v1/sessions", headers=bob).json()["items"] == []

    # Direct access by id returns 404 (does not reveal existence).
    checks = [
        ("patch", f"/v1/children/{cid}", {"display_name": "X"}),
        ("delete", f"/v1/children/{cid}", None),
        ("get", f"/v1/children/{cid}/preferences", None),
        ("put", f"/v1/children/{cid}/preferences", {}),
        ("get", f"/v1/devices/{did}", None),
        ("patch", f"/v1/devices/{did}", {"name": "Mine now"}),
        ("delete", f"/v1/devices/{did}/ownership", None),
        ("post", f"/v1/devices/{did}/commands", {"id": new_id(), "kind": "factory_reset"}),
        ("post", f"/v1/devices/{did}/config/resend", None),
        ("get", f"/v1/sessions/{session_id}", None),
        ("delete", f"/v1/sessions/{session_id}", None),
        ("get", f"/v1/sessions?child_id={cid}", None),
    ]
    for method, url, body in checks:
        kwargs = {"headers": bob}
        if body is not None:
            kwargs["json"] = body
        r = getattr(client, method)(url, **kwargs)
        assert r.status_code == 404, (method, url, r.status_code, r.text)

    # Bob cannot point his device at Alice's child.
    bob_device = make_device(client)
    claim(client, bob, bob_device)
    r = client.patch(f"/v1/devices/{bob_device['device_id']}", headers=bob,
                     json={"active_child_id": cid})
    assert r.status_code == 404

    # Alice's data is intact.
    assert client.get(f"/v1/devices/{did}", headers=alice).json()["name"] == "Zivoo"
    assert len(client.get("/v1/children", headers=alice).json()) == 1


def test_claim_status_is_private(client, alice, bob):
    device = make_device(client)
    r = client.post("/v1/claims", headers=alice,
                    json={"serial": device["serial"], "setup_code": device["setup_code"]})
    claim_id = r.json()["id"]
    assert client.get(f"/v1/claims/{claim_id}", headers=bob).status_code == 404
    assert client.post(f"/v1/claims/{claim_id}/cancel", headers=bob).status_code == 404


def test_command_ids_cannot_be_hijacked(client, alice, bob):
    a_dev, b_dev = make_device(client), make_device(client)
    claim(client, alice, a_dev)
    claim(client, bob, b_dev)
    cmd_id = new_id()
    r = client.post(f"/v1/devices/{a_dev['device_id']}/commands", headers=alice,
                    json={"id": cmd_id, "kind": "play_greeting"})
    assert r.status_code == 201
    r = client.post(f"/v1/devices/{b_dev['device_id']}/commands", headers=bob,
                    json={"id": cmd_id, "kind": "play_greeting"})
    assert r.status_code == 409
    assert client.get(f"/v1/devices/{b_dev['device_id']}/commands/{cmd_id}",
                      headers=bob).status_code == 404


def test_device_cannot_ack_another_devices_command(client, alice):
    d1, d2 = make_device(client), make_device(client)
    claim(client, alice, d1)
    _c, cred2 = claim(client, alice, d2)
    cmd_id = new_id()
    client.post(f"/v1/devices/{d1['device_id']}/commands", headers=alice,
                json={"id": cmd_id, "kind": "play_greeting"})
    r = client.post(f"/v1/device/commands/{cmd_id}/ack", headers=dev_auth(cred2),
                    json={"result": "ok"})
    assert r.status_code == 404
