"""Domain services. Every parent-facing lookup goes through an `owned_*` helper
that scopes by the authenticated parent; ownership is never taken from input."""

import uuid
from datetime import timedelta

from sqlalchemy import func, select, update
from sqlalchemy.orm import Session

from app import device_auth
from app.config import Settings
from app.errors import ApiError, not_found
from app.models import (
    ActivityDefinition,
    Child,
    ClaimAttempt,
    ClaimStatus,
    CommandKind,
    CommandStatus,
    Device,
    DeviceCommand,
    DeviceConfigVersion,
    DeviceOwnership,
    LearningPreferences,
    LearningSession,
    Parent,
    utcnow,
)
from app.schemas import ACTIVITY_KEYS, DeviceOut, LearningPreferencesIn
from app.security import random_token, sha256_hex, verify_setup_code

MAX_FAILED_CLAIMS = 5
FAILED_CLAIM_WINDOW = timedelta(minutes=15)

# ------------------------------------------------------------------ ownership


def owned_child(db: Session, parent: Parent, child_id: uuid.UUID) -> Child:
    child = db.scalar(select(Child).where(Child.id == child_id, Child.parent_id == parent.id))
    if child is None:
        raise not_found("child")
    return child


def owner_id(db: Session, device_id: uuid.UUID) -> uuid.UUID | None:
    return db.scalar(
        select(DeviceOwnership.parent_id).where(
            DeviceOwnership.device_id == device_id, DeviceOwnership.released_at.is_(None)
        )
    )


def owned_device(db: Session, parent: Parent, device_id: uuid.UUID) -> Device:
    if owner_id(db, device_id) != parent.id:
        raise not_found("device")
    device = db.get(Device, device_id)
    if device is None:
        raise not_found("device")
    return device


def owned_devices(db: Session, parent: Parent) -> list[Device]:
    return list(
        db.scalars(
            select(Device)
            .join(DeviceOwnership, DeviceOwnership.device_id == Device.id)
            .where(DeviceOwnership.parent_id == parent.id, DeviceOwnership.released_at.is_(None))
            .order_by(DeviceOwnership.claimed_at)
        )
    )


def owned_session(db: Session, parent: Parent, session_id: uuid.UUID) -> LearningSession:
    s = db.scalar(
        select(LearningSession)
        .join(Child, Child.id == LearningSession.child_id)
        .where(LearningSession.id == session_id, Child.parent_id == parent.id)
    )
    if s is None:
        raise not_found("session")
    return s


def release_ownership(db: Session, device: Device) -> None:
    db.execute(
        update(DeviceOwnership)
        .where(DeviceOwnership.device_id == device.id, DeviceOwnership.released_at.is_(None))
        .values(released_at=utcnow())
    )
    device.active_child_id = None
    device.wifi_ssid = None
    # Cancel anything still queued for the previous family.
    db.execute(
        update(DeviceCommand)
        .where(
            DeviceCommand.device_id == device.id,
            DeviceCommand.status.in_([CommandStatus.pending, CommandStatus.delivered]),
        )
        .values(status=CommandStatus.expired, error="ownership_released")
    )


# ------------------------------------------------------------------ device view


def config_sync_state(db: Session, device: Device) -> str:
    if device.desired_config_version == 0:
        return "none"
    if device.applied_config_version >= device.desired_config_version:
        return "applied"
    failed = db.scalar(
        select(func.count())
        .select_from(DeviceCommand)
        .where(
            DeviceCommand.device_id == device.id,
            DeviceCommand.kind == CommandKind.apply_config,
            DeviceCommand.config_version == device.desired_config_version,
            DeviceCommand.status.in_([CommandStatus.failed, CommandStatus.expired]),
        )
    )
    return "failed" if failed else "pending"


def device_out(db: Session, device: Device, settings: Settings) -> DeviceOut:
    offline_after = timedelta(seconds=settings.device_offline_after_seconds)
    online = bool(device.last_seen_at and utcnow() - device.last_seen_at < offline_after)
    return DeviceOut(
        id=device.id,
        serial=device.serial,
        name=device.name,
        online=online,
        last_seen_at=device.last_seen_at,
        firmware_version=device.firmware_version,
        firmware_update_available=bool(
            device.latest_firmware_version
            and device.firmware_version
            and device.latest_firmware_version != device.firmware_version
        ),
        wifi_ssid=device.wifi_ssid,
        active_child_id=device.active_child_id,
        desired_config_version=device.desired_config_version,
        applied_config_version=device.applied_config_version,
        config_sync=config_sync_state(db, device),  # type: ignore[arg-type]
        is_simulated=device.is_simulated,
    )


# ------------------------------------------------------------------ preferences & config sync


def default_preferences() -> dict:
    return LearningPreferencesIn(
        activities={k: {"enabled": True, "difficulty": "gentle", "session_minutes": 10}
                    for k in ACTIVITY_KEYS}  # fmt: skip
    ).model_dump(exclude={"base_version"})


