"""Pydantic request/response schemas — the public API contract (served as OpenAPI at /docs).

All timestamps are UTC ISO-8601. Phone numbers are masked except where an active task requires them.
"""

from __future__ import annotations

from datetime import datetime
from typing import Generic, Literal, TypeVar

from pydantic import BaseModel, ConfigDict, Field, field_validator

T = TypeVar("T")

Role = Literal["resident", "caregiver", "neighbour", "volunteer", "admin", "operator"]
Need = Literal["hearing", "vision", "mobility", "bedridden", "cognitive", "elderly_alone", "speech", "feature_phone"]
Lang = Literal["en", "hi"]


class ORM(BaseModel):
    model_config = ConfigDict(from_attributes=True)


class Page(BaseModel, Generic[T]):
    items: list[T]
    total: int
    limit: int
    offset: int


class ErrorBody(BaseModel):
    code: str
    message: str


class ErrorOut(BaseModel):
    error: ErrorBody


# ----------------------------------------------------------------------------- auth / users
class LoginIn(BaseModel):
    identifier: str = Field(min_length=3, max_length=200, description="Email or phone")
    password: str = Field(min_length=6, max_length=200)


class OtpRequestIn(BaseModel):
    phone: str = Field(min_length=8, max_length=20)


class OtpVerifyIn(BaseModel):
    phone: str = Field(min_length=8, max_length=20)
    code: str = Field(pattern=r"^\d{6}$")
    full_name: str | None = Field(default=None, max_length=120, description="Required for first-time sign-up")


class DemoLoginIn(BaseModel):
    user_id: str


class UserOut(ORM):
    id: str
    full_name: str
    role: Role
    phone_masked: str
    email: str | None
    language: str
    is_demo: bool


class TokenOut(BaseModel):
    access_token: str
    token_type: str = "bearer"
    expires_in: int
    user: UserOut
    is_new_user: bool = False


class OtpRequestOut(BaseModel):
    sent: bool
    expires_in: int
    channel: str
    note: str


class DemoPersona(BaseModel):
    user_id: str
    full_name: str
    role: Role
    description: str


class MePatch(BaseModel):
    language: Lang | None = None
    full_name: str | None = Field(default=None, min_length=2, max_length=120)


class DeviceIn(BaseModel):
    fcm_token: str = Field(min_length=10, max_length=400)
    platform: Literal["android", "ios", "web"]


# ----------------------------------------------------------------------------- wards / residents
class WardOut(ORM):
    id: str
    code: str
    name: str
    district: str
    state: str
    lgd_district_code: str | None
    centroid_lat: float
    centroid_lng: float
    access_status: str
    access_note: str | None
    is_demo: bool
    boundary_geojson: dict | None = None


class WardIn(BaseModel):
    code: str = Field(min_length=2, max_length=40)
    name: str = Field(min_length=2, max_length=120)
    district: str
    state: str = "Uttarakhand"
    lgd_district_code: str | None = None
    boundary_geojson: dict
    is_demo: bool = False


class WardAccessIn(BaseModel):
    access_status: Literal["open", "restricted", "blocked"]
    note: str | None = Field(default=None, max_length=500)


class GeoJsonUploadOut(BaseModel):
    created: int
    updated: int
    errors: list[str]


class ShelterOut(ORM):
    id: str
    ward_id: str
    name: str
    address: str
    lat: float
    lng: float
    source: str
    is_demo: bool
    distance_m: float | None = None
    est_walk_minutes: float | None = None


class ShelterIn(BaseModel):
    ward_id: str
    name: str = Field(min_length=3, max_length=160)
    address: str = Field(min_length=3)
    lat: float = Field(ge=-90, le=90)
    lng: float = Field(ge=-180, le=180)
    source: str = Field(min_length=3, max_length=160, description="Official order/notification designating it")


