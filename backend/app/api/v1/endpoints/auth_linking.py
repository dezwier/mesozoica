"""Auth account-linking endpoints."""

from fastapi import APIRouter, Depends, HTTPException, status
from sqlmodel import Session, select

from app.api.v1.endpoints.auth_shared import (
    add_unlinked_firebase_provider,
    get_providers,
    linked_providers_response,
    remove_unlinked_firebase_provider,
    unlinked_firebase_providers_set,
)
from app.core.database import get_session
from app.core.security import get_current_user
from app.models.user import User
from app.models.user_auth_identity import UserAuthIdentity
from app.schemas.auth import (
    LinkAppleRequest,
    LinkGoogleRequest,
    LinkedAccountsMessageResponse,
    LinkedAccountsResponse,
)
from app.services.firebase_auth_service import (
    get_apple_sub_from_firebase_user,
    get_firebase_user_providers,
    get_google_sub_from_firebase_user,
    verify_firebase_id_token,
)

router = APIRouter(prefix="/auth", tags=["auth"])


@router.get("/linked-accounts", response_model=LinkedAccountsResponse)
async def get_linked_accounts(
    current_user: User = Depends(get_current_user),
    session: Session = Depends(get_session),
):
    return LinkedAccountsResponse(providers=linked_providers_response(session, current_user))


@router.post("/link/google", response_model=LinkedAccountsMessageResponse)
async def link_google(
    body: LinkGoogleRequest,
    current_user: User = Depends(get_current_user),
    session: Session = Depends(get_session),
):
    sub: str | None = None
    email: str | None = None

    if body.firebase_id_token and current_user.firebase_uid:
        try:
            claims = verify_firebase_id_token(body.firebase_id_token)
        except ValueError as error:
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail=str(error)) from error
        uid = claims.get("uid")
        if uid != current_user.firebase_uid:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Firebase token does not match the current user",
            )
        sub, email = get_google_sub_from_firebase_user(uid)
        if not sub:
            if "google" in get_firebase_user_providers(uid):
                remove_unlinked_firebase_provider(current_user, "google")
                session.add(current_user)
                session.commit()
                return LinkedAccountsMessageResponse(
                    message="Google account linked",
                    providers=linked_providers_response(session, current_user),
                )
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Google is not linked on this Firebase user. Complete Google sign-in in the app first.",
            )
    else:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Provide firebase_id_token after completing Google sign-in",
        )

    existing = session.exec(
        select(UserAuthIdentity).where(
            UserAuthIdentity.provider == "google",
            UserAuthIdentity.provider_user_id == sub,
        )
    ).first()
    if existing:
        if existing.user_id != current_user.id:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="This Google account is already linked to another user",
            )
        return LinkedAccountsMessageResponse(
            message="Google account is already linked",
            providers=get_providers(session, current_user),
        )

    session.add(
        UserAuthIdentity(
            user_id=current_user.id,
            provider="google",
            provider_user_id=sub,
            email=email,
        )
    )
    remove_unlinked_firebase_provider(current_user, "google")
    session.add(current_user)
    session.commit()
    return LinkedAccountsMessageResponse(
        message="Google account linked",
        providers=linked_providers_response(session, current_user),
    )


@router.post("/link/apple", response_model=LinkedAccountsMessageResponse)
async def link_apple(
    body: LinkAppleRequest,
    current_user: User = Depends(get_current_user),
    session: Session = Depends(get_session),
):
    sub: str | None = None
    email: str | None = None

    if body.firebase_id_token and current_user.firebase_uid:
        try:
            claims = verify_firebase_id_token(body.firebase_id_token)
        except ValueError as error:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(error)) from error
        uid = claims.get("uid")
        if uid != current_user.firebase_uid:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Firebase token does not match the current user",
            )
        sub, email = get_apple_sub_from_firebase_user(uid)
        if not sub:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Apple is not linked on this Firebase user. Complete Sign in with Apple in the app first.",
            )
    else:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Provide firebase_id_token after completing Apple sign-in",
        )

    existing = session.exec(
        select(UserAuthIdentity).where(
            UserAuthIdentity.provider == "apple",
            UserAuthIdentity.provider_user_id == sub,
        )
    ).first()
    if existing:
        if existing.user_id != current_user.id:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="This Apple account is already linked to another user",
            )
        return LinkedAccountsMessageResponse(
            message="Apple account is already linked",
            providers=get_providers(session, current_user),
        )

    session.add(
        UserAuthIdentity(
            user_id=current_user.id,
            provider="apple",
            provider_user_id=sub,
            email=email,
        )
    )
    remove_unlinked_firebase_provider(current_user, "apple")
    session.add(current_user)
    session.commit()
    return LinkedAccountsMessageResponse(
        message="Apple account linked",
        providers=linked_providers_response(session, current_user),
    )


@router.delete("/link/{provider}", response_model=LinkedAccountsMessageResponse)
async def unlink_provider(
    provider: str,
    current_user: User = Depends(get_current_user),
    session: Session = Depends(get_session),
):
    if provider not in ("password", "google", "apple", "firebase"):
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid provider")

    if current_user.firebase_uid:
        current_providers = get_firebase_user_providers(current_user.firebase_uid)
        if current_user.password is not None and "password" not in current_providers:
            current_providers = list(current_providers) + ["password"]
    else:
        current_providers = get_providers(session, current_user)

    if provider not in current_providers:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Provider not linked")
    if len(current_providers) <= 1:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Cannot unlink the last sign-in method. Link another method first.",
        )

    if provider == "password":
        identity = session.exec(
            select(UserAuthIdentity).where(
                UserAuthIdentity.user_id == current_user.id,
                UserAuthIdentity.provider == "password",
            )
        ).first()
        if identity:
            session.delete(identity)
        current_user.password = None
        session.add(current_user)
    else:
        identity = session.exec(
            select(UserAuthIdentity).where(
                UserAuthIdentity.user_id == current_user.id,
                UserAuthIdentity.provider == provider,
            )
        ).first()
        if identity:
            session.delete(identity)
        if current_user.firebase_uid and provider in ("google", "apple"):
            add_unlinked_firebase_provider(current_user, provider)
            session.add(current_user)

    session.commit()
    if current_user.firebase_uid:
        providers_after = get_firebase_user_providers(current_user.firebase_uid)
        if current_user.password is not None and "password" not in providers_after:
            providers_after = list(providers_after) + ["password"]
        unlinked = unlinked_firebase_providers_set(current_user)
        providers_after = [item for item in providers_after if item not in unlinked]
    else:
        providers_after = get_providers(session, current_user)
    return LinkedAccountsMessageResponse(
        message=f"{provider} unlinked",
        providers=providers_after,
    )
