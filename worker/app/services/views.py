"""Build API responses from persisted state. No business decisions are made here."""

from __future__ import annotations

from collections import Counter

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app import schemas as S
from app.core import AppContext
from app.dispatch.eligibility import estimate_walk_minutes, haversine_m
from app.escalation import rules
from app.integrations.sms_gateway import mask_phone
from app.models import (
    OPEN_TASK_STATUSES,
    CapMessage,
    ConsentRecord,
    Delivery,
    Incident,
    IncidentWard,
    Resident,
    ResidentLocation,
    Shelter,
    Task,
    TimelineEvent,
    User,
    Volunteer,
    Ward,
)
from app.notifications.templates import pictogram_for
from app.services.incidents import SOURCE_LABEL


async def get_incident_or_404(session: AsyncSession, incident_id: str) -> Incident:
    from app.core import NotFound

    inc = await session.get(Incident, incident_id)
    if inc is None:
        raise NotFound("Incident")
    return inc


def user_out(u: User) -> S.UserOut:
    return S.UserOut(
        id=u.id,
        full_name=u.full_name,
        role=u.role,
        phone_masked=mask_phone(u.phone),
        email=u.email,
        language=u.language,
        is_demo=u.is_demo,
    )


async def resident_out(session: AsyncSession, r: Resident, include_consents: bool = True) -> S.ResidentOut:
    ward = await session.get(Ward, r.ward_id)
    consents = []
    if include_consents:
        consents = [
            S.ConsentOut.model_validate(c)
            for c in (
                await session.execute(
                    select(ConsentRecord).where(ConsentRecord.resident_id == r.id).order_by(ConsentRecord.granted_at)
                )
            )
            .scalars()
            .all()
        ]
    has_loc = await session.scalar(select(ResidentLocation.id).where(ResidentLocation.resident_id == r.id))
    return S.ResidentOut(
        id=r.id,
        user_id=r.user_id,
        full_name=r.full_name,
        phone_masked=mask_phone(r.phone),
        ward_id=r.ward_id,
        ward_name=ward.name if ward else "?",
        language=r.language,
        needs=list(r.needs or []),
        lives_alone=r.lives_alone,
        has_smartphone=r.has_smartphone,
        registration_status=r.registration_status,
        registered_via=r.registered_via,
        reverify_due_at=r.reverify_due_at,
        is_demo=r.is_demo,
        consents=consents,
        has_exact_location=bool(has_loc),
    )


async def volunteer_out(session: AsyncSession, v: Volunteer) -> S.VolunteerOut:
    u = await session.get(User, v.user_id)
    ward = await session.get(Ward, v.ward_id) if v.ward_id else None
    active = await session.scalar(
        select(Task.id).where(Task.volunteer_id == v.id, Task.status.in_(OPEN_TASK_STATUSES)).limit(1)
    )
    return S.VolunteerOut(
        id=v.id,
        user_id=v.user_id,
        full_name=u.full_name,
        phone_masked=mask_phone(u.phone),
        ward_id=v.ward_id,
        ward_name=ward.name if ward else None,
        is_available=v.is_available,
        base_lat=v.base_lat,
        base_lng=v.base_lng,
        max_radius_m=v.max_radius_m,
        skills=list(v.skills or []),
        verified=v.verified,
        is_demo=v.is_demo,
        active_task_id=active,
    )


def ward_out(w: Ward, with_geometry: bool = False) -> S.WardOut:
    out = S.WardOut.model_validate(w)
    if not with_geometry:
        out.boundary_geojson = None
    return out


async def counts_for(session: AsyncSession, incident_id: str) -> S.Counts:
    rows = (
        await session.execute(
            select(Delivery.status, func.count()).where(Delivery.incident_id == incident_id).group_by(Delivery.status)
        )
    ).all()
    c = S.Counts()
    for status, n in rows:
        setattr(c, status, n)
        c.total += n
    return c