class ConsentOut(ORM):
    id: str
    consent_type: str
    granted: bool
    granted_by: str
    guardian_name: str | None
    granted_at: datetime
    expires_at: datetime
    withdrawn_at: datetime | None


class TrustedContactIn(BaseModel):
    full_name: str = Field(min_length=2, max_length=120)
    phone: str
    relationship: str = Field(default="family", max_length=40)
    can_view_location: bool = False


class RegistrationIn(BaseModel):
    full_name: str = Field(min_length=2, max_length=120)
    ward_id: str
    language: Lang = "hi"
    needs: list[Need] = []
    lives_alone: bool = False
    has_smartphone: bool = True
    lat: float | None = Field(default=None, ge=-90, le=90)
    lng: float | None = Field(default=None, ge=-180, le=180)
    address_text: str | None = Field(default=None, max_length=500)
    landmark: str | None = Field(default=None, max_length=200)
    consent_registry: bool
    consent_location: bool = False
    consent_caregiver_share: bool = False
    granted_by: Literal["self", "guardian", "assisted"] = "self"
    guardian_name: str | None = None
    trusted_contacts: list[TrustedContactIn] = []

    @field_validator("consent_registry")
    @classmethod
    def _must_consent(cls, v: bool) -> bool:
        if not v:
            raise ValueError("Registry consent is required to register")
        return v


class AssistedRegistrationIn(RegistrationIn):
    phone: str | None = None
    granted_by: Literal["self", "guardian", "assisted"] = "assisted"
    is_demo: bool = False


class ResidentPatch(BaseModel):
    language: Lang | None = None
    needs: list[Need] | None = None
    lives_alone: bool | None = None
    has_smartphone: bool | None = None
    lat: float | None = Field(default=None, ge=-90, le=90)
    lng: float | None = Field(default=None, ge=-180, le=180)
    address_text: str | None = None
    landmark: str | None = None


class ResidentOut(BaseModel):
    id: str
    user_id: str | None
    full_name: str
    phone_masked: str
    ward_id: str
    ward_name: str
    language: str
    needs: list[str]
    lives_alone: bool
    has_smartphone: bool
    registration_status: str
    registered_via: str
    reverify_due_at: datetime | None
    is_demo: bool
    consents: list[ConsentOut] = []
    has_exact_location: bool = False


class ExactLocationOut(BaseModel):
    lat: float
    lng: float
    address_text: str | None
    landmark: str | None
    source: str


class MeOut(BaseModel):
    user: UserOut
    resident: ResidentOut | None = None
    volunteer: VolunteerOut | None = None
    demo_mode: bool
    notify_real_residents: bool


class VolunteerOut(BaseModel):
    id: str
    user_id: str
    full_name: str
    phone_masked: str
    ward_id: str | None
    ward_name: str | None
    is_available: bool
    base_lat: float
    base_lng: float
    max_radius_m: float
    skills: list[str]
    verified: bool
    is_demo: bool
    active_task_id: str | None = None


class VolunteerIn(BaseModel):
    full_name: str = Field(min_length=2, max_length=120)
    phone: str
    ward_id: str | None = None
    base_lat: float = Field(ge=-90, le=90)
    base_lng: float = Field(ge=-180, le=180)
    max_radius_m: float = Field(default=3000, gt=0, le=50000)
    skills: list[str] = []
    is_demo: bool = False


class AvailabilityIn(BaseModel):
    is_available: bool


class NeighbourLinkIn(BaseModel):
    resident_id: str
    neighbour_user_id: str
    priority: int = Field(default=1, ge=1, le=10)
    distance_m: float | None = Field(default=None, ge=0)


class NeighbourLinkOut(BaseModel):
    id: str
    resident_id: str
    resident_name: str
    neighbour_user_id: str
    neighbour_name: str
    priority: int
    distance_m: float | None


class PreAssignedIn(BaseModel):
    resident_id: str
    volunteer_id: str
    priority: int = Field(default=1, ge=1, le=10)


