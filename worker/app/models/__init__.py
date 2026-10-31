"""ORM entities. Mirrors supabase/migrations (the Postgres source of truth).

tests/test_schema_parity.py checks that both definitions stay in sync when Postgres is available.
"""

from __future__ import annotations

from datetime import datetime

from sqlalchemy import (
    JSON,
    Boolean,
    CheckConstraint,
    Float,
    ForeignKey,
    Index,
    Integer,
    String,
    Text,
    UniqueConstraint,
    text,
)
from sqlalchemy.orm import Mapped, mapped_column

from app.db import Base, UTCDateTime, new_id, utcnow

ROLES = ("resident", "caregiver", "neighbour", "volunteer", "admin", "operator")
NEEDS = (
    "hearing",
    "vision",
    "mobility",
    "bedridden",
    "cognitive",
    "elderly_alone",
    "speech",
    "feature_phone",
)
DELIVERY_STATUSES = ("PENDING", "NO_REPLY", "SAFE", "HELP", "UNREACHABLE")
OPEN_DELIVERY_STATUSES = ("PENDING", "NO_REPLY", "HELP", "UNREACHABLE")
TASK_KINDS = ("neighbour_check", "volunteer_assist", "preevac_assist")
TASK_STATUSES = (
    "PENDING_APPROVAL",
    "ASSIGNED",
    "ACCEPTED",
    "REACHED",
    "CANT_GO",
    "CANCELLED",
    "REJECTED",
    "COMPLETED",
)
OPEN_TASK_STATUSES = ("PENDING_APPROVAL", "ASSIGNED", "ACCEPTED")
INCIDENT_SOURCES = ("live", "replay", "simulated", "exercise", "manual")


def _in(col: str, values: tuple[str, ...]) -> str:
    return f"{col} IN ({', '.join(repr(v) for v in values)})"


def _id() -> Mapped[str]:
    return mapped_column(String(36), primary_key=True, default=new_id)


def _created() -> Mapped[datetime]:
    return mapped_column(UTCDateTime(), default=utcnow, nullable=False)


class User(Base):
    __tablename__ = "users"
    __table_args__ = (CheckConstraint(_in("role", ROLES), name="ck_users_role"),)

    id: Mapped[str] = _id()
    auth_user_id: Mapped[str | None] = mapped_column(String(64), unique=True)
    full_name: Mapped[str] = mapped_column(String(120), nullable=False)
    phone: Mapped[str | None] = mapped_column(String(20), unique=True)
    email: Mapped[str | None] = mapped_column(String(200), unique=True)
    role: Mapped[str] = mapped_column(String(20), nullable=False)
    password_hash: Mapped[str | None] = mapped_column(String(255))
    language: Mapped[str] = mapped_column(String(5), default="en", nullable=False)
    is_demo: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
    created_at: Mapped[datetime] = _created()


class OtpChallenge(Base):
    __tablename__ = "otp_challenges"

    id: Mapped[str] = _id()
    phone: Mapped[str] = mapped_column(String(20), index=True, nullable=False)
    code_hash: Mapped[str] = mapped_column(String(128), nullable=False)
    attempts: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    expires_at: Mapped[datetime] = mapped_column(UTCDateTime(), nullable=False)
    consumed_at: Mapped[datetime | None] = mapped_column(UTCDateTime())
    created_at: Mapped[datetime] = _created()


class Ward(Base):
    __tablename__ = "wards"
    __table_args__ = (
        CheckConstraint("access_status IN ('open', 'restricted', 'blocked')", name="ck_wards_access"),
    )

    id: Mapped[str] = _id()
    code: Mapped[str] = mapped_column(String(40), unique=True, nullable=False)
    name: Mapped[str] = mapped_column(String(120), nullable=False)
    district: Mapped[str] = mapped_column(String(80), nullable=False)
    state: Mapped[str] = mapped_column(String(80), nullable=False)
    lgd_district_code: Mapped[str | None] = mapped_column(String(10), index=True)
    # GeoJSON Polygon/MultiPolygon geometry (lon, lat order). Postgres adds a generated PostGIS column.
    boundary_geojson: Mapped[dict] = mapped_column(JSON, nullable=False)
    centroid_lat: Mapped[float] = mapped_column(Float, nullable=False)
    centroid_lng: Mapped[float] = mapped_column(Float, nullable=False)
    access_status: Mapped[str] = mapped_column(String(12), default="open", nullable=False)
    access_note: Mapped[str | None] = mapped_column(Text)
    is_demo: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    created_at: Mapped[datetime] = _created()


