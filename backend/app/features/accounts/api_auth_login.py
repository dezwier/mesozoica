"""Auth login endpoints. Owned by the accounts feature."""

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import func, or_
from sqlmodel import Session, select

from app.features.accounts.api_auth_shared import (
    create_auth_response_with_new_token,
    ensure_firebase_provider_synced,
    unlinked_firebase_providers_set,
)
from app.core.database import get_session
from app.core.security import create_access_token
from app.models.user import User
from app.models.user_auth_identity import UserAuthIdentity
from app.schemas.auth import (
    AuthResponse,
    FirebaseLoginRequest,
    LoginRequest,
    RegisterRequest,
)
from app.features.accounts.application.auth_login import (
    create_oauth_user_with_identity,
    ensure_password_identity,
    generate_unique_username,
    try_link_firebase_identity_for_password_login,
)
from app.features.accounts.api_auth_shared import auth_response_for_user
from app.features.accounts.infrastructure.firebase_auth import verify_firebase_id_token

router = APIRouter(prefix="/auth", tags=["auth"])


@router.post("/firebase", response_model=AuthResponse)
async def login_firebase(
    body: FirebaseLoginRequest,
    session: Session = Depends(get_session),
):
    try:
        claims = verify_firebase_id_token(body.id_token)
    except ValueError as error:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=str(error),
        ) from error

    uid = claims["uid"]
    email = claims.get("email") or ""
    name = claims.get("name")
    sign_in_provider = claims.get("sign_in_provider")

    user = session.exec(select(User).where(User.firebase_uid == uid)).first()
    if user:
        if sign_in_provider and sign_in_provider in unlinked_firebase_providers_set(user):
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail={
                    "code": "provider_disconnected",
                    "message": "This sign-in method was disconnected. Sign in with your password or another linked method, then you can link it again in Account Settings.",
                },
            )
        ensure_firebase_provider_synced(session, user, uid, sign_in_provider)
        session.commit()
        return create_auth_response_with_new_token(session, user, "Login successful")

    username = generate_unique_username(session, email, fallback_prefix="user")
    user_email = email or f"firebase_{uid}@placeholder.local"
    display_name = name or (email.split("@")[0] if email else username)
    new_user = create_oauth_user_with_identity(
        session,
        provider="firebase",
        provider_user_id=uid,
        username=username,
        email=user_email,
        full_name=name or display_name,
        image_url=claims.get("picture"),
        firebase_uid=uid,
    )
    new_user.display_name = display_name
    session.add(new_user)
    ensure_firebase_provider_synced(session, new_user, uid, sign_in_provider)
    session.commit()
    return create_auth_response_with_new_token(session, new_user, "Login successful")


@router.post("/login", response_model=AuthResponse)
async def login(
    login_data: LoginRequest,
    session: Session = Depends(get_session),
):
    login_input = login_data.username.strip()
    login_input_lower = login_input.lower()
    statement = select(User).where(
        or_(
            User.username == login_input,
            func.lower(User.email) == login_input_lower,
        )
    )
    user = session.exec(statement).first()
    if not user or not user.verify_password(login_data.password):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid username/email or password",
        )

    try_link_firebase_identity_for_password_login(
        session,
        user=user,
        password=login_data.password,
    )
    ensure_password_identity(session, user=user)

    access_token = create_access_token(data={"sub": str(user.id)})
    return auth_response_for_user(session, user, access_token, "Login successful")


@router.post("/register", response_model=AuthResponse, status_code=status.HTTP_201_CREATED)
async def register(
    register_data: RegisterRequest,
    session: Session = Depends(get_session),
):
    existing_user = session.exec(
        select(User).where(User.username == register_data.username)
    ).first()
    if existing_user:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Username already exists")

    existing_email = session.exec(select(User).where(User.email == register_data.email)).first()
    if existing_email:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Email already exists")

    hashed_password = User.hash_password(register_data.password)
    display_name = register_data.full_name or register_data.username
    new_user = User(
        username=register_data.username,
        email=register_data.email,
        password=hashed_password,
        full_name=register_data.full_name,
        display_name=display_name,
    )
    session.add(new_user)
    session.commit()
    session.refresh(new_user)

    access_token = create_access_token(data={"sub": str(new_user.id)})
    session.add(
        UserAuthIdentity(
            user_id=new_user.id,
            provider="password",
            provider_user_id=str(new_user.id),
        )
    )
    session.commit()
    return auth_response_for_user(session, new_user, access_token, "Registration successful")