async def incident_out(session: AsyncSession, inc: Incident) -> S.IncidentOut:
    wards = (
        await session.execute(
            select(IncidentWard, Ward)
            .join(Ward, Ward.id == IncidentWard.ward_id)
            .where(IncidentWard.incident_id == inc.id)
        )
    ).all()
    pending = await session.scalar(
        select(func.count()).select_from(Task).where(Task.incident_id == inc.id, Task.status == "PENDING_APPROVAL")
    )
    return S.IncidentOut(
        id=inc.id,
        title=inc.title,
        hazard_type=inc.hazard_type,
        source=inc.source,
        source_label=SOURCE_LABEL.get(inc.source, inc.source),
        status=inc.status,
        is_demo=inc.is_demo,
        severity=inc.severity,
        urgency=inc.urgency,
        certainty=inc.certainty,
        sent=inc.sent,
        effective=inc.effective,
        onset=inc.onset,
        expires=inc.expires,
        onset_fallback_used=inc.onset_fallback_used,
        onset_fallback_note=inc.onset_fallback_note,
        headline=inc.headline,
        description=inc.description,
        instruction=inc.instruction,
        area_desc=inc.area_desc,
        official_url=inc.official_url,
        cap_identifier=inc.cap_identifier,
        cap_sender=inc.cap_sender,
        escalation_mode=inc.escalation_mode,
        mode_label=rules.mode_label(inc.escalation_mode),
        requires_dispatch_approval=inc.requires_dispatch_approval,
        created_at=inc.created_at,
        closed_at=inc.closed_at,
        close_note=inc.close_note,
        wards=[
            S.WardMatchOut(ward_id=w.id, ward_name=w.name, match_method=iw.match_method, match_note=iw.match_note)
            for iw, w in wards
        ],
        counts=await counts_for(session, inc.id),
        pending_approvals=pending or 0,
    )


async def _task_briefs(session: AsyncSession, delivery_ids: list[str]) -> dict[str, list[S.TaskBrief]]:
    if not delivery_ids:
        return {}
    rows = (
        await session.execute(
            select(Task, User.full_name)
            .outerjoin(User, User.id == Task.assignee_user_id)
            .where(Task.delivery_id.in_(delivery_ids), Task.status.in_(OPEN_TASK_STATUSES))
        )
    ).all()
    out: dict[str, list[S.TaskBrief]] = {}
    for t, name in rows:
        out.setdefault(t.delivery_id, []).append(
            S.TaskBrief(id=t.id, kind=t.kind, status=t.status, assignee_name=name, est_walk_minutes=t.est_walk_minutes)
        )
    return out


async def priority_list(
    session: AsyncSession,
    ctx: AppContext,
    incident_id: str,
    *,
    status: str | None = None,
    include_safe: bool = True,
) -> list[S.PriorityItem]:
    q = (
        select(Delivery, Resident, Ward)
        .join(Resident, Resident.id == Delivery.resident_id)
        .join(Ward, Ward.id == Resident.ward_id)
        .where(Delivery.incident_id == incident_id)
    )
    if status:
        q = q.where(Delivery.status == status)
    rows = (await session.execute(q)).all()
    tasks = await _task_briefs(session, [d.id for d, _, _ in rows])
    now = ctx.now()
    items = []
    for d, r, w in rows:
        if not include_safe and d.status == "SAFE":
            continue
        pb = rules.priority_score(
            needs=r.needs or [], lives_alone=r.lives_alone, status=d.status, alerted_at=d.alerted_at, now=now
        )
        items.append(
            S.PriorityItem(
                delivery_id=d.id,
                resident_id=r.id,
                resident_name=r.full_name,
                phone_masked=mask_phone(r.phone),
                ward_name=w.name,
                needs=list(r.needs or []),
                lives_alone=r.lives_alone,
                status=d.status,
                priority_total=pb.total,
                priority_components=[S.PriorityComponent(**c) for c in pb.components],
                alerted_at=d.alerted_at,
                seen_at=d.seen_at,
                replied_at=d.replied_at,
                reply_channel=d.reply_channel,
                resolved_by=d.resolved_by,
                escalation_level=d.escalation_level,
                escalation_step=d.escalation_step,
                next_action_at=d.next_action_at,
                needs_operator=d.needs_operator,
                needs_rescue=d.needs_rescue,
                rescue_reason=d.rescue_reason,
                channels=list(d.channels or []),
                lat=r.coarse_lat,
                lng=r.coarse_lng,
                open_tasks=tasks.get(d.id, []),
            )
        )
    items.sort(key=lambda i: (i.status == "SAFE", -i.priority_total, i.resident_name))
    return items


