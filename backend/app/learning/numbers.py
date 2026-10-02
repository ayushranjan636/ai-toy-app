"""Normalise spoken number answers from speech-to-text transcripts.

Returns a NumberParse describing either a single confident value, or why the
input is ambiguous. We prefer "uncertain" over guessing.
"""

import re
from dataclasses import dataclass

_UNITS = {
    "zero": 0, "oh": 0, "nought": 0, "nothing": 0,
    "one": 1, "won": 1, "two": 2, "to": 2, "too": 2, "three": 3, "four": 4, "for": 4,
    "five": 5, "six": 6, "seven": 7, "eight": 8, "ate": 8, "nine": 9, "ten": 10,
    "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14, "fifteen": 15,
    "sixteen": 16, "seventeen": 17, "eighteen": 18, "nineteen": 19,
}  # fmt: skip
_TENS = {
    "twenty": 20, "thirty": 30, "forty": 40, "fourty": 40, "fifty": 50,
    "sixty": 60, "seventy": 70, "eighty": 80, "ninety": 90,
}  # fmt: skip
# Homophones that are also common words: only count them when the utterance is short.
_WEAK = {"to", "too", "for", "won", "ate", "oh", "nothing"}
_FILLERS = {"um", "umm", "uh", "er", "erm", "hmm", "mm", "like", "maybe", "i", "think",
            "it's", "its", "it", "is", "the", "answer", "equals", "makes", "that's", "thats",
            "a", "and", "yes", "ok", "okay", "so", "well", "hmmm"}  # fmt: skip
_EQUALS = {"is", "equals", "makes", "=", "are"}


@dataclass(frozen=True)
class NumberParse:
    value: int | None
    reason: str  # "ok" | "no_number" | "multiple_numbers" | "empty"
    candidates: tuple[int, ...] = ()


def _tokens(text: str) -> list[str]:
    text = text.lower().replace("-", " ")
    text = re.sub(r"(\d)\s*,\s*(\d)", r"\1\2", text)
    return re.findall(r"\d+|[a-z']+|=", text)


def _read_numbers(tokens: list[str]) -> list[tuple[int, int]]:
    """Return (value, index_of_last_token) for each number phrase."""
    out: list[tuple[int, int]] = []
    i, short = 0, len(tokens) <= 3
    while i < len(tokens):
        t = tokens[i]
        if t.isdigit():
            out.append((int(t), i))
            i += 1
            continue
        if t in _TENS:
            value = _TENS[t]
            if i + 1 < len(tokens) and tokens[i + 1] in _UNITS and 0 < _UNITS[tokens[i + 1]] < 10:
                if tokens[i + 1] not in _WEAK or short:
                    value += _UNITS[tokens[i + 1]]
                    i += 1
            out.append((value, i))
            i += 1
            continue
        if t in _UNITS and (t not in _WEAK or short):
            value = _UNITS[t]
            if i + 1 < len(tokens) and tokens[i + 1] == "hundred":
                value *= 100
                i += 1
            out.append((value, i))
        i += 1
    return out


def parse_spoken_number(text: str) -> NumberParse:
    tokens = _tokens(text)
    if not tokens:
        return NumberParse(None, "empty")
    numbers = _read_numbers(tokens)
    if not numbers:
        return NumberParse(None, "no_number")
    values = tuple(v for v, _ in numbers)
    if len(set(values)) == 1:
        return NumberParse(values[0], "ok", values)
    # "three plus four is seven" -> the number after the final equals-word.
    eq_positions = [i for i, t in enumerate(tokens) if t in _EQUALS]
    if eq_positions:
        after = [v for v, idx in numbers if idx > eq_positions[-1]]
        if len(set(after)) == 1:
            return NumberParse(after[0], "ok", values)
    # Self-correction: "five, no, six" -> last number after "no"/"wait"/"actually".
    for marker in ("no", "wait", "actually", "sorry"):
        if marker in tokens:
            pos = len(tokens) - 1 - tokens[::-1].index(marker)
            after = [v for v, idx in numbers if idx > pos]
            if len(set(after)) == 1:
                return NumberParse(after[0], "ok", values)
    return NumberParse(None, "multiple_numbers", values)
