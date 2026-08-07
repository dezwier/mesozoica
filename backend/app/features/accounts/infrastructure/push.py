"""
Push notification service (FCM). Sends to user device tokens when configured.
If Firebase Admin is not configured or credentials are missing, sends are no-ops.
"""

from __future__ import annotations

import logging
from typing import List, Optional

from sqlmodel import Session, select

logger = logging.getLogger(__name__)

_firebase_app = None
_firebase_tried = False


def _get_firebase_app():
    """Return Firebase app if credentials are available, else None."""
    global _firebase_app, _firebase_tried
    if _firebase_tried:
        return _firebase_app or None
    _firebase_tried = True
    try:
        import firebase_admin

        if firebase_admin._apps:
            _firebase_app = firebase_admin.get_app()
            return _firebase_app

        from app.features.accounts.infrastructure.firebase_auth import _get_firebase_credentials

        cred = _get_firebase_credentials()
        if cred is not None:
            _firebase_app = firebase_admin.initialize_app(cred)
        else:
            _firebase_app = firebase_admin.initialize_app()
        return _firebase_app
    except Exception as exc:
        _firebase_app = False
        logger.debug("Firebase Admin not available for push: %s", exc)
        return None


def get_device_tokens(session: Session, user_id: int) -> List[str]:
    """Return list of FCM tokens for the user."""
    from app.models.user_device_token import UserDeviceToken

    rows = session.exec(
        select(UserDeviceToken.token).where(UserDeviceToken.user_id == user_id)
    ).all()
    return list(rows) if rows else []


def _get_unread_notification_badge_count(session: Session, user_id: int) -> int:
    from app.models.user_notification import UserNotification

    rows = session.exec(
        select(UserNotification.id)
        .where(UserNotification.user_id == user_id)
        .where(UserNotification.read == False)  # noqa: E712
    ).all()
    return len(rows)


def send_push_to_tokens(
    tokens: List[str],
    title: str,
    body: str,
    data: Optional[dict] = None,
    badge_count: Optional[int] = None,
) -> List[str]:
    """
    Send FCM notification to the given tokens.
    Returns list of token strings that failed (invalid/unregistered).
    """
    app = _get_firebase_app()
    if not app or not tokens:
        return []
    try:
        from firebase_admin import messaging

        string_data = {
            str(key): str(value) for key, value in (data or {}).items()
        }
        invalid_tokens: list[str] = []
        for token in tokens:
            try:
                apns_config = None
                android_config = None
                if badge_count is not None:
                    apns_config = messaging.APNSConfig(
                        payload=messaging.APNSPayload(
                            aps=messaging.Aps(
                                badge=badge_count,
                                sound="default",
                            )
                        )
                    )
                    android_config = messaging.AndroidConfig(
                        notification=messaging.AndroidNotification(
                            notification_count=badge_count,
                        )
                    )
                msg = messaging.Message(
                    notification=messaging.Notification(title=title, body=body),
                    data=string_data,
                    token=token,
                    apns=apns_config,
                    android=android_config,
                )
                message_id = messaging.send(msg)
                logger.info(
                    "FCM send ok token=%s... message_id=%s payload_type=%s",
                    token[:20],
                    message_id,
                    string_data.get("type"),
                )
            except messaging.UnregisteredError:
                logger.warning("FCM token unregistered token=%s...", token[:20])
                invalid_tokens.append(token)
            except Exception as exc:
                logger.warning("FCM send failed for token %s...: %s", token[:20], exc)
                if "not found" in str(exc).lower() or "unregistered" in str(exc).lower():
                    invalid_tokens.append(token)
        return invalid_tokens
    except Exception as exc:
        logger.warning("FCM send failed: %s", exc)
        return []


def remove_tokens(session: Session, tokens: List[str]) -> None:
    """Remove device tokens from the database (e.g. after FCM reports invalid)."""
    if not tokens:
        return
    from app.models.user_device_token import UserDeviceToken

    for token in tokens:
        row = session.exec(
            select(UserDeviceToken).where(UserDeviceToken.token == token)
        ).first()
        if row:
            session.delete(row)
    session.commit()


def send_badge_sync_to_tokens(
    tokens: List[str],
    badge_count: int,
) -> List[str]:
    """
    Silently update the OS app-icon badge without showing an alert.
    Used after in-app mark-read so the launcher badge matches unread count.
    """
    app = _get_firebase_app()
    if not app or not tokens:
        return []
    try:
        from firebase_admin import messaging

        invalid_tokens: list[str] = []
        for token in tokens:
            try:
                apns_config = messaging.APNSConfig(
                    headers={"apns-priority": "5"},
                    payload=messaging.APNSPayload(
                        aps=messaging.Aps(
                            badge=badge_count,
                            content_available=True,
                        )
                    ),
                )
                android_config = messaging.AndroidConfig(
                    priority="normal",
                    data={"type": "badge_sync", "badge": str(badge_count)},
                )
                msg = messaging.Message(
                    data={"type": "badge_sync", "badge": str(badge_count)},
                    token=token,
                    apns=apns_config,
                    android=android_config,
                )
                messaging.send(msg)
            except messaging.UnregisteredError:
                logger.warning("FCM badge sync unregistered token=%s...", token[:20])
                invalid_tokens.append(token)
            except Exception as exc:
                logger.warning(
                    "FCM badge sync failed for token %s...: %s", token[:20], exc
                )
                if "not found" in str(exc).lower() or "unregistered" in str(exc).lower():
                    invalid_tokens.append(token)
        return invalid_tokens
    except Exception as exc:
        logger.warning("FCM badge sync failed: %s", exc)
        return []


def sync_unread_badge(session: Session, user_id: int) -> None:
    """Push the current unread notification count to the device app-icon badge."""
    tokens = get_device_tokens(session, user_id)
    if not tokens:
        return
    badge_count = _get_unread_notification_badge_count(session, user_id)
    invalid = send_badge_sync_to_tokens(tokens, badge_count)
    if invalid:
        remove_tokens(session, invalid)


def send_site_celebration_push(
    session: Session,
    *,
    user_id: int,
    site_id: int,
    notification_id: int,
    notification_type: str,
    site_label: str,
) -> None:
    """Send the standard FCM payload for a site celebration."""
    from app.features.accounts.models.user_notification import UserNotificationType

    labels = {
        UserNotificationType.SITE_DISCOVERED: "discovered",
        UserNotificationType.SITE_IDENTIFIED: "identified",
        UserNotificationType.SITE_DOCUMENTED: "documented",
    }
    verb = labels.get(notification_type)
    if verb is None:
        raise ValueError(f"Unsupported site celebration type: {notification_type}")
    tokens = get_device_tokens(session, user_id)
    if not tokens:
        return
    badge_count = _get_unread_notification_badge_count(session, user_id)
    invalid = send_push_to_tokens(
        tokens,
        title="Mesozoica",
        body=f"Site {verb}: {site_label}",
        data={
            "type": notification_type,
            "site_id": str(site_id),
            "notification_id": str(notification_id),
        },
        badge_count=badge_count,
    )
    if invalid:
        remove_tokens(session, invalid)