class PreAssignedOut(BaseModel):
    id: str
    resident_id: str
    resident_name: str
    volunteer_id: str
    volunteer_name: str
    priority: int


class UserAdminOut(UserOut):
    is_active: bool
    created_at: datetime


class UserCreateIn(BaseModel):
    full_name: str = Field(min_length=2, max_length=120)
    role: Role
    phone: str | None = None
    email: str | None = None
    password: str | None = Field(default=None, min_length=10, description="Ops roles only; min 10 chars")
    language: Lang = "en"
    is_demo: bool = False


class UserPatchIn(BaseModel):
    role: Role | None = None
    is_active: bool | None = None


class TemplateOut(ORM):
    id: str
    hazard_type: str
    language: str
    style: str
    title: str
    body: str
    pictogram: str | None
    audio_asset_url: str | None
    is_active: bool


class TemplateIn(BaseModel):
    hazard_type: str = Field(min_length=1, max_length=60, description="'*' for any hazard")
    language: Lang
    style: Literal["standard", "easy_read", "sms"]
    title: str = Field(min_length=1, max_length=200)
    body: str = Field(min_length=1, max_length=1000)
    pictogram: str | None = None
    audio_asset_url: str | None = None
    is_active: bool = True

    @field_validator("body")
    @classmethod
    def _must_include_official(cls, v: str) -> str:
        if "{headline}" not in v:
            raise ValueError("Template body must include {headline} so the official text is always shown")
        return v


# ----------------------------------------------------------------------------- incidents
class WardMatchOut(BaseModel):
    ward_id: str
    ward_name: str
    match_method: str
    match_note: str | None


class Counts(BaseModel):
    SAFE: int = 0
    HELP: int = 0
    NO_REPLY: int = 0
    UNREACHABLE: int = 0
    PENDING: int = 0
    total: int = 0


class IncidentOut(BaseModel):
    id: str
    title: str
    hazard_type: str
    source: str
    source_label: str
    status: str
    is_demo: bool
    severity: str
    urgency: str
    certainty: str
    sent: datetime | None
    effective: datetime | None
    onset: datetime | None
    expires: datetime | None
    onset_fallback_used: bool
    onset_fallback_note: str | None
    headline: str | None
    description: str | None
    instruction: str | None
    area_desc: str | None
    official_url: str | None
    cap_identifier: str | None
    cap_sender: str | None
    escalation_mode: str
    mode_label: str
    requires_dispatch_approval: bool
    created_at: datetime
    closed_at: datetime | None
    close_note: str | None
    wards: list[WardMatchOut]
    counts: Counts
    pending_approvals: int = 0


class IncidentCreateIn(BaseModel):
    title: str = Field(min_length=3, max_length=300)
    hazard_type: str = Field(min_length=2, max_length=60)
    ward_ids: list[str] = Field(min_length=1)
    severity: Literal["Extreme", "Severe", "Moderate", "Minor", "Unknown"] = "Unknown"
    urgency: Literal["Immediate", "Expected", "Future", "Past", "Unknown"] = "Unknown"
    onset_in_minutes: int | None = Field(default=None, ge=-1440, le=7 * 1440)
    headline: str | None = None
    instruction: str | None = None
    is_demo: bool = True


class IncidentPatchIn(BaseModel):
    title: str | None = Field(default=None, min_length=3, max_length=300)
    severity: Literal["Extreme", "Severe", "Moderate", "Minor", "Unknown"] | None = None
    onset_in_minutes: int | None = Field(default=None, ge=-1440, le=7 * 1440)
    requires_dispatch_approval: bool | None = None
    reason: str = Field(min_length=5, max_length=500)


class CloseIn(BaseModel):
    note: str = Field(min_length=3, max_length=1000)


class TaskBrief(BaseModel):
    id: str
    kind: str
    status: str
    assignee_name: str | None
    est_walk_minutes: float | None


class PriorityComponent(BaseModel):
    factor: str
    points: int


