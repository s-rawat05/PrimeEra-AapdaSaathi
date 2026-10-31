"""Admin portal endpoints: preparation and configuration. All changes are audited."""

from __future__ import annotations

import json

from fastapi import APIRouter, Depends, File, Query, UploadFile
from shapely.geometry import shape
from shapely.validation import explain_validity
from sqlalchemy import or_, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app import schemas as S
from app.api.common import PageParams, finalize, paged
from app.audit.log import audit
from app.auth.deps import OPS, actor_of, admin_user, get_ctx, require_roles
from app.auth.security import hash_password
from app.core import AppContext, Conflict, DomainError, NotFound
from app.db import get_session
from app.integrations.sms_gateway import mask_phone, normalize_phone
from app.models import (
    AlertTemplate,
    NeighbourLink,
    PreAssignedHelper,
    Resident,
    Shelter,
    User,
    Volunteer,
    Ward,
)
from app.services import residents as residents_svc
from app.services import views

router = APIRouter(prefix="/admin", tags=["admin"])
ops_or_admin = require_roles(*OPS)


# ----------------------------------------------------------------------------- wards
@router.get("/wards", response_model=list[S.WardOut])
async def list_wards(with_geometry: bool = False, _: User = Depends(ops_or_admin),
                     session: AsyncSession = Depends(get_session)):
    rows = (await session.execute(select(Ward).order_by(Ward.is_demo.desc(), Ward.code))).scalars().all()
    return [views.ward_out(w, with_geometry) for w in rows]


def _validate_geometry(geom: dict) -> tuple[float, float]:
    try:
        g = shape(geom)
    except Exception as exc:  # noqa: BLE001
        raise DomainError("invalid_geometry", f"Invalid GeoJSON geometry: {exc}", 422) from exc
    if g.geom_type not in ("Polygon", "MultiPolygon"):
        raise DomainError("invalid_geometry", "Ward boundary must be a Polygon or MultiPolygon", 422)
    if not g.is_valid:
        raise DomainError("invalid_geometry", f"Invalid polygon: {explain_validity(g)}", 422)
    minx, miny, maxx, maxy = g.bounds
    if not (-180 <= minx <= maxx <= 180 and -90 <= miny <= maxy <= 90):
        raise DomainError("invalid_geometry", "Coordinates must be [longitude, latitude] in WGS84", 422)
    c = g.centroid
    return round(c.y, 6), round(c.x, 6)


@router.post("/wards", response_model=S.WardOut, status_code=201)
async def create_ward(body: S.WardIn, user: User = Depends(admin_user), session: AsyncSession = Depends(get_session),
                      ctx: AppContext = Depends(get_ctx)):
    lat, lng = _validate_geometry(body.boundary_geojson)
    if await session.scalar(select(Ward.id).where(Ward.code == body.code)):
        raise Conflict("duplicate", "A ward with this code exists")
    w = Ward(code=body.code, name=body.name, district=body.district, state=body.state,
             lgd_district_code=body.lgd_district_code, boundary_geojson=body.boundary_geojson, centroid_lat=lat,
             centroid_lng=lng, is_demo=body.is_demo)
    session.add(w)
    await session.flush()
    audit(session, actor_of(user), "ward.create", "ward", w.id, after={"code": w.code})
    await finalize(session, ctx)
    return views.ward_out(w, True)


@router.post("/wards/geojson", response_model=S.GeoJsonUploadOut,
             summary="Upload a GeoJSON FeatureCollection (properties: code, name, district, state, lgd_district_code)")