async def shelters_near(
    session: AsyncSession, ctx: AppContext, ward_id: str, is_demo: bool, origin: tuple[float, float] | None
) -> list[S.ShelterOut]:
    rows = (
        (await session.execute(select(Shelter).where(Shelter.ward_id == ward_id, Shelter.is_demo.is_(is_demo))))
        .scalars()
        .all()
    )
    out = []
    for s in rows:
        so = S.ShelterOut.model_validate(s)
        if origin:
            dist = haversine_m(origin[0], origin[1], s.lat, s.lng)
            so.distance_m = round(dist)
            so.est_walk_minutes = estimate_walk_minutes(
                dist, ctx.settings.walking_speed_m_per_min, ctx.settings.hill_terrain_factor
            )
        out.append(so)
    out.sort(key=lambda s: s.distance_m if s.distance_m is not None else 1e12)
    return out


EASY_READ = {
    "en": [
        "Stay calm.",
        "Read or listen to the official message.",
        "Tap SAFE if you are safe.",
        "Tap HELP if you need help.",
        "Follow your family, neighbour or volunteer.",
    ],
    "hi": [
        "शांत रहें।",
        "आधिकारिक संदेश पढ़ें या सुनें।",
        "सुरक्षित हैं तो 'सुरक्षित' दबाएँ।",
        "मदद चाहिए तो 'मदद' दबाएँ।",
        "परिवार, पड़ोसी या स्वयंसेवक के साथ चलें।",
    ],
}


async def alert_out(session: AsyncSession, ctx: AppContext, d: Delivery) -> S.AlertOut:
    from app.notifications import templates

    inc = await session.get(Incident, d.incident_id)
    r = await session.get(Resident, d.resident_id)
    lang = r.language if r.language in ("en", "hi") else "en"
    style = "easy_read" if "easy_read" in (d.accessibility_modes or []) else "standard"
    title, body = await templates.render(session, inc, lang, style)
    loc = await session.scalar(select(ResidentLocation).where(ResidentLocation.resident_id == r.id))
    origin = (loc.lat, loc.lng) if loc else ((r.coarse_lat, r.coarse_lng) if r.coarse_lat else None)
    shelters = await shelters_near(session, ctx, r.ward_id, r.is_demo, origin)
    open_t = (
        (await session.execute(select(Task).where(Task.delivery_id == d.id, Task.status.in_(OPEN_TASK_STATUSES))))
        .scalars()
        .all()
    )
    vol = next((t for t in open_t if t.kind != "neighbour_check"), None)
    neighbour = any(t.kind == "neighbour_check" for t in open_t)
    if d.status == "SAFE":
        summary = "You are marked safe." if lang == "en" else "आप सुरक्षित दर्ज हैं।"
    elif vol and vol.status == "ACCEPTED":
        summary = "A volunteer is on the way." if lang == "en" else "स्वयंसेवक रास्ते में है।"
    elif vol:
        summary = "Finding a volunteer for you." if lang == "en" else "आपके लिए स्वयंसेवक खोजा जा रहा है।"
    elif d.status == "HELP":
        summary = "Help request sent to the control room." if lang == "en" else "मदद अनुरोध नियंत्रण कक्ष को भेजा गया।"
    else:
        summary = "Please tell us if you are safe." if lang == "en" else "कृपया बताइए कि आप सुरक्षित हैं।"
    return S.AlertOut(
        delivery_id=d.id,
        incident_id=inc.id,
        incident_status=inc.status,
        is_demo=inc.is_demo,
        status=d.status,
        alerted_at=d.alerted_at,
        replied_at=d.replied_at,
        reply_channel=d.reply_channel,
        accessibility_modes=list(d.accessibility_modes or []),
        presentation=S.Presentation(
            label=(
                "AapdaSaathi presentation of an official alert"
                if lang == "en"
                else "आधिकारिक चेतावनी की आपदा साथी प्रस्तुति"
            ),
            title=title,
            body=body,
            style=style,
            pictogram=pictogram_for(inc.hazard_type),
            easy_read_steps=EASY_READ[lang] if style == "easy_read" else [],
        ),
        official=S.OfficialAlert(
            sender=inc.cap_sender,
            event=inc.hazard_type,
            headline=inc.headline,
            description=inc.description,
            instruction=inc.instruction,
            severity=inc.severity,
            urgency=inc.urgency,
            certainty=inc.certainty,
            onset=inc.onset,
            expires=inc.expires,
            area_desc=inc.area_desc,
            official_url=inc.official_url,
            source=inc.source,
            source_label=SOURCE_LABEL.get(inc.source, inc.source),
            onset_note=inc.onset_fallback_note,
        ),
        shelters=shelters,
        assistance=S.AssistanceStatus(
            summary=summary,
            neighbour_asked=neighbour,
            volunteer_status=vol.status if vol else None,
            volunteer_eta_minutes=vol.est_walk_minutes if vol and vol.status == "ACCEPTED" else None,
        ),
        sms_reply_hint="SMS 1 = SAFE, 2 = HELP" if lang == "en" else "SMS 1 = सुरक्षित, 2 = मदद",
    )