def get_preferences(db: Session, child: Child) -> LearningPreferences:
    prefs = db.get(LearningPreferences, child.id)
    if prefs is None:
        prefs = LearningPreferences(child_id=child.id, version=1, payload=default_preferences())
        db.add(prefs)
        db.flush()
    return prefs


def set_preferences(db: Session, child: Child, body: LearningPreferencesIn) -> LearningPreferences:
    prefs = get_preferences(db, child)
    if body.base_version is not None and body.base_version != prefs.version:
        raise ApiError(
            409,
            "version_conflict",
            "These settings were changed on another phone",
            {"current_version": prefs.version},
        )
    payload = default_preferences()
    payload.update(body.model_dump(exclude={"base_version"}, exclude_unset=False))
    if payload == prefs.payload:
        return prefs  # no-op: do not bump versions or re-send to the toy
    prefs.payload = payload
    prefs.version += 1
    prefs.updated_at = utcnow()
    db.flush()
    for device in db.scalars(select(Device).where(Device.active_child_id == child.id)):
        push_config(db, device)
    return prefs


def build_device_config(db: Session, device: Device) -> dict:
    child = db.get(Child, device.active_child_id) if device.active_child_id else None
    if child is None:
        return {"child": None, "preferences": None}
    prefs = get_preferences(db, child)
    return {
        # Only what the toy needs: first name for greetings and language.
        "child": {"id": str(child.id), "name": child.display_name, "language": child.language},
        "preferences": prefs.payload,
        "preferences_version": prefs.version,
    }


def push_config(db: Session, device: Device) -> int:
    """Record a new desired config version and queue one apply command.

    Older un-acknowledged apply commands are superseded, so a toy that was
    offline for several edits applies only the latest version once."""
    version = device.desired_config_version + 1
    db.add(DeviceConfigVersion(device_id=device.id, version=version,
                               payload=build_device_config(db, device)))  # fmt: skip
    db.execute(
        update(DeviceCommand)
        .where(
            DeviceCommand.device_id == device.id,
            DeviceCommand.kind == CommandKind.apply_config,
            DeviceCommand.status.in_([CommandStatus.pending, CommandStatus.delivered]),
        )
        .values(status=CommandStatus.expired, error="superseded")
    )
    device.desired_config_version = version
    db.add(
        DeviceCommand(
            id=uuid.uuid4(),
            device_id=device.id,
            parent_id=owner_id(db, device.id),
            kind=CommandKind.apply_config,
            payload={},
            config_version=version,
            expires_at=utcnow() + timedelta(days=30),
        )
    )
    db.flush()
    return version


# ------------------------------------------------------------------ commands


def create_command(
    db: Session, parent: Parent, device: Device, command_id: uuid.UUID, kind: str,
    settings: Settings,
) -> DeviceCommand:  # fmt: skip
    existing = db.get(DeviceCommand, command_id)
    if existing is not None:
        if existing.device_id != device.id or existing.parent_id != parent.id or (
            existing.kind != CommandKind(kind)
        ):
            raise ApiError(409, "command_id_conflict", "Command id already used")
        return existing  # idempotent retry
    cmd = DeviceCommand(
        id=command_id,
        device_id=device.id,
        parent_id=parent.id,
        kind=CommandKind(kind),
        payload={},
        expires_at=utcnow() + timedelta(seconds=settings.command_ttl_seconds),
    )
    db.add(cmd)
    db.flush()
    return cmd


def expire_stale_commands(db: Session, device: Device) -> None:
    db.execute(
        update(DeviceCommand)
        .where(
            DeviceCommand.device_id == device.id,
            DeviceCommand.status.in_([CommandStatus.pending, CommandStatus.delivered]),
            DeviceCommand.expires_at < utcnow(),
        )
        .values(status=CommandStatus.expired, error="expired")
    )


def ack_command(
    db: Session, device: Device, command_id: uuid.UUID, ok: bool, error: str | None
) -> DeviceCommand:
    cmd = db.get(DeviceCommand, command_id)
    if cmd is None or cmd.device_id != device.id:
        raise not_found("command")
    if cmd.status in (CommandStatus.acknowledged, CommandStatus.failed, CommandStatus.expired):
        return cmd  # duplicate or late ack: no second effect
    cmd.status = CommandStatus.acknowledged if ok else CommandStatus.failed
    cmd.acked_at = utcnow()
    cmd.error = None if ok else (error or "failed")
    if ok and cmd.kind is CommandKind.apply_config and cmd.config_version:
        device.applied_config_version = max(device.applied_config_version, cmd.config_version)
    if ok and cmd.kind is CommandKind.factory_reset:
        release_ownership(db, device)
    db.flush()
    return cmd


# ------------------------------------------------------------------ claiming


