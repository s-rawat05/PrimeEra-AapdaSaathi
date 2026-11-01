"""AapdaSaathi API + worker.

Run locally:   uvicorn app.main:app --reload --port 8000     (from worker/)
OpenAPI docs:  http://localhost:8000/docs
"""

from __future__ import annotations

import asyncio
import json
import logging
import time
from collections import defaultdict, deque
from contextlib import asynccontextmanager

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from sqlalchemy import select

from app.api import admin, auth, misc, ops, people
from app.config import Settings, get_settings
from app.core import AppContext, Clock, DomainError
from app.db import db
from app.escalation import engine
from app.integrations import sachet_ingest
from app.integrations.fcm_gateway import FcmGateway
from app.integrations.sms_gateway import SimulatorSmsGateway, build_sms_gateway
from app.models import Ward
from app.notifications.dispatcher import flush_outbox
from app.services import residents as residents_svc
from app.services.realtime import EventBus


class JsonFormatter(logging.Formatter):
    def format(self, record: logging.LogRecord) -> str:
        out = {
            "ts": self.formatTime(record),
            "level": record.levelname,
            "logger": record.name,
            "msg": record.getMessage(),
        }
        if record.exc_info:
            out["exc"] = self.formatException(record.exc_info)
        return json.dumps(out, ensure_ascii=False)


def setup_logging() -> None:
    handler = logging.StreamHandler()
    handler.setFormatter(JsonFormatter())
    root = logging.getLogger()
    root.handlers[:] = [handler]
    root.setLevel(logging.INFO)
    for noisy in ("httpx", "httpcore", "sqlalchemy.engine"):
        logging.getLogger(noisy).setLevel(logging.WARNING)


log = logging.getLogger("aapdasaathi")


def build_context(settings: Settings, clock: Clock | None = None) -> AppContext:
    sim = SimulatorSmsGateway({p.strip() for p in settings.sim_unreachable_phones.split(",") if p.strip()})
    return AppContext(
        settings=settings,
        clock=clock or Clock(),
        sms=build_sms_gateway(settings),
        fcm=FcmGateway(settings),
        bus=EventBus(),
        extras={"sim_sms": sim},
    )


async def _loop(name: str, interval: float, fn) -> None:
    while True:
        try:
            await fn()
        except asyncio.CancelledError:
            raise
        except Exception:  # noqa: BLE001 - background jobs must survive transient failures
            log.exception("background job %s failed", name)
        await asyncio.sleep(interval)


async def _expire_consents(ctx: AppContext) -> None:
    async with db.session() as s:
        n = await residents_svc.expire_overdue(s, ctx)
        await s.commit()
        if n:
            log.info("expired %s registrations past re-verification date", n)


async def init_storage(settings: Settings, ctx: AppContext) -> None:
    db.init(settings.database_url)
    if db.is_sqlite:
        await db.create_all()
    if settings.demo_mode_enabled:
        async with db.session() as s:
            has_demo = await s.scalar(select(Ward.id).where(Ward.is_demo.is_(True)).limit(1))
        if not has_demo:
            from app.demo.seed import seed_demo

            log.info("seeding fictional demo data: %s", await seed_demo(ctx.now()))


