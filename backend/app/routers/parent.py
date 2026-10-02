import base64
import json
import uuid
from datetime import datetime

from fastapi import APIRouter, Depends, Query, Response
from sqlalchemy import func, select, tuple_
from sqlalchemy.orm import Session

from app import services
from app.auth import current_parent
from app.config import Settings, get_settings
from app.db import get_db
from app.errors import ApiError, not_found
from app.models import (
    ActivityDefinition,
    AssessmentResult,
    Child,
    ClaimAttempt,
    ClaimStatus,
    DeviceCommand,
    LearningSession,
    Outcome,
    Parent,
    utcnow,
)
from app.schemas import (
    ActivityOut,
    ChildIn,
    ChildOut,
    ChildUpdate,
    ClaimIn,
    ClaimOut,
    CommandIn,
    CommandOut,
    DeleteAccountIn,
    DeviceOut,
    DeviceUpdate,
    LearningPreferencesIn,
    LearningPreferencesOut,
    Page,
    ParentOut,
    ParentUpdate,
    SessionDetailOut,
    SessionSummaryOut,
)

router = APIRouter(prefix="/v1", tags=["parent"])
Db = Depends(get_db)
Me = Depends(current_parent)
Cfg = Depends(get_settings)


# ------------------------------------------------------------------ account


@router.get("/me", response_model=ParentOut)
def get_me(parent: Parent = Me):
    return parent


@router.patch("/me", response_model=ParentOut)
def update_me(body: ParentUpdate, parent: Parent = Me, db: Session = Db):
    for k, v in body.model_dump(exclude_unset=True).items():
        setattr(parent, k, v)
    db.flush()
    return parent


@router.post("/me/delete", status_code=202)
def delete_account(body: DeleteAccountIn, parent: Parent = Me, db: Session = Db):
    """Release devices, delete children (cascades sessions), and mark the
    account deleted. The identity-provider user must also be deleted by the
    server-side admin job (see docs/OPERATIONS.md); the app signs out."""
    for device in services.owned_devices(db, parent):
        services.release_ownership(db, device)
    for child in list(parent.children):
        db.delete(child)
    parent.deletion_requested_at = utcnow()
    parent.email = f"deleted-{parent.id}"
    parent.display_name = None
    db.flush()
    return {"status": "scheduled"}


# ------------------------------------------------------------------ children


@router.get("/children", response_model=list[ChildOut])
def list_children(parent: Parent = Me, db: Session = Db):
    return db.scalars(
        select(Child).where(Child.parent_id == parent.id).order_by(Child.created_at)
    ).all()


@router.post("/children", response_model=ChildOut, status_code=201)
def create_child(body: ChildIn, parent: Parent = Me, db: Session = Db):
    count = db.scalar(select(func.count()).select_from(Child).where(Child.parent_id == parent.id))
    if (count or 0) >= 6:
        raise ApiError(400, "child_limit", "You can add up to 6 children")
    child = Child(parent_id=parent.id, **body.model_dump())
    db.add(child)
    db.flush()
    services.get_preferences(db, child)
    # First child becomes active on any of this parent's devices that has none.
    for device in services.owned_devices(db, parent):
        if device.active_child_id is None:
            device.active_child_id = child.id
            services.push_config(db, device)
    return child


@router.patch("/children/{child_id}", response_model=ChildOut)
def update_child(child_id: uuid.UUID, body: ChildUpdate, parent: Parent = Me, db: Session = Db):
    child = services.owned_child(db, parent, child_id)
    for k, v in body.model_dump(exclude_unset=True).items():
        setattr(child, k, v)
    db.flush()
    for device in services.owned_devices(db, parent):
        if device.active_child_id == child.id:
            services.push_config(db, device)
    return child


@router.delete("/children/{child_id}", status_code=204)
def delete_child(child_id: uuid.UUID, parent: Parent = Me, db: Session = Db):
    child = services.owned_child(db, parent, child_id)
    affected = [d for d in services.owned_devices(db, parent) if d.active_child_id == child.id]
    db.delete(child)
    db.flush()
    for device in affected:
        device.active_child_id = None
        services.push_config(db, device)
    return Response(status_code=204)


@router.get("/children/{child_id}/preferences", response_model=LearningPreferencesOut)
def get_child_preferences(child_id: uuid.UUID, parent: Parent = Me, db: Session = Db):
    prefs = services.get_preferences(db, services.owned_child(db, parent, child_id))
    return LearningPreferencesOut(version=prefs.version, updated_at=prefs.updated_at,
                                  payload=prefs.payload)  # fmt: skip


