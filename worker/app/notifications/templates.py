"""Resident-facing presentation of official alerts.

Rules enforced here:
- The official headline/description/instruction are passed through VERBATIM — never rewritten.
- AapdaSaathi framing is labelled as such ("AapdaSaathi") so it is never mistaken for official text.
- No instructions, shelters or routes are invented. If the official message has no instruction,
  we say so and point to the official source.
- Admin-edited templates (alert_templates) may change only the framing; placeholders insert official text.
"""

from __future__ import annotations

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import AlertTemplate, Incident

# Accessibility needs → presentation behaviours. Applied as a UNION: no need silently drops another's.
NEED_MODES: dict[str, list[str]] = {
    "hearing": ["vibrate", "flash_screen", "torch_blink", "large_text", "pictograms"],
    "vision": ["text_to_speech", "voice_prompts", "large_controls"],
    "mobility": ["assistance_prompt"],
    "bedridden": ["assistance_prompt"],
    "cognitive": ["easy_read", "pictograms", "step_by_step", "large_controls"],
    "elderly_alone": ["large_text", "repeat_reminders", "large_controls"],
    "speech": ["no_voice_response"],
    "feature_phone": ["sms_only"],
}


def accessibility_modes(needs: list[str]) -> list[str]:
    modes: list[str] = []
    for need in needs:
        for m in NEED_MODES.get(need, []):
            if m not in modes:
                modes.append(m)
    return modes


HAZARD_PICTOGRAM = {
    "flood": "flood",
    "landslide": "landslide",
    "cloudburst": "flood",
    "thunderstorm": "storm",
    "earthquake": "earthquake",
    "fire": "fire",
}


def pictogram_for(hazard_type: str) -> str:
    h = (hazard_type or "").lower()
    for key, pic in HAZARD_PICTOGRAM.items():
        if key in h:
            return pic
    return "warning"


DEFAULTS = {
    ("en", "standard"): (
        "AapdaSaathi: {event} alert",
        "Official alert from {sender}: {headline}\nInstruction: {instruction}",
    ),
    ("hi", "standard"): (
        "आपदा साथी: {event} चेतावनी",
        "{sender} की आधिकारिक चेतावनी: {headline}\nनिर्देश: {instruction}",
    ),
    ("en", "easy_read"): (
        "Danger: {event}",
        "There is danger near you: {event}.\nOfficial message: {headline}\nTell us if you are safe.",
    ),
    ("hi", "easy_read"): (
        "खतरा: {event}",
        "आपके पास खतरा है: {event}।\nआधिकारिक संदेश: {headline}\nबताइए आप सुरक्षित हैं या नहीं।",
    ),
    ("en", "sms"): (
        "AapdaSaathi",
        "AapdaSaathi ALERT ({sender}): {headline} Reply 1=SAFE 2=HELP",
    ),
    ("hi", "sms"): (
        "AapdaSaathi",
        "आपदा साथी चेतावनी ({sender}): {headline} उत्तर दें 1=सुरक्षित 2=मदद",
    ),
}

NO_INSTRUCTION = {
    "en": "No instruction was included in the official message. Follow local authority guidance.",
    "hi": "आधिकारिक संदेश में कोई निर्देश नहीं है। स्थानीय प्रशासन के निर्देशों का पालन करें।",
}


class _SafeDict(dict):
    def __missing__(self, key):
        return "{" + key + "}"


def _fields(incident: Incident, language: str) -> dict[str, str]:
    return {
        "event": incident.hazard_type,
        "sender": incident.cap_sender or "District authority",
        "headline": (incident.headline or incident.title or "").strip(),
        "instruction": (incident.instruction or NO_INSTRUCTION.get(language, NO_INSTRUCTION["en"])).strip(),
        "area": incident.area_desc or "",
    }


async def render(
    session: AsyncSession, incident: Incident, language: str, style: str
) -> tuple[str, str]:
    language = language if language in ("en", "hi") else "en"
    tpl = (
        await session.execute(
            select(AlertTemplate).where(
                AlertTemplate.hazard_type.in_([incident.hazard_type, "*"]),
                AlertTemplate.language == language,
                AlertTemplate.style == style,
                AlertTemplate.is_active.is_(True),
            )
        )
    ).scalars().all()
    chosen = next((t for t in tpl if t.hazard_type == incident.hazard_type), None) or (tpl[0] if tpl else None)
    title_t, body_t = (chosen.title, chosen.body) if chosen else DEFAULTS[(language, style)]
    f = _SafeDict(_fields(incident, language))
    return title_t.format_map(f), body_t.format_map(f)


def neighbour_check_sms(language: str, resident_name: str, hazard: str) -> str:
    if language == "hi":
        return (
            f"आपदा साथी: {hazard} चेतावनी। कृपया पड़ोसी {resident_name} की जाँच करें (केवल सुरक्षित हो तो)। "
            "उत्तर: 1=सुरक्षित 2=मदद चाहिए 3=नहीं पहुँच सका"
        )
    return (
        f"AapdaSaathi: {hazard} alert. Please check on your neighbour {resident_name} only if it is safe "
        "for you. Reply 1=SAFE 2=NEEDS HELP 3=CANNOT REACH"
    )


def reply_ack_sms(language: str, action: str) -> str:
    msgs = {
        ("en", "SAFE"): "AapdaSaathi: Marked SAFE. Thank you. Keep following official instructions.",
        ("en", "HELP"): "AapdaSaathi: Help request received. A helper/control room is being notified.",
        ("en", "CANNOT_REACH"): "AapdaSaathi: Noted. A volunteer/control room is being notified. Stay safe.",
        ("hi", "SAFE"): "आपदा साथी: आप सुरक्षित दर्ज हैं। आधिकारिक निर्देशों का पालन करते रहें।",
        ("hi", "HELP"): "आपदा साथी: मदद अनुरोध मिला। सहायक/नियंत्रण कक्ष को सूचित किया जा रहा है।",
        ("hi", "CANNOT_REACH"): "आपदा साथी: दर्ज किया गया। स्वयंसेवक/नियंत्रण कक्ष को सूचित किया जा रहा है।",
    }
    return msgs.get((language, action)) or msgs[("en", action)]


def reply_reject_sms(language: str, reason: str) -> str:
    if language == "hi":
        return f"आपदा साथी: उत्तर दर्ज नहीं हुआ ({reason})। 1=सुरक्षित 2=मदद भेजें या 112 पर कॉल करें।"
    return f"AapdaSaathi: reply not recorded ({reason}). Send 1=SAFE or 2=HELP, or call 112."
