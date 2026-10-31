"""CAP 1.2 parsing and validation (OASIS Common Alerting Protocol).

Uses defusedxml to block entity-expansion / external-entity attacks. The original XML is never
modified — callers store it verbatim and keep this parse result alongside it.
"""

from __future__ import annotations

from dataclasses import asdict, dataclass, field
from datetime import datetime

from defusedxml import ElementTree as SafeET
from defusedxml.common import DefusedXmlException

CAP_NS = "urn:oasis:names:tc:emergency:cap:1.2"
_NS = {"cap": CAP_NS}

STATUS = {"Actual", "Exercise", "System", "Test", "Draft"}
MSG_TYPES = {"Alert", "Update", "Cancel", "Ack", "Error"}
SCOPES = {"Public", "Restricted", "Private"}
URGENCY = {"Immediate", "Expected", "Future", "Past", "Unknown"}
SEVERITY = {"Extreme", "Severe", "Moderate", "Minor", "Unknown"}
CERTAINTY = {"Observed", "Likely", "Possible", "Unlikely", "Unknown", "Very Likely"}
SEVERITY_RANK = {"Extreme": 4, "Severe": 3, "Moderate": 2, "Minor": 1, "Unknown": 0}
URGENCY_RANK = {"Immediate": 4, "Expected": 3, "Future": 2, "Past": 1, "Unknown": 0}


class CapParseError(ValueError):
    """Raised for XML that is unsafe, malformed or not a CAP 1.2 <alert>."""


@dataclass
class CapArea:
    area_desc: str
    polygons: list[list[list[float]]] = field(default_factory=list)  # GeoJSON rings [[lon, lat], ...]
    circles: list[dict] = field(default_factory=list)  # {lat, lng, radius_km}
    geocodes: dict[str, list[str]] = field(default_factory=dict)


@dataclass
class CapInfo:
    language: str
    categories: list[str]
    event: str
    urgency: str
    severity: str
    certainty: str
    effective: datetime | None
    onset: datetime | None
    expires: datetime | None
    sender_name: str | None
    headline: str | None
    description: str | None
    instruction: str | None
    web: str | None
    parameters: dict[str, list[str]]
    areas: list[CapArea]


@dataclass
class CapReference:
    sender: str
    identifier: str
    sent: str


@dataclass
class CapAlert:
    identifier: str
    sender: str
    sent: datetime
    status: str
    msg_type: str
    scope: str
    references: list[CapReference]
    references_raw: str | None
    infos: list[CapInfo]
    validation_errors: list[str]

    @property
    def is_valid(self) -> bool:
        return not self.validation_errors

    def primary_info(self, prefer_language: str = "en") -> CapInfo | None:
        """The info block in the preferred language, else the first one."""
        for info in self.infos:
            if info.language.lower().startswith(prefer_language.lower()):
                return info
        return self.infos[0] if self.infos else None

    def info_in(self, language: str) -> CapInfo | None:
        for info in self.infos:
            if info.language.lower().startswith(language.lower()):
                return info
        return None

    def to_dict(self) -> dict:
        def conv(o):
            if isinstance(o, datetime):
                return o.isoformat()
            if isinstance(o, dict):
                return {k: conv(v) for k, v in o.items()}
            if isinstance(o, list):
                return [conv(v) for v in o]
            return o

        return conv(asdict(self))


def _text(el, path: str) -> str | None:
    found = el.find(path, _NS)
    if found is None or found.text is None:
        return None
    value = found.text.strip()
    return value or None


def _texts(el, path: str) -> list[str]:
    return [t.text.strip() for t in el.findall(path, _NS) if t.text and t.text.strip()]


def parse_cap_datetime(value: str | None) -> datetime | None:
    if not value:
        return None
    try:
        dt = datetime.fromisoformat(value.strip())
    except ValueError:
        return None
    return dt if dt.tzinfo else None  # CAP requires an explicit offset


def parse_polygon(value: str) -> list[list[float]]:
    """CAP polygons are 'lat,lon lat,lon ...' — convert to a GeoJSON ring of [lon, lat]."""
    ring: list[list[float]] = []
    for pair in value.split():
        lat_s, lon_s = pair.split(",")[:2]
        lat, lon = float(lat_s), float(lon_s)
        if not (-90 <= lat <= 90 and -180 <= lon <= 180):
            raise ValueError(f"coordinate out of range: {pair}")
        ring.append([lon, lat])
    if len(ring) < 4:
        raise ValueError("polygon needs at least 4 points")
    if ring[0] != ring[-1]:
        raise ValueError("polygon ring is not closed")
    return ring


def parse_circle(value: str) -> dict:
    point, radius = value.split()
    lat_s, lon_s = point.split(",")
    return {"lat": float(lat_s), "lng": float(lon_s), "radius_km": float(radius)}


def parse_references(raw: str | None) -> list[CapReference]:
    refs = []
    for triple in (raw or "").split():
        parts = triple.split(",")
        if len(parts) >= 3:
            refs.append(CapReference(parts[0], parts[1], ",".join(parts[2:])))
    return refs


def _check(value: str | None, allowed: set[str], name: str, errors: list[str]) -> None:
    if value is None:
        errors.append(f"missing <{name}>")
    elif value not in allowed:
        errors.append(f"invalid <{name}> '{value}'")


