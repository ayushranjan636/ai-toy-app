"""Device-facing API. Authenticated with per-device credentials only."""

import copy
import random
import uuid

from fastapi import APIRouter, Depends
from sqlalchemy import select
from sqlalchemy.orm import Session

from app import services
from app.db import get_db
from app.device_auth import current_device
from app.errors import ApiError, not_found
from app.learning.assessors import Heard
from app.learning.controller import ActivityController, summarize
from app.logging import log
from app.models import (
    AssessmentResult,
    Child,
    CommandStatus,
    ConversationTurn,
    Device,
    DeviceCommand,
    DeviceConfigVersion,
    LatencySample,
    LearningSession,
    Parent,
    utcnow,
)
from app.schemas import (
    ActivityStartIn,
    ChildUtteranceIn,
    CommandAckIn,
    DeviceClaimIn,
    DeviceClaimOut,
    DeviceCommandOut,
    DeviceSyncOut,
    HeartbeatIn,
    LatencyBatchIn,
    ToyReplyOut,
)

router = APIRouter(prefix="/v1/device", tags=["device"])
Db = Depends(get_db)
Dev = Depends(current_device)
controller = ActivityController()


def _owned(db: Session, device: Device) -> uuid.UUID:
    owner = services.owner_id(db, device.id)
    if owner is None:
        raise ApiError(403, "device_unclaimed", "Device is not linked to an account")
    return owner


@router.post("/claim", response_model=DeviceClaimOut)
def device_claim(body: DeviceClaimIn, device: Device = Dev, db: Session = Db):
    _attempt, credential = services.complete_claim(
        db, device, body.claim_token, body.firmware_version, body.wifi_ssid
    )
    log.info("device.claimed", device_id=str(device.id))
    return DeviceClaimOut(device_id=device.id, credential=credential,
                          desired_config_version=device.desired_config_version)  # fmt: skip


@router.post("/heartbeat", response_model=DeviceSyncOut)
def heartbeat(body: HeartbeatIn, device: Device = Dev, db: Session = Db):
    """Report status and receive the latest desired config plus pending commands.

    Production transport should be a persistent TLS connection (MQTT/WebSocket);
    this polling endpoint carries the same messages."""
    if body.firmware_version:
        device.firmware_version = body.firmware_version
    if body.wifi_ssid is not None:
        device.wifi_ssid = body.wifi_ssid or None
    if services.owner_id(db, device.id) is None:
        return DeviceSyncOut(desired_config_version=0, config=None, commands=[])
    services.expire_stale_commands(db, device)

    config = None
    if device.applied_config_version < device.desired_config_version:
        row = db.get(DeviceConfigVersion, (device.id, device.desired_config_version))
        config = row.payload if row else None

    cmds = list(
        db.scalars(
            select(DeviceCommand)
            .where(
                DeviceCommand.device_id == device.id,
                DeviceCommand.status.in_([CommandStatus.pending, CommandStatus.delivered]),
            )
            .order_by(DeviceCommand.created_at)
            .limit(20)
        )
    )
    now = utcnow()
    for c in cmds:
        if c.status is CommandStatus.pending:
            c.status, c.delivered_at = CommandStatus.delivered, now
    return DeviceSyncOut(
        desired_config_version=device.desired_config_version,
        config=config,
        commands=[
            DeviceCommandOut(id=c.id, kind=c.kind, payload=c.payload,
                             config_version=c.config_version)  # fmt: skip
            for c in cmds
        ],
    )


@router.post("/commands/{command_id}/ack")
def ack(command_id: uuid.UUID, body: CommandAckIn, device: Device = Dev, db: Session = Db):
    cmd = services.ack_command(db, device, command_id, body.result == "ok", body.error)
    return {"id": str(cmd.id), "status": cmd.status.value,
            "applied_config_version": device.applied_config_version}  # fmt: skip


# ------------------------------------------------------------------ learning sessions


def _active_child(db: Session, device: Device, owner: uuid.UUID) -> Child:
    child = db.get(Child, device.active_child_id) if device.active_child_id else None
    if child is None or child.parent_id != owner:
        raise ApiError(409, "no_active_child", "Add a child profile in the Zivoo app")
    return child


