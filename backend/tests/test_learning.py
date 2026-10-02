import pytest

from app.learning.assessors import (
    Heard,
    MathsQuestion,
    Rubric,
    UnavailablePronunciationAssessor,
    assess_maths,
    assess_rubric,
    assess_spelling,
    generate_maths_questions,
)
from app.learning.controller import MAX_ATTEMPTS, MAX_UNCLEAR, ActivityController, summarize
from app.learning.numbers import parse_spoken_number
from app.models import Outcome
from app.services import default_preferences

# ------------------------------------------------------------- numbers


@pytest.mark.parametrize(
    "text,value",
    [
        ("seven", 7), ("7", 7), ("it's seven", 7), ("um I think it's 12", 12),
        ("twenty one", 21), ("twenty-one", 21), ("ninety nine", 99), ("one hundred", 100),
        ("three plus four is seven", 7), ("five no six", 6), ("five, wait, actually six", 6),
        ("four", 4), ("for", 4), ("to", 2), ("zero", 0), ("seven seven", 7),
    ],
)  # fmt: skip
def test_parse_spoken_number(text, value):
    assert parse_spoken_number(text).value == value


@pytest.mark.parametrize(
    "text,reason",
    [("", "empty"), ("banana", "no_number"), ("five six", "multiple_numbers"),
     ("I want to go for a walk with my dog and my cat", "no_number")],
)  # fmt: skip
def test_parse_spoken_number_refuses_to_guess(text, reason):
    p = parse_spoken_number(text)
    assert p.value is None and p.reason == reason


# ------------------------------------------------------------- maths


def test_maths_generation_is_deterministic_and_bounded():
    a = generate_maths_questions(42, 8, ["addition", "subtraction"], 10, "steady")
    b = generate_maths_questions(42, 8, ["addition", "subtraction"], 10, "steady")
    assert a == b
    for q in a:
        assert 0 <= q.answer <= 10
        assert q.answer == (q.a + q.b if q.op == "+" else q.a - q.b)


def test_maths_assessment():
    q = MathsQuestion(3, 4, "+")
    assert assess_maths(q, Heard("seven")).outcome is Outcome.correct
    assert assess_maths(q, Heard("eight")).outcome is Outcome.needs_practice
    assert assess_maths(q, Heard("seven", stt_confidence=0.3)).outcome is Outcome.uncertain
    assert assess_maths(q, Heard("", audio_quality="silent")).outcome is Outcome.uncertain
    assert assess_maths(q, Heard("six or seven")).outcome is Outcome.uncertain
    r = assess_maths(q, Heard("seven"))
    assert (r.source, r.source_version) == ("maths.deterministic", "1")


# ------------------------------------------------------------- spelling


@pytest.mark.parametrize(
    "text,outcome",
    [
        ("c a t", Outcome.correct), ("C-A-T", Outcome.correct), ("see ay tee", Outcome.correct),
        ("um c, a, t", Outcome.correct), ("c a c a t", Outcome.correct),  # restart
        ("k a t", Outcome.needs_practice), ("c a", Outcome.needs_practice),
        ("c a a t", Outcome.uncertain),  # stutter or echo: ask again
        ("cat", Outcome.uncertain),  # said the word, not the letters
        ("c a banana t", Outcome.uncertain),
    ],
)  # fmt: skip
def test_spelling(text, outcome):
    assert assess_spelling("cat", Heard(text)).outcome is outcome


def test_spelling_double_letters():
    assert assess_spelling("tree", Heard("t r double e")).outcome is Outcome.correct
    assert assess_spelling("wet", Heard("double u e t")).outcome is Outcome.correct


# ------------------------------------------------------------- stories / vocabulary


def test_rubric_accepts_varied_wording():
    rubric = Rubric((("rabbit", "bunny"), ("owl",)))
    for answer in ("Rabbit", "the bunny helped", "owl and rabbit", "it was the owls"):
        assert assess_rubric(rubric, Heard(answer)).outcome is Outcome.correct
    assert assess_rubric(rubric, Heard("a big dog")).outcome is Outcome.needs_practice
    assert assess_rubric(rubric, Heard("", audio_quality="noisy")).outcome is Outcome.uncertain