class Shelter(Base):
    """Officially designated relief posts. Only operators/admins enter these — never generated."""

    __tablename__ = "shelters"

    id: Mapped[str] = _id()
    ward_id: Mapped[str] = mapped_column(ForeignKey("wards.id", ondelete="CASCADE"), index=True)
    name: Mapped[str] = mapped_column(String(160), nullable=False)
    address: Mapped[str] = mapped_column(Text, nullable=False)
    lat: Mapped[float] = mapped_column(Float, nullable=False)
    lng: Mapped[float] = mapped_column(Float, nullable=False)
    source: Mapped[str] = mapped_column(String(160), nullable=False)
    is_demo: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    created_at: Mapped[datetime] = _created()


class Resident(Base):
    __tablename__ = "residents"

    id: Mapped[str] = _id()
    user_id: Mapped[str | None] = mapped_column(ForeignKey("users.id", ondelete="SET NULL"), unique=True)
    full_name: Mapped[str] = mapped_column(String(120), nullable=False)
    phone: Mapped[str | None] = mapped_column(String(20), index=True)
    ward_id: Mapped[str] = mapped_column(ForeignKey("wards.id"), index=True, nullable=False)
    language: Mapped[str] = mapped_column(String(5), default="hi", nullable=False)
    needs: Mapped[list] = mapped_column(JSON, default=list, nullable=False)
    lives_alone: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    has_smartphone: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
    # Coarse location (≈110 m grid) for status maps. Exact coordinates live in resident_locations.
    coarse_lat: Mapped[float | None] = mapped_column(Float)
    coarse_lng: Mapped[float | None] = mapped_column(Float)
    registration_status: Mapped[str] = mapped_column(String(20), default="active", nullable=False)
    registered_via: Mapped[str] = mapped_column(String(20), default="self", nullable=False)
    reverify_due_at: Mapped[datetime | None] = mapped_column(UTCDateTime())
    is_demo: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    created_at: Mapped[datetime] = _created()
    updated_at: Mapped[datetime] = mapped_column(UTCDateTime(), default=utcnow, onupdate=utcnow)

    __table_args__ = (
        CheckConstraint(
            "registration_status IN ('active', 'expired', 'withdrawn')", name="ck_residents_reg_status"
        ),
    )


class ResidentLocation(Base):
    """Exact location — readable only by the resident, linked caregivers (if consented),
    operators during an active incident, and volunteers holding an accepted task."""

    __tablename__ = "resident_locations"

    id: Mapped[str] = _id()
    resident_id: Mapped[str] = mapped_column(
        ForeignKey("residents.id", ondelete="CASCADE"), unique=True, nullable=False
    )
    lat: Mapped[float] = mapped_column(Float, nullable=False)
    lng: Mapped[float] = mapped_column(Float, nullable=False)
    address_text: Mapped[str | None] = mapped_column(Text)
    landmark: Mapped[str | None] = mapped_column(Text)
    source: Mapped[str] = mapped_column(String(20), default="registration", nullable=False)
    updated_at: Mapped[datetime] = mapped_column(UTCDateTime(), default=utcnow, onupdate=utcnow)


class ConsentRecord(Base):
    __tablename__ = "consent_records"

    id: Mapped[str] = _id()
    resident_id: Mapped[str] = mapped_column(ForeignKey("residents.id", ondelete="CASCADE"), index=True)
    consent_type: Mapped[str] = mapped_column(String(30), nullable=False)
    granted: Mapped[bool] = mapped_column(Boolean, nullable=False)
    granted_by: Mapped[str] = mapped_column(String(20), nullable=False)  # self | guardian | assisted
    guardian_name: Mapped[str | None] = mapped_column(String(120))
    recorded_by_user_id: Mapped[str | None] = mapped_column(ForeignKey("users.id", ondelete="SET NULL"))
    granted_at: Mapped[datetime] = _created()
    expires_at: Mapped[datetime] = mapped_column(UTCDateTime(), nullable=False)
    withdrawn_at: Mapped[datetime | None] = mapped_column(UTCDateTime())

    __table_args__ = (
        CheckConstraint(
            "consent_type IN ('registry', 'location', 'caregiver_share', 'sms')", name="ck_consent_type"
        ),
        CheckConstraint("granted_by IN ('self', 'guardian', 'assisted')", name="ck_consent_by"),
    )