def parse_cap(xml: str | bytes) -> CapAlert:
    try:
        root = SafeET.fromstring(xml)
    except DefusedXmlException as exc:
        raise CapParseError(f"unsafe XML rejected: {type(exc).__name__}") from exc
    except SafeET.ParseError as exc:
        raise CapParseError(f"malformed XML: {exc}") from exc

    if root.tag != f"{{{CAP_NS}}}alert":
        raise CapParseError(f"not a CAP 1.2 alert (root element {root.tag!r})")

    errors: list[str] = []
    identifier = _text(root, "cap:identifier")
    sender = _text(root, "cap:sender")
    sent = parse_cap_datetime(_text(root, "cap:sent"))
    status = _text(root, "cap:status")
    msg_type = _text(root, "cap:msgType")
    scope = _text(root, "cap:scope")
    if not identifier:
        raise CapParseError("missing <identifier>")
    if not sender:
        errors.append("missing <sender>")
    if sent is None:
        errors.append("missing or invalid <sent> (must include a UTC offset)")
    _check(status, STATUS, "status", errors)
    _check(msg_type, MSG_TYPES, "msgType", errors)
    _check(scope, SCOPES, "scope", errors)
    references_raw = _text(root, "cap:references")
    if msg_type in ("Update", "Cancel") and not references_raw:
        errors.append(f"<references> required for msgType {msg_type}")

    infos: list[CapInfo] = []
    for i, info_el in enumerate(root.findall("cap:info", _NS)):
        urgency = _text(info_el, "cap:urgency")
        severity = _text(info_el, "cap:severity")
        certainty = _text(info_el, "cap:certainty")
        event = _text(info_el, "cap:event")
        categories = _texts(info_el, "cap:category")
        if not categories:
            errors.append(f"info[{i}]: missing <category>")
        if not event:
            errors.append(f"info[{i}]: missing <event>")
        _check(urgency, URGENCY, f"info[{i}].urgency", errors)
        _check(severity, SEVERITY, f"info[{i}].severity", errors)
        _check(certainty, CERTAINTY, f"info[{i}].certainty", errors)

        params: dict[str, list[str]] = {}
        for p in info_el.findall("cap:parameter", _NS):
            name = _text(p, "cap:valueName")
            val = _text(p, "cap:value")
            if name and val:
                params.setdefault(name, []).append(val)

        areas: list[CapArea] = []
        for a_el in info_el.findall("cap:area", _NS):
            area = CapArea(area_desc=_text(a_el, "cap:areaDesc") or "")
            for poly in _texts(a_el, "cap:polygon"):
                try:
                    area.polygons.append(parse_polygon(poly))
                except (ValueError, IndexError) as exc:
                    errors.append(f"info[{i}]: invalid polygon ({exc})")
            for circ in _texts(a_el, "cap:circle"):
                try:
                    area.circles.append(parse_circle(circ))
                except (ValueError, IndexError) as exc:
                    errors.append(f"info[{i}]: invalid circle ({exc})")
            for g in a_el.findall("cap:geocode", _NS):
                name = _text(g, "cap:valueName")
                val = _text(g, "cap:value")
                if name and val:
                    area.geocodes.setdefault(name, []).append(val)
            areas.append(area)

        infos.append(
            CapInfo(
                language=_text(info_el, "cap:language") or "en-US",
                categories=categories,
                event=event or "",
                urgency=urgency or "Unknown",
                severity=severity or "Unknown",
                certainty=certainty or "Unknown",
                effective=parse_cap_datetime(_text(info_el, "cap:effective")),
                onset=parse_cap_datetime(_text(info_el, "cap:onset")),
                expires=parse_cap_datetime(_text(info_el, "cap:expires")),
                sender_name=_text(info_el, "cap:senderName"),
                headline=_text(info_el, "cap:headline"),
                description=_text(info_el, "cap:description"),
                instruction=_text(info_el, "cap:instruction"),
                web=_text(info_el, "cap:web"),
                parameters=params,
                areas=areas,
            )
        )

    if msg_type in ("Alert", "Update") and not infos:
        errors.append("Alert/Update without <info> block")

    return CapAlert(
        identifier=identifier,
        sender=sender or "",
        sent=sent or datetime.fromtimestamp(0).astimezone(),
        status=status or "Unknown",
        msg_type=msg_type or "Unknown",
        scope=scope or "Unknown",
        references=parse_references(references_raw),
        references_raw=references_raw,
        infos=infos,
        validation_errors=errors,
    )


def lgd_district_codes(alert: CapAlert) -> set[str]:
    codes: set[str] = set()
    for info in alert.infos:
        for area in info.areas:
            for name, values in area.geocodes.items():
                if "lgd" in name.lower() and "district" in name.lower():
                    codes.update(values)
    return codes


def area_polygons(alert: CapAlert) -> list[list[list[float]]]:
    out: list[list[list[float]]] = []
    seen: set[str] = set()
    for info in alert.infos:
        for area in info.areas:
            for ring in area.polygons:
                key = repr(ring)
                if key not in seen:
                    seen.add(key)
                    out.append(ring)
    return out