async def upload_geojson(file: UploadFile = File(...), is_demo: bool = Query(False), user: User = Depends(admin_user),
                         session: AsyncSession = Depends(get_session), ctx: AppContext = Depends(get_ctx)):
    raw = await file.read()
    if len(raw) > 10 * 1024 * 1024:
        raise DomainError("too_large", "GeoJSON must be under 10 MB", 413)
    try:
        fc = json.loads(raw)
    except json.JSONDecodeError as exc:
        raise DomainError("invalid_json", "File is not valid JSON", 422) from exc
    if fc.get("type") != "FeatureCollection":
        raise DomainError("invalid_geojson", "Expected a FeatureCollection", 422)
    created = updated = 0
    errors: list[str] = []
    for i, f in enumerate(fc.get("features", [])):
        p = f.get("properties") or {}
        code, name = p.get("code"), p.get("name")
        if not code or not name:
            errors.append(f"feature {i}: 'code' and 'name' properties are required")
            continue
        try:
            lat, lng = _validate_geometry(f.get("geometry") or {})
        except DomainError as exc:
            errors.append(f"feature {i} ({code}): {exc.message}")
            continue
        w = await session.scalar(select(Ward).where(Ward.code == code))
        if w is None:
            session.add(Ward(code=code, name=name, district=p.get("district") or "Unknown",
                             state=p.get("state") or "Uttarakhand", lgd_district_code=p.get("lgd_district_code"),
                             boundary_geojson=f["geometry"], centroid_lat=lat, centroid_lng=lng, is_demo=is_demo))
            created += 1
        else:
            if w.is_demo != is_demo:
                errors.append(f"feature {i} ({code}): exists with different demo flag")
                continue
            w.name, w.boundary_geojson, w.centroid_lat, w.centroid_lng = name, f["geometry"], lat, lng
            w.lgd_district_code = p.get("lgd_district_code") or w.lgd_district_code
            updated += 1
    audit(session, actor_of(user), "ward.geojson_upload", "ward", None,
          after={"created": created, "updated": updated, "errors": len(errors)})
    await finalize(session, ctx)
    return S.GeoJsonUploadOut(created=created, updated=updated, errors=errors[:50])


@router.put("/wards/{ward_id}/access", response_model=S.WardOut,
            summary="Mark a ward open / restricted (dispatch needs approval) / blocked (no automatic dispatch)")
async def ward_access(ward_id: str, body: S.WardAccessIn, user: User = Depends(ops_or_admin),
                      session: AsyncSession = Depends(get_session), ctx: AppContext = Depends(get_ctx)):
    w = await session.get(Ward, ward_id)
    if w is None:
        raise NotFound("Ward")
    before = {"access": w.access_status}
    w.access_status, w.access_note = body.access_status, body.note
    audit(session, actor_of(user), "ward.access", "ward", w.id, reason=body.note, before=before,
          after={"access": w.access_status})
    await finalize(session, ctx)
    return views.ward_out(w)


@router.delete("/wards/{ward_id}", status_code=204)
async def delete_ward(ward_id: str, user: User = Depends(admin_user), session: AsyncSession = Depends(get_session),
                      ctx: AppContext = Depends(get_ctx)):
    w = await session.get(Ward, ward_id)
    if w is None:
        raise NotFound("Ward")
    if await session.scalar(select(Resident.id).where(Resident.ward_id == ward_id).limit(1)):
        raise Conflict("ward_in_use", "Move or remove residents in this ward first")
    await session.delete(w)
    audit(session, actor_of(user), "ward.delete", "ward", ward_id)
    await finalize(session, ctx)


# ----------------------------------------------------------------------------- shelters
@router.get("/shelters", response_model=list[S.ShelterOut])
async def list_shelters(_: User = Depends(ops_or_admin), session: AsyncSession = Depends(get_session)):
    return [S.ShelterOut.model_validate(s) for s in (await session.execute(select(Shelter))).scalars().all()]


@router.post("/shelters", response_model=S.ShelterOut, status_code=201,
             summary="Register an OFFICIALLY designated relief post (source required)")
async def create_shelter(body: S.ShelterIn, user: User = Depends(admin_user),
                         session: AsyncSession = Depends(get_session), ctx: AppContext = Depends(get_ctx)):
    w = await session.get(Ward, body.ward_id)
    if w is None:
        raise NotFound("Ward")
    s = Shelter(**body.model_dump(), is_demo=w.is_demo)
    session.add(s)
    await session.flush()
    audit(session, actor_of(user), "shelter.create", "shelter", s.id, after={"name": s.name, "source": s.source})
    await finalize(session, ctx)
    return S.ShelterOut.model_validate(s)


@router.delete("/shelters/{shelter_id}", status_code=204)
async def delete_shelter(shelter_id: str, user: User = Depends(admin_user),
                         session: AsyncSession = Depends(get_session), ctx: AppContext = Depends(get_ctx)):
    s = await session.get(Shelter, shelter_id)
    if s is None:
        raise NotFound("Shelter")
    await session.delete(s)
    audit(session, actor_of(user), "shelter.delete", "shelter", shelter_id)
    await finalize(session, ctx)


