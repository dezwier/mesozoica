import logging
import os
import traceback
from contextlib import asynccontextmanager

from fastapi import FastAPI, HTTPException, Request, status
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from fastapi.staticfiles import StaticFiles
from sqlalchemy.exc import OperationalError, TimeoutError as SATimeoutError

from app.api.v1 import api_router
from app.core.config import settings
from app.core.database import check_connection, init_db
from app.core.exceptions import MesozoicaException, NotFoundError, ValidationError

logger = logging.getLogger(__name__)

API_VERSION = os.getenv("API_VERSION", "0.1.0")
IS_DEVELOPMENT = settings.environment.lower() in ("development", "dev", "local")


@asynccontextmanager
async def lifespan(app: FastAPI):
    from app.services.site_service.field_site_logging import _configure_logger

    _configure_logger()
    init_db()
    yield


def _register_exception_handlers(app: FastAPI) -> None:
    @app.exception_handler(RequestValidationError)
    async def validation_exception_handler(
        request: Request, exc: RequestValidationError
    ):
        logger.error("Validation error on %s %s: %s", request.method, request.url.path, exc.errors())
        return JSONResponse(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            content={"detail": exc.errors()},
        )

    @app.exception_handler(MesozoicaException)
    async def mesozoica_exception_handler(request: Request, exc: MesozoicaException):
        if isinstance(exc, ValidationError):
            status_code = status.HTTP_400_BAD_REQUEST
        elif isinstance(exc, NotFoundError):
            status_code = status.HTTP_404_NOT_FOUND
        else:
            status_code = status.HTTP_500_INTERNAL_SERVER_ERROR

        logger.warning(
            "Application exception on %s %s: %s: %s",
            request.method,
            request.url.path,
            type(exc).__name__,
            exc,
        )
        return JSONResponse(
            status_code=status_code,
            content={"detail": str(exc), "type": type(exc).__name__},
        )

    @app.exception_handler(SATimeoutError)
    async def sqlalchemy_timeout_handler(request: Request, exc: SATimeoutError):
        logger.error(
            "DB pool exhausted on %s %s: %s",
            request.method,
            request.url.path,
            exc,
        )
        return JSONResponse(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            content={
                "detail": (
                    "Database connection pool exhausted — too many concurrent "
                    "requests. Wait a moment and try again."
                ),
                "type": "DatabasePoolTimeout",
            },
        )

    @app.exception_handler(OperationalError)
    async def sqlalchemy_operational_handler(
        request: Request, exc: OperationalError
    ):
        logger.error(
            "DB operational error on %s %s: %s",
            request.method,
            request.url.path,
            exc,
        )
        detail = str(exc.orig) if getattr(exc, "orig", None) else str(exc)
        # Statement timeout / SSL drop — tell the client to retry rather than 500.
        return JSONResponse(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            content={
                "detail": (
                    "Database temporarily unavailable. "
                    f"{detail[:180]}"
                ),
                "type": "DatabaseOperationalError",
            },
        )

    @app.exception_handler(Exception)
    async def global_exception_handler(request: Request, exc: Exception):
        logger.error(
            "Unhandled exception on %s %s",
            request.method,
            request.url.path,
            exc_info=exc,
        )
        if IS_DEVELOPMENT:
            return JSONResponse(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                content={
                    "detail": str(exc),
                    "type": type(exc).__name__,
                    "traceback": traceback.format_exc(),
                },
            )
        return JSONResponse(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            content={
                "detail": "An internal server error occurred.",
                "type": "InternalServerError",
            },
        )


def create_app() -> FastAPI:
    app = FastAPI(
        title="Mesozoica API",
        version=API_VERSION,
        lifespan=lifespan,
    )

    _register_exception_handlers(app)

    app.add_middleware(
        CORSMiddleware,
        allow_origins=settings.cors_origins,
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )

    @app.get("/")
    async def root():
        return {
            "message": "Mesozoica API",
            "status": "running",
            "docs": {"swagger": "/docs", "redoc": "/redoc"},
        }

    @app.get("/health")
    async def health():
        return {"status": "healthy"}

    @app.get("/ready")
    async def ready():
        ok, message = await check_connection()
        if not ok:
            raise HTTPException(status_code=503, detail=message)
        return {"status": "ready"}

    app.include_router(api_router, prefix=settings.api_v1_prefix)

    images_dir = settings.resolved_dinosaur_images_dir
    images_dir.mkdir(parents=True, exist_ok=True)
    app.mount(
        "/media/dinosaurs",
        StaticFiles(directory=str(images_dir)),
        name="dinosaur-images",
    )

    fossil_images_dir = settings.resolved_fossil_images_dir
    fossil_images_dir.mkdir(parents=True, exist_ok=True)
    app.mount(
        "/media/fossils",
        StaticFiles(directory=str(fossil_images_dir)),
        name="fossil-images",
    )

    site_type_images_dir = settings.resolved_site_type_images_dir
    site_type_images_dir.mkdir(parents=True, exist_ok=True)
    app.mount(
        "/media/site-types",
        StaticFiles(directory=str(site_type_images_dir)),
        name="site-type-images",
    )

    tool_images_dir = settings.resolved_tool_images_dir
    tool_images_dir.mkdir(parents=True, exist_ok=True)
    app.mount(
        "/media/tools",
        StaticFiles(directory=str(tool_images_dir)),
        name="tool-images",
    )

    user_images_dir = settings.resolved_user_images_dir
    user_images_dir.mkdir(parents=True, exist_ok=True)
    app.mount(
        "/media/users",
        StaticFiles(directory=str(user_images_dir)),
        name="user-images",
    )

    return app
