"""SMS gateway adapters and reply parsing.

- SimulatorSmsGateway: records messages in notification_attempts (status 'simulated') so the
  Feature-phone simulator in the command center shows exactly what a phone would receive.
- HttpSmsGateway: sends through httpSMS (https://httpsms.com, self-hostable Android SMS gateway).
"""

from __future__ import annotations

import logging
import re
import uuid
from dataclasses import dataclass
from typing import Protocol

import httpx
import jwt

from app.config import Settings

log = logging.getLogger(__name__)

E164 = re.compile(r"^\+[1-9]\d{7,14}$")


def normalize_phone(raw: str) -> str:
    """Normalise Indian numbers to E.164. Raises ValueError for anything unparseable."""
    digits = re.sub(r"[^\d+]", "", raw or "")
    if digits.startswith("00"):
        digits = "+" + digits[2:]
    if not digits.startswith("+"):
        digits = digits.lstrip("0")
        if len(digits) == 10:
            digits = "+91" + digits
        else:
            digits = "+" + digits
    if not E164.match(digits):
        raise ValueError("invalid phone number")
    return digits


def mask_phone(phone: str | None) -> str:
    if not phone:
        return "—"
    return phone[:3] + "•" * max(len(phone) - 7, 0) + phone[-4:]


@dataclass(frozen=True)
class SmsSendResult:
    ok: bool
    provider: str
    provider_message_id: str | None
    error: str | None = None
    simulated: bool = False


class SmsGateway(Protocol):
    name: str

    async def send(self, to: str, body: str) -> SmsSendResult: ...


class SimulatorSmsGateway:
    name = "simulator"

    def __init__(self, unreachable: set[str] | None = None) -> None:
        self.unreachable = unreachable or set()

    async def send(self, to: str, body: str) -> SmsSendResult:
        if to in self.unreachable:
            return SmsSendResult(False, self.name, None, "Simulated: handset switched off", simulated=True)
        return SmsSendResult(True, self.name, f"sim-{uuid.uuid4().hex[:12]}", simulated=True)


class HttpSmsGateway:
    name = "httpsms"

    def __init__(self, settings: Settings, client: httpx.AsyncClient | None = None) -> None:
        self.url = settings.httpsms_api_url
        self.api_key = settings.httpsms_api_key
        self.from_number = settings.httpsms_from_number
        self._client = client

    async def send(self, to: str, body: str) -> SmsSendResult:
        if not self.api_key or not self.from_number:
            return SmsSendResult(False, self.name, None, "httpSMS not configured")
        payload = {"content": body, "from": self.from_number, "to": to}
        headers = {"x-api-key": self.api_key, "Accept": "application/json"}
        client = self._client or httpx.AsyncClient(timeout=httpx.Timeout(10.0, connect=5.0))
        try:
            resp = await client.post(self.url, json=payload, headers=headers)
            if resp.status_code >= 300:
                return SmsSendResult(False, self.name, None, f"HTTP {resp.status_code}")
            data = resp.json().get("data") or {}
            return SmsSendResult(True, self.name, str(data.get("id") or ""))
        except httpx.HTTPError as exc:
            log.warning("httpSMS send failed: %s", type(exc).__name__)
            return SmsSendResult(False, self.name, None, type(exc).__name__)
        finally:
            if self._client is None:
                await client.aclose()


def build_sms_gateway(settings: Settings) -> SmsGateway:
    if settings.sms_provider == "httpsms":
        return HttpSmsGateway(settings)
    unreachable = {p.strip() for p in settings.sim_unreachable_phones.split(",") if p.strip()}
    return SimulatorSmsGateway(unreachable)


# ---------------------------------------------------------------------------
# Inbound replies
# ---------------------------------------------------------------------------

SAFE, HELP, CANNOT_REACH = "SAFE", "HELP", "CANNOT_REACH"

_WORDS = {
    "1": SAFE,
    "SAFE": SAFE,
    "SURAKSHIT": SAFE,
    "सुरक्षित": SAFE,
    "2": HELP,
    "HELP": HELP,
    "MADAD": HELP,
    "मदद": HELP,
    "3": CANNOT_REACH,
}


def parse_sms_reply(body: str) -> str | None:
    """'1'/'SAFE' → SAFE, '2'/'HELP' → HELP, '3' → CANNOT_REACH (neighbour checks only).

    Only the first token counts, and anything else is rejected as ambiguous rather than guessed.
    """
    tokens = (body or "").strip().upper().split()
    if not tokens:
        return None
    first = tokens[0].strip(".!,")
    return _WORDS.get(first)


def verify_httpsms_webhook(authorization: str | None, secret: str) -> bool:
    """httpSMS signs webhook requests with an HS256 JWT in the Authorization header."""
    if not authorization or not authorization.startswith("Bearer "):
        return False
    try:
        jwt.decode(authorization[7:], secret, algorithms=["HS256"], options={"verify_aud": False})
        return True
    except jwt.PyJWTError:
        return False


def extract_inbound(payload: dict) -> tuple[str, str, str] | None:
    """Return (provider_message_id, from_phone, body) from an httpSMS 'message.phone.received' event."""
    if payload.get("type") != "message.phone.received":
        return None
    data = payload.get("data") or {}
    msg_id = data.get("message_id") or data.get("id") or payload.get("id")
    contact = data.get("contact")
    content = data.get("content")
    if not (msg_id and contact and isinstance(content, str)):
        return None
    return str(msg_id), str(contact), content
