"""Verify Firebase ID tokens via Firebase Admin SDK."""

from __future__ import annotations

import json
import logging
import os
from typing import Any

logger = logging.getLogger(__name__)

_firebase_app = None


def _get_firebase_credentials():
    json_str = os.environ.get("FIREBASE_SERVICE_ACCOUNT_JSON", "").strip()
    if json_str:
        try:
            from firebase_admin import credentials

            return credentials.Certificate(json.loads(json_str))
        except Exception as exc:
            logger.warning("Invalid FIREBASE_SERVICE_ACCOUNT_JSON: %s", exc)
    return None


def _get_firebase_app():
    global _firebase_app
    if _firebase_app is None:
        try:
            import firebase_admin

            if not firebase_admin._apps:
                cred = _get_firebase_credentials()
                _firebase_app = (
                    firebase_admin.initialize_app(cred)
                    if cred
                    else firebase_admin.initialize_app()
                )
            else:
                _firebase_app = firebase_admin.get_app()
        except Exception as exc:
            logger.exception("Firebase Admin init failed: %s", exc)
            raise ValueError("Firebase is not configured") from exc
    return _firebase_app


def verify_firebase_id_token(id_token: str) -> dict[str, Any]:
    from firebase_admin import auth

    _get_firebase_app()
    try:
        decoded = auth.verify_id_token(id_token)
    except auth.ExpiredIdTokenError as exc:
        raise ValueError("Firebase token has expired") from exc
    except auth.InvalidIdTokenError as exc:
        logger.warning("Firebase InvalidIdTokenError: %s", exc)
        raise ValueError("Invalid Firebase token") from exc
    except Exception as exc:
        logger.warning("Firebase token verification failed: %s", exc)
        raise ValueError("Invalid Firebase token") from exc

    uid = decoded.get("uid")
    if not uid:
        raise ValueError("Firebase token missing uid")

    firebase_claims = decoded.get("firebase") or {}
    sign_in_provider = firebase_claims.get("sign_in_provider") or ""
    provider_map = {"google.com": "google", "apple.com": "apple", "password": "password"}
    return {
        "uid": uid,
        "email": (decoded.get("email") or "").strip().lower() or None,
        "name": decoded.get("name"),
        "picture": decoded.get("picture"),
        "sign_in_provider": provider_map.get(sign_in_provider),
    }


def get_google_sub_from_firebase_user(uid: str) -> tuple[str | None, str | None]:
    from firebase_admin import auth

    _get_firebase_app()
    try:
        user_record = auth.get_user(uid)
    except Exception as exc:
        logger.warning("Firebase get_user failed: %s", exc)
        return None, None
    for info in getattr(user_record, "provider_data", []) or []:
        if getattr(info, "provider_id", None) == "google.com":
            sub = getattr(info, "uid", None) or getattr(info, "raw_id", None)
            email = (getattr(info, "email", None) or "").strip().lower() or None
            return sub, email
    return None, None


def get_apple_sub_from_firebase_user(uid: str) -> tuple[str | None, str | None]:
    from firebase_admin import auth

    _get_firebase_app()
    try:
        user_record = auth.get_user(uid)
    except Exception as exc:
        logger.warning("Firebase get_user failed: %s", exc)
        return None, None
    for info in getattr(user_record, "provider_data", []) or []:
        if getattr(info, "provider_id", None) == "apple.com":
            sub = getattr(info, "uid", None) or getattr(info, "raw_id", None)
            email = (getattr(info, "email", None) or "").strip().lower() or None
            return sub, email
    return None, None


def get_firebase_user_providers(uid: str) -> list[str]:
    from firebase_admin import auth

    _get_firebase_app()
    try:
        user_record = auth.get_user(uid)
    except Exception as exc:
        logger.warning("Firebase get_user failed: %s", exc)
        return []
    provider_map = {"google.com": "google", "apple.com": "apple", "password": "password"}
    providers: list[str] = []
    for info in getattr(user_record, "provider_data", []) or []:
        pid = getattr(info, "provider_id", None)
        if pid and pid in provider_map and provider_map[pid] not in providers:
            providers.append(provider_map[pid])
    return providers


def ensure_firebase_uid_for_email_password(email: str, password: str) -> str:
    from firebase_admin import auth

    _get_firebase_app()
    email_clean = (email or "").strip().lower()
    if not email_clean:
        raise ValueError("Email required for Firebase migration")
    try:
        user_record = auth.create_user(
            email=email_clean,
            password=password,
            email_verified=True,
        )
        return user_record.uid
    except auth.EmailAlreadyExistsError:
        user_record = auth.get_user_by_email(email_clean)
        try:
            auth.update_user(user_record.uid, password=password)
        except Exception:
            pass
        return user_record.uid
    except Exception as exc:
        logger.warning("Firebase ensure user failed: %s", exc)
        raise ValueError(f"Could not create Firebase user: {exc}") from exc


def delete_firebase_user(uid: str) -> None:
    if not uid or not str(uid).strip():
        return
    uid = str(uid).strip()
    try:
        from firebase_admin import auth

        _get_firebase_app()
        auth.delete_user(uid)
    except Exception as exc:
        if type(exc).__name__ == "UserNotFoundError":
            return
        logger.warning("Firebase delete_user failed for uid=%s: %s", uid, exc)