class PriorityItem(BaseModel):
    delivery_id: str
    resident_id: str
    resident_name: str
    phone_masked: str
    ward_name: str
    needs: list[str]
    lives_alone: bool
    status: str
    priority_total: int
    priority_components: list[PriorityComponent]
    alerted_at: datetime | None
    seen_at: datetime | None
    replied_at: datetime | None
    reply_channel: str | None
    resolved_by: str | None
    escalation_level: int
    escalation_step: str
    next_action_at: datetime | None
    needs_operator: bool
    needs_rescue: bool
    rescue_reason: str | None
    channels: list[str]
    lat: float | None
    lng: float | None
    open_tasks: list[TaskBrief]


class OverrideIn(BaseModel):
    status: Literal["SAFE", "HELP", "NO_REPLY", "UNREACHABLE"]
    reason: str = Field(min_length=5, max_length=500)


class TimelineOut(BaseModel):
    id: str
    incident_id: str
    delivery_id: str | None
    resident_id: str | None
    event_type: str
    message: str
    actor_kind: str
    actor_name: str | None
    created_at: datetime


class MapMarker(BaseModel):
    delivery_id: str
    resident_first_name: str
    status: str
    lat: float
    lng: float
    priority: int
    needs: list[str]
    precision: str


class MapVolunteer(BaseModel):
    volunteer_id: str
    name: str
    lat: float
    lng: float
    is_available: bool
    busy: bool


class MapOut(BaseModel):
    wards: list[WardOut]
    markers: list[MapMarker]
    volunteers: list[MapVolunteer]
    shelters: list[ShelterOut]


# ----------------------------------------------------------------------------- alerts (resident)
class Presentation(BaseModel):
    label: str
    title: str
    body: str
    style: str
    pictogram: str
    easy_read_steps: list[str]


class OfficialAlert(BaseModel):
    sender: str | None
    event: str
    headline: str | None
    description: str | None
    instruction: str | None
    severity: str
    urgency: str
    certainty: str
    onset: datetime | None
    expires: datetime | None
    area_desc: str | None
    official_url: str | None
    source: str
    source_label: str
    onset_note: str | None


class AssistanceStatus(BaseModel):
    summary: str
    neighbour_asked: bool
    volunteer_status: str | None
    volunteer_eta_minutes: float | None


class AlertOut(BaseModel):
    delivery_id: str
    incident_id: str
    incident_status: str
    is_demo: bool
    status: str
    alerted_at: datetime | None
    replied_at: datetime | None
    reply_channel: str | None
    accessibility_modes: list[str]
    presentation: Presentation
    official: OfficialAlert
    shelters: list[ShelterOut]
    assistance: AssistanceStatus
    sms_reply_hint: str


class RespondIn(BaseModel):
    status: Literal["SAFE", "HELP"]
    client_request_id: str | None = Field(default=None, max_length=100)
    note: str | None = Field(default=None, max_length=300)


class RespondOut(BaseModel):
    delivery_id: str
    status: str
    changed: bool
    server_time: datetime


class CaregiverResidentOut(BaseModel):
    resident: ResidentOut
    active_alerts: list[PriorityItem]
    exact_location: ExactLocationOut | None


# ----------------------------------------------------------------------------- tasks
class TaskOut(BaseModel):
    id: str
    incident_id: str
    incident_title: str
    hazard_type: str
    is_demo: bool
    delivery_id: str
    resident_id: str
    resident_first_name: str
    resident_needs: list[str]
    kind: str
    status: str
    assignee_user_id: str | None
    assignee_name: str | None
    volunteer_id: str | None
    reason: str
    outcome: str | None
    outcome_note: str | None
    cant_go_reason: str | None
    distance_m: float | None
    est_walk_minutes: float | None
    attempt_no: int
    created_at: datetime
    approved_at: datetime | None
    accepted_at: datetime | None
    reached_at: datetime | None
    closed_at: datetime | None


