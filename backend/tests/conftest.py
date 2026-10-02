import os
import uuid

os.environ.setdefault("ZIVOO_ENV", "test")
os.environ.setdefault(
    "ZIVOO_DATABASE_URL", "postgresql+psycopg://zivoo@localhost:54329/zivoo_test"
)

import pytest
from alembic import command
from alembic.config import Config
from fastapi.testclient import TestClient
from sqlalchemy import text

from app.config import get_settings
from app.db import get_engine
from app.main import create_app
from app.routers.dev import mint_dev_token


@pytest.fixture(scope="session", autouse=True)
def _migrate():
    engine = get_engine()
    with engine.begin() as conn:
        conn.execute(text("DROP SCHEMA public CASCADE; CREATE SCHEMA public;"))
    cfg = Config(os.path.join(os.path.dirname(__file__), "..", "alembic.ini"))
    cfg.set_main_option("script_location",
                        os.path.join(os.path.dirname(__file__), "..", "migrations"))
    command.upgrade(cfg, "head")
    # Prove the downgrade path works, then upgrade again for the tests.
    command.downgrade(cfg, "base")
    command.upgrade(cfg, "head")
    yield


@pytest.fixture(autouse=True)
def _clean():
    from app import db as dbm
    from app.seed import seed_activities

    engine = dbm.get_engine()
    with engine.begin() as conn:
        tables = conn.execute(
            text("SELECT tablename FROM pg_tables WHERE schemaname='public' "
                 "AND tablename <> 'alembic_version'")
        ).scalars().all()
        conn.execute(text(f"TRUNCATE {', '.join(tables)} CASCADE"))
    assert dbm._SessionLocal is not None
    with dbm._SessionLocal() as db:
        seed_activities(db)
        db.commit()
    yield


@pytest.fixture
def client():
    return TestClient(create_app())


def auth(email: str, verified: bool = True, ttl: int = 3600) -> dict:
    return {"authorization": f"Bearer {mint_dev_token(get_settings(), email, verified, ttl)}"}


def dev_auth(credential: str) -> dict:
    return {"authorization": f"Bearer {credential}"}


@pytest.fixture
def alice():
    return auth("alice@example.com")


@pytest.fixture
def bob():
    return auth("bob@example.com")


def make_device(client) -> dict:
    r = client.post("/dev/simulated-devices")
    assert r.status_code == 201
    return r.json()


def claim(client, parent_headers, device: dict) -> tuple[dict, str]:
    """Run the full claim handshake. Returns (claim, active credential)."""
    r = client.post("/v1/claims", headers=parent_headers,
                    json={"serial": device["serial"], "setup_code": device["setup_code"]})
    assert r.status_code == 201, r.text
    c = r.json()
    r = client.post("/v1/device/claim", headers=dev_auth(device["factory_credential"]),
                    json={"claim_token": c["claim_token"], "firmware_version": "sim-0.1.0",
                          "wifi_ssid": "Home"})
    assert r.status_code == 200, r.text
    credential = r.json()["credential"]
    # First use activates the rotated credential.
    assert client.post("/v1/device/heartbeat", headers=dev_auth(credential),
                       json={}).status_code == 200
    return c, credential


def add_child(client, headers, name: str = "Maya") -> dict:
    r = client.post("/v1/children", headers=headers, json={"display_name": name})
    assert r.status_code == 201, r.text
    return r.json()


def new_id() -> str:
    return str(uuid.uuid4())
