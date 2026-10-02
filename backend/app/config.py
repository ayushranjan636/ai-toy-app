from functools import lru_cache
from typing import Literal

from pydantic import model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Runtime configuration. All secrets come from the environment."""

    model_config = SettingsConfigDict(env_prefix="ZIVOO_", env_file=".env", extra="ignore")

    env: Literal["development", "test", "staging", "production"] = "development"
    database_url: str = "postgresql+psycopg://zivoo:zivoo@localhost:5432/zivoo"

    # Parent authentication (managed identity provider, e.g. Supabase Auth).
    auth_mode: Literal["jwks", "dev_hs256"] = "dev_hs256"
    auth_jwks_url: str | None = None
    auth_issuer: str | None = None
    auth_audience: str = "authenticated"
    # Only used when auth_mode == dev_hs256, which is refused outside development/test.
    dev_jwt_secret: str = "dev-only-insecure-secret-change-me-0123456789"  # noqa: S105

    claim_ttl_seconds: int = 600
    command_ttl_seconds: int = 24 * 3600
    device_offline_after_seconds: int = 120
    cors_origins: list[str] = []

    @property
    def dev_tools_enabled(self) -> bool:
        return self.env in ("development", "test")

    @model_validator(mode="after")
    def _guard_production(self) -> "Settings":
        if self.env in ("staging", "production"):
            if self.auth_mode != "jwks":
                raise ValueError("staging/production require ZIVOO_AUTH_MODE=jwks")
            if not self.auth_jwks_url or not self.auth_issuer:
                raise ValueError("ZIVOO_AUTH_JWKS_URL and ZIVOO_AUTH_ISSUER are required")
        return self


@lru_cache
def get_settings() -> Settings:
    return Settings()
