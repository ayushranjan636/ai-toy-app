import uuid
from datetime import datetime
from typing import Annotated, Literal

from pydantic import BaseModel, ConfigDict, Field, StringConstraints, field_validator

from app.models import ClaimStatus, CommandKind, CommandStatus, OnboardingStep, Outcome

ShortName = Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=40)]
Difficulty = Literal["gentle", "steady", "stretch"]


class Out(BaseModel):
    model_config = ConfigDict(from_attributes=True)


class Page[T](BaseModel):
    items: list[T]
    next_cursor: str | None = None


# ---------- Parent ----------


class ParentOut(Out):
    id: uuid.UUID
    email: str
    display_name: str | None
    marketing_opt_in: bool
    store_transcripts: bool
    product_analytics: bool
    data_choices_confirmed: bool
    onboarding_step: OnboardingStep
    notify_session_summaries: bool
    notify_device_offline: bool


class ParentUpdate(BaseModel):
    model_config = ConfigDict(extra="forbid")
    display_name: Annotated[str, StringConstraints(strip_whitespace=True, max_length=80)] | None = (
        None
    )
    marketing_opt_in: bool | None = None
    store_transcripts: bool | None = None
    product_analytics: bool | None = None
    data_choices_confirmed: bool | None = None
    onboarding_step: OnboardingStep | None = None
    notify_session_summaries: bool | None = None
    notify_device_offline: bool | None = None


class DeleteAccountIn(BaseModel):
    confirm: Literal["DELETE"]


# ---------- Children & preferences ----------

ACTIVITY_KEYS = ("phonics", "vocabulary", "spelling", "maths", "stories")
PHONICS_SOUNDS = ("s", "a", "t", "p", "i", "n", "m", "d", "sh", "ch", "th", "ng", "ai", "ee")
VOCAB_THEMES = ("animals", "food", "home", "nature", "feelings", "transport")
STORY_KEYS = ("the-lost-acorn", "moon-garden", "river-boat")


class MathsOptions(BaseModel):
    model_config = ConfigDict(extra="forbid")
    operations: list[Literal["addition", "subtraction"]] = ["addition"]
    max_number: Literal[5, 10, 20, 50, 100] = 10

    @field_validator("operations")
    @classmethod
    def _non_empty(cls, v):
        if not v:
            raise ValueError("choose at least one operation")
        return sorted(set(v))


class SpellingOptions(BaseModel):
    model_config = ConfigDict(extra="forbid")
    words: list[Annotated[str, StringConstraints(pattern=r"^[A-Za-z]{2,12}$")]] = Field(
        default_factory=list, max_length=20
    )

    @field_validator("words")
    @classmethod
    def _lower(cls, v):
        return list(dict.fromkeys(w.lower() for w in v))


class PhonicsOptions(BaseModel):
    model_config = ConfigDict(extra="forbid")
    sounds: list[Literal[PHONICS_SOUNDS]] = ["s", "a", "t"]  # type: ignore[valid-type]


class VocabularyOptions(BaseModel):
    model_config = ConfigDict(extra="forbid")
    themes: list[Literal[VOCAB_THEMES]] = ["animals"]  # type: ignore[valid-type]


class StoryOptions(BaseModel):
    model_config = ConfigDict(extra="forbid")
    stories: list[Literal[STORY_KEYS]] = ["the-lost-acorn"]  # type: ignore[valid-type]


class ActivityPrefs(BaseModel):
    model_config = ConfigDict(extra="forbid")
    enabled: bool = True
    difficulty: Difficulty = "gentle"
    session_minutes: int = Field(10, ge=5, le=20)


class LearningPreferencesIn(BaseModel):
    """Full preferences document; the client sends the whole thing with base_version."""

    model_config = ConfigDict(extra="forbid")
    base_version: int | None = Field(None, description="Version the client edited (optimistic)")
    daily_limit_minutes: int = Field(30, ge=10, le=120)
    quiet_start: str | None = Field(None, pattern=r"^\d{2}:\d{2}$")
    quiet_end: str | None = Field(None, pattern=r"^\d{2}:\d{2}$")
    activities: dict[Literal[ACTIVITY_KEYS], ActivityPrefs] = Field(  # type: ignore[valid-type]
        default_factory=dict
    )
    maths: MathsOptions = MathsOptions()
    spelling: SpellingOptions = SpellingOptions()
    phonics: PhonicsOptions = PhonicsOptions()
    vocabulary: VocabularyOptions = VocabularyOptions()
    stories: StoryOptions = StoryOptions()


class LearningPreferencesOut(BaseModel):
    version: int
    updated_at: datetime
    payload: dict


class ChildIn(BaseModel):
    model_config = ConfigDict(extra="forbid")
    display_name: ShortName
    birth_year: int | None = Field(None, ge=2010, le=2030)
    language: Literal["en-GB", "en-US", "en-IN"] = "en-GB"


class ChildUpdate(BaseModel):
    model_config = ConfigDict(extra="forbid")
    display_name: ShortName | None = None
    birth_year: int | None = Field(None, ge=2010, le=2030)
    language: Literal["en-GB", "en-US", "en-IN"] | None = None


class ChildOut(Out):
    id: uuid.UUID
    display_name: str
    birth_year: int | None
    language: str
    created_at: datetime


# ---------- Devices ----------

SyncState = Literal["applied", "pending", "failed", "none"]


