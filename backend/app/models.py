import enum
import uuid
from datetime import UTC, datetime

from sqlalchemy import (
    JSON,
    Boolean,
    DateTime,
    Enum,
    Float,
    ForeignKey,
    Index,
    Integer,
    String,
    Text,
    UniqueConstraint,
    text,
)
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db import Base

JsonB = JSON().with_variant(JSONB(), "postgresql")


def utcnow() -> datetime:
    return datetime.now(UTC)


def uuid_pk() -> Mapped[uuid.UUID]:
    return mapped_column(primary_key=True, default=uuid.uuid4)


def ts(nullable: bool = False, default=None) -> Mapped:
    return mapped_column(DateTime(timezone=True), nullable=nullable, default=default)


def _enum(cls: type[enum.Enum], name: str) -> Enum:
    return Enum(cls, name=name, values_callable=lambda e: [m.value for m in e])


class OnboardingStep(enum.StrEnum):
    verify_email = "verify_email"
    intro = "intro"
    connect_toy = "connect_toy"
    child_profile = "child_profile"
    preferences = "preferences"
    done = "done"


class ClaimStatus(enum.StrEnum):
    pending = "pending"
    completed = "completed"
    expired = "expired"
    cancelled = "cancelled"
    failed = "failed"


class CommandStatus(enum.StrEnum):
    pending = "pending"
    delivered = "delivered"
    acknowledged = "acknowledged"
    failed = "failed"
    expired = "expired"


class CommandKind(enum.StrEnum):
    apply_config = "apply_config"
    play_greeting = "play_greeting"
    enter_wifi_setup = "enter_wifi_setup"
    factory_reset = "factory_reset"
    check_firmware = "check_firmware"


class Outcome(enum.StrEnum):
    correct = "correct"
    needs_practice = "needs_practice"
    uncertain = "uncertain"


class Parent(Base):
    __tablename__ = "parent"
    id: Mapped[uuid.UUID] = uuid_pk()
    idp_subject: Mapped[str] = mapped_column(String(255), unique=True)
    email: Mapped[str] = mapped_column(String(320))
    display_name: Mapped[str | None] = mapped_column(String(80))
    marketing_opt_in: Mapped[bool] = mapped_column(Boolean, default=False)
    store_transcripts: Mapped[bool] = mapped_column(Boolean, default=False)
    product_analytics: Mapped[bool] = mapped_column(Boolean, default=False)
    data_choices_confirmed: Mapped[bool] = mapped_column(Boolean, default=False)
    onboarding_step: Mapped[OnboardingStep] = mapped_column(
        _enum(OnboardingStep, "onboarding_step"), default=OnboardingStep.intro
    )
    notify_session_summaries: Mapped[bool] = mapped_column(Boolean, default=True)
    notify_device_offline: Mapped[bool] = mapped_column(Boolean, default=True)
    created_at: Mapped[datetime] = ts(default=utcnow)
    deletion_requested_at: Mapped[datetime | None] = ts(nullable=True)

    children: Mapped[list["Child"]] = relationship(back_populates="parent")


class Child(Base):
    __tablename__ = "child"
    id: Mapped[uuid.UUID] = uuid_pk()
    parent_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("parent.id", ondelete="CASCADE"), index=True
    )
    display_name: Mapped[str] = mapped_column(String(40))
    birth_year: Mapped[int | None] = mapped_column(Integer)
    language: Mapped[str] = mapped_column(String(16), default="en-GB")
    created_at: Mapped[datetime] = ts(default=utcnow)

    parent: Mapped[Parent] = relationship(back_populates="children")
    preferences: Mapped["LearningPreferences | None"] = relationship(
        back_populates="child", cascade="all, delete-orphan", uselist=False
    )