def _recent_failures(db: Session, parent: Parent) -> int:
    return db.scalar(
        select(func.count())
        .select_from(ClaimAttempt)
        .where(
            ClaimAttempt.parent_id == parent.id,
            ClaimAttempt.status == ClaimStatus.failed,
            ClaimAttempt.created_at > utcnow() - FAILED_CLAIM_WINDOW,
        )
    ) or 0


def create_claim(
    db: Session, parent: Parent, serial: str, setup_code: str, settings: Settings
) -> tuple[ClaimAttempt, str]:
    if _recent_failures(db, parent) >= MAX_FAILED_CLAIMS:
        raise ApiError(429, "too_many_attempts", "Too many attempts. Try again in 15 minutes")
    device = db.scalar(select(Device).where(Device.serial == serial.strip().upper()))
    if device is None or not verify_setup_code(setup_code, device.setup_code_hash):
        db.add(
            ClaimAttempt(
                device_id=device.id if device else None,
                parent_id=parent.id,
                status=ClaimStatus.failed,
                failure_reason="setup_code_invalid",
                expires_at=utcnow(),
            )
        )
        # Persist the failure even though the request errors (rate limiting relies on it).
        db.commit()
        # Same response whether the serial exists or not.
        raise ApiError(400, "setup_code_invalid", "That code doesn't match this Zivoo")
    current = owner_id(db, device.id)
    if current is not None and current != parent.id:
        raise ApiError(
            409, "device_owned_elsewhere",
            "This Zivoo is linked to another account. Ask them to remove it, "
            "or factory reset the toy.",
        )  # fmt: skip
    # One live attempt per parent+device: cancel earlier pending ones.
    db.execute(
        update(ClaimAttempt)
        .where(
            ClaimAttempt.device_id == device.id,
            ClaimAttempt.parent_id == parent.id,
            ClaimAttempt.status == ClaimStatus.pending,
        )
        .values(status=ClaimStatus.cancelled)
    )
    token = random_token("zcl", 24)
    attempt = ClaimAttempt(
        device_id=device.id,
        parent_id=parent.id,
        token_hash=sha256_hex(token),
        expires_at=utcnow() + timedelta(seconds=settings.claim_ttl_seconds),
    )
    db.add(attempt)
    db.flush()
    return attempt, token


def refresh_claim_status(attempt: ClaimAttempt) -> ClaimAttempt:
    if attempt.status is ClaimStatus.pending and attempt.expires_at < utcnow():
        attempt.status = ClaimStatus.expired
    return attempt


def complete_claim(
    db: Session, device: Device, token: str, firmware: str, ssid: str | None
) -> tuple[ClaimAttempt, str]:
    attempt = db.scalar(select(ClaimAttempt).where(ClaimAttempt.token_hash == sha256_hex(token)))
    if attempt is None or attempt.device_id != device.id:
        raise ApiError(400, "claim_invalid", "Claim token not recognised")
    refresh_claim_status(attempt)
    if attempt.status is ClaimStatus.completed:
        # Device retry after a lost response: same outcome, fresh pending credential.
        return attempt, device_auth.rotate(db, device)
    if attempt.status is not ClaimStatus.pending:
        raise ApiError(410, f"claim_{attempt.status.value}", "Claim is no longer valid")

    current = owner_id(db, device.id)
    if current is not None and current != attempt.parent_id:
        attempt.status, attempt.failure_reason = ClaimStatus.failed, "device_owned_elsewhere"
        db.commit()
        raise ApiError(409, "device_owned_elsewhere", "Device belongs to another account")
    if current is None:
        db.add(DeviceOwnership(device_id=device.id, parent_id=attempt.parent_id))

    device.firmware_version = firmware
    device.wifi_ssid = ssid
    attempt.status, attempt.completed_at = ClaimStatus.completed, utcnow()

    if device.active_child_id is None:
        first_child = db.scalar(
            select(Child).where(Child.parent_id == attempt.parent_id).order_by(Child.created_at)
        )
        if first_child is not None:
            device.active_child_id = first_child.id
    db.flush()
    push_config(db, device)
    return attempt, device_auth.rotate(db, device)


# ------------------------------------------------------------------ sessions


def minutes_today(db: Session, child_id: uuid.UUID) -> float:
    start = utcnow().replace(hour=0, minute=0, second=0, microsecond=0)
    rows = db.execute(
        select(LearningSession.started_at, LearningSession.ended_at).where(
            LearningSession.child_id == child_id, LearningSession.started_at >= start
        )
    ).all()
    now = utcnow()
    return sum(((e or now) - s).total_seconds() for s, e in rows) / 60.0


def activity_enabled(db: Session, key: str) -> ActivityDefinition:
    act = db.get(ActivityDefinition, key)
    if act is None or not act.enabled:
        raise ApiError(404, "activity_unavailable", "Activity not available")
    return act