def test_open_ended_rubric_accepts_any_reply():
    rubric = Rubric((), open_ended=True)
    assert assess_rubric(rubric, Heard("happy and excited")).outcome is Outcome.correct


# ------------------------------------------------------------- pronunciation


def test_pronunciation_is_never_inferred_from_text():
    a = UnavailablePronunciationAssessor().assess(b"", "sh", "en-GB")
    assert a.outcome is Outcome.uncertain and a.reason == "no_audio_assessor"


# ------------------------------------------------------------- controller


def _prefs(activity="maths", minutes=5, **extra):
    p = default_preferences()
    p["activities"][activity]["session_minutes"] = minutes
    p.update(extra)
    return p


def test_controller_happy_path_to_summary():
    ctl = ActivityController()
    step = ctl.start("maths", _prefs(), seed=1)
    state = step.state
    assert step.reply.state == "listen" and "What is" in step.reply.say
    n = len(state["items"])
    for i in range(n):
        answer = state["items"][state["index"]]["expected"]
        step = ctl.handle(state, f"t{i}", Heard(answer))
        assert step.reply.outcome is Outcome.correct
    assert step.reply.done and step.reply.state == "summary"
    assert state["finals"] == ["correct"] * n
    assert summarize("maths", state["finals"]) == f"{n} items practised, {n} correct."


def test_controller_limits_unsuccessful_attempts():
    ctl = ActivityController()
    state = ctl.start("maths", _prefs(), seed=3).state
    expected = int(state["items"][0]["expected"])
    wrong = str(expected + 1)
    replies = [ctl.handle(state, f"w{i}", Heard(wrong)).reply for i in range(MAX_ATTEMPTS)]
    assert replies[0].state == "listen" and state["index"] == 1  # moved on after limit
    assert "It's" in replies[-1].say  # answer shown gently
    assert state["finals"] == ["needs_practice"]


def test_controller_never_says_wrong_when_it_could_not_hear():
    ctl = ActivityController()
    state = ctl.start("maths", _prefs(), seed=5).state
    says = []
    for i in range(MAX_UNCLEAR + 1):
        r = ctl.handle(state, f"u{i}", Heard("", audio_quality="noisy")).reply
        assert r.outcome is Outcome.uncertain
        says.append(r.say.lower())
    assert all("wrong" not in s and "no," not in s and "nice try" not in s for s in says)
    assert "catch" in says[0]
    assert state["finals"] == ["uncertain"] and state["index"] == 1


def test_duplicate_turn_is_not_reassessed():
    ctl = ActivityController()
    state = ctl.start("maths", _prefs(), seed=7).state
    answer = state["items"][0]["expected"]
    first = ctl.handle(state, "same", Heard(answer))
    again = ctl.handle(state, "same", Heard(answer))
    assert first.records and not again.records
    assert again.reply.say == first.reply.say
    assert state["index"] == 1


def test_phonics_without_audio_assessor_records_practice_only():
    ctl = ActivityController()
    state = ctl.start("phonics", _prefs("phonics"), seed=1).state
    step = ctl.handle(state, "p1", Heard("sss"))
    assert step.reply.outcome is Outcome.uncertain
    assert step.records[0].assessment.source == "pronunciation.unavailable"
    assert state["index"] == 1  # advances without nagging


@pytest.mark.parametrize("activity", ["phonics", "vocabulary", "spelling", "maths", "stories"])
def test_every_activity_starts_and_completes(activity):
    ctl = ActivityController()
    step = ctl.start(activity, _prefs(activity), seed=11)
    state, i = step.state, 0
    while not step.reply.done:
        step = ctl.handle(state, f"t{i}", Heard("", audio_quality="silent"))
        i += 1
        assert i < 100
    assert step.reply.state == "summary"
