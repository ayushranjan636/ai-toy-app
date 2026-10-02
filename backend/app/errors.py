"""Consistent error envelope: {"error": {"code": str, "message": str, "details": ...}}."""

from typing import Any

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from starlette.exceptions import HTTPException as StarletteHTTPException


class ApiError(Exception):
    def __init__(self, status: int, code: str, message: str, details: Any = None):
        self.status, self.code, self.message, self.details = status, code, message, details


def not_found(what: str = "resource") -> ApiError:
    # Same response for "missing" and "belongs to someone else" to avoid leaking existence.
    return ApiError(404, "not_found", f"{what} not found")


def _body(code: str, message: str, details: Any = None) -> dict:
    return {"error": {"code": code, "message": message, "details": details}}


def install_error_handlers(app: FastAPI) -> None:
    @app.exception_handler(ApiError)
    async def _api(_r: Request, e: ApiError):
        return JSONResponse(_body(e.code, e.message, e.details), status_code=e.status)

    @app.exception_handler(RequestValidationError)
    async def _validation(_r: Request, e: RequestValidationError):
        details = [
            {"loc": list(err.get("loc", [])), "msg": err.get("msg"), "type": err.get("type")}
            for err in e.errors()
        ]
        return JSONResponse(
            _body("validation_error", "Request is invalid", details), status_code=422
        )

    @app.exception_handler(StarletteHTTPException)
    async def _http(_r: Request, e: StarletteHTTPException):
        return JSONResponse(_body("http_error", str(e.detail)), status_code=e.status_code)