class TaskDetailOut(TaskOut):
    resident_full_name: str | None
    resident_phone: str | None
    exact_location: ExactLocationOut | None
    location_note: str
    official_instruction: str | None
    shelters: list[ShelterOut]
    walk_estimate_note: str


class NeighbourRespondIn(BaseModel):
    outcome: Literal["SAFE", "HELP", "CANNOT_REACH"]
    note: str | None = Field(default=None, max_length=300)


class CantGoIn(BaseModel):
    reason: Literal["route_blocked", "too_far", "unsafe", "unavailable"]
    note: str | None = Field(default=None, max_length=300)


class ReachedIn(BaseModel):
    outcome: Literal["resident_safe", "evacuated", "needs_rescue", "not_found"]
    note: str | None = Field(default=None, max_length=300)


class RejectIn(BaseModel):
    reason: str = Field(min_length=5, max_length=500)


class ReassignIn(BaseModel):
    to_volunteer_id: str | None = None
    reason: str = Field(min_length=5, max_length=500)


class CandidateOut(BaseModel):
    volunteer_id: str
    name: str
    eligible: bool
    distance_m: float
    walk_minutes: float
    reason: str


# ----------------------------------------------------------------------------- feed / sms / audit
class FeedHealth(BaseModel):
    url: str
    healthy: bool
    last_fetch_at: datetime | None
    last_success_at: datetime | None
    last_status_code: int | None
    last_error: str | None
    consecutive_failures: int
    next_fetch_at: datetime | None
    items_seen: int
    etag: str | None


class FeedStatusOut(BaseModel):
    polling_enabled: bool
    notify_real_residents: bool
    feeds: list[FeedHealth]


class CapMessageOut(BaseModel):
    id: str
    identifier: str
    sender: str | None
    sent: datetime | None
    status: str | None
    msg_type: str | None
    event: str | None
    severity: str | None
    urgency: str | None
    certainty: str | None
    onset: datetime | None
    expires: datetime | None
    headline: str | None
    area_desc: str | None
    official_url: str | None
    is_valid: bool
    validation_errors: list[str]
    is_fixture: bool
    superseded_by: str | None
    fetched_at: datetime
    incident_ids: list[str] = []


class ReplayIn(BaseModel):
    ward_ids: list[str] | None = None
    onset_in_minutes: int = Field(default=20, ge=-60, le=24 * 60)


class SimulateIn(BaseModel):
    fixture: str = Field(min_length=1, max_length=100)
    onset_in_minutes: int = Field(default=20, ge=-60, le=24 * 60)
    ward_ids: list[str] | None = None


class SimSmsIn(BaseModel):
    from_phone: str
    body: str = Field(min_length=1, max_length=320)


class SmsResultOut(BaseModel):
    result: str
    action: str | None = None
    delivery_id: str | None = None
    task_id: str | None = None
    detail: str | None = None


class OutboxItem(BaseModel):
    id: str
    channel: str
    recipient_kind: str
    recipient_phone: str | None
    title: str | None
    body: str | None
    status: str
    provider: str | None
    error: str | None
    round: str
    created_at: datetime
    sent_at: datetime | None


class AuditOut(BaseModel):
    id: str
    actor_user_id: str | None
    actor_name: str | None
    actor_role: str | None
    action: str
    entity_type: str
    entity_id: str | None
    reason: str | None
    before: dict | None
    after: dict | None
    created_at: datetime


class DemoStatusOut(BaseModel):
    demo_mode_enabled: bool
    notify_real_residents: bool
    demo_wards: list[WardOut]
    demo_residents: int
    active_demo_incidents: int
    escalation_interval_seconds: int
    fixtures: list[str]
    personas: list[DemoPersona]


class DemoResetOut(BaseModel):
    incidents_removed: int
    sms_removed: int
    volunteers_reset: int
    real_data_untouched: bool


MeOut.model_rebuild()