# ----------------------------------------------------------------------------- residents
@router.get("/residents", response_model=S.Page[S.ResidentOut])
async def list_residents(q: str | None = Query(None, max_length=60), ward_id: str | None = None,
                         status: str | None = None, need: str | None = None, page: PageParams = Depends(),
                         user: User = Depends(admin_user), session: AsyncSession = Depends(get_session)):
    query = select(Resident).order_by(Resident.full_name)
    if q:
        query = query.where(Resident.full_name.ilike(f"%{q}%"))
    if ward_id:
        query = query.where(Resident.ward_id == ward_id)
    if status:
        query = query.where(Resident.registration_status == status)
    rows, total = await paged(session, query, page)
    items = [await views.resident_out(session, r) for r in rows]
    if need:
        items = [i for i in items if need in i.needs]
    audit(session, actor_of(user), "registry.list", "resident", None, after={"count": len(items)})
    await session.commit()
    return S.Page(items=items, total=total, limit=page.limit, offset=page.offset)


@router.post("/residents", response_model=S.ResidentOut, status_code=201,
             summary="Assisted registration (e.g. by an ASHA worker or ward officer)")
async def assisted_registration(body: S.AssistedRegistrationIn, user: User = Depends(admin_user),
                                session: AsyncSession = Depends(get_session), ctx: AppContext = Depends(get_ctx)):
    resident_user = None
    if body.phone and body.has_smartphone and "feature_phone" not in body.needs:
        phone = normalize_phone(body.phone)
        resident_user = await session.scalar(select(User).where(User.phone == phone))
        if resident_user is None:
            resident_user = User(full_name=body.full_name, phone=phone, role="resident", language=body.language,
                                 is_demo=body.is_demo)
            session.add(resident_user)
            await session.flush()
    try:
        r = await residents_svc.register(session, ctx, body, user=resident_user, phone=body.phone,
                                         registered_via="assisted", actor=actor_of(user), is_demo=body.is_demo)
        await finalize(session, ctx)
    except IntegrityError as exc:
        raise Conflict("duplicate", "A resident or contact with this phone already exists") from exc
    return await views.resident_out(session, r)


@router.post("/residents/{resident_id}/reverify", response_model=S.ResidentOut)
async def admin_reverify(resident_id: str, user: User = Depends(admin_user),
                         session: AsyncSession = Depends(get_session), ctx: AppContext = Depends(get_ctx)):
    r = await session.get(Resident, resident_id)
    if r is None:
        raise NotFound("Resident")
    await residents_svc.reverify(session, ctx, r, actor_of(user), granted_by="assisted")
    await finalize(session, ctx)
    return await views.resident_out(session, r)


@router.post("/residents/{resident_id}/withdraw", response_model=S.ResidentOut)
async def admin_withdraw(resident_id: str, body: S.RejectIn, user: User = Depends(admin_user),
                         session: AsyncSession = Depends(get_session), ctx: AppContext = Depends(get_ctx)):
    r = await session.get(Resident, resident_id)
    if r is None:
        raise NotFound("Resident")
    await residents_svc.withdraw(session, ctx, r, actor_of(user), body.reason)
    await finalize(session, ctx)
    return await views.resident_out(session, r)


@router.delete("/residents/{resident_id}", status_code=204,
               summary="Erase a resident's registry record (deletion request). Reason is audited.")
async def delete_resident(resident_id: str, reason: str = Query(min_length=5, max_length=300),
                          user: User = Depends(admin_user), session: AsyncSession = Depends(get_session),
                          ctx: AppContext = Depends(get_ctx)):
    r = await session.get(Resident, resident_id)
    if r is None:
        raise NotFound("Resident")
    await session.delete(r)
    audit(session, actor_of(user), "resident.erase", "resident", resident_id, reason=reason)
    await finalize(session, ctx)


# ----------------------------------------------------------------------------- volunteers
@router.get("/volunteers", response_model=list[S.VolunteerOut])
async def list_volunteers(_: User = Depends(ops_or_admin), session: AsyncSession = Depends(get_session)):
    rows = (await session.execute(select(Volunteer))).scalars().all()
    return sorted([await views.volunteer_out(session, v) for v in rows], key=lambda v: v.full_name)


