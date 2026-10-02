import pytest
from conftest import add_child, auth, claim, make_device, new_id

from app.config import Settings


def test_missing_token_is_401(client):
    r = client.get("/v1/me")
    assert r.status_code == 401
    assert r.json()["error"]["code"] == "unauthenticated"


def test_garbage_token_is_401(client):
    r = client.get("/v1/me", headers={"authorization": "Bearer not-a-jwt"})
    assert r.status_code == 401


def test_expired_token_reports_session_expired(client):
    r = client.get("/v1/me", headers=auth("a@example.com", ttl=-10))
    assert r.status_code == 401
    assert r.json()["error"]["code"] == "session_expired"


def test_unverified_email_is_blocked(client):
    r = client.get("/v1/me", headers=auth("a@example.com", verified=False))
    assert r.status_code == 403
    assert r.json()["error"]["code"] == "email_not_verified"


def test_token_signed_with_other_secret_rejected(client):
    import jwt

    token = jwt.encode({"sub": "x", "aud": "authenticated", "exp": 9999999999,
                        "email_verified": True}, "wrong-secret-wrong-secret-wrong-secret!",
                       algorithm="HS256")  # fmt: skip
    r = client.get("/v1/me", headers={"authorization": f"Bearer {token}"})
    assert r.status_code == 401


def test_production_refuses_dev_auth():
    with pytest.raises(ValueError):
        Settings(env="production", auth_mode="dev_hs256")
    with pytest.raises(ValueError):
        Settings(env="production", auth_mode="jwks")  # missing JWKS URL / issuer


def test_dev_routes_absent_in_production(monkeypatch):
    from fastapi.testclient import TestClient

    from app import config
    from app.main import create_app

    prod = Settings(env="production", auth_mode="jwks", auth_jwks_url="https://idp/jwks",
                    auth_issuer="https://idp")  # fmt: skip
    monkeypatch.setattr(config, "get_settings", lambda: prod)
    monkeypatch.setattr("app.main.get_settings", lambda: prod)
    c = TestClient(create_app())
    assert c.post("/dev/simulated-devices").status_code == 404
    assert c.post("/dev/auth/token", json={"email": "a@b.co"}).status_code == 404


def test_me_created_on_first_call_and_updatable(client, alice):
    r = client.get("/v1/me", headers=alice)
    assert r.status_code == 200
    me = r.json()
    assert me["email"] == "alice@example.com"
    assert me["marketing_opt_in"] is False  # optional, off by default
    assert me["store_transcripts"] is False  # privacy default
    r = client.patch("/v1/me", headers=alice, json={"marketing_opt_in": True,
                                                    "onboarding_step": "connect_toy"})
    assert r.json()["marketing_opt_in"] is True
    assert r.json()["onboarding_step"] == "connect_toy"


def test_cannot_set_ownership_fields(client, alice):
    r = client.patch("/v1/me", headers=alice, json={"id": new_id()})
    assert r.status_code == 422
    r = client.post("/v1/children", headers=alice,
                    json={"display_name": "Maya", "parent_id": new_id()})
    assert r.status_code == 422


def test_account_deletion_releases_devices_and_blocks_access(client, alice, bob):
    add_child(client, alice)
    device = make_device(client)
    _c, cred = claim(client, alice, device)
    r = client.post("/v1/me/delete", headers=alice, json={"confirm": "DELETE"})
    assert r.status_code == 202
    assert client.get("/v1/me", headers=alice).json()["error"]["code"] == "account_deleted"
    # Device no longer serves this family; a new family can claim with the setup code.
    sync = client.post("/v1/device/heartbeat", headers={"authorization": f"Bearer {cred}"},
                       json={}).json()
    assert sync["config"] is None and sync["commands"] == []
    r = client.post("/v1/claims", headers=bob,
                    json={"serial": device["serial"], "setup_code": device["setup_code"]})
    assert r.status_code == 201
