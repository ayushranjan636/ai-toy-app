"""Curated, age-appropriate content. The toy only runs items from this file
(or validated parent word lists). Nothing here is model-generated at runtime."""

from app.learning.assessors import Rubric

SPELLING_WORDS = {
    "gentle": ["cat", "dog", "sun", "hat", "pig", "bed", "cup", "map"],
    "steady": ["fish", "frog", "ship", "milk", "jump", "tree", "rain", "duck"],
    "stretch": ["apple", "green", "train", "plant", "smile", "cloud", "light", "house"],
}

VOCABULARY = {
    "animals": [
        ("Which animal says moo and gives us milk?", Rubric((("cow",),))),
        ("What do we call a baby dog?", Rubric((("puppy", "pup"),))),
        ("Which animal has a very long neck?", Rubric((("giraffe",),))),
    ],
    "food": [
        ("What yellow fruit do monkeys like to eat?", Rubric((("banana",),))),
        ("What do bees make that is sweet and sticky?", Rubric((("honey",),))),
    ],
    "home": [
        ("Where do you sleep at night?", Rubric((("bed", "bedroom", "cot"),))),
        ("What do you open to go into a room?", Rubric((("door",),))),
    ],
    "nature": [
        ("What falls from clouds and makes puddles?", Rubric((("rain", "water"),))),
        ("What grows on trees and turns orange in autumn?", Rubric((("leaf", "leave"),))),
    ],
    "feelings": [
        ("How might you feel at your birthday party?",
         Rubric((), open_ended=True)),
    ],
    "transport": [
        ("What has wings and flies people far away?", Rubric((("plane", "aeroplane",
                                                                 "airplane", "jet"),))),
        ("What runs on tracks and stops at stations?", Rubric((("train",),))),
    ],
}  # fmt: skip

STORIES = {
    "the-lost-acorn": {
        "title": "The Lost Acorn",
        "text": (
            "Pip the squirrel hid an acorn under the big oak tree. When winter came, "
            "Pip could not remember where it was. Pip asked Rabbit and Owl for help. "
            "Together they dug by the oak tree and found the acorn. Pip shared it with "
            "both friends."
        ),
        "questions": [
            ("Who helped Pip look for the acorn?",
             Rubric((("rabbit", "bunny"), ("owl",)), min_matches=1)),
            ("Where was the acorn hidden?",
             Rubric((("oak", "tree"), ("under", "ground", "dug"),), min_matches=1)),
            ("How do you think Pip felt when the acorn was found?",
             Rubric((), open_ended=True)),
        ],
    },
    "moon-garden": {
        "title": "The Moon Garden",
        "text": (
            "Mira planted seeds in her garden. Every night she watered them while the "
            "moon was bright. One morning, tiny white flowers had opened. Mira's grandad "
            "said they were moonflowers, which bloom at night."
        ),
        "questions": [
            ("What did Mira plant?", Rubric((("seed",), ("flower",), ("plant",)))),
            ("When did Mira water her garden?",
             Rubric((("night", "evening", "dark", "moon"),))),
            ("What would you grow in a garden?", Rubric((), open_ended=True)),
        ],
    },
    "river-boat": {
        "title": "The River Boat",
        "text": (
            "Sam made a little boat out of a leaf and a twig. Sam set it on the river. "
            "The boat floated past a duck and a frog, then stopped by a rock. Sam waved "
            "goodbye and made another one."
        ),
        "questions": [
            ("What did Sam make the boat from?",
             Rubric((("leaf", "leave"), ("twig", "stick")))),
            ("Which animals did the boat float past?",
             Rubric((("duck",), ("frog",)))),
            ("What would you make a boat from?", Rubric((), open_ended=True)),
        ],
    },
}  # fmt: skip

PHONICS_EXAMPLES = {
    "s": "sun", "a": "apple", "t": "tap", "p": "pan", "i": "insect", "n": "net",
    "m": "moon", "d": "dog", "sh": "ship", "ch": "chair", "th": "thumb", "ng": "ring",
    "ai": "rain", "ee": "tree",
}  # fmt: skip

DEFAULT_ACTIVITIES = [
    {
        "key": "phonics", "kind": "phonics", "title": "Sounds", "sort_order": 1,
        "summary": "Hear a letter sound, then say it back with a word that starts with it.",
        "assessment_note": (
            "Pronunciation scoring needs an audio assessment service that is not connected "
            "yet. Attempts are recorded as practice, not marked right or wrong."
        ),
        "options_schema": {"sounds": {"type": "multi", "choices": list(PHONICS_EXAMPLES)}},
    },
    {
        "key": "vocabulary", "kind": "vocabulary", "title": "Words", "sort_order": 2,
        "summary": "Short riddles about everyday things to grow your child's vocabulary.",
        "assessment_note": None,
        "options_schema": {"themes": {"type": "multi", "choices": list(VOCABULARY)}},
    },
    {
        "key": "spelling", "kind": "spelling", "title": "Spelling", "sort_order": 3,
        "summary": "Zivoo says a word and your child spells it out letter by letter.",
        "assessment_note": "If Zivoo is unsure which letters it heard, it asks again.",
        "options_schema": {"words": {"type": "word_list", "max": 20}},
    },
    {
        "key": "maths", "kind": "maths", "title": "Numbers", "sort_order": 4,
        "summary": "Spoken adding and taking away, with answers checked exactly.",
        "assessment_note": None,
        "options_schema": {
            "operations": {"type": "multi", "choices": ["addition", "subtraction"]},
            "max_number": {"type": "single", "choices": [5, 10, 20, 50, 100]},
        },
    },
    {
        "key": "stories", "kind": "stories", "title": "Stories", "sort_order": 5,
        "summary": "A short story followed by a few gentle questions to talk it through.",
        "assessment_note": "Many answers are accepted. Zivoo listens for the main idea.",
        "options_schema": {
            "stories": {"type": "multi",
                        "choices": [{"key": k, "label": v["title"]} for k, v in STORIES.items()]},
        },
    },
]  # fmt: skip