class CaregiverLink(Base):
    __tablename__ = "caregiver_links"
    __table_args__ = (UniqueConstraint("caregiver_user_id", "resident_id"),)

    id: Mapped[str] = _id()
    caregiver_user_id: Mapped[str] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    resident_id: Mapped[str] = mapped_column(ForeignKey("residents.id", ondelete="CASCADE"), index=True)
    relationship: Mapped[str] = mapped_column(String(40), default="family", nullable=False)
    can_view_location: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    created_at: Mapped[datetime] = _created()


class NeighbourLink(Base):
    __tablename__ = "neighbour_links"
    __table_args__ = (UniqueConstraint("resident_id", "neighbour_user_id"),)

    id: Mapped[str] = _id()
    resident_id: Mapped[str] = mapped_column(ForeignKey("residents.id", ondelete="CASCADE"), index=True)
    neighbour_user_id: Mapped[str] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    priority: Mapped[int] = mapped_column(Integer, default=1, nullable=False)
    distance_m: Mapped[float | None] = mapped_column(Float)
    created_at: Mapped[datetime] = _created()


class Volunteer(Base):
    __tablename__ = "volunteers"

    id: Mapped[str] = _id()
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), unique=True)
    ward_id: Mapped[str | None] = mapped_column(ForeignKey("wards.id", ondelete="SET NULL"), index=True)
    is_available: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
    base_lat: Mapped[float] = mapped_column(Float, nullable=False)
    base_lng: Mapped[float] = mapped_column(Float, nullable=False)
    max_radius_m: Mapped[float] = mapped_column(Float, default=3000, nullable=False)
    skills: Mapped[list] = mapped_column(JSON, default=list, nullable=False)
    verified: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
    is_demo: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(UTCDateTime(), default=utcnow, onupdate=utcnow)


class PreAssignedHelper(Base):
    __tablename__ = "pre_assigned_helpers"
    __table_args__ = (UniqueConstraint("resident_id", "volunteer_id"),)

    id: Mapped[str] = _id()
    resident_id: Mapped[str] = mapped_column(ForeignKey("residents.id", ondelete="CASCADE"), index=True)
    volunteer_id: Mapped[str] = mapped_column(ForeignKey("volunteers.id", ondelete="CASCADE"), index=True)
    priority: Mapped[int] = mapped_column(Integer, default=1, nullable=False)
    created_at: Mapped[datetime] = _created()


class FeedState(Base):
    __tablename__ = "feed_state"

    url: Mapped[str] = mapped_column(String(400), primary_key=True)
    etag: Mapped[str | None] = mapped_column(String(200))
    last_modified: Mapped[str | None] = mapped_column(String(100))
    last_fetch_at: Mapped[datetime | None] = mapped_column(UTCDateTime())
    last_success_at: Mapped[datetime | None] = mapped_column(UTCDateTime())
    last_status_code: Mapped[int | None] = mapped_column(Integer)
    last_error: Mapped[str | None] = mapped_column(Text)
    consecutive_failures: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    next_fetch_at: Mapped[datetime | None] = mapped_column(UTCDateTime())
    items_seen: Mapped[int] = mapped_column(Integer, default=0, nullable=False)


class CapMessage(Base):
    __tablename__ = "cap_messages"

    id: Mapped[str] = _id()
    identifier: Mapped[str] = mapped_column(String(200), unique=True, nullable=False)
    feed_guid: Mapped[str | None] = mapped_column(String(100), index=True)
    feed_url: Mapped[str | None] = mapped_column(String(400))
    official_url: Mapped[str | None] = mapped_column(String(400))
    sender: Mapped[str | None] = mapped_column(String(200))
    sent: Mapped[datetime | None] = mapped_column(UTCDateTime())
    status: Mapped[str | None] = mapped_column(String(20))
    msg_type: Mapped[str | None] = mapped_column(String(20))
    references_raw: Mapped[str | None] = mapped_column(Text)
    event: Mapped[str | None] = mapped_column(String(200))
    severity: Mapped[str | None] = mapped_column(String(20))
    urgency: Mapped[str | None] = mapped_column(String(20))
    certainty: Mapped[str | None] = mapped_column(String(20))
    onset: Mapped[datetime | None] = mapped_column(UTCDateTime())
    expires: Mapped[datetime | None] = mapped_column(UTCDateTime())
    headline: Mapped[str | None] = mapped_column(Text)
    area_desc: Mapped[str | None] = mapped_column(Text)
    raw_xml: Mapped[str] = mapped_column(Text, nullable=False)  # stored unchanged for audit
    parsed: Mapped[dict] = mapped_column(JSON, default=dict, nullable=False)
    is_valid: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
    validation_errors: Mapped[list] = mapped_column(JSON, default=list, nullable=False)
    superseded_by: Mapped[str | None] = mapped_column(String(200))
    is_fixture: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    fetched_at: Mapped[datetime] = _created()