def create_app(settings: Settings | None = None, ctx: AppContext | None = None, *, manage_db: bool = True) -> FastAPI:
    settings = settings or get_settings()
    settings.assert_safe_for_production()
    ctx = ctx or build_context(settings)

    @asynccontextmanager
    async def lifespan(app: FastAPI):
        setup_logging()
        tasks: list[asyncio.Task] = []
        if manage_db:
            await init_storage(settings, ctx)
        if settings.run_background_jobs:
            tasks.append(
                asyncio.create_task(_loop("escalation", settings.escalation_tick_seconds, lambda: engine.tick(ctx)))
            )
            tasks.append(asyncio.create_task(_loop("outbox", 5, lambda: flush_outbox(ctx))))
            tasks.append(asyncio.create_task(_loop("consent-expiry", 3600, lambda: _expire_consents(ctx))))
            if settings.feed_poll_enabled:
                tasks.append(asyncio.create_task(_loop("sachet", 10, lambda: sachet_ingest.poll_all(ctx))))
        log.info(
            "AapdaSaathi started env=%s notify_real_residents=%s demo=%s db=%s",
            settings.app_env,
            settings.notify_real_residents,
            settings.demo_mode_enabled,
            "sqlite" if db.is_sqlite else "postgres",
        )
        yield
        for t in tasks:
            t.cancel()
        await asyncio.gather(*tasks, return_exceptions=True)
        if manage_db:
            await db.dispose()

    app = FastAPI(
        title="AapdaSaathi API",
        version="1.0.0",
        description=(
            "Disaster-alert accountability platform by Team PRIME ERA (SAARTHI'26). "
            "App where possible. SMS everywhere. A human for those who don't reply.\n\n"
            'All timestamps are UTC. Errors: `{"error": {"code", "message"}}`.'
        ),
        lifespan=lifespan,
    )
    app.state.ctx = ctx
    app.add_middleware(
        CORSMiddleware,
        allow_origins=settings.cors_origin_list,
        allow_credentials=False,
        allow_methods=["GET", "POST", "PUT", "PATCH", "DELETE"],
        allow_headers=["Authorization", "Content-Type", "Idempotency-Key"],
    )

    hits: dict[str, deque] = defaultdict(deque)

    @app.middleware("http")
    async def guard(request: Request, call_next):
        # Simple per-client sliding-window rate limit (per process). Webhook and health are exempt.
        path = request.url.path
        if path.startswith("/api/v1") and not path.endswith(("/health", "/ready", "/sms/webhook")):
            key = request.client.host if request.client else "?"
            now = time.monotonic()
            q = hits[key]
            while q and now - q[0] > 60:
                q.popleft()
            if len(q) >= settings.rate_limit_per_minute:
                return JSONResponse({"error": {"code": "rate_limited", "message": "Too many requests"}}, 429)
            q.append(now)
        response = await call_next(request)
        response.headers["X-Content-Type-Options"] = "nosniff"
        response.headers["Referrer-Policy"] = "no-referrer"
        response.headers["Cache-Control"] = "no-store"
        return response

    @app.exception_handler(DomainError)
    async def domain_error(_: Request, exc: DomainError):
        return JSONResponse({"error": {"code": exc.code, "message": exc.message}}, status_code=exc.status)

    @app.exception_handler(RequestValidationError)
    async def validation_error(_: Request, exc: RequestValidationError):
        msgs = [f"{'.'.join(str(p) for p in e['loc'][1:])}: {e['msg']}" for e in exc.errors()]
        return JSONResponse({"error": {"code": "validation_error", "message": "; ".join(msgs)[:500]}}, 422)

    @app.exception_handler(Exception)
    async def unhandled(_: Request, exc: Exception):
        log.exception("unhandled error")
        return JSONResponse({"error": {"code": "internal_error", "message": "Something went wrong"}}, 500)

    for r in (auth.router, auth.me_router, people.router, ops.router, admin.router, misc.router):
        app.include_router(r, prefix="/api/v1")
    _mount_web_apps(app, settings)
    return app


def _mount_web_apps(app: FastAPI, settings: Settings) -> None:
    """Optionally serve the built Flutter web apps from this server (one public address, same origin).
    Mounted after the API routers, so /api/v1/* always wins."""
    from pathlib import Path

    from fastapi.staticfiles import StaticFiles

    for prefix, folder in (("/app", settings.web_app_dir), ("/", settings.web_dashboard_dir)):
        if folder and (Path(folder) / "index.html").is_file():
            app.mount(prefix, StaticFiles(directory=folder, html=True), name=f"web{prefix.strip('/') or 'root'}")
            log.info("serving web app %s from %s", prefix, folder)


app = create_app()