class Device(Base):
    __tablename__ = "device"
    id: Mapped[uuid.UUID] = uuid_pk()
    serial: Mapped[str] = mapped_column(String(64), unique=True)
    # Hash of the per-unit setup secret printed in the QR code (never stored in clear).
    setup_code_hash: Mapped[str] = mapped_column(String(128))
    hardware_rev: Mapped[str] = mapped_column(String(32), default="esp32s3-rev-a")
    firmware_version: Mapped[str | None] = mapped_column(String(32))
    latest_firmware_version: Mapped[str | None] = mapped_column(String(32))
    name: Mapped[str] = mapped_column(String(40), default="Zivoo")
    last_seen_at: Mapped[datetime | None] = ts(nullable=True)
    wifi_ssid: Mapped[str | None] = mapped_column(String(64))
    desired_config_version: Mapped[int] = mapped_column(Integer, default=0)
    applied_config_version: Mapped[int] = mapped_column(Integer, default=0)
    active_child_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("child.id", ondelete="SET NULL")
    )
    is_simulated: Mapped[bool] = mapped_column(Boolean, default=False)
    created_at: Mapped[datetime] = ts(default=utcnow)


class DeviceCredential(Base):
    __tablename__ = "device_credential"
    id: Mapped[uuid.UUID] = uuid_pk()
    device_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("device.id", ondelete="CASCADE"), index=True
    )
    secret_hash: Mapped[str] = mapped_column(String(128))
    created_at: Mapped[datetime] = ts(default=utcnow)
    # A rotated credential is pending until first used; then older ones are revoked.
    activated_at: Mapped[datetime | None] = ts(nullable=True)
    revoked_at: Mapped[datetime | None] = ts(nullable=True)


class DeviceOwnership(Base):
    __tablename__ = "device_ownership"
    __table_args__ = (
        Index(
            "uq_device_ownership_active",
            "device_id",
            unique=True,
            postgresql_where=text("released_at IS NULL"),
            sqlite_where=text("released_at IS NULL"),
        ),
    )
    id: Mapped[uuid.UUID] = uuid_pk()
    device_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("device.id", ondelete="CASCADE"))
    parent_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("parent.id", ondelete="CASCADE"), index=True
    )
    claimed_at: Mapped[datetime] = ts(default=utcnow)
    released_at: Mapped[datetime | None] = ts(nullable=True)


class ClaimAttempt(Base):
    __tablename__ = "claim_attempt"
    id: Mapped[uuid.UUID] = uuid_pk()
    device_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("device.id", ondelete="CASCADE"), index=True
    )
    parent_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("parent.id", ondelete="CASCADE"), index=True
    )
    token_hash: Mapped[str | None] = mapped_column(String(128), unique=True)
    status: Mapped[ClaimStatus] = mapped_column(
        _enum(ClaimStatus, "claim_status"), default=ClaimStatus.pending
    )
    expires_at: Mapped[datetime] = ts()
    created_at: Mapped[datetime] = ts(default=utcnow)
    completed_at: Mapped[datetime | None] = ts(nullable=True)
    failure_reason: Mapped[str | None] = mapped_column(String(64))


class LearningPreferences(Base):
    __tablename__ = "learning_preferences"
    child_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("child.id", ondelete="CASCADE"), primary_key=True
    )
    version: Mapped[int] = mapped_column(Integer, default=1)
    payload: Mapped[dict] = mapped_column(JsonB)
    updated_at: Mapped[datetime] = ts(default=utcnow)

    child: Mapped[Child] = relationship(back_populates="preferences")


class DeviceConfigVersion(Base):
    __tablename__ = "device_config_version"
    device_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("device.id", ondelete="CASCADE"), primary_key=True
    )
    version: Mapped[int] = mapped_column(Integer, primary_key=True)
    payload: Mapped[dict] = mapped_column(JsonB)
    created_at: Mapped[datetime] = ts(default=utcnow)


class ActivityDefinition(Base):
    __tablename__ = "activity_definition"
    key: Mapped[str] = mapped_column(String(40), primary_key=True)
    kind: Mapped[str] = mapped_column(String(20))
    title: Mapped[str] = mapped_column(String(60))
    summary: Mapped[str] = mapped_column(String(240))
    min_age: Mapped[int] = mapped_column(Integer, default=4)
    max_age: Mapped[int] = mapped_column(Integer, default=9)
    options_schema: Mapped[dict] = mapped_column(JsonB, default=dict)
    assessment_note: Mapped[str | None] = mapped_column(String(240))
    enabled: Mapped[bool] = mapped_column(Boolean, default=True)
    sort_order: Mapped[int] = mapped_column(Integer, default=0)


