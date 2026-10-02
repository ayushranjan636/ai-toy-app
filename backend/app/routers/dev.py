"""DEVELOPMENT ONLY. Mounted only when ZIVOO_ENV is development or test.

- /dev/auth/token: mints HS256 tokens that stand in for the identity
  provider so the app can be exercised without Supabase credentials.
- /dev/simulated-devices: registers a simulated toy and returns what a real
  toy would have from manufacturing (serial, setup code, factory credential).
- /dev/latency: p50/p95 over recorded latency samples.
"""

import statistics
import uuid
from datetime import timedelta

import jwt
from fastapi import APIRouter, Depends
from pydantic import BaseModel, EmailStr
from sqlalchemy import select
from sqlalchemy.orm import Session

from app import device_auth
from app.config import Settings, get_settings
from app.db import get_db
from app.models import Device, LatencySample, utcnow
from app.schemas import LatencyStat
from app.security import hash_setup_code, new_setup_code

router = APIRouter(prefix="/dev", tags=["development only"])


class DevTokenIn(BaseModel):
    email: EmailStr
    email_verified: bool = True
    ttl_seconds: int = 3600


def mint_dev_token(settings: Settings, email: str, verified: bool = True, ttl: int = 3600,
                   subject: str | None = None) -> str:  # fmt: skip
    now = utcnow()
    return jwt.encode(
        {
            "sub": subject or str(uuid.uuid5(uuid.NAMESPACE_URL, f"zivoo-dev:{email.lower()}")),
            "email": email.lower(),
            "email_verified": verified,
            "aud": settings.auth_audience,
            "iat": int(now.timestamp()),
            "exp": int((now + timedelta(seconds=ttl)).timestamp()),
        },
        settings.dev_jwt_secret,
        algorithm="HS256",
    )


@router.post("/auth/token")
def dev_token(body: DevTokenIn, settings: Settings = Depends(get_settings)):
    return {
        "access_token": mint_dev_token(settings, body.email, body.email_verified,
                                       body.ttl_seconds),  # fmt: skip
        "expires_in": body.ttl_seconds,
    }


@router.post("/simulated-devices", status_code=201)
def create_simulated_device(db: Session = Depends(get_db)):
    serial = f"SIM-{uuid.uuid4().hex[:8].upper()}"
    code = new_setup_code()
    device = Device(serial=serial, setup_code_hash=hash_setup_code(code), is_simulated=True,
                    firmware_version="sim-0.1.0", latest_firmware_version="sim-0.1.0")  # fmt: skip
    db.add(device)
    db.flush()
    credential = device_auth.issue_factory_credential(db, device)
    return {
        "device_id": str(device.id),
        "serial": serial,
        "setup_code": code,
        "qr_payload": f"ZIVOO:1:{serial}:{code}",
        "factory_credential": credential,
    }


@router.get("/latency", response_model=list[LatencyStat])
def latency_report(db: Session = Depends(get_db)):
    out: list[LatencyStat] = []
    metrics = db.scalars(select(LatencySample.metric).distinct()).all()
    for m in sorted(metrics):
        values = sorted(db.scalars(select(LatencySample.value_ms)
                                   .where(LatencySample.metric == m)).all())  # fmt: skip
        out.append(LatencyStat(metric=m, count=len(values), p50_ms=percentile(values, 50),
                               p95_ms=percentile(values, 95)))  # fmt: skip
    return out


def percentile(values: list[float], p: int) -> float | None:
    if not values:
        return None
    if len(values) == 1:
        return values[0]
    return statistics.quantiles(values, n=100, method="inclusive")[p - 1]
