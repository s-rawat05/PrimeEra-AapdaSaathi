"""Seed the fictional demo environment. Idempotent: re-running only adds what is missing.

Every person, phone number, ward and relief post here is FICTIONAL. Demo SMS always goes to the
simulator unless a number is explicitly allow-listed (DEMO_SMS_ALLOWLIST) for a live demo.

Run:  python -m app.demo.seed
"""

from __future__ import annotations

import asyncio
import json
import os
from datetime import timedelta
from pathlib import Path

from shapely.geometry import shape
from sqlalchemy import select

from app.config import get_settings
from app.db import db, utcnow
from app.models import (
    AlertTemplate,
    CaregiverLink,
    ConsentRecord,
    NeighbourLink,
    PreAssignedHelper,
    Resident,
    ResidentLocation,
    Shelter,
    User,
    Volunteer,
    Ward,
)
from app.notifications.templates import DEFAULTS

FIXTURES_DIR = Path(os.environ.get("FIXTURES_DIR") or Path(__file__).resolve().parents[3] / "fixtures")

OPS = [
    (
        "demo-admin",
        "Priya Nair (Demo Admin)",
        "admin",
        "+919000000101",
        "admin@demo.aapdasaathi.invalid",
        "Configures wards, registry, volunteers and templates.",
    ),
    (
        "demo-operator",
        "Arjun Mehta (Control Room)",
        "operator",
        "+919000000102",
        "operator@demo.aapdasaathi.invalid",
        "Runs the live command centre: approvals, overrides, reports.",
    ),
]

# key, name, ward, lang, needs, lives_alone, smartphone, phone, (dlat, dlng) offset inside ward, description
RESIDENTS = [
    (
        "kamla",
        "Kamla Devi Bisht",
        "DW-01",
        "hi",
        ["elderly_alone", "mobility"],
        True,
        True,
        "+919000000001",
        (0.0021, 0.0032),
        "78, lives alone, uses a walker. Caregiver: daughter Neha. Pre-assigned helper.",
    ),
    (
        "ramesh",
        "Ramesh Joshi",
        "DW-01",
        "en",
        ["hearing"],
        False,
        True,
        "+919000000002",
        (0.0060, 0.0050),
        "Deaf; app alerts flash the screen, vibrate and blink the torch.",
    ),
    (
        "govind",
        "Govind Singh Negi",
        "DW-01",
        "hi",
        ["feature_phone"],
        False,
        False,
        "+919000000003",
        (0.0035, 0.0080),
        "Feature phone only — replies by SMS '1' or '2'.",
    ),
    (
        "sunita",
        "Sunita Rawat",
        "DW-01",
        "hi",
        ["mobility"],
        False,
        True,
        "+919000000004",
        (0.0040, 0.0105),
        "Wheelchair user; neighbour Vikram is linked.",
    ),
    (
        "mohan",
        "Mohan Lal Arya",
        "DW-01",
        "hi",
        ["bedridden"],
        True,
        False,
        "+919000000005",
        (0.0075, 0.0090),
        "Bedridden, lives alone, feature phone. Neighbour Vikram, then Pooja.",
    ),
    (
        "anita",
        "Anita Negi",
        "DW-01",
        "en",
        ["vision"],
        False,
        True,
        "+919000000006",
        (0.0050, 0.0020),
        "Blind; alerts are spoken aloud with screen-reader labels.",
    ),
    (
        "bhuwan",
        "Bhuwan Chandra",
        "DW-01",
        "hi",
        ["cognitive"],
        False,
        True,
        "+919000000007",
        (0.0085, 0.0040),
        "Easy-read pictogram alerts, one step at a time.",
    ),
    (
        "pushpa",
        "Pushpa Arya",
        "DW-01",
        "hi",
        ["speech"],
        False,
        True,
        "+919000000008",
        (0.0015, 0.0110),
        "Speech impairment; responds by tap or SMS only.",
    ),
    ("harish", "Harish Pant", "DW-01", "en", [], False, True, "+919000000009", (0.0065, 0.0120), "No declared needs."),
    (
        "deepa",
        "Deepa Kandpal",
        "DW-01",
        "hi",
        ["hearing", "elderly_alone"],
        True,
        True,
        "+919000000010",
        (0.0090, 0.0015),
        "Combined profile: hearing + elderly living alone.",
    ),
    (
        "naveen",
        "Naveen Tiwari",
        "DW-01",
        "en",
        [],
        False,
        True,
        "+919000000011",
        (0.0025, 0.0060),
        "No declared needs.",
    ),
    (
        "leela",
        "Leela Bhatt",
        "DW-01",
        "hi",
        ["vision", "mobility"],
        False,
        True,
        "+919000000012",
        (0.0055, 0.0070),
        "Combined profile: low vision + mobility limitation.",
    ),
    (
        "kishan",
        "Kishan Ram",
        "DW-01",
        "hi",
        ["feature_phone"],
        True,
        False,
        "+919000000013",
        (0.0080, 0.0125),
        "Feature phone that is switched off in the simulator → UNREACHABLE.",
    ),
    (
        "meena",
        "Meena Kumari",
        "DW-01",
        "hi",
        ["elderly_alone"],
        True,
        True,
        "+919000000014",
        (0.0010, 0.0045),
        "Elderly, lives alone — shorter escalation intervals and repeated reminders.",
    ),
    ("rahul", "Rahul Mehra", "DW-01", "en", [], False, True, "+919000000015", (0.0045, 0.0030), "No declared needs."),
    (
        "saroj",
        "Saroj Pandey",
        "DW-01",
        "hi",
        ["bedridden", "cognitive"],
        False,
        True,
        "+919000000016",
        (0.0070, 0.0025),
        "Bedridden; registered with guardian consent.",
    ),
    (
        "tara",
        "Tara Datt",
        "DW-02",
        "hi",
        [],
        False,
        True,
        "+919000000017",
        (0.0040, 0.0040),
        "Lives in the second demo ward.",
    ),
    (
        "gita",
        "Gita Bora",
        "DW-02",
        "hi",
        ["cognitive", "feature_phone"],
        True,
        False,
        "+919000000018",
        (0.0060, 0.0080),
        "Combined profile: easy-read + feature phone.",
    ),
    (
        "prakash",
        "Prakash Rana",
        "DW-01",
        "en",
        [],
        False,
        True,
        "+919000000019",
        (0.0030, 0.0095),
        "Consent EXPIRED — demonstrates re-verification (not alerted).",
    ),
]