@router.post("/sessions", response_model=ToyReplyOut)
def start_session(body: ActivityStartIn, device: Device = Dev, db: Session = Db):
    owner = _owned(db, device)
    child = _active_child(db, device, owner)
    existing = db.scalar(
        select(LearningSession).where(
            LearningSession.device_id == device.id,
            LearningSession.client_session_id == body.client_session_id,
        )
    )
    if existing is not None:
        return ToyReplyOut(**existing.state.get("opening", {"state": "listen", "say": ""}))

    services.activity_enabled(db, body.activity_key)
    prefs = services.get_preferences(db, child).payload
    act_prefs = prefs.get("activities", {}).get(body.activity_key, {})
    if not act_prefs.get("enabled", True):
        raise ApiError(409, "activity_disabled", "This activity is turned off")
    limit = prefs.get("daily_limit_minutes", 30)
    if services.minutes_today(db, child.id) >= limit:
        return ToyReplyOut(state="summary", done=True,
                           say="That's all the playing for today. See you tomorrow.")  # fmt: skip

    seed = random.SystemRandom().randint(0, 2**31)
    step = controller.start(body.activity_key, prefs, seed, child.language)
    step.state["opening"] = {"state": step.reply.state, "say": step.reply.say,
                             "done": step.reply.done}  # fmt: skip
    session = LearningSession(
        device_id=device.id, child_id=child.id, activity_key=body.activity_key,
        client_session_id=body.client_session_id, state=step.state,
    )  # fmt: skip
    db.add(session)
    db.flush()
    _store_turn(db, session, "toy", step.reply.say, owner)
    if step.reply.done:
        _finish(session)
    return ToyReplyOut(state=step.reply.state, say=step.reply.say, done=step.reply.done)


def _store_turn(db: Session, session: LearningSession, speaker: str, text: str,
                owner: uuid.UUID) -> None:  # fmt: skip
    parent = db.get(Parent, owner)
    seq = len(session.turns) + 1
    # Transcript text is kept only if the parent opted in; otherwise only the turn exists.
    keep = bool(parent and parent.store_transcripts)
    session.turns.append(ConversationTurn(seq=seq, speaker=speaker, text=text if keep else None))


def _finish(session: LearningSession) -> None:
    session.status = "completed"
    session.ended_at = utcnow()
    session.summary = summarize(session.activity_key, session.state.get("finals", []))


def _device_session(db: Session, device: Device, client_session_id: str) -> LearningSession:
    s = db.scalar(
        select(LearningSession).where(
            LearningSession.device_id == device.id,
            LearningSession.client_session_id == client_session_id,
        )
    )
    if s is None:
        raise not_found("session")
    return s


@router.post("/sessions/{client_session_id}/turns", response_model=ToyReplyOut)
def child_turn(
    client_session_id: str, body: ChildUtteranceIn, device: Device = Dev, db: Session = Db
):
    owner = _owned(db, device)
    session = _device_session(db, device, client_session_id)
    state = copy.deepcopy(session.state)  # new object so the JSON column is marked dirty
    already = body.turn_id in state.get("turns", {})
    step = controller.handle(
        state, body.turn_id,
        Heard(body.transcript, body.stt_confidence, body.audio_quality),
    )  # fmt: skip
    if not already:
        session.state = step.state
        _store_turn(db, session, "child", body.transcript, owner)
        _store_turn(db, session, "toy", step.reply.say, owner)
        for r in step.records:
            db.add(AssessmentResult(
                session_id=session.id, seq=r.seq, item_index=r.item_index,
                item_prompt=r.item_prompt, expected=r.expected,
                response_text=r.response_text if _keeps_text(db, owner) else None,
                outcome=r.assessment.outcome, attempt=r.attempt,
                source=r.assessment.source, source_version=r.assessment.source_version,
                confidence=r.assessment.confidence,
                details={"reason": r.assessment.reason, "normalized": r.assessment.normalized,
                         **r.assessment.details},
            ))  # fmt: skip
        if step.reply.done and session.status != "completed":
            _finish(session)
    return ToyReplyOut(state=step.reply.state, say=step.reply.say,
                       outcome=step.reply.outcome, done=step.reply.done)  # fmt: skip


def _keeps_text(db: Session, owner: uuid.UUID) -> bool:
    parent = db.get(Parent, owner)
    return bool(parent and parent.store_transcripts)


@router.post("/sessions/{client_session_id}/end", response_model=ToyReplyOut)
def end_session(client_session_id: str, device: Device = Dev, db: Session = Db):
    """Child walked away or interrupted. Idempotent."""
    _owned(db, device)
    session = _device_session(db, device, client_session_id)
    if session.status != "completed":
        _finish(session)
        session.status = "ended_early"
    return ToyReplyOut(state="summary", say="", done=True)


@router.post("/telemetry/latency", status_code=202)
def latency(body: LatencyBatchIn, device: Device = Dev, db: Session = Db):
    for s in body.samples:
        db.add(LatencySample(device_id=device.id, metric=s.metric, value_ms=s.value_ms,
                             conditions=s.conditions))  # fmt: skip
    return {"accepted": len(body.samples)}
