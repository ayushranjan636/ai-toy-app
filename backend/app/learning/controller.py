"""Activity controller: Prompt -> Listen -> Assess -> Feedback -> Retry|Advance -> Summary.

Pure logic over a JSON-serialisable state dict, so it can be persisted per
session and replayed in tests. Duplicate utterances (same turn_id) return
the original reply without re-assessing.
"""

from dataclasses import dataclass, field

from app.learning import ENGINE_VERSION
from app.learning.assessors import (
    Assessment,
    Heard,
    MathsQuestion,
    PronunciationAssessor,
    UnavailablePronunciationAssessor,
    assess_maths,
    assess_rubric,
    assess_spelling,
    generate_maths_questions,
)
from app.learning.content import (
    PHONICS_EXAMPLES,
    SPELLING_WORDS,
    STORIES,
    VOCABULARY,
)
from app.models import Outcome

MAX_ATTEMPTS = 2  # unsuccessful attempts before we show the answer and move on
MAX_UNCLEAR = 2  # "didn't hear you" retries before moving on without judging


class Phase:
    prompt = "prompt"
    listen = "listen"
    assess = "assess"
    feedback = "feedback"
    summary = "summary"


@dataclass
class Reply:
    state: str
    say: str
    outcome: Outcome | None = None
    done: bool = False


@dataclass
class Record:
    """One persisted assessment row."""

    seq: int
    item_index: int
    item_prompt: str
    expected: str | None
    response_text: str | None
    attempt: int
    assessment: Assessment


@dataclass
class StepResult:
    state: dict
    reply: Reply
    records: list[Record] = field(default_factory=list)


