"""Deterministic assessors. Each returns an Assessment with source + version."""

import random
import re
from dataclasses import dataclass, field
from typing import Protocol

from app.learning.numbers import parse_spoken_number
from app.models import Outcome

MIN_STT_CONFIDENCE = 0.55  # provisional; calibrate with representative recordings


@dataclass(frozen=True)
class Heard:
    transcript: str
    stt_confidence: float | None = None
    audio_quality: str = "good"  # good | noisy | clipped | silent


@dataclass(frozen=True)
class Assessment:
    outcome: Outcome
    source: str
    source_version: str
    confidence: float | None = None
    reason: str = ""  # machine-readable: why uncertain / what was wrong
    normalized: str | None = None
    details: dict = field(default_factory=dict)


def hearing_problem(heard: Heard) -> str | None:
    """Reasons we should not judge the child's answer at all."""
    if heard.audio_quality in ("silent", "clipped", "noisy"):
        return f"audio_{heard.audio_quality}"
    if not heard.transcript.strip():
        return "empty"
    if heard.stt_confidence is not None and heard.stt_confidence < MIN_STT_CONFIDENCE:
        return "low_stt_confidence"
    return None


# ---------------------------------------------------------------- maths


@dataclass(frozen=True)
class MathsQuestion:
    a: int
    b: int
    op: str  # "+" | "-"

    @property
    def answer(self) -> int:  # computed deterministically, never by a model
        return self.a + self.b if self.op == "+" else self.a - self.b

    @property
    def spoken(self) -> str:
        word = "plus" if self.op == "+" else "take away"
        return f"What is {self.a} {word} {self.b}?"

    def to_dict(self) -> dict:
        return {"a": self.a, "b": self.b, "op": self.op}


