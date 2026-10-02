"""Parent authentication.

Tokens are issued by a managed identity provider (Supabase Auth by default).
The backend verifies signature, issuer, audience and expiry, then maps the
`sub` claim to a Parent row. Ownership is always derived from this row,
never from client-supplied fields.
"""

from dataclasses import dataclass
from functools import lru_cache

import jwt
from fastapi import Depends, Request
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.config import Settings, get_settings
from app.db import get_db
from app.errors import ApiError
from app.models import Parent


@dataclass(frozen=True)
class Identity:
    subject: str
    email: str
    email_verified: bool


@lru_cache
def _jwks_client(url: str) -> jwt.PyJWKClient:
    return jwt.PyJWKClient(url, cache_keys=True, lifespan=3600)


def verify_token(token: str, settings: Settings) -> Identity:
    try:
        if settings.auth_mode == "dev_hs256":
            if not settings.dev_tools_enabled:
                raise ApiError(401, "unauthenticated", "Sign in again")
            claims = jwt.decode(
                token,
                settings.dev_jwt_secret,
                algorithms=["HS256"],
                audience=settings.auth_audience,
                options={"require": ["exp", "sub"]},
            )
        else:
            assert settings.auth_jwks_url
            key = _jwks_client(settings.auth_jwks_url).get_signing_key_from_jwt(token)
            claims = jwt.decode(
                token,
                key.key,
                algorithms=["RS256", "ES256"],
                audience=settings.auth_audience,
                issuer=settings.auth_issuer,
                options={"require": ["exp", "sub", "iss"]},
            )
    except jwt.ExpiredSignatureError as e:
        raise ApiError(401, "session_expired", "Your session has expired") from e
    except jwt.PyJWTError as e:
        raise ApiError(401, "unauthenticated", "Sign in again") from e

    meta = claims.get("user_metadata") or {}
    verified = bool(
        claims.get("email_verified", meta.get("email_verified", False))
        or claims.get("email_confirmed_at")
    )
    return Identity(subject=str(claims["sub"]), email=str(claims.get("email", "")),
                    email_verified=verified)


def get_identity(request: Request, settings: Settings = Depends(get_settings)) -> Identity:
    header = request.headers.get("authorization", "")
    if not header.lower().startswith("bearer "):
        raise ApiError(401, "unauthenticated", "Sign in again")
    return verify_token(header[7:].strip(), settings)


def current_parent(
    identity: Identity = Depends(get_identity), db: Session = Depends(get_db)
) -> Parent:
    if not identity.email_verified:
        raise ApiError(403, "email_not_verified", "Verify your email to continue")
    parent = db.scalar(select(Parent).where(Parent.idp_subject == identity.subject))
    if parent is None:
        parent = Parent(idp_subject=identity.subject, email=identity.email)
        db.add(parent)
        db.flush()
    if parent.deletion_requested_at is not None:
        raise ApiError(403, "account_deleted", "This account has been deleted")
    return parent