class DeviceOut(BaseModel):
    id: uuid.UUID
    serial: str
    name: str
    online: bool
    last_seen_at: datetime | None
    firmware_version: str | None
    firmware_update_available: bool
    wifi_ssid: str | None
    active_child_id: uuid.UUID | None
    desired_config_version: int
    applied_config_version: int
    config_sync: SyncState
    is_simulated: bool


class DeviceUpdate(BaseModel):
    model_config = ConfigDict(extra="forbid")
    name: ShortName | None = None
    active_child_id: uuid.UUID | None = None


class ClaimIn(BaseModel):
    model_config = ConfigDict(extra="forbid")
    serial: Annotated[str, StringConstraints(strip_whitespace=True, min_length=4, max_length=64)]
    setup_code: Annotated[str, StringConstraints(min_length=8, max_length=32)]


class ClaimOut(BaseModel):
    id: uuid.UUID
    status: ClaimStatus
    expires_at: datetime
    device_id: uuid.UUID | None = None
    failure_reason: str | None = None
    # Present only in the creation response; delivered to the toy over BLE, never stored.
    claim_token: str | None = None


class CommandIn(BaseModel):
    model_config = ConfigDict(extra="forbid")
    id: uuid.UUID = Field(description="Client-generated idempotency key")
    kind: Literal["play_greeting", "enter_wifi_setup", "factory_reset", "check_firmware"]


class CommandOut(Out):
    id: uuid.UUID
    kind: CommandKind
    status: CommandStatus
    config_version: int | None
    created_at: datetime
    acked_at: datetime | None
    error: str | None


# ---------- Activities & sessions ----------


class ActivityOut(Out):
    key: str
    kind: str
    title: str
    summary: str
    min_age: int
    max_age: int
    options_schema: dict
    assessment_note: str | None


class AssessmentOut(Out):
    seq: int
    item_index: int
    item_prompt: str
    expected: str | None
    response_text: str | None
    outcome: Outcome
    attempt: int
    source: str
    source_version: str
    confidence: float | None


class TurnOut(Out):
    seq: int
    speaker: str
    text: str | None
    created_at: datetime


class SessionSummaryOut(BaseModel):
    id: uuid.UUID
    child_id: uuid.UUID
    activity_key: str
    status: str
    started_at: datetime
    ended_at: datetime | None
    summary: str | None
    correct: int
    needs_practice: int
    uncertain: int


class SessionDetailOut(SessionSummaryOut):
    assessments: list[AssessmentOut]
    turns: list[TurnOut]
    transcripts_available: bool


# ---------- Device-facing ----------


class DeviceClaimIn(BaseModel):
    model_config = ConfigDict(extra="forbid")
    claim_token: Annotated[str, StringConstraints(min_length=10, max_length=128)]
    firmware_version: Annotated[str, StringConstraints(max_length=32)]
    wifi_ssid: Annotated[str, StringConstraints(max_length=64)] | None = None


class DeviceClaimOut(BaseModel):
    device_id: uuid.UUID
    credential: str  # rotated per-device credential
    desired_config_version: int


class HeartbeatIn(BaseModel):
    model_config = ConfigDict(extra="forbid")
    firmware_version: Annotated[str, StringConstraints(max_length=32)] | None = None
    wifi_ssid: Annotated[str, StringConstraints(max_length=64)] | None = None
    applied_config_version: int | None = Field(None, ge=0)


class DeviceCommandOut(BaseModel):
    id: uuid.UUID
    kind: CommandKind
    payload: dict
    config_version: int | None


class DeviceSyncOut(BaseModel):
    desired_config_version: int
    config: dict | None
    commands: list[DeviceCommandOut]


class CommandAckIn(BaseModel):
    model_config = ConfigDict(extra="forbid")
    result: Literal["ok", "failed"]
    error: Annotated[str, StringConstraints(max_length=120)] | None = None


class ActivityStartIn(BaseModel):
    model_config = ConfigDict(extra="forbid")
    client_session_id: Annotated[str, StringConstraints(min_length=8, max_length=64)]
    activity_key: Literal[ACTIVITY_KEYS]  # type: ignore[valid-type]


class ChildUtteranceIn(BaseModel):
    """What the toy heard. Text comes from on-cloud STT; confidence from that STT."""

    model_config = ConfigDict(extra="forbid")
    turn_id: Annotated[str, StringConstraints(min_length=1, max_length=64)]
    transcript: Annotated[str, StringConstraints(max_length=400)]
    stt_confidence: float | None = Field(None, ge=0, le=1)
    audio_quality: Literal["good", "noisy", "clipped", "silent"] = "good"


class ToyReplyOut(BaseModel):
    state: str
    say: str
    outcome: Outcome | None = None
    done: bool = False


class LatencyIn(BaseModel):
    model_config = ConfigDict(extra="forbid")
    metric: Literal[
        "speech_end_to_first_audio",
        "stt",
        "assessment",
        "response_generation",
        "tts_first_audio",
        "reconnect",
        "network_failure",
    ]
    value_ms: float = Field(ge=0, le=600000)
    conditions: Annotated[str, StringConstraints(max_length=120)] | None = None


class LatencyBatchIn(BaseModel):
    samples: list[LatencyIn] = Field(max_length=200)


class LatencyStat(BaseModel):
    metric: str
    count: int
    p50_ms: float | None
    p95_ms: float | None