HELPERS = [
    # key, name, role, phone, lang, description
    ("neha", "Neha Bisht", "caregiver", "+919000000201", "hi", "Caregiver (daughter) of Kamla Devi and Saroj."),
    ("vikram", "Vikram Rawat", "neighbour", "+919000000202", "hi", "Neighbour linked to Sunita, Mohan and Kamla."),
    ("pooja", "Pooja Joshi", "neighbour", "+919000000203", "en", "Second-priority neighbour for Mohan and Leela."),
    ("aman", "Aman Verma (NSS)", "volunteer", "+919000000301", "en", "Verified volunteer ~400 m from the ward."),
    ("sneha", "Sneha Karki (NCC)", "volunteer", "+919000000302", "hi", "Verified volunteer stationed in the ward."),
    ("dev", "Dev Bisht (Civil Defence)", "volunteer", "+919000000303", "en", "Volunteer 6 km away — outside radius."),
]

VOLUNTEER_BASE = {
    "aman": ("DW-01", 29.3480, 79.5575, 3000),
    "sneha": ("DW-01", 29.3500, 79.5660, 3000),
    "dev": (None, 29.3920, 79.5200, 3000),
}

SHELTERS = [
    (
        "DW-01",
        "Demo Relief Post A — Community Hall (fictional)",
        "Upper lane, Sarovar Nagar (fictional)",
        29.3545,
        79.5560,
    ),
    ("DW-02", "Demo Relief Post B — School Ground (fictional)", "Hill road, Pahadi Tola (fictional)", 29.3540, 79.5740),
]


def persona_descriptions() -> dict[str, str]:
    """Phone → persona description, for the demo login picker."""
    out = {o[3]: o[5] for o in OPS}
    out.update({r[7]: r[9] for r in RESIDENTS})
    out.update({h[3]: h[5] for h in HELPERS})
    return out


