"""Secret generation and hashing.

- Random high-entropy tokens (claim tokens, device secrets) are hashed with SHA-256.
- Setup codes are shorter and printed on the box/QR, so they use scrypt with a salt.
"""

import base64
import hashlib
import hmac
import secrets

_B32 = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"  # no 0/O/1/I for manual entry


def random_token(prefix: str, nbytes: int = 32) -> str:
    return f"{prefix}_{secrets.token_urlsafe(nbytes)}"


def sha256_hex(value: str) -> str:
    return hashlib.sha256(value.encode()).hexdigest()


def constant_eq(a: str, b: str) -> bool:
    return hmac.compare_digest(a.encode(), b.encode())


def new_setup_code(length: int = 12) -> str:
    return "".join(secrets.choice(_B32) for _ in range(length))


def normalize_setup_code(code: str) -> str:
    return "".join(ch for ch in code.upper() if ch.isalnum())


def hash_setup_code(code: str) -> str:
    salt = secrets.token_bytes(16)
    digest = hashlib.scrypt(normalize_setup_code(code).encode(), salt=salt, n=2**14, r=8, p=1)
    return "scrypt$" + base64.b64encode(salt).decode() + "$" + base64.b64encode(digest).decode()


def verify_setup_code(code: str, stored: str) -> bool:
    try:
        _algo, salt_b64, digest_b64 = stored.split("$")
    except ValueError:
        return False
    digest = hashlib.scrypt(
        normalize_setup_code(code).encode(), salt=base64.b64decode(salt_b64), n=2**14, r=8, p=1
    )
    return hmac.compare_digest(digest, base64.b64decode(digest_b64))