class LearningSession(Base):
    __tablename__ = "learning_session"
    __table_args__ = (UniqueConstraint("device_id", "client_session_id"),)
    id: Mapped[uuid.UUID] = uuid_pk()
    device_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("device.id", ondelete="SET NULL"), index=True
    )
    child_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("child.id", ondelete="CASCADE"), index=True
    )
    activity_key: Mapped[str] = mapped_column(ForeignKey("activity_definition.key"))
    client_session_id: Mapped[str] = mapped_column(String(64))
    status: Mapped[str] = mapped_column(String(20), default="in_progress")
    state: Mapped[dict] = mapped_column(JsonB, default=dict)  # controller state
    summary: Mapped[str | None] = mapped_column(Text)
    started_at: Mapped[datetime] = ts(default=utcnow)
    ended_at: Mapped[datetime | None] = ts(nullable=True)

    turns: Mapped[list["ConversationTurn"]] = relationship(
        cascade="all, delete-orphan", order_by="ConversationTurn.seq"
    )
    assessments: Mapped[list["AssessmentResult"]] = relationship(
        cascade="all, delete-orphan", order_by="AssessmentResult.seq"
    )


class ConversationTurn(Base):
    __tablename__ = "conversation_turn"
    id: Mapped[uuid.UUID] = uuid_pk()
    session_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("learning_session.id", ondelete="CASCADE"), index=True
    )
    seq: Mapped[int] = mapped_column(Integer)
    speaker: Mapped[str] = mapped_column(String(10))  # child | toy
    text: Mapped[str | None] = mapped_column(Text)  # null unless transcripts enabled
    created_at: Mapped[datetime] = ts(default=utcnow)


class AssessmentResult(Base):
    __tablename__ = "assessment_result"
    id: Mapped[uuid.UUID] = uuid_pk()
    session_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("learning_session.id", ondelete="CASCADE"), index=True
    )
    seq: Mapped[int] = mapped_column(Integer)
    item_index: Mapped[int] = mapped_column(Integer, default=0)
    item_prompt: Mapped[str] = mapped_column(String(240))
    expected: Mapped[str | None] = mapped_column(String(120))
    response_text: Mapped[str | None] = mapped_column(String(240))
    outcome: Mapped[Outcome] = mapped_column(_enum(Outcome, "assessment_outcome"))
    attempt: Mapped[int] = mapped_column(Integer, default=1)
    source: Mapped[str] = mapped_column(String(40))
    source_version: Mapped[str] = mapped_column(String(20))
    confidence: Mapped[float | None] = mapped_column(Float)
    details: Mapped[dict] = mapped_column(JsonB, default=dict)
    created_at: Mapped[datetime] = ts(default=utcnow)


class DeviceCommand(Base):
    __tablename__ = "device_command"
    id: Mapped[uuid.UUID] = mapped_column(primary_key=True)  # client idempotency key
    device_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("device.id", ondelete="CASCADE"), index=True
    )
    parent_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("parent.id", ondelete="SET NULL")
    )
    kind: Mapped[CommandKind] = mapped_column(_enum(CommandKind, "command_kind"))
    payload: Mapped[dict] = mapped_column(JsonB, default=dict)
    status: Mapped[CommandStatus] = mapped_column(
        _enum(CommandStatus, "command_status"), default=CommandStatus.pending
    )
    config_version: Mapped[int | None] = mapped_column(Integer)
    created_at: Mapped[datetime] = ts(default=utcnow)
    expires_at: Mapped[datetime] = ts()
    delivered_at: Mapped[datetime | None] = ts(nullable=True)
    acked_at: Mapped[datetime | None] = ts(nullable=True)
    error: Mapped[str | None] = mapped_column(String(120))


class LatencySample(Base):
    __tablename__ = "latency_sample"
    id: Mapped[uuid.UUID] = uuid_pk()
    device_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("device.id", ondelete="CASCADE"), index=True
    )
    metric: Mapped[str] = mapped_column(String(48), index=True)
    value_ms: Mapped[float] = mapped_column(Float)
    conditions: Mapped[str | None] = mapped_column(String(120))
    recorded_at: Mapped[datetime] = ts(default=utcnow)