async def task_out(session: AsyncSession, t: Task) -> S.TaskOut:
    inc = await session.get(Incident, t.incident_id)
    r = await session.get(Resident, t.resident_id)
    assignee = await session.get(User, t.assignee_user_id) if t.assignee_user_id else None
    return S.TaskOut(
        id=t.id,
        incident_id=t.incident_id,
        incident_title=inc.title,
        hazard_type=inc.hazard_type,
        is_demo=inc.is_demo,
        delivery_id=t.delivery_id,
        resident_id=t.resident_id,
        resident_first_name=r.full_name.split(" ")[0],
        resident_needs=list(r.needs or []),
        kind=t.kind,
        status=t.status,
        assignee_user_id=t.assignee_user_id,
        assignee_name=assignee.full_name if assignee else None,
        volunteer_id=t.volunteer_id,
        reason=t.reason,
        outcome=t.outcome,
        outcome_note=t.outcome_note,
        cant_go_reason=t.cant_go_reason,
        distance_m=t.distance_m,
        est_walk_minutes=t.est_walk_minutes,
        attempt_no=t.attempt_no,
        created_at=t.created_at,
        approved_at=t.approved_at,
        accepted_at=t.accepted_at,
        reached_at=t.reached_at,
        closed_at=t.closed_at,
    )


async def task_detail(session: AsyncSession, ctx: AppContext, t: Task) -> S.TaskDetailOut:
    """Exact location and phone are disclosed only while the task is active and the incident is live."""
    from app.audit.log import audit
    from app.core import Actor

    base = await task_out(session, t)
    inc = await session.get(Incident, t.incident_id)
    r = await session.get(Resident, t.resident_id)
    active = t.status in ("ASSIGNED", "ACCEPTED") and inc.status == "active"
    loc = await session.scalar(select(ResidentLocation).where(ResidentLocation.resident_id == r.id)) if active else None
    exact = (
        S.ExactLocationOut(
            lat=loc.lat, lng=loc.lng, address_text=loc.address_text, landmark=loc.landmark, source=loc.source
        )
        if loc
        else None
    )
    if active and loc is not None:
        audit(
            session,
            Actor("user", t.assignee_user_id, t.kind.split("_")[0]),
            "location.view",
            "resident",
            r.id,
            reason=f"active task {t.id}",
        )
    origin = (loc.lat, loc.lng) if loc else ((r.coarse_lat, r.coarse_lng) if r.coarse_lat else None)
    return S.TaskDetailOut(
        **base.model_dump(),
        resident_full_name=r.full_name if active else None,
        resident_phone=r.phone if active else None,
        exact_location=exact,
        location_note=(
            "Exact location shown because this task is active. It is hidden once the task closes."
            if exact
            else "Exact location is only available while the task is active."
        ),
        official_instruction=inc.instruction,
        shelters=await shelters_near(session, ctx, r.ward_id, r.is_demo, origin) if active else [],
        walk_estimate_note=(
            f"Walking time is an ESTIMATE: straight-line distance × {ctx.settings.hill_terrain_factor} "
            f"hill factor at {ctx.settings.walking_speed_m_per_min:.0f} m/min. The route is not "
            "checked for hazards — use your judgement and official instructions."
        ),
    )