@router.post("/volunteers", response_model=S.VolunteerOut, status_code=201)
async def create_volunteer(body: S.VolunteerIn, user: User = Depends(admin_user),
                           session: AsyncSession = Depends(get_session), ctx: AppContext = Depends(get_ctx)):
    phone = normalize_phone(body.phone)
    u = await session.scalar(select(User).where(User.phone == phone))
    if u is None:
        u = User(full_name=body.full_name, phone=phone, role="volunteer", is_demo=body.is_demo)
        session.add(u)
        await session.flush()
    elif u.role not in ("volunteer", "neighbour"):
        raise Conflict("role_conflict", f"This phone belongs to a {u.role} account")
    u.role = "volunteer"
    if await session.scalar(select(Volunteer.id).where(Volunteer.user_id == u.id)):
        raise Conflict("duplicate", "Already a volunteer")
    v = Volunteer(user_id=u.id, ward_id=body.ward_id, base_lat=body.base_lat, base_lng=body.base_lng,
                  max_radius_m=body.max_radius_m, skills=body.skills, is_demo=body.is_demo)
    session.add(v)
    await session.flush()
    audit(session, actor_of(user), "volunteer.create", "volunteer", v.id)
    await finalize(session, ctx)
    return await views.volunteer_out(session, v)


@router.put("/volunteers/{volunteer_id}/availability", response_model=S.VolunteerOut)
async def admin_availability(volunteer_id: str, body: S.AvailabilityIn, user: User = Depends(ops_or_admin),
                             session: AsyncSession = Depends(get_session), ctx: AppContext = Depends(get_ctx)):
    v = await session.get(Volunteer, volunteer_id)
    if v is None:
        raise NotFound("Volunteer")
    v.is_available = body.is_available
    audit(session, actor_of(user), "volunteer.availability", "volunteer", v.id, after={"available": body.is_available})
    await finalize(session, ctx)
    return await views.volunteer_out(session, v)


@router.put("/volunteers/{volunteer_id}/verified", response_model=S.VolunteerOut)
async def admin_verify_volunteer(volunteer_id: str, verified: bool = Query(...), user: User = Depends(admin_user),
                                 session: AsyncSession = Depends(get_session), ctx: AppContext = Depends(get_ctx)):
    v = await session.get(Volunteer, volunteer_id)
    if v is None:
        raise NotFound("Volunteer")
    v.verified = verified
    audit(session, actor_of(user), "volunteer.verified", "volunteer", v.id, after={"verified": verified})
    await finalize(session, ctx)
    return await views.volunteer_out(session, v)


# ----------------------------------------------------------------------------- neighbour links / helpers
@router.get("/neighbour-links", response_model=list[S.NeighbourLinkOut])
async def list_links(_: User = Depends(admin_user), session: AsyncSession = Depends(get_session)):
    rows = (await session.execute(
        select(NeighbourLink, Resident.full_name, User.full_name)
        .join(Resident, Resident.id == NeighbourLink.resident_id)
        .join(User, User.id == NeighbourLink.neighbour_user_id)
        .order_by(Resident.full_name, NeighbourLink.priority))).all()
    return [S.NeighbourLinkOut(id=link.id, resident_id=link.resident_id, resident_name=rn,
                               neighbour_user_id=link.neighbour_user_id, neighbour_name=nn, priority=link.priority,
                               distance_m=link.distance_m) for link, rn, nn in rows]


@router.post("/neighbour-links", response_model=S.NeighbourLinkOut, status_code=201)
async def create_link(body: S.NeighbourLinkIn, user: User = Depends(admin_user),
                      session: AsyncSession = Depends(get_session), ctx: AppContext = Depends(get_ctx)):
    r = await session.get(Resident, body.resident_id)
    n = await session.get(User, body.neighbour_user_id)
    if r is None or n is None:
        raise NotFound("Resident or neighbour")
    if r.is_demo != n.is_demo:
        raise DomainError("demo_mismatch", "Cannot link demo and real people", 422)
    if r.user_id == n.id:
        raise DomainError("self_link", "A resident cannot be their own neighbour", 422)
    link = NeighbourLink(**body.model_dump())
    session.add(link)
    try:
        await session.flush()
    except IntegrityError as exc:
        raise Conflict("duplicate", "Link already exists") from exc
    audit(session, actor_of(user), "neighbour_link.create", "neighbour_link", link.id)
    await finalize(session, ctx)
    return S.NeighbourLinkOut(id=link.id, resident_id=r.id, resident_name=r.full_name, neighbour_user_id=n.id,
                              neighbour_name=n.full_name, priority=link.priority, distance_m=link.distance_m)