class DemoSession(Base):
    __tablename__ = "demo_sessions"

    id: Mapped[str] = _id()
    started_by_user_id: Mapped[str | None] = mapped_column(ForeignKey("users.id", ondelete="SET NULL"))
    scenario: Mapped[str] = mapped_column(String(60), nullable=False)
    started_at: Mapped[datetime] = _created()
    reset_at: Mapped[datetime | None] = mapped_column(UTCDateTime())


class Incident(Base):
    __tablename__ = "incidents"
    __table_args__ = (
        CheckConstraint(_in("source", INCIDENT_SOURCES), name="ck_incidents_source"),
        CheckConstraint("status IN ('active', 'closed', 'cancelled')", name="ck_incidents_status"),
        CheckConstraint("escalation_mode IN ('A', 'B', 'C', 'D')", name="ck_incidents_mode"),
        Index("ix_incidents_status", "status", "is_demo"),
    )

    id: Mapped[str] = _id()
    title: Mapped[str] = mapped_column(String(300), nullable=False)
    hazard_type: Mapped[str] = mapped_column(String(60), nullable=False)
    source: Mapped[str] = mapped_column(String(20), nullable=False)
    status: Mapped[str] = mapped_column(String(20), default="active", nullable=False)
    is_demo: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    demo_session_id: Mapped[str | None] = mapped_column(ForeignKey("demo_sessions.id", ondelete="SET NULL"))
    cap_message_id: Mapped[str | None] = mapped_column(ForeignKey("cap_messages.id", ondelete="SET NULL"))
    cap_identifier: Mapped[str | None] = mapped_column(String(200), index=True)
    cap_sender: Mapped[str | None] = mapped_column(String(200))
    severity: Mapped[str] = mapped_column(String(20), default="Unknown", nullable=False)
    urgency: Mapped[str] = mapped_column(String(20), default="Unknown", nullable=False)
    certainty: Mapped[str] = mapped_column(String(20), default="Unknown", nullable=False)
    sent: Mapped[datetime | None] = mapped_column(UTCDateTime())
    effective: Mapped[datetime | None] = mapped_column(UTCDateTime())
    onset: Mapped[datetime | None] = mapped_column(UTCDateTime())
    expires: Mapped[datetime | None] = mapped_column(UTCDateTime())
    onset_fallback_used: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    onset_fallback_note: Mapped[str | None] = mapped_column(Text)
    # Official text — never modified.
    headline: Mapped[str | None] = mapped_column(Text)
    description: Mapped[str | None] = mapped_column(Text)
    instruction: Mapped[str | None] = mapped_column(Text)
    area_desc: Mapped[str | None] = mapped_column(Text)
    official_url: Mapped[str | None] = mapped_column(String(400))
    escalation_mode: Mapped[str] = mapped_column(String(1), nullable=False)
    requires_dispatch_approval: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    interval_override_seconds: Mapped[int | None] = mapped_column(Integer)
    created_by_user_id: Mapped[str | None] = mapped_column(ForeignKey("users.id", ondelete="SET NULL"))
    created_at: Mapped[datetime] = _created()
    updated_at: Mapped[datetime] = mapped_column(UTCDateTime(), default=utcnow, onupdate=utcnow)
    closed_at: Mapped[datetime | None] = mapped_column(UTCDateTime())
    closed_by_user_id: Mapped[str | None] = mapped_column(ForeignKey("users.id", ondelete="SET NULL"))
    close_note: Mapped[str | None] = mapped_column(Text)


