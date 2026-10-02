"""Per-device credentials.

Format: `zdv_<device_uuid>.<random secret>`. Only a SHA-256 hash of the full
credential is stored. Each device has its own credential(s); there is no fleet
secret.

Rotation: `rotate()` adds a *pending* credential and returns it once. The old
credential keeps working until the device first authenticates with the new
one, at which point every other credential is revoked. A lost response
therefore cannot lock the device out. `revoke_all()` is used on factory reset.

Production note: replace bearer secrets with mutual TLS using a per-device
X.509 certificate whose private key is kept in ESP32-S3 encrypted flash
(flash encryption + secure boot enabled). The rotation model stays the same.
"""

import uuid

from fastapi import Depends, Request
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.db import get_db
from app.errors import ApiError
from app.models import Device, DeviceCredential, utcnow
from app.security import constant_eq, random_token, sha256_hex


def _new(db: Session, device: Device, active: bool) -> str:
    credential = f"zdv_{device.id}.{random_token('x', 32)[2:]}"
    db.add(
        DeviceCredential(
            device_id=device.id,
            secret_hash=sha256_hex(credential),
            activated_at=utcnow() if active else None,
        )
    )
    db.flush()
    return credential


def issue_factory_credential(db: Session, device: Device) -> str:
    """Manufacturing-time credential (also used by the development simulator)."""
    return _new(db, device, active=True)


def rotate(db: Session, device: Device) -> str:
    # Drop any earlier pending credential that was never used.
    for cred in _live(db, device.id):
        if cred.activated_at is None:
            cred.revoked_at = utcnow()
    return _new(db, device, active=False)


def revoke_all(db: Session, device_id: uuid.UUID) -> None:
    now = utcnow()
    for cred in _live(db, device_id):
        cred.revoked_at = now


def _live(db: Session, device_id: uuid.UUID) -> list[DeviceCredential]:
    return list(
        db.scalars(
            select(DeviceCredential).where(
                DeviceCredential.device_id == device_id, DeviceCredential.revoked_at.is_(None)
            )
        )
    )


def current_device(request: Request, db: Session = Depends(get_db)) -> Device:
    header = request.headers.get("authorization", "")
    if not header.lower().startswith("bearer zdv_"):
        raise ApiError(401, "device_unauthenticated", "Device credential required")
    credential = header[7:].strip()
    try:
        device_id = uuid.UUID(credential[4:].split(".", 1)[0])
    except ValueError as e:
        raise ApiError(401, "device_unauthenticated", "Device credential invalid") from e
    digest = sha256_hex(credential)
    creds = _live(db, device_id)
    match = next((c for c in creds if constant_eq(c.secret_hash, digest)), None)
    if match is None:
        raise ApiError(401, "device_unauthenticated", "Device credential invalid")
    now = utcnow()
    if match.activated_at is None:
        match.activated_at = now
        for other in creds:
            if other is not match:
                other.revoked_at = now
    device = db.get(Device, device_id)
    if device is None:
        raise ApiError(401, "device_unauthenticated", "Device credential invalid")
    device.last_seen_at = now
    return device