def generate_maths_questions(
    seed: int, count: int, operations: list[str], max_number: int, difficulty: str
) -> list[MathsQuestion]:
    rng = random.Random(seed)  # noqa: S311 - not security sensitive
    ceiling = {"gentle": max(5, max_number // 2), "steady": max_number, "stretch": max_number}[
        difficulty
    ]
    ops = ["+" if o == "addition" else "-" for o in operations] or ["+"]
    questions: list[MathsQuestion] = []
    seen: set[tuple[int, int, str]] = set()
    while len(questions) < count:
        op = rng.choice(ops)
        if op == "+":
            a = rng.randint(0 if difficulty == "gentle" else 1, ceiling)
            b = rng.randint(0, ceiling - a)
        else:
            a = rng.randint(1, ceiling)
            b = rng.randint(0, a)  # no negative answers for this age group
        if (a, b, op) in seen and len(seen) < ceiling * ceiling:
            continue
        seen.add((a, b, op))
        questions.append(MathsQuestion(a, b, op))
    return questions


def assess_maths(question: MathsQuestion, heard: Heard) -> Assessment:
    src, ver = "maths.deterministic", "1"
    if problem := hearing_problem(heard):
        return Assessment(Outcome.uncertain, src, ver, heard.stt_confidence, problem)
    parsed = parse_spoken_number(heard.transcript)
    if parsed.value is None:
        return Assessment(
            Outcome.uncertain, src, ver, heard.stt_confidence, parsed.reason,
            details={"candidates": list(parsed.candidates)},
        )  # fmt: skip
    outcome = Outcome.correct if parsed.value == question.answer else Outcome.needs_practice
    return Assessment(
        outcome, src, ver, heard.stt_confidence,
        "" if outcome is Outcome.correct else "different_number",
        normalized=str(parsed.value),
    )  # fmt: skip


# ---------------------------------------------------------------- spelling

_LETTER_NAMES = {
    "a": "a", "ay": "a", "eh": "a", "b": "b", "bee": "b", "be": "b", "c": "c", "see": "c",
    "sea": "c", "cee": "c", "d": "d", "dee": "d", "e": "e", "ee": "e", "f": "f", "ef": "f",
    "eff": "f", "g": "g", "gee": "g", "h": "h", "aitch": "h", "haitch": "h", "i": "i",
    "eye": "i", "j": "j", "jay": "j", "k": "k", "kay": "k", "l": "l", "el": "l", "ell": "l",
    "m": "m", "em": "m", "n": "n", "en": "n", "o": "o", "oh": "o", "p": "p", "pee": "p",
    "pea": "p", "q": "q", "queue": "q", "cue": "q", "r": "r", "are": "r", "ar": "r",
    "s": "s", "ess": "s", "es": "s", "t": "t", "tee": "t", "tea": "t", "u": "u", "you": "u",
    "v": "v", "vee": "v", "w": "w", "x": "x", "ex": "x", "y": "y", "why": "y", "z": "z",
    "zed": "z", "zee": "z",
}  # fmt: skip
_SPELL_FILLERS = {"um", "uh", "er", "erm", "hmm", "it's", "its", "is", "spelled", "spelt",
                  "and", "then", "letter"}  # fmt: skip


def letters_from_transcript(text: str) -> tuple[list[str], list[str]]:
    """Return (letters, unknown_tokens)."""
    raw = re.findall(r"[a-z']+", text.lower().replace("-", " ").replace(".", " "))
    letters: list[str] = []
    unknown: list[str] = []
    i = 0
    while i < len(raw):
        t = raw[i]
        if t == "double" and i + 1 < len(raw):
            nxt = raw[i + 1]
            if nxt in ("u", "you"):
                letters.append("w")  # "double u" is the letter W
            elif nxt in _LETTER_NAMES:
                letters += [_LETTER_NAMES[nxt]] * 2
            else:
                unknown.append(t)
            i += 2
            continue
        if t in _SPELL_FILLERS:
            pass
        elif t in _LETTER_NAMES:
            letters.append(_LETTER_NAMES[t])
        elif len(t) > 1 and t.isalpha() and len(raw) == 1:
            unknown.append(t)  # said a whole word instead of letters
        else:
            unknown.append(t)
        i += 1
    return letters, unknown


def assess_spelling(target: str, heard: Heard) -> Assessment:
    src, ver = "spelling.letter_sequence", "1"
    target = target.lower()
    if problem := hearing_problem(heard):
        return Assessment(Outcome.uncertain, src, ver, heard.stt_confidence, problem)
    letters, unknown = letters_from_transcript(heard.transcript)
    if not letters:
        reason = "said_word_not_letters" if unknown else "no_letters"
        return Assessment(Outcome.uncertain, src, ver, heard.stt_confidence, reason)
    if unknown:
        return Assessment(
            Outcome.uncertain, src, ver, heard.stt_confidence, "unrecognised_tokens",
            normalized="".join(letters),
        )  # fmt: skip
    spelled = "".join(letters)
    if spelled == target:
        return Assessment(Outcome.correct, src, ver, heard.stt_confidence, normalized=spelled)
    # A child restarting ("c a c a t") ends with the target: accept the final attempt.
    if spelled.endswith(target) and spelled[: -len(target)] and target.startswith(
        spelled[: -len(target)]
    ):
        return Assessment(
            Outcome.correct, src, ver, heard.stt_confidence, "restart", normalized=target
        )
    # Only difference is an adjacent repeated letter: could be a stutter or STT echo.
    if _collapse(spelled) == _collapse(target) and spelled != target:
        return Assessment(
            Outcome.uncertain, src, ver, heard.stt_confidence, "repeated_letter",
            normalized=spelled,
        )  # fmt: skip
    return Assessment(
        Outcome.needs_practice, src, ver, heard.stt_confidence, "different_letters",
        normalized=spelled,
    )  # fmt: skip


def _collapse(s: str) -> str:
    return re.sub(r"(.)\1+", r"\1", s)


# ---------------------------------------------------------------- rubric (stories, vocabulary)


@dataclass(frozen=True)
class Rubric:
    """Accept any answer mentioning at least `min_matches` concept groups.

    Each concept group is a set of words/phrases that express the same idea.
    `open_ended` questions (e.g. feelings) accept any on-topic, non-empty reply.
    """

    concepts: tuple[tuple[str, ...], ...]
    min_matches: int = 1
    open_ended: bool = False


def _normal_words(text: str) -> str:
    words = re.findall(r"[a-z]+", text.lower())
    stemmed = [w[:-1] if len(w) > 3 and w.endswith("s") and not w.endswith("ss") else w
               for w in words]  # fmt: skip
    return " " + " ".join(stemmed) + " "


def assess_rubric(rubric: Rubric, heard: Heard, source: str = "rubric") -> Assessment:
    ver = "1"
    if problem := hearing_problem(heard):
        return Assessment(Outcome.uncertain, source, ver, heard.stt_confidence, problem)
    text = _normal_words(heard.transcript)
    if rubric.open_ended:
        words = text.split()
        if len(words) >= 1 and words not in (["no"], ["dunno"], ["don't", "know"]):
            return Assessment(Outcome.correct, source, ver, heard.stt_confidence, "open_ended")
    matched = [
        i
        for i, group in enumerate(rubric.concepts)
        if any(_normal_words(p) in text for p in group)
    ]
    if len(matched) >= rubric.min_matches:
        return Assessment(
            Outcome.correct, source, ver, heard.stt_confidence, details={"matched": matched}
        )
    if re.search(r"\b(don t|dont|dunno|not sure|no idea)\b", text):
        return Assessment(Outcome.needs_practice, source, ver, heard.stt_confidence, "dont_know")
    return Assessment(
        Outcome.needs_practice, source, ver, heard.stt_confidence, "no_rubric_match",
        details={"matched": matched},
    )  # fmt: skip


# ---------------------------------------------------------------- pronunciation


class PronunciationAssessor(Protocol):
    """Audio-based assessor. Must analyse audio, never only the transcript."""

    name: str
    version: str

    def supports(self, language: str, age: int | None) -> bool: ...

    def assess(self, audio: bytes, target: str, language: str) -> Assessment: ...


class UnavailablePronunciationAssessor:
    """Used until a validated provider is integrated and calibrated.

    It always reports `uncertain`; we will not infer pronunciation quality
    from speech-to-text output.
    """

    name = "pronunciation.unavailable"
    version = "0"

    def supports(self, language: str, age: int | None) -> bool:
        return False

    def assess(self, audio: bytes, target: str, language: str) -> Assessment:
        return Assessment(Outcome.uncertain, self.name, self.version, None, "no_audio_assessor")
