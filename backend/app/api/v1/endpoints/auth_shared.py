"""Shared auth endpoint helpers."""

from __future__ import annotations

from sqlmodel import Session, select

from app.core.security import create_access_token
from app.models.user import User
from app.models.user_auth_identity import UserAuthIdentity
from app.schemas.auth import AuthResponse
from app.services.firebase_auth_service import get_firebase_user_providers
from app.services.user_service import user_to_response


def auth_response_for_user(
    session: Session,
    user: User,
    access_token: str,
    message: str,
) -> AuthResponse:
    return AuthResponse(
        user=user_to_response(user),
        access_token=access_token,
        message=message,
    )


def create_auth_response_with_new_token(session: Session, user: User, message: str) -> AuthResponse:
    access_token = create_access_token(data={"sub": str(user.id)})
    return auth_response_for_user(session, user, access_token, message)


def unlinked_firebase_providers_set(user: User) -> set[str]:
    raw = (user.unlinked_firebase_providers or "").strip()
    if not raw:
        return set()
    return {part.strip() for part in raw.split(",") if part.strip()}


def add_unlinked_firebase_provider(user: User, provider: str) -> None:
    current = unlinked_firebase_providers_set(user)
    current.add(provider)
    user.unlinked_firebase_providers = ",".join(sorted(current))


def remove_unlinked_firebase_provider(user: User, provider: str) -> None:
    current = unlinked_firebase_providers_set(user)
    current.discard(provider)
    user.unlinked_firebase_providers = ",".join(sorted(current)) if current else None


def ensure_firebase_provider_synced(
    session: Session,
    user: User,
    firebase_uid: str,
    sign_in_provider: str | None,
) -> None:
    if not sign_in_provider or sign_in_provider not in ("google", "apple", "password"):
        return
    existing = session.exec(
        select(UserAuthIdentity).where(
            UserAuthIdentity.user_id == user.id,
            UserAuthIdentity.provider == sign_in_provider,
        )
    ).first()
    if existing:
        return
    session.add(
        UserAuthIdentity(
            user_id=user.id,
            provider=sign_in_provider,
            provider_user_id=firebase_uid,
            email=user.email,
        )
    )


def get_providers(session: Session, user: User) -> list[str]:
    identities = session.exec(
        select(UserAuthIdentity.provider).where(UserAuthIdentity.user_id == user.id)
    ).all()
    providers = list(identities)
    if user.password is not None and "password" not in providers:
        providers.append("password")
    return providers


def linked_providers_response(session: Session, user: User) -> list[str]:
    if user.firebase_uid:
        providers = get_firebase_user_providers(user.firebase_uid)
        if user.password is not None and "password" not in providers:
            providers = list(providers) + ["password"]
        unlinked = unlinked_firebase_providers_set(user)
        return [provider for provider in providers if provider not in unlinked]
    return get_providers(session, user)