class IncidentWard(Base):
    __tablename__ = "incident_wards"
    __table_args__ = (UniqueConstraint("incident_id", "ward_id"),)

    id: Mapped[str] = _id()
    incident_id: Mapped[str] = mapped_column(ForeignKey("incidents.id", ondelete="CASCADE"), index=True)
    ward_id: Mapped[str] = mapped_column(ForeignKey("wards.id", ondelete="CASCADE"), index=True)
    match_method: Mapped[str] = mapped_column(String(20), nullable=False)  # geometry | lgd_code | manual
    match_note: Mapped[str | None] = mapped_column(Text)


class Delivery(Base):
    """One per matched resident per incident. Holds response status + persisted escalation state."""

    __tablename__ = "deliveries"
    __table_args__ = (
        UniqueConstraint("incident_id", "resident_id", name="uq_delivery_incident_resident"),
        CheckConstraint(_in("status", DELIVERY_STATUSES), name="ck_deliveries_status"),
        Index("ix_deliveries_due", "next_action_at", "status"),
        Index("ix_deliveries_incident_status", "incident_id", "status"),
    )

    id: Mapped[str] = _id()
    incident_id: Mapped[str] = mapped_column(ForeignKey("incidents.id", ondelete="CASCADE"), nullable=False)
    resident_id: Mapped[str] = mapped_column(ForeignKey("residents.id", ondelete="CASCADE"), nullable=False)
    status: Mapped[str] = mapped_column(String(12), default="PENDING", nullable=False)
    channels: Mapped[list] = mapped_column(JSON, default=list, nullable=False)
    accessibility_modes: Mapped[list] = mapped_column(JSON, default=list, nullable=False)
    alerted_at: Mapped[datetime | None] = mapped_column(UTCDateTime())
    seen_at: Mapped[datetime | None] = mapped_column(UTCDateTime())
    replied_at: Mapped[datetime | None] = mapped_column(UTCDateTime())
    reply_channel: Mapped[str | None] = mapped_column(String(20))
    resolved_at: Mapped[datetime | None] = mapped_column(UTCDateTime())
    resolved_by: Mapped[str | None] = mapped_column(String(30))
    help_requested_at: Mapped[datetime | None] = mapped_column(UTCDateTime())
    escalation_level: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    escalation_step: Mapped[str] = mapped_column(String(40), default="alerted", nullable=False)
    next_action_at: Mapped[datetime | None] = mapped_column(UTCDateTime())
    needs_operator: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    needs_rescue: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    rescue_reason: Mapped[str | None] = mapped_column(Text)
    override_reason: Mapped[str | None] = mapped_column(Text)
    reminders_sent: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    version: Mapped[int] = mapped_column(Integer, default=1, nullable=False)
    created_at: Mapped[datetime] = _created()
    updated_at: Mapped[datetime] = mapped_column(UTCDateTime(), default=utcnow, onupdate=utcnow)


class NotificationAttempt(Base):
    __tablename__ = "notification_attempts"

    id: Mapped[str] = _id()
    delivery_id: Mapped[str | None] = mapped_column(ForeignKey("deliveries.id", ondelete="CASCADE"), index=True)
    task_id: Mapped[str | None] = mapped_column(ForeignKey("tasks.id", ondelete="CASCADE"), index=True)
    incident_id: Mapped[str | None] = mapped_column(ForeignKey("incidents.id", ondelete="CASCADE"), index=True)
    channel: Mapped[str] = mapped_column(String(12), nullable=False)  # push | sms | in_app
    recipient_kind: Mapped[str] = mapped_column(String(20), nullable=False)
    recipient_user_id: Mapped[str | None] = mapped_column(ForeignKey("users.id", ondelete="SET NULL"))
    recipient_phone: Mapped[str | None] = mapped_column(String(20), index=True)
    body: Mapped[str | None] = mapped_column(Text)
    # queued -> sent | failed (retried up to MAX_RETRIES) ; blocked = refused by NOTIFY_REAL_RESIDENTS
    status: Mapped[str] = mapped_column(String(12), nullable=False)
    title: Mapped[str | None] = mapped_column(String(200))
    data: Mapped[dict] = mapped_column(JSON, default=dict, nullable=False)
    provider: Mapped[str | None] = mapped_column(String(20))
    provider_message_id: Mapped[str | None] = mapped_column(String(120))
    error: Mapped[str | None] = mapped_column(Text)
    retries: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    next_retry_at: Mapped[datetime | None] = mapped_column(UTCDateTime())
    round: Mapped[str] = mapped_column(String(30), default="initial", nullable=False)
    idempotency_key: Mapped[str] = mapped_column(String(200), unique=True, nullable=False)
    created_at: Mapped[datetime] = _created()
    sent_at: Mapped[datetime | None] = mapped_column(UTCDateTime())

    __table_args__ = (
        CheckConstraint("status IN ('queued', 'sent', 'failed', 'blocked')", name="ck_attempts_status"),
        CheckConstraint("channel IN ('push', 'sms', 'in_app')", name="ck_attempts_channel"),
        Index("ix_attempts_queue", "status", "next_retry_at"),
    )