@router.patch("/neighbour-links/{link_id}", response_model=S.NeighbourLinkOut)
async def reorder_link(link_id: str, priority: int = Query(ge=1, le=10), user: User = Depends(admin_user),
                       session: AsyncSession = Depends(get_session), ctx: AppContext = Depends(get_ctx)):
    link = await session.get(NeighbourLink, link_id)
    if link is None:
        raise NotFound("Neighbour link")
    link.priority = priority
    audit(session, actor_of(user), "neighbour_link.priority", "neighbour_link", link.id, after={"priority": priority})
    await finalize(session, ctx)
    r = await session.get(Resident, link.resident_id)
    n = await session.get(User, link.neighbour_user_id)
    return S.NeighbourLinkOut(id=link.id, resident_id=r.id, resident_name=r.full_name, neighbour_user_id=n.id,
                              neighbour_name=n.full_name, priority=link.priority, distance_m=link.distance_m)


@router.delete("/neighbour-links/{link_id}", status_code=204)
async def delete_link(link_id: str, user: User = Depends(admin_user), session: AsyncSession = Depends(get_session),
                      ctx: AppContext = Depends(get_ctx)):
    link = await session.get(NeighbourLink, link_id)
    if link is None:
        raise NotFound("Neighbour link")
    await session.delete(link)
    audit(session, actor_of(user), "neighbour_link.delete", "neighbour_link", link_id)
    await finalize(session, ctx)


@router.get("/pre-assigned", response_model=list[S.PreAssignedOut])
async def list_pre_assigned(_: User = Depends(admin_user), session: AsyncSession = Depends(get_session)):
    rows = (await session.execute(
        select(PreAssignedHelper, Resident.full_name, User.full_name)
        .join(Resident, Resident.id == PreAssignedHelper.resident_id)
        .join(Volunteer, Volunteer.id == PreAssignedHelper.volunteer_id)
        .join(User, User.id == Volunteer.user_id))).all()
    return [S.PreAssignedOut(id=p.id, resident_id=p.resident_id, resident_name=rn, volunteer_id=p.volunteer_id,
                             volunteer_name=vn, priority=p.priority) for p, rn, vn in rows]


@router.post("/pre-assigned", response_model=S.PreAssignedOut, status_code=201)
async def create_pre_assigned(body: S.PreAssignedIn, user: User = Depends(admin_user),
                              session: AsyncSession = Depends(get_session), ctx: AppContext = Depends(get_ctx)):
    r = await session.get(Resident, body.resident_id)
    v = await session.get(Volunteer, body.volunteer_id)
    if r is None or v is None:
        raise NotFound("Resident or volunteer")
    p = PreAssignedHelper(**body.model_dump())
    session.add(p)
    try:
        await session.flush()
    except IntegrityError as exc:
        raise Conflict("duplicate", "Already pre-assigned") from exc
    audit(session, actor_of(user), "pre_assigned.create", "pre_assigned_helper", p.id)
    await finalize(session, ctx)
    vu = await session.get(User, v.user_id)
    return S.PreAssignedOut(id=p.id, resident_id=r.id, resident_name=r.full_name, volunteer_id=v.id,
                            volunteer_name=vu.full_name, priority=p.priority)


@router.delete("/pre-assigned/{pid}", status_code=204)
async def delete_pre_assigned(pid: str, user: User = Depends(admin_user), session: AsyncSession = Depends(get_session),
                              ctx: AppContext = Depends(get_ctx)):
    p = await session.get(PreAssignedHelper, pid)
    if p is None:
        raise NotFound("Pre-assigned helper")
    await session.delete(p)
    audit(session, actor_of(user), "pre_assigned.delete", "pre_assigned_helper", pid)
    await finalize(session, ctx)


