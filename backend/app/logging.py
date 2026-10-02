"""Structured, redacted logging.

Never log passwords, tokens, setup secrets, Wi-Fi credentials, raw audio or
conversation text. The redaction processor is a safety net, not a licence to
pass such values to the logger.
"""

import logging
import re
from typing import Any

import structlog

SENSITIVE_KEYS = re.compile(
    r"(pass(word)?|secret|token|authorization|setup_code|claim|psk|audio|transcript|text|"
    r"credential|cookie)",
    re.IGNORECASE,
)


def _redact(value: Any, depth: int = 0) -> Any:
    if depth > 4:
        return "[depth]"
    if isinstance(value, dict):
        return {
            k: ("[redacted]" if SENSITIVE_KEYS.search(str(k)) else _redact(v, depth + 1))
            for k, v in value.items()
        }
    if isinstance(value, list | tuple):
        return [_redact(v, depth + 1) for v in value]
    return value


def redact_processor(_logger: Any, _method: str, event_dict: dict[str, Any]) -> dict[str, Any]:
    return {
        k: (
            v
            if k in ("event", "level", "timestamp")
            else ("[redacted]" if SENSITIVE_KEYS.search(k) else _redact(v))
        )
        for k, v in event_dict.items()
    }


def configure_logging(level: str = "INFO") -> None:
    logging.basicConfig(format="%(message)s", level=level)
    structlog.configure(
        processors=[
            structlog.contextvars.merge_contextvars,
            structlog.processors.add_log_level,
            structlog.processors.TimeStamper(fmt="iso"),
            redact_processor,
            structlog.processors.JSONRenderer(),
        ],
        wrapper_class=structlog.make_filtering_bound_logger(logging.getLevelName(level)),
    )


log = structlog.get_logger("zivoo")