@router.put("/children/{child_id}/preferences", response_model=LearningPreferencesOut)
def put_child_preferences(
    child_id: uuid.UUID, body: LearningPreferencesIn, parent: Parent = Me, db: Session = Db
):
    prefs = services.set_preferences(db, services.owned_child(db, parent, child_id), body)
    return LearningPreferencesOut(version=prefs.version, updated_at=prefs.updated_at,
                                  payload=prefs.payload)  # fmt: skip


# ------------------------------------------------------------------ devices


@router.get("/devices", response_model=list[DeviceOut])
def list_devices(parent: Parent = Me, db: Session = Db, settings: Settings = Cfg):
    return [services.device_out(db, d, settings) for d in services.owned_devices(db, parent)]


@router.get("/devices/{device_id}", response_model=DeviceOut)
def get_device(device_id: uuid.UUID, parent: Parent = Me, db: Session = Db,
               settings: Settings = Cfg):  # fmt: skip
    return services.device_out(db, services.owned_device(db, parent, device_id), settings)


@router.patch("/devices/{device_id}", response_model=DeviceOut)
def update_device(
    device_id: uuid.UUID, body: DeviceUpdate, parent: Parent = Me, db: Session = Db,
    settings: Settings = Cfg,
):  # fmt: skip
    device = services.owned_device(db, parent, device_id)
    data = body.model_dump(exclude_unset=True)
    if "name" in data:
        device.name = data["name"]
    if "active_child_id" in data and data["active_child_id"] != device.active_child_id:
        if data["active_child_id"] is not None:
            services.owned_child(db, parent, data["active_child_id"])
        device.active_child_id = data["active_child_id"]
        services.push_config(db, device)
    db.flush()
    return services.device_out(db, device, settings)


@router.delete("/devices/{device_id}/ownership", status_code=204)
def remove_device(device_id: uuid.UUID, parent: Parent = Me, db: Session = Db):
    """Remove from this account. The toy can no longer reach this family's
    profiles, preferences or sessions, and queued commands are cancelled. Its
    own credential is kept so a new owner can set it up with the setup code.
    (Credential revocation is an operations action for compromised units.)"""
    device = services.owned_device(db, parent, device_id)
    services.release_ownership(db, device)
    return Response(status_code=204)


@router.post("/devices/{device_id}/commands", response_model=CommandOut)
def send_command(
    device_id: uuid.UUID, body: CommandIn, response: Response, parent: Parent = Me,
    db: Session = Db, settings: Settings = Cfg,
):  # fmt: skip
    device = services.owned_device(db, parent, device_id)
    before = db.get(DeviceCommand, body.id)
    cmd = services.create_command(db, parent, device, body.id, body.kind, settings)
    response.status_code = 200 if before is not None else 201
    return cmd


@router.get("/devices/{device_id}/commands/{command_id}", response_model=CommandOut)
def get_command(device_id: uuid.UUID, command_id: uuid.UUID, parent: Parent = Me,
                db: Session = Db):  # fmt: skip
    device = services.owned_device(db, parent, device_id)
    cmd = db.get(DeviceCommand, command_id)
    if cmd is None or cmd.device_id != device.id:
        raise not_found("command")
    services.expire_stale_commands(db, device)
    return cmd


@router.post("/devices/{device_id}/config/resend", response_model=DeviceOut)
def resend_config(device_id: uuid.UUID, parent: Parent = Me, db: Session = Db,
                  settings: Settings = Cfg):  # fmt: skip
    device = services.owned_device(db, parent, device_id)
    services.push_config(db, device)
    return services.device_out(db, device, settings)


# ------------------------------------------------------------------ claims


@router.post("/claims", response_model=ClaimOut, status_code=201)
def start_claim(body: ClaimIn, parent: Parent = Me, db: Session = Db, settings: Settings = Cfg):
    attempt, token = services.create_claim(db, parent, body.serial, body.setup_code, settings)
    return ClaimOut(id=attempt.id, status=attempt.status, expires_at=attempt.expires_at,
                    device_id=attempt.device_id, claim_token=token)  # fmt: skip


@router.get("/claims/{claim_id}", response_model=ClaimOut)
def get_claim(claim_id: uuid.UUID, parent: Parent = Me, db: Session = Db):
    attempt = db.get(ClaimAttempt, claim_id)
    if attempt is None or attempt.parent_id != parent.id:
        raise not_found("claim")
    services.refresh_claim_status(attempt)
    return ClaimOut(id=attempt.id, status=attempt.status, expires_at=attempt.expires_at,
                    device_id=attempt.device_id, failure_reason=attempt.failure_reason)  # fmt: skip


