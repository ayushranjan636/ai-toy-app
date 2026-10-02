"""Idempotent seed of curated activity definitions. Run: python -m app.seed"""

from sqlalchemy.orm import Session

from app.learning.content import DEFAULT_ACTIVITIES
from app.models import ActivityDefinition


def seed_activities(db: Session) -> None:
    for spec in DEFAULT_ACTIVITIES:
        row = db.get(ActivityDefinition, spec["key"])
        if row is None:
            db.add(ActivityDefinition(**spec))
        else:
            for k, v in spec.items():
                setattr(row, k, v)
    db.flush()


if __name__ == "__main__":
    from app.db import get_db

    gen = get_db()
    seed_activities(next(gen))
    try:
        next(gen)
    except StopIteration:
        pass
    print("seeded activities")
