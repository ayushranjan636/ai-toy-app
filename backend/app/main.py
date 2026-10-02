import time
import uuid

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy import text

from app.config import get_settings
from app.db import get_engine
from app.errors import install_error_handlers
from app.logging import configure_logging, log
from app.routers import dev, device, parent


def create_app() -> FastAPI:
    settings = get_settings()
    configure_logging()
    app = FastAPI(
        title="Zivoo API",
        version="1.0.0",
        description="Parent and device APIs for the Zivoo learning toy. All routes are "
        "versioned under /v1. Errors use {error: {code, message, details}}.",
    )
    install_error_handlers(app)
    if settings.cors_origins:
        app.add_middleware(
            CORSMiddleware,
            allow_origins=settings.cors_origins,
            allow_methods=["*"],
            allow_headers=["authorization", "content-type"],
        )

    @app.middleware("http")
    async def access_log(request: Request, call_next):
        rid = request.headers.get("x-request-id") or uuid.uuid4().hex
        start = time.perf_counter()
        response = await call_next(request)
        # Path only: no query strings, headers or bodies (may contain secrets).
        log.info(
            "http",
            method=request.method,
            path=request.url.path,
            status=response.status_code,
            ms=round((time.perf_counter() - start) * 1000, 1),
            request_id=rid,
        )
        response.headers["x-request-id"] = rid
        return response

    @app.get("/healthz", tags=["ops"])
    def healthz():
        return {"status": "ok"}

    @app.get("/readyz", tags=["ops"])
    def readyz():
        with get_engine().connect() as conn:
            conn.execute(text("SELECT 1"))
        return {"status": "ready"}

    app.include_router(parent.router)
    app.include_router(device.router)
    if settings.dev_tools_enabled:
        app.include_router(dev.router)
    return app


app = create_app()