async def seed_demo(now=None) -> dict:
    now = now or utcnow()
    settings = get_settings()
    stats = {"wards": 0, "users": 0, "residents": 0, "volunteers": 0}
    async with db.session() as s:
        fc = json.loads((FIXTURES_DIR / "geojson" / "demo_wards.geojson").read_text(encoding="utf-8"))
        wards: dict[str, Ward] = {}
        for f in fc["features"]:
            p = f["properties"]
            w = await s.scalar(select(Ward).where(Ward.code == p["code"]))
            if w is None:
                c = shape(f["geometry"]).centroid
                w = Ward(
                    code=p["code"],
                    name=p["name"],
                    district=p["district"],
                    state=p["state"],
                    lgd_district_code=p.get("lgd_district_code"),
                    boundary_geojson=f["geometry"],
                    centroid_lat=round(c.y, 6),
                    centroid_lng=round(c.x, 6),
                    is_demo=True,
                )
                s.add(w)
                stats["wards"] += 1
            wards[p["code"]] = w
        await s.flush()

        for code, name, addr, lat, lng in SHELTERS:
            if not await s.scalar(select(Shelter.id).where(Shelter.name == name)):
                s.add(
                    Shelter(
                        ward_id=wards[code].id,
                        name=name,
                        address=addr,
                        lat=lat,
                        lng=lng,
                        source="Fictional designation for the demo",
                        is_demo=True,
                    )
                )

        users: dict[str, User] = {}

        async def ensure_user(key, name, role, phone, lang, email=None) -> User:
            u = await s.scalar(select(User).where(User.phone == phone))
            if u is None:
                u = User(full_name=name, role=role, phone=phone, email=email, language=lang, is_demo=True)
                s.add(u)
                await s.flush()
                stats["users"] += 1
            users[key] = u
            return u

        for key, name, role, phone, email, _ in OPS:
            await ensure_user(key, name, role, phone, "en", email)
        for key, name, role, phone, lang, _ in HELPERS:
            await ensure_user(key, name, role, phone, lang)

        residents: dict[str, Resident] = {}
        for idx, (key, name, wcode, lang, needs, alone, smart, phone, (dlat, dlng), _) in enumerate(RESIDENTS):
            r = await s.scalar(select(Resident).where(Resident.phone == phone, Resident.is_demo.is_(True)))
            if r is None:
                w = wards[wcode]
                base_lat, base_lng = (
                    w.boundary_geojson["coordinates"][0][0][1],
                    w.boundary_geojson["coordinates"][0][0][0],
                )
                lat, lng = round(base_lat + dlat, 6), round(base_lng + dlng, 6)
                u = await ensure_user(key, name, "resident", phone, lang) if smart else None
                expired = key == "prakash"
                granted_at = now - timedelta(days=120) if expired else now
                expires = granted_at + timedelta(days=settings.consent_validity_days)
                r = Resident(
                    user_id=u.id if u else None,
                    full_name=name,
                    phone=phone,
                    ward_id=w.id,
                    language=lang,
                    needs=needs,
                    lives_alone=alone,
                    has_smartphone=smart,
                    coarse_lat=round(lat, 3),
                    coarse_lng=round(lng, 3),
                    registered_via="assisted" if not smart else "self",
                    reverify_due_at=expires,
                    is_demo=True,
                    registration_status="active",
                )
                s.add(r)
                await s.flush()
                s.add(
                    ResidentLocation(
                        resident_id=r.id,
                        lat=lat,
                        lng=lng,
                        address_text=f"House {idx * 7 + 11}, {w.name}",
                        landmark="Fictional landmark",
                        source="registration",
                    )
                )
                by = "guardian" if key == "saroj" else ("assisted" if not smart else "self")
                for ctype in ("registry", "location", "caregiver_share"):
                    s.add(
                        ConsentRecord(
                            resident_id=r.id,
                            consent_type=ctype,
                            granted=True,
                            granted_by=by,
                            guardian_name="Rekha Pandey (fictional)" if by == "guardian" else None,
                            granted_at=granted_at,
                            expires_at=expires,
                        )
                    )
                stats["residents"] += 1
            residents[key] = r
        await s.flush()

        async def link(model, **kw):
            q = select(model)
            for k, v in kw.items():
                if k in ("resident_id", "caregiver_user_id", "neighbour_user_id", "volunteer_id"):
                    q = q.where(getattr(model, k) == v)
            if await s.scalar(q) is None:
                s.add(model(**kw))

        await link(
            CaregiverLink,
            caregiver_user_id=users["neha"].id,
            resident_id=residents["kamla"].id,
            relationship="daughter",
            can_view_location=True,
        )
        await link(
            CaregiverLink,
            caregiver_user_id=users["neha"].id,
            resident_id=residents["saroj"].id,
            relationship="relative",
            can_view_location=True,
        )
        for res_key, nb_key, prio, dist in [
            ("sunita", "vikram", 1, 60),
            ("mohan", "vikram", 1, 90),
            ("mohan", "pooja", 2, 150),
            ("kamla", "vikram", 1, 120),
            ("leela", "pooja", 1, 80),
            ("deepa", "pooja", 1, 110),
        ]:
            await link(
                NeighbourLink,
                resident_id=residents[res_key].id,
                neighbour_user_id=users[nb_key].id,
                priority=prio,
                distance_m=dist,
            )

        vols: dict[str, Volunteer] = {}
        for key, (wcode, lat, lng, radius) in VOLUNTEER_BASE.items():
            v = await s.scalar(select(Volunteer).where(Volunteer.user_id == users[key].id))
            if v is None:
                v = Volunteer(
                    user_id=users[key].id,
                    ward_id=wards[wcode].id if wcode else None,
                    base_lat=lat,
                    base_lng=lng,
                    max_radius_m=radius,
                    skills=["first_aid", "evacuation_support"],
                    is_demo=True,
                )
                s.add(v)
                stats["volunteers"] += 1
            vols[key] = v
        await s.flush()
        await link(PreAssignedHelper, resident_id=residents["kamla"].id, volunteer_id=vols["aman"].id, priority=1)

        for (lang, style), (title, body) in DEFAULTS.items():
            exists = await s.scalar(
                select(AlertTemplate.id).where(
                    AlertTemplate.hazard_type == "*", AlertTemplate.language == lang, AlertTemplate.style == style
                )
            )
            if not exists:
                s.add(AlertTemplate(hazard_type="*", language=lang, style=style, title=title, body=body))
        await s.commit()
    return stats


async def _main() -> None:
    settings = get_settings()
    db.init(settings.database_url)
    if db.is_sqlite:
        await db.create_all()
    print(await seed_demo())
    await db.dispose()


if __name__ == "__main__":
    asyncio.run(_main())