# ----------------------------------------------------------------------------- templates
@router.get("/templates", response_model=list[S.TemplateOut])
async def list_templates(_: User = Depends(admin_user), session: AsyncSession = Depends(get_session)):
    rows = (await session.execute(select(AlertTemplate).order_by(AlertTemplate.hazard_type, AlertTemplate.language,
                                                                 AlertTemplate.style))).scalars().all()
    return [S.TemplateOut.model_validate(t) for t in rows]


@router.post("/templates", response_model=S.TemplateOut, status_code=201)
async def upsert_template(body: S.TemplateIn, user: User = Depends(admin_user),
                          session: AsyncSession = Depends(get_session), ctx: AppContext = Depends(get_ctx)):
    t = await session.scalar(select(AlertTemplate).where(
        AlertTemplate.hazard_type == body.hazard_type, AlertTemplate.language == body.language,
        AlertTemplate.style == body.style))
    before = None
    if t is None:
        t = AlertTemplate(**body.model_dump())
        session.add(t)
    else:
        before = {"title": t.title, "body": t.body}
        for k, v in body.model_dump().items():
            setattr(t, k, v)
    await session.flush()
    audit(session, actor_of(user), "template.upsert", "alert_template", t.id, before=before,
          after={"title": t.title, "body": t.body})
    await finalize(session, ctx)
    return S.TemplateOut.model_validate(t)


# ----------------------------------------------------------------------------- users
@router.get("/users", response_model=S.Page[S.UserAdminOut])
async def list_users(role: str | None = None, q: str | None = Query(None, max_length=60), page: PageParams = Depends(),
                     _: User = Depends(admin_user), session: AsyncSession = Depends(get_session)):
    query = select(User).order_by(User.role, User.full_name)
    if role:
        query = query.where(User.role == role)
    if q:
        query = query.where(or_(User.full_name.ilike(f"%{q}%"), User.email.ilike(f"%{q}%")))
    rows, total = await paged(session, query, page)
    return S.Page(items=[S.UserAdminOut(**views.user_out(u).model_dump(), is_active=u.is_active,
                                        created_at=u.created_at) for u in rows],
                  total=total, limit=page.limit, offset=page.offset)


@router.post("/users", response_model=S.UserAdminOut, status_code=201)
async def create_user(body: S.UserCreateIn, user: User = Depends(admin_user),
                      session: AsyncSession = Depends(get_session), ctx: AppContext = Depends(get_ctx)):
    if body.role in OPS and not (body.email and body.password):
        raise DomainError("password_required", "Admin/operator accounts need an email and a password (10+ chars)", 422)
    if not body.phone and not body.email:
        raise DomainError("contact_required", "Phone or email required", 422)
    u = User(full_name=body.full_name, role=body.role, phone=normalize_phone(body.phone) if body.phone else None,
             email=body.email.lower() if body.email else None, language=body.language, is_demo=body.is_demo,
             password_hash=hash_password(body.password) if body.password else None)
    session.add(u)
    try:
        await session.flush()
    except IntegrityError as exc:
        raise Conflict("duplicate", "Phone or email already registered") from exc
    audit(session, actor_of(user), "user.create", "user", u.id, after={"role": u.role})
    await finalize(session, ctx)
    return S.UserAdminOut(**views.user_out(u).model_dump(), is_active=u.is_active, created_at=u.created_at)


@router.patch("/users/{user_id}", response_model=S.UserAdminOut)
async def patch_user(user_id: str, body: S.UserPatchIn, user: User = Depends(admin_user),
                     session: AsyncSession = Depends(get_session), ctx: AppContext = Depends(get_ctx)):
    u = await session.get(User, user_id)
    if u is None:
        raise NotFound("User")
    if u.id == user.id and (body.is_active is False or (body.role and body.role != "admin")):
        raise DomainError("self_lockout", "You cannot deactivate or demote yourself", 422)
    before = {"role": u.role, "is_active": u.is_active}
    if body.role:
        u.role = body.role
    if body.is_active is not None:
        u.is_active = body.is_active
    audit(session, actor_of(user), "user.update", "user", u.id, before=before,
          after={"role": u.role, "is_active": u.is_active, "phone": mask_phone(u.phone)})
    await finalize(session, ctx)
    return S.UserAdminOut(**views.user_out(u).model_dump(), is_active=u.is_active, created_at=u.created_at)