class Task(Base):
    __tablename__ = "tasks"
    __table_args__ = (
        CheckConstraint(_in("kind", TASK_KINDS), name="ck_tasks_kind"),
        CheckConstraint(_in("status", TASK_STATUSES), name="ck_tasks_status"),
        CheckConstraint(
            "status <> 'CANT_GO' OR cant_go_reason IS NOT NULL", name="ck_tasks_cant_go_reason"
        ),
        # At most one open task of each kind per delivery — prevents duplicate assignment.
        Index(
            "uq_tasks_open_per_delivery_kind",
            "delivery_id",
            "kind",
            unique=True,
            sqlite_where=text("status IN ('PENDING_APPROVAL','ASSIGNED','ACCEPTED')"),
            postgresql_where=text("status IN ('PENDING_APPROVAL','ASSIGNED','ACCEPTED')"),
        ),
        Index("ix_tasks_assignee_status", "assignee_user_id", "status"),
    )

    id: Mapped[str] = _id()
    incident_id: Mapped[str] = mapped_column(ForeignKey("incidents.id", ondelete="CASCADE"), index=True)
    delivery_id: Mapped[str] = mapped_column(ForeignKey("deliveries.id", ondelete="CASCADE"), nullable=False)
    resident_id: Mapped[str] = mapped_column(ForeignKey("residents.id", ondelete="CASCADE"), nullable=False)
    kind: Mapped[str] = mapped_column(String(20), nullable=False)
    status: Mapped[str] = mapped_column(String(20), nullable=False)
    assignee_user_id: Mapped[str | None] = mapped_column(ForeignKey("users.id", ondelete="SET NULL"))
    volunteer_id: Mapped[str | None] = mapped_column(ForeignKey("volunteers.id", ondelete="SET NULL"))
    reason: Mapped[str] = mapped_column(Text, nullable=False)
    outcome: Mapped[str | None] = mapped_column(String(30))
    outcome_note: Mapped[str | None] = mapped_column(Text)
    cant_go_reason: Mapped[str | None] = mapped_column(String(30))
    distance_m: Mapped[float | None] = mapped_column(Float)
    est_walk_minutes: Mapped[float | None] = mapped_column(Float)
    attempt_no: Mapped[int] = mapped_column(Integer, default=1, nullable=False)
    approved_by_user_id: Mapped[str | None] = mapped_column(ForeignKey("users.id", ondelete="SET NULL"))
    approved_at: Mapped[datetime | None] = mapped_column(UTCDateTime())
    accepted_at: Mapped[datetime | None] = mapped_column(UTCDateTime())
    reached_at: Mapped[datetime | None] = mapped_column(UTCDateTime())
    closed_at: Mapped[datetime | None] = mapped_column(UTCDateTime())
    created_at: Mapped[datetime] = _created()
    version: Mapped[int] = mapped_column(Integer, default=1, nullable=False)


class TimelineEvent(Base):
    __tablename__ = "incident_timeline"
    __table_args__ = (Index("ix_timeline_incident_time", "incident_id", "created_at"),)

    id: Mapped[str] = _id()
    incident_id: Mapped[str] = mapped_column(ForeignKey("incidents.id", ondelete="CASCADE"), nullable=False)
    delivery_id: Mapped[str | None] = mapped_column(ForeignKey("deliveries.id", ondelete="CASCADE"), index=True)
    resident_id: Mapped[str | None] = mapped_column(ForeignKey("residents.id", ondelete="CASCADE"))
    event_type: Mapped[str] = mapped_column(String(40), nullable=False)
    message: Mapped[str] = mapped_column(Text, nullable=False)
    actor_kind: Mapped[str] = mapped_column(String(20), nullable=False)  # system | user | sms
    actor_user_id: Mapped[str | None] = mapped_column(ForeignKey("users.id", ondelete="SET NULL"))
    data: Mapped[dict] = mapped_column(JSON, default=dict, nullable=False)
    created_at: Mapped[datetime] = _created()


