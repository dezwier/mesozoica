"""Auth profile endpoints."""

from datetime import datetime, timezone

from fastapi import APIRouter, Depends, File, HTTPException, Query, UploadFile, status
from sqlmodel import Session, select

from app.core.database import get_session
from app.core.security import get_current_user
from app.models.user import User
from app.models.user_device_token import UserDeviceToken
from app.schemas.auth import (
    AuthResponse,
    AvailabilityResponse,
    DeleteUserDataRequest,
    DeleteUserDataResponse,
    RegisterDeviceTokenRequest,
    UpdateProfileRequest,
)
from app.services.user_image_service import (
    delete_user_image_file,
    process_user_profile_image,
    save_user_image,
)
from app.services.user_service import (
    delete_user_account,
    delete_user_progress,
    user_to_profile_response,
    user_to_response,
)

router = APIRouter(prefix="/auth", tags=["auth"])


@router.post("/device-token", status_code=status.HTTP_204_NO_CONTENT)
async def register_device_token(
    body: RegisterDeviceTokenRequest,
    current_user: User = Depends(get_current_user),
    session: Session = Depends(get_session),
):
    """Register or refresh device token for push notifications."""
    now = datetime.now(timezone.utc)
    existing = session.exec(
        select(UserDeviceToken).where(UserDeviceToken.token == body.token)
    ).first()
    if existing:
        if existing.user_id != current_user.id:
            existing.user_id = current_user.id
            existing.last_used_at = now
            existing.platform = body.platform
            session.add(existing)
        else:
            existing.last_used_at = now
            existing.platform = body.platform
            session.add(existing)
    else:
        session.add(
            UserDeviceToken(
                user_id=current_user.id,
                token=body.token,
                platform=body.platform,
                last_used_at=now,
            )
        )
    session.commit()
    return None


@router.post("/upload-profile-image", response_model=AuthResponse)
async def upload_profile_image(
    file: UploadFile = File(...),
    current_user: User = Depends(get_current_user),
    session: Session = Depends(get_session),
):
    try:
        file_content = await file.read()
        image_bytes = process_user_profile_image(file_content)
        save_user_image(current_user.username, image_bytes)
        image_url = f"/media/users/{current_user.username}.jpg"
        if current_user.image_url and current_user.image_url != image_url:
            delete_user_image_file(current_user.image_url)
        current_user.image_url = image_url
        session.add(current_user)
        session.commit()
        session.refresh(current_user)
        return AuthResponse(
            user=user_to_response(current_user),
            access_token="",
            message="Profile image uploaded successfully",
        )
    except HTTPException:
        raise
    except Exception as error:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to upload profile image: {error}",
        ) from error


@router.get("/check-username", response_model=AvailabilityResponse)
async def check_username(
    username: str = Query(..., min_length=3, max_length=50),
    current_user: User = Depends(get_current_user),
    session: Session = Depends(get_session),
):
    if username == current_user.username:
        return AvailabilityResponse(available=True)
    existing_user = session.exec(select(User).where(User.username == username)).first()
    return AvailabilityResponse(available=existing_user is None)


@router.patch("/update-profile", response_model=AuthResponse)
async def update_profile(
    update_data: UpdateProfileRequest,
    current_user: User = Depends(get_current_user),
    session: Session = Depends(get_session),
):
    user = current_user
    if update_data.password is not None:
        if user.password is not None:
            if not update_data.current_password:
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail="Current password is required when updating password",
                )
            if not user.verify_password(update_data.current_password):
                raise HTTPException(
                    status_code=status.HTTP_400_BAD_REQUEST,
                    detail="Current password is incorrect",
                )
        user.password = User.hash_password(update_data.password)

    if update_data.username is not None and update_data.username != user.username:
        existing = session.exec(
            select(User).where(User.username == update_data.username)
        ).first()
        if existing:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Username already exists",
            )
        user.username = update_data.username

    if update_data.email is not None and update_data.email != user.email:
        existing = session.exec(select(User).where(User.email == update_data.email)).first()
        if existing:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Email already exists",
            )
        user.email = str(update_data.email)

    if update_data.full_name is not None:
        user.full_name = update_data.full_name
        if not user.display_name or user.display_name == user.username:
            user.display_name = update_data.full_name

    session.add(user)
    session.commit()
    session.refresh(user)
    return AuthResponse(
        user=user_to_response(user),
        access_token="",
        message="Profile updated successfully",
    )


@router.post("/delete-data", response_model=DeleteUserDataResponse)
async def delete_data(
    body: DeleteUserDataRequest,
    current_user: User = Depends(get_current_user),
    session: Session = Depends(get_session),
):
    deleted = delete_user_progress(
        session,
        current_user.id,
        sites=body.sites,
        fossils=body.fossils,
        dinosaurs=body.dinosaurs,
    )
    session.refresh(current_user)
    return DeleteUserDataResponse(
        deleted_sites=deleted["deleted_sites"],
        deleted_fossils=deleted["deleted_fossils"],
        deleted_dinosaurs=deleted["deleted_dinosaurs"],
        user=user_to_profile_response(session, current_user),
        message="Selected progress data deleted successfully",
    )


@router.delete("/delete-account", response_model=AuthResponse)
async def delete_account(
    current_user: User = Depends(get_current_user),
    session: Session = Depends(get_session),
):
    delete_user_account(session, current_user)
    return AuthResponse(
        user=user_to_response(current_user),
        access_token="",
        message="Account deleted successfully",
    )