def item_count(session_minutes: int) -> int:
    return max(3, min(10, session_minutes // 2 + 2))


# --------------------------------------------------------------- item building


def build_items(activity: str, prefs: dict, seed: int) -> tuple[list[dict], str | None]:
    """Return (items, intro). Items carry everything needed to assess them."""
    act = prefs.get("activities", {}).get(activity, {})
    difficulty = act.get("difficulty", "gentle")
    count = item_count(int(act.get("session_minutes", 10)))

    if activity == "maths":
        opts = prefs.get("maths", {})
        qs = generate_maths_questions(
            seed, count, opts.get("operations", ["addition"]), int(opts.get("max_number", 10)),
            difficulty,
        )  # fmt: skip
        return [{"prompt": q.spoken, "expected": str(q.answer), "q": q.to_dict()} for q in qs], (
            "Let's do some numbers together."
        )
    if activity == "spelling":
        words = prefs.get("spelling", {}).get("words") or SPELLING_WORDS[difficulty]
        words = (words * ((count // len(words)) + 1))[:count] if words else []
        return [{"prompt": f"Can you spell {w}? {w}.", "expected": w} for w in words], (
            "Let's spell some words. Say each letter one at a time."
        )
    if activity == "vocabulary":
        themes = prefs.get("vocabulary", {}).get("themes") or ["animals"]
        items = [
            {"prompt": p, "expected": None, "theme": t, "idx": i}
            for t in themes
            for i, (p, _r) in enumerate(VOCABULARY.get(t, []))
        ]
        return items[:count], "Here are some riddles. Tell me what you think."
    if activity == "stories":
        chosen = prefs.get("stories", {}).get("stories") or ["the-lost-acorn"]
        key = chosen[seed % len(chosen)]
        story = STORIES[key]
        items = [
            {"prompt": q, "expected": None, "story": key, "idx": i}
            for i, (q, _r) in enumerate(story["questions"])
        ]
        return items, f"Here is a story called {story['title']}. {story['text']}"
    if activity == "phonics":
        sounds = prefs.get("phonics", {}).get("sounds") or ["s", "a", "t"]
        items = [
            {"prompt": f"This sound is {s}, like in {PHONICS_EXAMPLES[s]}. Can you say it?",
             "expected": s}
            for s in sounds
        ][:count]  # fmt: skip
        return items, "Let's practise some sounds."
    raise ValueError(f"unknown activity {activity}")


def _assess(
    activity: str, item: dict, heard: Heard, pron: PronunciationAssessor, language: str
) -> Assessment:
    if activity == "maths":
        q = item["q"]
        return assess_maths(MathsQuestion(q["a"], q["b"], q["op"]), heard)
    if activity == "spelling":
        return assess_spelling(item["expected"], heard)
    if activity == "vocabulary":
        _p, rubric = VOCABULARY[item["theme"]][item["idx"]]
        return assess_rubric(rubric, heard, "vocabulary.rubric")
    if activity == "stories":
        _p, rubric = STORIES[item["story"]]["questions"][item["idx"]]
        return assess_rubric(rubric, heard, "story.rubric")
    if activity == "phonics":
        # Audio is required. STT text alone is never used to judge pronunciation.
        return pron.assess(b"", item["expected"], language)
    raise ValueError(activity)


# --------------------------------------------------------------- wording


class TemplateWriter:
    """Deterministic, child-friendly wording. An LLM writer could replace this,
    but only to rephrase: outcomes, answers and commands are fixed beforehand."""

    def correct(self, item: dict) -> str:
        return "Yes, that's right."

    def retry(self, activity: str, item: dict, a: Assessment) -> str:
        if activity == "maths":
            return f"Nice try. Let's count it again. {item['prompt']}"
        if activity == "spelling":
            return f"Close. Let's try {item['expected']} once more, one letter at a time."
        return f"Good thinking. Here's the question again. {item['prompt']}"

    def reveal(self, activity: str, item: dict) -> str:
        if activity == "maths":
            return f"It's {item['expected']}. We can practise that one again later."
        if activity == "spelling":
            letters = ", ".join(item["expected"].upper())
            return f"{item['expected']} is spelled {letters}. We'll come back to it."
        return "That's a tricky one. Let's think about it together another time."

    def unclear(self, a: Assessment) -> str:
        if a.reason == "said_word_not_letters":
            return "Can you spell it out, one letter at a time?"
        if a.reason == "multiple_numbers":
            return "I heard a few numbers. Which one is your answer?"
        if a.reason == "repeated_letter":
            return "I want to be sure I heard you. Can you spell it once more, slowly?"
        return "I didn't quite catch that. Can you say it once more?"

    def move_on_unclear(self) -> str:
        return "Let's try a different one."

    def practice_only(self) -> str:
        return "Lovely. Let's try the next one."

    def summary(self, correct: int, practice: int, unclear: int) -> str:
        return "That's the end of this session. Thank you for playing with me."


def summarize(activity: str, finals: list[str]) -> str:
    """Parent-facing summary built only from recorded outcomes."""
    c, p, u = (finals.count(o.value) for o in Outcome)
    parts = [f"{len(finals)} {'item' if len(finals) == 1 else 'items'} practised"]
    if c:
        parts.append(f"{c} correct")
    if p:
        parts.append(f"{p} to revisit")
    if u:
        parts.append(f"{u} Zivoo couldn't assess")
    return ", ".join(parts) + "."


# --------------------------------------------------------------- controller


class ActivityController:
    def __init__(
        self,
        pron: PronunciationAssessor | None = None,
        writer: TemplateWriter | None = None,
    ):
        self.pron = pron or UnavailablePronunciationAssessor()
        self.writer = writer or TemplateWriter()

    def start(self, activity: str, prefs: dict, seed: int, language: str = "en-GB") -> StepResult:
        items, intro = build_items(activity, prefs, seed)
        if not items:
            state = {"activity": activity, "phase": Phase.summary, "items": [], "finals": []}
            return StepResult(state, Reply(Phase.summary, "There's nothing to practise yet.",
                                           done=True))  # fmt: skip
        state = {
            "engine": ENGINE_VERSION,
            "activity": activity,
            "language": language,
            "phase": Phase.listen,
            "items": items,
            "index": 0,
            "attempt": 1,
            "unclear": 0,
            "seq": 0,
            "finals": [],
            "turns": {},
        }
        say = f"{intro} {items[0]['prompt']}" if intro else items[0]["prompt"]
        return StepResult(state, Reply(Phase.listen, say))

    def handle(self, state: dict, turn_id: str, heard: Heard) -> StepResult:
        if turn_id in state.get("turns", {}):
            prev = state["turns"][turn_id]
            outcome = Outcome(prev["outcome"]) if prev.get("outcome") else None
            return StepResult(state, Reply(prev["state"], prev["say"], outcome, prev["done"]))
        if state["phase"] != Phase.listen:
            return StepResult(state, Reply(state["phase"], "", None, True))

        activity = state["activity"]
        item = state["items"][state["index"]]
        a = _assess(activity, item, heard, self.pron, state.get("language", "en-GB"))
        state["seq"] += 1
        record = Record(state["seq"], state["index"], item["prompt"][:240], item.get("expected"),
                        heard.transcript[:240] or None, state["attempt"], a)  # fmt: skip

        w = self.writer
        if a.outcome is Outcome.correct:
            reply = self._advance(state, w.correct(item), Outcome.correct)
        elif a.outcome is Outcome.needs_practice:
            if state["attempt"] < MAX_ATTEMPTS:
                state["attempt"] += 1
                reply = Reply(Phase.listen, w.retry(activity, item, a), a.outcome)
            else:
                reply = self._advance(state, w.reveal(activity, item), Outcome.needs_practice)
        else:  # uncertain: never tell the child they are wrong
            if a.reason == "no_audio_assessor":
                reply = self._advance(state, w.practice_only(), Outcome.uncertain)
            elif state["unclear"] < MAX_UNCLEAR:
                state["unclear"] += 1
                reply = Reply(Phase.listen, w.unclear(a), Outcome.uncertain)
            else:
                reply = self._advance(state, w.move_on_unclear(), Outcome.uncertain)

        state["turns"][turn_id] = {
            "state": reply.state, "say": reply.say, "done": reply.done,
            "outcome": reply.outcome.value if reply.outcome else None,
        }  # fmt: skip
        return StepResult(state, reply, [record])

    def _advance(self, state: dict, feedback: str, final: Outcome) -> Reply:
        state["finals"].append(final.value)
        state["index"] += 1
        state["attempt"], state["unclear"] = 1, 0
        if state["index"] >= len(state["items"]):
            state["phase"] = Phase.summary
            f = state["finals"]
            closing = self.writer.summary(
                f.count("correct"), f.count("needs_practice"), f.count("uncertain")
            )
            return Reply(Phase.summary, f"{feedback} {closing}", final, done=True)
        nxt = state["items"][state["index"]]["prompt"]
        return Reply(Phase.listen, f"{feedback} {nxt}", final)
