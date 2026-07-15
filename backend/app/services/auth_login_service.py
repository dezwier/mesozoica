"""Auth login helpers."""

from __future__ import annotations

import logging
import uuid

from sqlmodel import Session, select

from app.models.user import User
from app.models.user_auth_identity import UserAuthIdentity
from app.services.firebase_auth_service import ensure_firebase_uid_for_email_password

logger = logging.getLogger(__name__)


def generate_unique_username(session: Session, email: str, fallback_prefix: str = "user") -> str:
    base_username = (email.split("@")[0] if email else fallback_prefix).replace(".", "_")[:30] or "user"
    username = base_username
    n = 0
    while session.exec(select(User).where(User.username == username)).first():
        n += 1
        username = f"{base_username}{n}" if n > 0 else f"{base_username}_{uuid.uuid4().hex[:8]}"
    return username


def create_oauth_user_with_identity(
    session: Session,
    *,
    provider: str,
    provider_user_id: str,
    username: str,
    email: str,
    full_name: str | None,
    image_url: str | None = None,
    firebase_uid: str | None = None,
) -> User:
    display_name = full_name or (email.split("@")[0] if email else username)
    new_user = User(
        username=username,
        email=email,
        password=None,
        firebase_uid=firebase_uid,
        full_name=full_name,
        image_url=image_url,
        display_name=display_name,
    )
    session.add(new_user)
    session.commit()
    session.refresh(new_user)
    session.add(
        UserAuthIdentity(
            user_id=new_user.id,
            provider=provider,
            provider_user_id=provider_user_id,
            email=email or None,
        )
    )
    session.commit()
    return new_user


def try_link_firebase_identity_for_password_login(
    session: Session,
    *,
    user: User,
    password: str,
) -> None:
    if user.firebase_uid is not None:
        return
    if not user.email or "@" not in user.email or "placeholder" in user.email.lower():
        return
    try:
        firebase_uid = ensure_firebase_uid_for_email_password(user.email, password)
        user.firebase_uid = firebase_uid
        session.add(user)
        existing = session.exec(
            select(UserAuthIdentity).where(
                UserAuthIdentity.user_id == user.id,
                UserAuthIdentity.provider == "firebase",
            )
        ).first()
        if not existing:
            session.add(
                UserAuthIdentity(
                    user_id=user.id,
                    provider="firebase",
                    provider_user_id=firebase_uid,
                    email=user.email,
                )
            )
        session.commit()
    except Exception as exc:
        session.rollback()
        logger.warning(
            "Non-blocking Firebase identity link failed for user_id=%s: %s",
            user.id,
            exc,
        )


def ensure_password_identity(session: Session, *, user: User) -> None:
    existing = session.exec(
        select(UserAuthIdentity).where(
            UserAuthIdentity.user_id == user.id,
            UserAuthIdentity.provider == "password",
        )
    ).first()
    if existing:
        return
    session.add(
        UserAuthIdentity(
            user_id=user.id,
            provider="password",
            provider_user_id=str(user.id),
        )
    )
    session.commit()
