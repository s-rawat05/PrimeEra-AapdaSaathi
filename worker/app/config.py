"""Centralised configuration. Every tunable comes from the environment (or worker/.env)."""

from __future__ import annotations

from functools import lru_cache

from pydantic import Field, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", extra="ignore")

    app_env: str = "development"
    notify_real_residents: bool = False

    database_url: str = "sqlite+aiosqlite:///./data/aapdasaathi.db"

    auth_mode: str = "local"  # local | supabase
    jwt_secret: str = "dev-only-insecure-secret-change-me-0123456789"
    access_token_minutes: int = 720
    supabase_url: str = ""
    supabase_jwt_secret: str = ""

    demo_mode_enabled: bool = True
    demo_escalation_interval_seconds: int = 30

    sachet_rss_urls: str = "https://sachet.ndma.gov.in/cap_public_website/rss/rss_uttarakhand.xml"
    sachet_cap_url_template: str = "https://sachet.ndma.gov.in/cap_public_website/FetchXMLFile?identifier={identifier}"
    feed_poll_seconds: int = Field(default=45, ge=15, le=600)
    feed_poll_enabled: bool = False
    feed_connect_timeout: float = 10.0
    feed_read_timeout: float = 20.0
    feed_max_backoff_seconds: int = 900

    run_background_jobs: bool = True
    escalation_tick_seconds: float = 5.0

    walking_speed_m_per_min: float = 75.0
    hill_terrain_factor: float = 1.4
    assist_buffer_minutes: float = 10.0
    max_walk_minutes_active_hazard: float = 15.0

    firebase_credentials_file: str = ""

    sms_provider: str = "simulator"  # simulator | httpsms
    httpsms_api_url: str = "https://api.httpsms.com/v1/messages/send"
    httpsms_api_key: str = ""
    httpsms_from_number: str = ""
    sms_webhook_secret: str = "dev-only-webhook-secret"
    # Simulator only: numbers that behave like a switched-off phone (delivery fails) so the
    # UNREACHABLE path can be demonstrated. Uses fictional demo numbers.
    sim_unreachable_phones: str = "+919000000013"
    notification_max_retries: int = 3
    # Demo-incident SMS goes to the simulator UNLESS the number is listed here (team phones for a
    # live on-stage demo). Fictional seed numbers must never reach a real SMS gateway.
    demo_sms_allowlist: str = ""

    @property
    def demo_sms_allowed(self) -> set[str]:
        return {p.strip() for p in self.demo_sms_allowlist.split(",") if p.strip()}

    cors_origins: str = "http://localhost:8080,http://localhost:8081,http://127.0.0.1:8080,http://127.0.0.1:8081"

    otp_ttl_seconds: int = 300
    consent_validity_days: int = 90
    rate_limit_per_minute: int = 240

    @field_validator("auth_mode")
    @classmethod
    def _auth_mode(cls, v: str) -> str:
        if v not in {"local", "supabase"}:
            raise ValueError("AUTH_MODE must be 'local' or 'supabase'")
        return v

    @property
    def is_sqlite(self) -> bool:
        return self.database_url.startswith("sqlite")

    @property
    def rss_urls(self) -> list[str]:
        return [u.strip() for u in self.sachet_rss_urls.split(",") if u.strip()]

    @property
    def cors_origin_list(self) -> list[str]:
        return [o.strip() for o in self.cors_origins.split(",") if o.strip()]

    def assert_safe_for_production(self) -> None:
        """Refuse to boot a production deployment with development secrets or demo logins."""
        if self.app_env != "production":
            return
        problems = []
        if "dev-only" in self.jwt_secret or len(self.jwt_secret) < 32:
            problems.append("JWT_SECRET is a development value or too short")
        if "dev-only" in self.sms_webhook_secret:
            problems.append("SMS_WEBHOOK_SECRET is a development value")
        if self.demo_mode_enabled:
            problems.append("DEMO_MODE_ENABLED must be false in production")
        if self.sms_provider == "simulator":
            problems.append("SMS_PROVIDER=simulator is not allowed in production")
        if problems:
            raise RuntimeError("Unsafe production configuration: " + "; ".join(problems))


@lru_cache
def get_settings() -> Settings:
    return Settings()
