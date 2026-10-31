"""Firebase Cloud Messaging adapter.

Disabled (returns ok=False, 'not configured') unless FIREBASE_CREDENTIALS_FILE points to a
service-account JSON stored outside the repository. The in-app channel (WebSocket + polling)
always works, so alerts still reach an open app without FCM.
"""

from __future__ import annotations

import asyncio
import logging
import os
from dataclasses import dataclass

from app.config import Settings

log = logging.getLogger(__name__)


@dataclass(frozen=True)
class PushResult:
    ok: bool
    provider_message_id: str | None
    error: str | None = None


class FcmGateway:
    def __init__(self, settings: Settings) -> None:
        self._cred_path = settings.firebase_credentials_file
        self._app = None
        self._init_error: str | None = None

    @property
    def configured(self) -> bool:
        return bool(self._cred_path) and os.path.exists(self._cred_path)

    def _ensure_app(self):
        if self._app is not None or self._init_error:
            return self._app
        try:
            import firebase_admin
            from firebase_admin import credentials

            self._app = firebase_admin.initialize_app(
                credentials.Certificate(self._cred_path), name="aapdasaathi"
            )
        except Exception as exc:  # noqa: BLE001 - surface any init failure as a delivery error
            self._init_error = f"firebase init failed: {type(exc).__name__}"
            log.error(self._init_error)
        return self._app

    async def send(self, token: str, title: str, body: str, data: dict[str, str]) -> PushResult:
        if not self.configured:
            return PushResult(False, None, "FCM not configured")
        app = self._ensure_app()
        if app is None:
            return PushResult(False, None, self._init_error)
        from firebase_admin import messaging

        message = messaging.Message(
            token=token,
            notification=messaging.Notification(title=title, body=body),
            data=data,
            android=messaging.AndroidConfig(
                priority="high",
                ttl=3600,
                notification=messaging.AndroidNotification(
                    channel_id="aapda_emergency", sound="default", default_vibrate_timings=False
                ),
            ),
        )
        try:
            msg_id = await asyncio.to_thread(messaging.send, message, app=app)
            return PushResult(True, msg_id)
        except Exception as exc:  # noqa: BLE001
            return PushResult(False, None, type(exc).__name__)