@router.post("/claims/{claim_id}/cancel", response_model=ClaimOut)
def cancel_claim(claim_id: uuid.UUID, parent: Parent = Me, db: Session = Db):
    attempt = db.get(ClaimAttempt, claim_id)
    if attempt is None or attempt.parent_id != parent.id:
        raise not_found("claim")
    services.refresh_claim_status(attempt)
    if attempt.status is ClaimStatus.pending:
        attempt.status = ClaimStatus.cancelled
    return ClaimOut(id=attempt.id, status=attempt.status, expires_at=attempt.expires_at,
                    device_id=attempt.device_id)  # fmt: skip


# ------------------------------------------------------------------ activities & sessions


@router.get("/activities", response_model=list[ActivityOut])
def list_activities(_parent: Parent = Me, db: Session = Db):
    return db.scalars(
        select(ActivityDefinition)
        .where(ActivityDefinition.enabled.is_(True))
        .order_by(ActivityDefinition.sort_order)
    ).all()


def _encode_cursor(started_at: datetime, sid: uuid.UUID) -> str:
    raw = json.dumps({"t": started_at.isoformat(), "id": str(sid)}).encode()
    return base64.urlsafe_b64encode(raw).decode()


def _decode_cursor(cursor: str) -> tuple[datetime, uuid.UUID]:
    try:
        data = json.loads(base64.urlsafe_b64decode(cursor.encode()))
        return datetime.fromisoformat(data["t"]), uuid.UUID(data["id"])
    except (ValueError, KeyError, json.JSONDecodeError) as e:
        raise ApiError(400, "invalid_cursor", "Invalid cursor") from e


def _counts(db: Session, ids: list[uuid.UUID]) -> dict[uuid.UUID, dict[str, int]]:
    """Count the final outcome of each item (last attempt per seq-group)."""
    out: dict[uuid.UUID, dict[str, int]] = {i: {o.value: 0 for o in Outcome} for i in ids}
    if not ids:
        return out
    rows = db.execute(
        select(AssessmentResult.session_id, AssessmentResult.item_index,
               AssessmentResult.outcome)  # fmt: skip
        .where(AssessmentResult.session_id.in_(ids))
        .order_by(AssessmentResult.session_id, AssessmentResult.seq)
    ).all()
    final: dict[tuple[uuid.UUID, int], Outcome] = {}
    for sid, index, outcome in rows:
        final[(sid, index)] = outcome
    for (sid, _p), outcome in final.items():
        out[sid][outcome.value] += 1
    return out


def _summary(s: LearningSession, counts: dict[str, int]) -> dict:
    return dict(
        id=s.id, child_id=s.child_id, activity_key=s.activity_key, status=s.status,
        started_at=s.started_at, ended_at=s.ended_at, summary=s.summary,
        correct=counts["correct"], needs_practice=counts["needs_practice"],
        uncertain=counts["uncertain"],
    )  # fmt: skip


@router.get("/sessions", response_model=Page[SessionSummaryOut])
def list_sessions(
    parent: Parent = Me,
    db: Session = Db,
    child_id: uuid.UUID | None = None,
    cursor: str | None = None,
    limit: int = Query(20, ge=1, le=50),
):
    q = (
        select(LearningSession)
        .join(Child, Child.id == LearningSession.child_id)
        .where(Child.parent_id == parent.id)
    )
    if child_id is not None:
        services.owned_child(db, parent, child_id)
        q = q.where(LearningSession.child_id == child_id)
    if cursor:
        t, sid = _decode_cursor(cursor)
        q = q.where(tuple_(LearningSession.started_at, LearningSession.id) < tuple_(t, sid))
    rows = list(
        db.scalars(
            q.order_by(LearningSession.started_at.desc(), LearningSession.id.desc()).limit(
                limit + 1
            )
        )
    )
    more = len(rows) > limit
    rows = rows[:limit]
    counts = _counts(db, [r.id for r in rows])
    return Page(
        items=[SessionSummaryOut(**_summary(r, counts[r.id])) for r in rows],
        next_cursor=_encode_cursor(rows[-1].started_at, rows[-1].id) if more and rows else None,
    )


@router.get("/sessions/{session_id}", response_model=SessionDetailOut)
def get_session(session_id: uuid.UUID, parent: Parent = Me, db: Session = Db):
    s = services.owned_session(db, parent, session_id)
    counts = _counts(db, [s.id])[s.id]
    turns = [t for t in s.turns if t.text is not None] if parent.store_transcripts else []
    return SessionDetailOut(
        **_summary(s, counts),
        assessments=s.assessments,  # type: ignore[arg-type]
        turns=turns,  # type: ignore[arg-type]
        transcripts_available=bool(turns),
    )


@router.delete("/sessions/{session_id}", status_code=204)
def delete_session(session_id: uuid.UUID, parent: Parent = Me, db: Session = Db):
    db.delete(services.owned_session(db, parent, session_id))
    return Response(status_code=204)