class AuditLog(Base):
    __tablename__ = "audit_log"
    __table_args__ = (Index("ix_audit_entity", "entity_type", "entity_id"),)

    id: Mapped[str] = _id()
    actor_user_id: Mapped[str | None] = mapped_column(ForeignKey("users.id", ondelete="SET NULL"), index=True)
    actor_role: Mapped[str | None] = mapped_column(String(20))
    action: Mapped[str] = mapped_column(String(60), nullable=False)
    entity_type: Mapped[str] = mapped_column(String(40), nullable=False)
    entity_id: Mapped[str | None] = mapped_column(String(64))
    reason: Mapped[str | None] = mapped_column(Text)
    before: Mapped[dict | None] = mapped_column(JSON)
    after: Mapped[dict | None] = mapped_column(JSON)
    created_at: Mapped[datetime] = mapped_column(UTCDateTime(), default=utcnow, index=True)


class DeviceRegistration(Base):
    __tablename__ = "device_registrations"
    __table_args__ = (UniqueConstraint("user_id", "fcm_token"),)

    id: Mapped[str] = _id()
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), index=True)
    fcm_token: Mapped[str] = mapped_column(String(400), nullable=False)
    platform: Mapped[str] = mapped_column(String(20), nullable=False)
    created_at: Mapped[datetime] = _created()
    last_seen_at: Mapped[datetime] = mapped_column(UTCDateTime(), default=utcnow, onupdate=utcnow)


class AlertTemplate(Base):
    __tablename__ = "alert_templates"
    __table_args__ = (UniqueConstraint("hazard_type", "language", "style"),)

    id: Mapped[str] = _id()
    hazard_type: Mapped[str] = mapped_column(String(60), nullable=False)
    language: Mapped[str] = mapped_column(String(5), nullable=False)
    style: Mapped[str] = mapped_column(String(20), nullable=False)  # standard | easy_read | sms
    title: Mapped[str] = mapped_column(String(200), nullable=False)
    body: Mapped[str] = mapped_column(Text, nullable=False)
    pictogram: Mapped[str | None] = mapped_column(String(40))
    audio_asset_url: Mapped[str | None] = mapped_column(String(400))
    is_active: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
    updated_at: Mapped[datetime] = mapped_column(UTCDateTime(), default=utcnow, onupdate=utcnow)


class SmsInbound(Base):
    __tablename__ = "sms_inbound"

    id: Mapped[str] = _id()
    provider_message_id: Mapped[str] = mapped_column(String(120), unique=True, nullable=False)
    from_phone: Mapped[str] = mapped_column(String(20), index=True, nullable=False)
    body: Mapped[str] = mapped_column(Text, nullable=False)
    parsed_action: Mapped[str | None] = mapped_column(String(20))
    result: Mapped[str] = mapped_column(String(40), nullable=False)
    delivery_id: Mapped[str | None] = mapped_column(ForeignKey("deliveries.id", ondelete="SET NULL"))
    task_id: Mapped[str | None] = mapped_column(ForeignKey("tasks.id", ondelete="SET NULL"))
    is_simulated: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    received_at: Mapped[datetime] = _created()


class IdempotencyKey(Base):
    __tablename__ = "idempotency_keys"
    __table_args__ = (UniqueConstraint("user_id", "key"),)

    id: Mapped[str] = _id()
    user_id: Mapped[str] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    key: Mapped[str] = mapped_column(String(100), nullable=False)
    endpoint: Mapped[str] = mapped_column(String(200), nullable=False)
    response: Mapped[dict] = mapped_column(JSON, nullable=False)
    created_at: Mapped[datetime] = _created()


class WorkerHeartbeat(Base):
    __tablename__ = "worker_heartbeats"

    worker_id: Mapped[str] = mapped_column(String(80), primary_key=True)
    job: Mapped[str] = mapped_column(String(40), nullable=False)
    last_beat_at: Mapped[datetime] = mapped_column(UTCDateTime(), default=utcnow, nullable=False)
    last_result: Mapped[str | None] = mapped_column(Text)