async def timeline_out(session: AsyncSession, rows: list[TimelineEvent]) -> list[S.TimelineOut]:
    ids = {r.actor_user_id for r in rows if r.actor_user_id}
    names = {}
    if ids:
        names = dict((await session.execute(select(User.id, User.full_name).where(User.id.in_(ids)))).all())
    return [
        S.TimelineOut(
            id=r.id,
            incident_id=r.incident_id,
            delivery_id=r.delivery_id,
            resident_id=r.resident_id,
            event_type=r.event_type,
            message=r.message,
            actor_kind=r.actor_kind,
            actor_name=names.get(r.actor_user_id) if r.actor_user_id else None,
            created_at=r.created_at,
        )
        for r in rows
    ]


async def cap_out(session: AsyncSession, m: CapMessage) -> S.CapMessageOut:
    inc_ids = (await session.execute(select(Incident.id).where(Incident.cap_message_id == m.id))).scalars().all()
    return S.CapMessageOut(
        id=m.id,
        identifier=m.identifier,
        sender=m.sender,
        sent=m.sent,
        status=m.status,
        msg_type=m.msg_type,
        event=m.event,
        severity=m.severity,
        urgency=m.urgency,
        certainty=m.certainty,
        onset=m.onset,
        expires=m.expires,
        headline=m.headline,
        area_desc=m.area_desc,
        official_url=m.official_url,
        is_valid=m.is_valid,
        validation_errors=list(m.validation_errors or []),
        is_fixture=m.is_fixture,
        superseded_by=m.superseded_by,
        fetched_at=m.fetched_at,
        incident_ids=list(inc_ids),
    )


async def map_out(session: AsyncSession, ctx: AppContext, inc: Incident) -> S.MapOut:
    ward_ids = (
        (await session.execute(select(IncidentWard.ward_id).where(IncidentWard.incident_id == inc.id))).scalars().all()
    )
    wards = (await session.execute(select(Ward).where(Ward.id.in_(ward_ids)))).scalars().all()
    items = await priority_list(session, ctx, inc.id)
    markers = [
        S.MapMarker(
            delivery_id=i.delivery_id,
            resident_first_name=i.resident_name.split(" ")[0],
            status=i.status,
            lat=i.lat,
            lng=i.lng,
            priority=i.priority_total,
            needs=i.needs,
            precision="~110 m grid",
        )
        for i in items
        if i.lat is not None
    ]
    vols = (
        await session.execute(
            select(Volunteer, User).join(User, User.id == Volunteer.user_id).where(Volunteer.is_demo.is_(inc.is_demo))
        )
    ).all()
    busy = Counter(
        (
            await session.execute(
                select(Task.volunteer_id).where(Task.status.in_(OPEN_TASK_STATUSES), Task.volunteer_id.is_not(None))
            )
        )
        .scalars()
        .all()
    )
    shelters = (await session.execute(select(Shelter).where(Shelter.ward_id.in_(ward_ids)))).scalars().all()
    return S.MapOut(
        wards=[ward_out(w, with_geometry=True) for w in wards],
        markers=markers,
        volunteers=[
            S.MapVolunteer(
                volunteer_id=v.id,
                name=u.full_name,
                lat=v.base_lat,
                lng=v.base_lng,
                is_available=v.is_available,
                busy=busy[v.id] > 0,
            )
            for v, u in vols
        ],
        shelters=[S.ShelterOut.model_validate(s) for s in shelters],
    )
